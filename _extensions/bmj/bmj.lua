--[[
bmj.lua: Quarto filter for BMJ manuscript submissions.

Runs after Quarto's own filters (`at: post-quarto`) and

  * builds a BMJ-style title page from Quarto's normalised author and
    affiliation metadata (authors with ORCID iDs, numbered addresses with
    job titles, a single corresponding author, keywords and word counts);
  * moves the structured abstract into the body, followed by the journal's
    summary box (for The BMJ: "What is already known on this topic / What
    this study adds");
  * optionally removes figures from the body (BMJ wants figures uploaded as
    separate files), exports their image files with submission-friendly
    names and lists the figure legends at the end of the manuscript;
  * counts words in the main text (excluding the abstract, references,
    tables, boxes, figures and the end-of-manuscript statements) and warns
    about common submission problems.

Journal-specific rules (word limits, the summary box, the corresponding-author
and ORCID rules) come from the journal profile selected by `bmj.journal` and
`bmj.article-type`. Each journal is a YAML file in journals/; README.md
describes the fields under "Adding a journal".

Options live under the `bmj` metadata key; see README.md.
]]

local stringify = pandoc.utils.stringify

-- Resolved while the filter is loaded, relative to this file
local JOURNAL_DIR = quarto.utils.resolve_path("journals")
local DEFAULT_JOURNAL = "the-bmj"

local opts = {}
local legends = pandoc.List()
local removed_figure_ids = {}
local stats = { main = nil, abstract = nil }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function warn(msg)
  quarto.log.warning("[bmj] " .. msg)
end

--- Stop the render. Quarto replaces the global `error` with a function that
--- only logs, so raise the error through `assert`, which it leaves alone.
local function abort(msg)
  assert(false, "[bmj] " .. msg)
end

local function is_docx()
  return quarto.doc.is_format("docx")
end

local function is_latex()
  return quarto.doc.is_format("latex")
end

local function is_html()
  return quarto.doc.is_format("html")
end

local function nonempty(v)
  return v ~= nil and stringify(v) ~= ""
end

local function meta_bool(v, default)
  if v == nil then
    return default
  end
  if type(v) == "boolean" then
    return v
  end
  local s = stringify(v):lower()
  if s == "true" or s == "yes" then
    return true
  elseif s == "false" or s == "no" then
    return false
  end
  return default
end

local function meta_string(v, default)
  if nonempty(v) then
    return stringify(v)
  end
  return default
end

--- Convert a metadata value (string, inlines or blocks) to a list of blocks.
local function to_blocks(v)
  if v == nil then
    return pandoc.Blocks({})
  end
  local t = pandoc.utils.type(v)
  if t == "Blocks" then
    return pandoc.Blocks(v)
  elseif t == "Inlines" then
    return pandoc.Blocks({ pandoc.Para(v) })
  elseif t == "List" then
    -- MetaBlocks may come through as a plain list of blocks
    return pandoc.Blocks(v)
  end
  return pandoc.Blocks({ pandoc.Para(pandoc.Inlines(stringify(v))) })
end

--- Convert a metadata value to inlines.
local function to_inlines(v)
  if v == nil then
    return pandoc.Inlines({})
  end
  local t = pandoc.utils.type(v)
  if t == "Inlines" then
    return pandoc.Inlines(v)
  elseif t == "Blocks" then
    return pandoc.utils.blocks_to_inlines(v)
  end
  return pandoc.Inlines(stringify(v))
end

local function as_list(v)
  if v == nil then
    return {}
  end
  local t = pandoc.utils.type(v)
  if t == "List" then
    return v
  end
  return { v }
end

--- A paragraph-level page break that works in Word and LaTeX.
local function page_break()
  if is_docx() then
    return pandoc.RawBlock("openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
  elseif is_latex() then
    return pandoc.RawBlock("latex", "\\clearpage")
  end
  return pandoc.HorizontalRule()
end

local function styled(blocks, style)
  if is_docx() then
    return pandoc.Div(blocks, pandoc.Attr("", {}, { ["custom-style"] = style }))
  end
  return pandoc.Div(blocks, pandoc.Attr("", { style:lower():gsub("%s+", "-") }))
end

local function unnumbered_header(level, text, id)
  return pandoc.Header(level, pandoc.Inlines(text), pandoc.Attr(id, { "unnumbered", "unlisted" }))
end

-- ---------------------------------------------------------------------------
-- Word counting
-- ---------------------------------------------------------------------------

local function is_float(div)
  return div.attributes and div.attributes["__quarto_custom_type"] == "FloatRefTarget"
end

local excluded_div_classes = {
  ["bmj-statements"] = true,
  ["no-wordcount"] = true,
  ["summary-box"] = true,
}

local strip_for_count = {
  Cite = function(cite)
    -- Citations count as the text the reader sees ("[1]", "[2–4]"); see
    -- with_rendered_citations. One that citeproc did not render still
    -- holds the citation keys: count it as one word.
    local text = stringify(cite.content)
    if text == "" or text:find("@") then
      return pandoc.Str("[1]")
    end
    return cite.content
  end,
  Note = function() return {} end,
  Superscript = function() return {} end,
  RawInline = function(raw)
    -- LaTeX cross-references: Quarto writes "Figure~\ref{fig-x}" where other
    -- formats have "Figure 1", so count the reference as the number it shows.
    if raw.format == "latex" and raw.text:match("^\\ref%b{}$") then
      return pandoc.Str("1")
    end
    return {}
  end,
  Math = function() return {} end,
  Code = function() return {} end,
  Table = function() return {} end,
  CodeBlock = function() return {} end,
  RawBlock = function() return {} end,
  Figure = function() return {} end,
  Div = function(div)
    if is_float(div) or div.identifier == "refs" then
      return {}
    end
    for _, cls in ipairs(div.classes) do
      if excluded_div_classes[cls] then
        return {}
      end
    end
    return nil
  end,
}

--- Replace the characters that separate words in Microsoft Word's count with
--- an ASCII space: Unicode spaces (no-break space, the U+2000 spaces, narrow
--- no-break space, medium mathematical space, ideographic space) and the en
--- and em dashes. Quarto joins "Figure" and its number with a no-break space.
local function normalise_separators(text)
  return (text
    :gsub("\xC2\xA0", " ")
    :gsub("\xE2\x80[\x80-\x8B\xAF]", " ")
    :gsub("\xE2\x80[\x93\x94]", " ")
    :gsub("\xE2\x81\x9F", " ")
    :gsub("\xE3\x80\x80", " "))
end

--- Count words as Microsoft Word does: split the text at spaces (and the
--- characters above) and count every remaining run of characters, including
--- runs of punctuation only such as "-" or "&".
local function count_words(blocks)
  local doc = pandoc.Pandoc(pandoc.Blocks(blocks)):walk(strip_for_count)
  local parts = {}
  local function sep()
    table.insert(parts, " ")
  end
  -- top-down, so that elements are visited in document order and each block
  -- starts with a separator
  doc:walk({
    traverse = "topdown",
    Block = sep,
    Space = sep,
    SoftBreak = sep,
    LineBreak = sep,
    Str = function(s)
      table.insert(parts, s.text)
    end,
  })
  local n = 0
  for _ in normalise_separators(table.concat(parts)):gmatch("%S+") do
    n = n + 1
  end
  return n
end

--- A copy of `doc` with the citations rendered by citeproc, so that they are
--- counted as they appear in the output. Quarto runs citeproc only after
--- this filter. Returns `doc` itself when there is nothing to render or
--- citeproc fails (for example without a bibliography).
local function with_rendered_citations(doc)
  local has_cite = false
  doc:walk({ Cite = function() has_cite = true end })
  if not has_cite then
    return doc
  end
  local ok, rendered = pcall(pandoc.utils.citeproc, doc)
  if ok and rendered then
    return rendered
  end
  return doc
end

--- Main text = everything before the reference list / an appendix.
local function main_text_blocks(blocks)
  local out = pandoc.Blocks({})
  for _, b in ipairs(blocks) do
    if b.t == "Div" and b.identifier == "refs" then
      break
    end
    if b.t == "Header" and (b.identifier == "references" or b.classes:includes("appendix")) then
      break
    end
    out:insert(b)
  end
  return out
end

local function has_cite(blocks)
  local found = false
  pandoc.Pandoc(pandoc.Blocks(blocks)):walk({
    Cite = function()
      found = true
    end,
  })
  return found
end

-- ---------------------------------------------------------------------------
-- Journal profiles (journals/<journal>.yml)
-- ---------------------------------------------------------------------------

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("a")
  f:close()
  return data
end

--- Turn parsed YAML metadata into plain Lua values (strings, booleans,
--- arrays and tables), so profile values can be compared directly.
local function plain(v)
  if type(v) == "boolean" or type(v) == "string" then
    return v
  end
  local t = pandoc.utils.type(v)
  if t == "Inlines" or t == "Blocks" then
    return stringify(v)
  end
  local out = {}
  if t == "List" then
    for i, x in ipairs(v) do
      out[i] = plain(x)
    end
  elseif type(v) == "table" then
    for k, x in pairs(v) do
      out[k] = plain(x)
    end
  else
    return stringify(v)
  end
  return out
end

local function known_journals()
  local names = {}
  for _, f in ipairs(pandoc.system.list_directory(JOURNAL_DIR)) do
    local stem, ext = pandoc.path.split_extension(f)
    if ext == ".yml" then
      table.insert(names, stem)
    end
  end
  table.sort(names)
  return names
end

--- Read journals/<name>.yml, or nil if there is no such journal.
local function load_journal(name)
  -- the name becomes a file path: allow only plain profile names
  if not name:match("^[a-z0-9][a-z0-9-]*$") then
    return nil
  end
  local file = pandoc.path.join({ JOURNAL_DIR, name .. ".yml" })
  local text = read_file(file)
  if text == nil then
    return nil
  end
  -- Pandoc reads YAML through a Markdown metadata block; "-smart" keeps
  -- quotes and dashes in the strings as written.
  local meta = pandoc.read("---\n" .. text .. "\n---\n", "markdown-smart").meta
  return plain(meta), file
end

--- Check the fields bmj.lua relies on, so that a mistake in a profile file
--- stops the render with a message that names the file and the field.
local function check_profile(p, file, type_key)
  local where = file .. ", article-types." .. type_key .. ": "
  local function fail(msg)
    abort(where .. msg)
  end
  if type(p.name) ~= "string" or p.name == "" then
    fail("missing 'name'")
  end
  if type(p.label) ~= "string" or p.label == "" then
    fail("missing 'label'")
  end
  for _, key in ipairs({ "abstract-word-limit", "word-limit" }) do
    if p[key] ~= nil then
      local n = tonumber(p[key])
      if n == nil or n < 1 or n ~= math.floor(n) then
        fail("'" .. key .. "' must be a positive whole number")
      end
      p[key] = n
    end
  end
  for _, key in ipairs({ "single-corresponding", "orcid-corresponding" }) do
    if p[key] == nil then
      p[key] = false
    elseif type(p[key]) ~= "boolean" then
      fail("'" .. key .. "' must be true or false")
    end
  end
  local box = p.box
  if box ~= nil then
    if type(box.key) ~= "string" or box.key == "" then
      fail("'box' needs a 'key'")
    end
    box.sections = box.sections or {}
    for i, s in ipairs(box.sections) do
      if type(s.key) ~= "string" or type(s.title) ~= "string" then
        fail("'box.sections' entry " .. i .. " needs a 'key' and a 'title'")
      end
    end
    if box.title ~= nil and type(box.title) ~= "string" then
      fail("'box.title' must be text")
    end
  end
end

--- Select the journal and article type. Unknown names fall back to the
--- defaults with a warning.
local function resolve_profile(bmj)
  local journal_key = meta_string(bmj.journal, DEFAULT_JOURNAL)
  local journal, file = load_journal(journal_key)
  if journal == nil then
    warn(string.format("unknown bmj.journal '%s' (known: %s); using '%s'",
      journal_key, table.concat(known_journals(), ", "), DEFAULT_JOURNAL))
    journal_key = DEFAULT_JOURNAL
    journal, file = load_journal(journal_key)
    if journal == nil then
      abort("cannot read the default journal profile journals/" .. DEFAULT_JOURNAL .. ".yml")
    end
  end
  local types = journal["article-types"] or {}
  local default_type = journal["default-article-type"]
  local type_key = meta_string(bmj["article-type"], default_type)
  local article = types[type_key]
  if article == nil then
    warn(string.format("%s has no bmj.article-type '%s' (known: %s); using '%s'",
      journal.name, type_key, table.concat(sorted_keys(types), ", "), tostring(default_type)))
    type_key = default_type
    article = types[type_key]
    if article == nil then
      abort(file .. ": 'default-article-type' does not name an entry in 'article-types'")
    end
  end
  local p = {}
  for k, v in pairs(article) do
    p[k] = v
  end
  p.name = journal.name
  p.journal = journal_key
  p.article_type = type_key
  check_profile(p, file, type_key)
  return p
end

-- ---------------------------------------------------------------------------
-- Pass 1: options, word counts, checks
-- ---------------------------------------------------------------------------

--- A positive whole-number option, or `fallback` (with a warning if invalid).
local function count_option(v, name, fallback)
  if not nonempty(v) then
    return fallback
  end
  local n = tonumber(stringify(v))
  if n == nil or n < 1 or n ~= math.floor(n) then
    warn(string.format("bmj.%s must be a positive whole number; using %s",
      name, fallback and tostring(fallback) or "no limit"))
    return fallback
  end
  return n
end

--- Copy the profile's box and apply `box-title` / `box-headings` overrides.
local function resolve_box(profile, bmj)
  local box = profile.box
  if box == nil then
    if nonempty(bmj["box-title"]) or bmj["box-headings"] ~= nil then
      warn(string.format("%s %s have no summary box; bmj.box-title and bmj.box-headings are ignored",
        profile.name, profile.label))
    end
    return nil
  end
  local out = { key = box.key, title = box.title, sections = {} }
  for _, s in ipairs(box.sections) do
    table.insert(out.sections, { key = s.key, title = s.title })
  end
  if nonempty(bmj["box-title"]) then
    out.title = stringify(bmj["box-title"])
  end
  local headings = bmj["box-headings"]
  if headings ~= nil then
    if type(headings) ~= "table" or pandoc.utils.type(headings) == "List" then
      warn("bmj.box-headings must map section names to headings; ignored")
    else
      for _, key in ipairs(sorted_keys(headings)) do
        local section
        for _, s in ipairs(out.sections) do
          if s.key == key then
            section = s
          end
        end
        if section then
          section.title = stringify(headings[key])
        else
          warn(string.format("bmj.box-headings.%s is ignored: the box for %s %s has no section '%s'",
            key, profile.name, profile.label, key))
        end
      end
    end
  end
  return out
end

local function read_options(meta)
  local bmj = meta.bmj or {}
  local profile = resolve_profile(bmj)
  opts.profile = profile
  opts.box = resolve_box(profile, bmj)
  opts.abstract_limit = count_option(bmj["abstract-word-limit"], "abstract-word-limit",
    profile["abstract-word-limit"])
  opts.word_limit = count_option(bmj["word-limit"], "word-limit", profile["word-limit"])

  local default_figures = is_docx() and "separate" or "inline"
  opts.figures = meta_string(bmj.figures, default_figures)
  if opts.figures ~= "separate" and opts.figures ~= "inline" then
    warn("bmj.figures must be 'separate' or 'inline'; using '" .. default_figures .. "'")
    opts.figures = default_figures
  end
  opts.export_figures = meta_bool(bmj["export-figures"], true)
  opts.figure_dir = meta_string(bmj["figure-dir"], nil)
  opts.word_count = meta_bool(bmj["word-count"], true)
  -- HTML uses Quarto's own title block (authors, affiliations, abstract)
  opts.page_breaks = meta_bool(bmj["page-breaks"], not is_html())
  opts.title_page = meta_bool(bmj["title-page"], not is_html())
  opts.flatten_tables = meta_bool(bmj["flatten-tables"], true)
  opts.fig_title = meta_string(meta.crossref and meta.crossref["fig-title"], "Figure")
  opts.tbl_title = meta_string(meta.crossref and meta.crossref["tbl-title"], "Table")
  opts.abstract_title = meta_string(meta["abstract-title"], "Abstract")
end

--- Warning text for a count over its limit. When the document overrides the
--- profile's limit, name the option instead of quoting the journal.
local function limit_message(what, n, limit, option, profile_limit, guidance)
  if limit ~= profile_limit then
    return string.format("%s has %d words, more than bmj.%s (%d)", what, n, option, limit)
  end
  local p = opts.profile
  return string.format("%s has %d words; %s asks for %s", what, n, p.name,
    guidance or string.format("no more than %d words for %s", limit, p.label))
end

local pass_setup = {
  Pandoc = function(doc)
    read_options(doc.meta)
    local p = opts.profile
    local counted = with_rendered_citations(doc)
    stats.main = count_words(main_text_blocks(counted.blocks))
    if opts.word_limit and stats.main > opts.word_limit then
      warn(limit_message("main text", stats.main, opts.word_limit, "word-limit", p["word-limit"]))
    end
    if doc.meta.abstract ~= nil then
      local abstract = to_blocks(doc.meta.abstract)
      stats.abstract = count_words(to_blocks(counted.meta.abstract or doc.meta.abstract))
      if opts.abstract_limit and stats.abstract > opts.abstract_limit then
        warn(limit_message("abstract", stats.abstract, opts.abstract_limit, "abstract-word-limit",
          p["abstract-word-limit"], p["abstract-guidance"]))
      end
      if has_cite(abstract) then
        warn("BMJ: references should not be included in the abstract")
      end
    end
    return nil
  end,
}

-- ---------------------------------------------------------------------------
-- Pass 2: figures as separate files + legends at the end
-- ---------------------------------------------------------------------------

local function caption_inlines(caption)
  if caption == nil then
    return pandoc.Inlines({})
  end
  local t = pandoc.utils.type(caption)
  if t == "Inlines" then
    return caption
  elseif t == "Block" then
    return caption.content or pandoc.Inlines({})
  elseif t == "Blocks" or t == "List" then
    return pandoc.utils.blocks_to_inlines(caption)
  end
  return pandoc.Inlines(stringify(caption))
end

local function input_dir()
  local input = quarto.doc.input_file
  if input then
    return pandoc.path.directory(input)
  end
  return pandoc.system.get_working_directory()
end

local function figure_dir()
  if opts.figure_dir then
    if pandoc.path.is_absolute(opts.figure_dir) then
      return opts.figure_dir
    end
    return pandoc.path.join({ input_dir(), opts.figure_dir })
  end
  local stem = "manuscript"
  if quarto.doc.input_file then
    stem = pandoc.path.split_extension(pandoc.path.filename(quarto.doc.input_file))
  end
  return pandoc.path.join({ input_dir(), stem .. "-figures" })
end

local accepted_ext = { tif = true, tiff = true, eps = true, jpg = true, jpeg = true, pdf = true }

local function export_image(src, number, suffix)
  if src:match("^%a[%w+.-]*://") or src:match("^data:") then
    warn("figure " .. number .. ": remote/embedded image '" .. src .. "' was not exported")
    return
  end
  local candidates = { src }
  if not pandoc.path.is_absolute(src) then
    table.insert(candidates, pandoc.path.join({ input_dir(), src }))
  end
  local data
  for _, path in ipairs(candidates) do
    data = read_file(path)
    if data then
      break
    end
  end
  if not data then
    -- the image may live in Pandoc's media bag (e.g. fetched resources)
    local _, contents = pandoc.mediabag.lookup(src)
    data = contents
  end
  if not data then
    warn("figure " .. number .. ": could not read image '" .. src .. "'")
    return
  end
  local _, ext = pandoc.path.split_extension(src)
  ext = (ext or ""):gsub("^%.", ""):lower()
  local dir = figure_dir()
  pandoc.system.make_directory(dir, true)
  local name = "figure-" .. number .. suffix .. (ext ~= "" and ("." .. ext) or "")
  local out = io.open(pandoc.path.join({ dir, name }), "wb")
  if not out then
    warn("figure " .. number .. ": could not write " .. name)
    return
  end
  out:write(data)
  out:close()
  if not accepted_ext[ext] then
    warn(string.format(
      "figure %s exported as .%s; BMJ accepts TIFF, EPS, JPEG or PDF (300 dpi minimum, 1200 dpi for line art)",
      number, ext))
  end
end

--- Word: Quarto wraps captioned tables in an outer layout table. BMJ wants
--- plain Word tables, so emit "Table N Caption" followed by the table itself.
local function flatten_docx_table(float)
  local number = float.order and float.order.order
  if number == nil then
    return nil
  end
  local caption = pandoc.Inlines({
    pandoc.Strong(pandoc.Inlines(opts.tbl_title .. " " .. tostring(number))),
    pandoc.Space(),
  })
  caption:extend(caption_inlines(float.caption_long))
  local blocks = pandoc.Blocks({ styled({ pandoc.Para(caption) }, "Table Caption") })
  local content = float.content
  if pandoc.utils.type(content) == "Block" then
    blocks:insert(content)
  else
    blocks:extend(content)
  end
  return pandoc.Div(blocks, pandoc.Attr(float.identifier or ""))
end

local pass_figures = {
  FloatRefTarget = function(float)
    if float.type == "Table" and float.parent_id == nil and is_docx() and opts.flatten_tables then
      return flatten_docx_table(float)
    end
    if opts.figures ~= "separate" or float.type ~= "Figure" or float.parent_id ~= nil then
      return nil
    end
    local number = float.order and float.order.order
    if number == nil then
      -- unlabelled figure: no cross-reference number, keep it in place
      warn("unlabelled figure left in the body; give it an id such as {#fig-name} to move it to the legends")
      return nil
    end
    number = tostring(number)

    -- collect images and sub-figure captions
    local images = pandoc.List()
    local subcaps = pandoc.List()
    local walker = {
      Image = function(img)
        images:insert(img.src)
      end,
      FloatRefTarget = function(sub)
        subcaps:insert(caption_inlines(sub.caption_long))
      end,
    }
    quarto._quarto.ast.walk(float.content, walker)

    if opts.export_figures then
      if #images > 1 then
        warn("figure " .. number .. " has " .. #images
          .. " parts; BMJ requires multi-part figures as a single composite file")
      end
      for i, src in ipairs(images) do
        local suffix = (#images > 1) and string.char(96 + i) or ""
        export_image(src, number, suffix)
      end
    end

    local legend = pandoc.Inlines({ pandoc.Strong(pandoc.Inlines(opts.fig_title .. " " .. number)), pandoc.Space() })
    legend:extend(caption_inlines(float.caption_long))
    local first_sub = true
    for i, sc in ipairs(subcaps) do
      if #sc > 0 then
        if not first_sub then
          legend:insert(pandoc.Str(";"))
        end
        first_sub = false
        legend:extend({ pandoc.Space(), pandoc.Str("(" .. string.char(96 + i) .. ")"), pandoc.Space() })
        legend:extend(sc)
      end
    end
    legends:insert(pandoc.Para(legend))
    if float.identifier and float.identifier ~= "" then
      removed_figure_ids[float.identifier] = true
    end
    return {}
  end,
}

-- Cross-references to removed figures would point to missing anchors.
local pass_links = {
  Link = function(link)
    local target = link.target:match("^#(.+)$")
    if target and removed_figure_ids[target] then
      return link.content
    end
    return nil
  end,
}

-- ---------------------------------------------------------------------------
-- Pass 3: title page, abstract, summary box, legends
-- ---------------------------------------------------------------------------

local function author_name(a)
  if a.name == nil then
    return pandoc.Inlines({})
  end
  if a.name.literal ~= nil then
    return to_inlines(a.name.literal)
  end
  return to_inlines(a.name)
end

local function format_affiliation(af)
  local parts = pandoc.List()
  for _, key in ipairs({ "department", "name", "address", "city", "region", "postal-code", "country" }) do
    if nonempty(af[key]) then
      parts:insert(stringify(af[key]))
    end
  end
  return table.concat(parts, ", ")
end

local function author_position(a)
  local m = a.metadata
  if m then
    for _, key in ipairs({ "position", "job-title", "degrees" }) do
      if nonempty(m[key]) then
        return stringify(m[key])
      end
    end
  end
  return nil
end

local function author_attr(a, key)
  return a.attributes and meta_bool(a.attributes[key], false)
end

local function build_title_page(meta)
  local authors = meta["by-author"] or {}
  local affiliations = meta["by-affiliation"] or {}
  local blocks = pandoc.Blocks({})
  if #authors == 0 then
    return blocks
  end

  local any_equal = false
  local corresponding = pandoc.List()

  -- Author line: Name<sup>1,2</sup> (ORCID), ...
  local line = pandoc.Inlines({})
  for i, a in ipairs(authors) do
    if i > 1 then
      line:extend({ pandoc.Str(","), pandoc.Space() })
    end
    line:extend(author_name(a))
    local marks = {}
    for _, af in ipairs(a.affiliations or {}) do
      if nonempty(af.number) then
        table.insert(marks, stringify(af.number))
      end
    end
    if author_attr(a, "equal-contributor") then
      any_equal = true
      table.insert(marks, "*")
    end
    if #marks > 0 then
      line:insert(pandoc.Superscript(pandoc.Inlines(table.concat(marks, ","))))
    end
    if nonempty(a.orcid) then
      line:extend({ pandoc.Space(), pandoc.Str("(" .. stringify(a.orcid) .. ")") })
    end
    if author_attr(a, "corresponding") then
      corresponding:insert(a)
    end
  end
  local front = pandoc.Blocks({ pandoc.Para(line) })
  if any_equal then
    front:insert(pandoc.Para({ pandoc.Superscript("*"), pandoc.Str("Joint"), pandoc.Space(),
      pandoc.Str("first"), pandoc.Space(), pandoc.Str("authors") }))
  end

  -- Addresses, each followed by the authors (and job titles) at that address
  for _, af in ipairs(affiliations) do
    local inl = pandoc.Inlines({})
    if nonempty(af.number) then
      inl:insert(pandoc.Superscript(pandoc.Inlines(stringify(af.number))))
    end
    inl:extend(pandoc.Inlines(format_affiliation(af)))
    for _, a in ipairs(authors) do
      for _, aaf in ipairs(a.affiliations or {}) do
        if stringify(aaf.id or "") == stringify(af.id or "") then
          inl:insert(pandoc.LineBreak())
          inl:extend(author_name(a))
          local pos = author_position(a)
          if pos then
            inl:extend({ pandoc.Str(","), pandoc.Space() })
            inl:extend(pandoc.Inlines(pos))
          end
          break
        end
      end
    end
    front:insert(pandoc.Para(inl))
  end

  -- Corresponding author(s)
  local p = opts.profile
  if #corresponding == 0 then
    warn("no corresponding author; mark one author with 'corresponding: true'")
  else
    if #corresponding > 1 and p["single-corresponding"] then
      warn(p.name .. " allows only one corresponding author; using the first")
      corresponding = pandoc.List({ corresponding[1] })
    end
    for _, c in ipairs(corresponding) do
      local inl = pandoc.Inlines({ pandoc.Strong(pandoc.Inlines("Correspondence to:")), pandoc.Space() })
      inl:extend(author_name(c))
      local first_aff = c.affiliations and c.affiliations[1]
      if first_aff then
        inl:extend({ pandoc.Str(","), pandoc.Space() })
        inl:extend(pandoc.Inlines(format_affiliation(first_aff)))
      end
      if nonempty(c.email) then
        inl:extend({ pandoc.Str(";"), pandoc.Space(), pandoc.Str(stringify(c.email)) })
      else
        warn("the corresponding author has no email address")
      end
      if p["orcid-corresponding"] and not nonempty(c.orcid) then
        warn(p.name .. " requires an ORCID iD for the corresponding author of " .. p.label)
      end
      front:insert(pandoc.Para(inl))
    end
  end

  -- Keywords, date, word counts
  if meta.keywords ~= nil then
    local kw = pandoc.Inlines({ pandoc.Strong(pandoc.Inlines("Keywords:")), pandoc.Space() })
    for i, k in ipairs(as_list(meta.keywords)) do
      if i > 1 then
        kw:extend({ pandoc.Str(";"), pandoc.Space() })
      end
      kw:extend(to_inlines(k))
    end
    front:insert(pandoc.Para(kw))
  end
  if nonempty(meta.date) then
    local d = pandoc.Inlines({ pandoc.Strong(pandoc.Inlines("Date:")), pandoc.Space() })
    d:extend(to_inlines(meta.date))
    front:insert(pandoc.Para(d))
  end
  if opts.word_count and stats.main then
    local text = string.format("%d (main text, excluding abstract, references, tables, boxes and figures)",
      stats.main)
    if stats.abstract then
      text = text .. string.format("; abstract %d", stats.abstract)
    end
    local wc = pandoc.Inlines({ pandoc.Strong(pandoc.Inlines("Word count:")), pandoc.Space() })
    wc:extend(pandoc.Inlines(text))
    front:insert(pandoc.Para(wc))
  end

  blocks:insert(styled(front, "BMJ Front Matter"))
  return blocks
end

local function box_heading(text)
  local title = pandoc.Para({ pandoc.Strong(pandoc.Inlines(text)) })
  if is_docx() then
    return styled({ title }, "BMJ Box Heading")
  end
  return title
end

local function box_bullets(items)
  if is_docx() then
    -- Word joins adjacent paragraphs with identical borders into one
    -- box, but Pandoc list items do not take a custom paragraph style,
    -- so write the bullets as plain paragraphs.
    local out = pandoc.Blocks({})
    for _, item in ipairs(items) do
      local inl = pandoc.Inlines({ pandoc.Str("\u{2022}"), pandoc.Space() })
      inl:extend(to_inlines(item))
      out:insert(pandoc.Para(inl))
    end
    return out
  end
  local list_items = pandoc.List()
  for _, item in ipairs(items) do
    list_items:insert({ pandoc.Plain(to_inlines(item)) })
  end
  return pandoc.Blocks({ pandoc.BulletList(list_items) })
end

local function is_map(v)
  return type(v) == "table" and pandoc.utils.type(v) ~= "List"
    and pandoc.utils.type(v) ~= "Inlines" and pandoc.utils.type(v) ~= "Blocks"
end

--- Contents of the profile's box: one bullet list per section, or a single
--- bullet list when the box has no sections.
local function box_content(box, value)
  local p = opts.profile
  local inner = pandoc.Blocks({})
  if #box.sections == 0 then
    if is_map(value) then
      warn(string.format("%s should be a list of bullets for %s %s; ignored", box.key, p.name, p.label))
      return inner
    end
    local items = as_list(value)
    if #items > 0 then
      inner:extend(box_bullets(items))
    end
    return inner
  end

  if not is_map(value) then
    local names = {}
    for _, s in ipairs(box.sections) do
      table.insert(names, s.key)
    end
    warn(string.format("%s should have the sections %s for %s %s; ignored",
      box.key, table.concat(names, ", "), p.name, p.label))
    return inner
  end
  local known = {}
  for _, s in ipairs(box.sections) do
    known[s.key] = true
    local items = as_list(value[s.key])
    if #items > 0 then
      inner:insert(box_heading(s.title))
      inner:extend(box_bullets(items))
    end
  end
  for _, key in ipairs(sorted_keys(value)) do
    if not known[key] then
      warn(string.format("%s.%s is ignored: the box for %s %s has no section '%s'",
        box.key, key, p.name, p.label, key))
    end
  end
  return inner
end

local function summary_box(meta)
  local box = opts.box
  if box == nil then
    if meta["summary-box"] ~= nil then
      warn(string.format("%s %s have no summary box; summary-box is ignored",
        opts.profile.name, opts.profile.label))
    end
    return nil
  end
  local value = meta[box.key]
  if value == nil then
    return nil
  end
  local inner = box_content(box, value)
  if #inner == 0 then
    return nil
  end
  if box.title then
    inner:insert(1, box_heading(box.title))
  end
  if is_docx() then
    return styled(inner, "BMJ Box")
  elseif is_latex() then
    local out = pandoc.Blocks({ pandoc.RawBlock("latex", "\\begin{bmjbox}") })
    out:extend(inner)
    out:insert(pandoc.RawBlock("latex", "\\end{bmjbox}"))
    return pandoc.Div(out, pandoc.Attr("", { "summary-box" }))
  end
  return pandoc.Div(inner, pandoc.Attr("", { "summary-box" }))
end

--- Replace an empty placeholder div (by id) with `content`; true if found.
local function fill_placeholder(blocks, id, content)
  local found = false
  local doc = pandoc.Pandoc(blocks):walk({
    Div = function(div)
      if div.identifier == id then
        found = true
        return content
      end
    end,
  })
  return found, doc.blocks
end

local pass_assemble = {
  Pandoc = function(doc)
    local meta = doc.meta
    local body = doc.blocks
    local head = pandoc.Blocks({})

    if opts.title_page then
      head:extend(build_title_page(meta))
    end

    -- Abstract (moved into the body together with the title page; otherwise
    -- the format's own title block shows it)
    if opts.title_page and meta.abstract ~= nil then
      if opts.page_breaks and #head > 0 then
        head:insert(page_break())
      end
      head:insert(unnumbered_header(1, opts.abstract_title, "abstract"))
      head:extend(to_blocks(meta.abstract))
    end

    -- Summary box: at the placeholder if present, otherwise after the abstract
    local box = summary_box(meta)
    if box then
      local found
      found, body = fill_placeholder(body, "bmj-summary-box", { box })
      if not found then
        head:insert(box)
      end
    end

    if opts.page_breaks and #head > 0 then
      head:insert(page_break())
    end

    -- Figure legends: at the placeholder if present, otherwise at the end
    if #legends > 0 then
      local section = pandoc.Blocks({ unnumbered_header(1, "Figure legends", "figure-legends") })
      section:extend(legends)
      local found
      found, body = fill_placeholder(body, "bmj-figure-legends", section)
      if not found then
        if opts.page_breaks then
          body:insert(page_break())
        end
        body:extend(section)
      end
    else
      local _
      _, body = fill_placeholder(body, "bmj-figure-legends", {})
    end

    head:extend(body)
    doc.blocks = head

    -- The title page now lives in the body; stop writers duplicating it.
    if opts.title_page then
      meta.abstract = nil
      meta.author = nil
      meta.date = nil
    end
    doc.meta = meta

    if opts.word_count and stats.main then
      quarto.log.output(string.format("[bmj] word count: main text %d%s", stats.main,
        stats.abstract and string.format(", abstract %d", stats.abstract) or ""))
    end
    return doc
  end,
}

return {
  pass_setup,
  pass_figures,
  pass_links,
  pass_assemble,
}
