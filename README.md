# BMJ format for Quarto

A [Quarto](https://quarto.org) journal format for preparing manuscripts for
*The BMJ* and other BMJ journals. Journal profiles set each journal's word
limits, summary box and author rules; in v0.4.0, profiles are included for
*The BMJ* and *BMJ Global Health*. More BMJ journals profiles will be added in  
future releases, or you can create your own.

The format provides three outputs:

| Format | Purpose |
|---|---|
| `bmj-pdf` | Preview with line numbers and double spacing, for proofreading with co-authors |
| `bmj-html` | Online preview, using Quarto's title block, a table of contents and links to the other formats |
| `bmj-docx` | **Submission file.** BMJ only accepts manuscripts as Word documents |

**Preview:** <https://tetra4rnav.github.io/quarto-template-bmj/> shows `template.qmd`
rendered as HTML, with links to the PDF and Word versions.

> [!IMPORTANT]
> This is an unofficial community template. It is not affiliated with or
> endorsed by BMJ. Requirements change, and each BMJ journal has its own
> instructions for authors, so check the current guidance before you submit:
> [BMJ Author Hub: Formatting your paper](https://authors.bmj.com/writing-and-formatting/formatting-your-paper/)
> and [The BMJ: Article types and preparation](https://www.bmj.com/about-bmj/resources-authors/article-types).

## What the format does

| BMJ requirement | How the format handles it |
|---|---|
| Submit a Word document; PDF is not accepted | `bmj-docx` writes a .docx based on a BMJ-style reference document |
| Heading hierarchy: **BOLD CAPS**, **bold lower case**, plain text, *italics* | Word styles Heading 1 to 4 follow this order, and so do the LaTeX and HTML headings |
| Title page: authors with ORCID iDs, addresses with job titles, a single corresponding author with full address and email | Built from Quarto's standard `author` / `affiliations` metadata (Word and PDF). HTML uses Quarto's title block |
| Structured abstract with no references, 250-300 words | Moved to the start of the body as an **ABSTRACT** section (Word and PDF). The filter warns about citations in the abstract or a word count over the journal's limit |
| Manuscripts show results, not code | Code is hidden by default (`echo: false`) |
| "What is already known on this topic / What this study adds" box | Built from `summary-box` metadata as a bordered box, with the headings of the selected [journal profile](#journal-profiles) |
| Word count for the main text, excluding abstract, references, tables, boxes and figures | Shown on the title page and printed in the render log. The filter warns when the count is over the journal's limit |
| Figures uploaded as separate files, with legends at the end of the manuscript | Figures are removed from the .docx, copied to `<name>-figures/figure-N.ext` and listed under **FIGURE LEGENDS** |
| Tables in Word format, placed where first cited | Plain Word tables, with captions written as "**Table 1** Caption" |
| Vancouver references, numbered in order of citation, in square brackets | BMJ CSL style (`[1]`, `[2-4]`) |
| Line and page numbers to help reviewers and reporting checklists | Continuous line numbers, page numbers in the footer, double spacing, A4 paper |
| Required statements (contributors and guarantor, funding, competing interests, ethics, data sharing, transparency, dissemination, licence) | Provided in `template.qmd` with BMJ wording to complete |

## Installation

To start a new manuscript from this template:

```bash
quarto use template tetra4rnav/quarto-template-bmj
```

To add the format to an existing document or project:

```bash
quarto add tetra4rnav/quarto-template-bmj
```

Requirements:

- Quarto 1.7.24 or later.
- For `bmj-pdf`, a TeX distribution such as TinyTeX (`quarto install tinytex`).

## Usage

```yaml
---
title: "Title of the article: a prospective cohort study"
format:
  bmj-pdf: default    # preview with line numbers
  bmj-html: default   # online preview
  bmj-docx: default   # submission file (BMJ only accepts Word)
---
```

`quarto render manuscript.qmd` renders all three. To render only one:

```bash
quarto render manuscript.qmd --to bmj-docx
```

Code chunks are hidden by default. Set `echo: true` in a chunk or in the
document to show code.

### Journal profiles

A journal profile holds the rules that differ between BMJ journals and
article types: the abstract and main-text word limits, the summary box, and
the corresponding-author and ORCID rules. Select one with `journal` and
`article-type` under the `bmj` key. Without them, the format uses *The BMJ*
research article profile.

```yaml
bmj:
  journal: bmj-global-health
  article-type: global-health-in-practice
```

| `journal` | `article-type` | Abstract limit | Main-text limit | Summary box | Checked |
|---|---|---|---|---|---|
| `the-bmj` (default) | `research` (default) | 300 | none | `known`, `adds` | 2026-11-16 |
| `bmj-global-health` | `research` (default; original research) | 300 | 5000 | `known`, `adds`, `implications` | 2026-11-16 |
| | `global-health-in-practice` | 250 | 1500 | list of key messages | 2026-11-16 |
| | `editorial` | none | 1500 | none | 2026-11-16 |
| | `commentary` | none | 1500 | list of key messages | 2026-11-16 |

The filter warns when the abstract or the main text is over its limit.
**Checked** is the date the values were last checked against the journal's
author guidelines, whose URL is the `source` of each article type in
`_extensions/bmj/journals/`. Requirements change, so check the journal's
current instructions for authors before you submit.

An unknown `journal` or `article-type` gives a warning, and the format falls
back to the default profile or article type.

To change a profile value for one document, set it under `bmj`:

```yaml
bmj:
  journal: bmj-global-health
  word-limit: 6000             # e.g. the editor agreed to a longer paper
  abstract-word-limit: 400
  box-title: Key messages      # heading at the top of the summary box
  box-headings:                # section headings, keyed by section
    known: What is already known
```

### Authors and affiliations

Use Quarto's standard [author schema](https://quarto.org/docs/journals/authors.html).
The format also reads a `position` field for the job title that BMJ asks for.

```yaml
author:
  - name: Jane Doe
    orcid: 0000-0002-1825-0097
    email: jane.doe@example.org
    corresponding: true            # exactly one corresponding author
    position: senior lecturer      # job title, shown under the address
    affiliations:
      - id: epi
        department: Department of Epidemiology
        name: Example University
        address: 1 Example Street
        city: London
        postal-code: WC1E 0AA
        country: UK
  - name: John Smith
    position: statistician
    attributes:
      equal-contributor: true      # marks joint first authors with *
    affiliations:
      - ref: epi
```

The format warns when there is no corresponding author or when the
corresponding author has no email address. Depending on the
[journal profile](#journal-profiles), it also warns about more than one
corresponding author and about a corresponding author without an ORCID iD.
The BMJ allows one corresponding author and requires an ORCID iD for the
corresponding author of research articles.

### Abstract, keywords and summary box

```yaml
abstract: |
  **Objectives** ...

  **Design** ...

  **Setting** ...

  **Participants** ...

  **Interventions** ...

  **Main outcome measures** ...

  **Results** ...

  **Conclusions** ...

  **Trial registration** ...
keywords:            # MeSH descriptors
  - Cohort Studies
  - Primary Health Care
summary-box:
  known:             # 2-3 single-sentence bullets
    - ...
  adds:              # 1-2 single-sentence bullets
    - ...
```

The sections of `summary-box` depend on the
[journal profile](#journal-profiles). *BMJ Global Health* original research
adds a third section, `implications` ("How this study might affect research,
practice or policy"). For *BMJ Global Health* practice articles and
commentaries, `summary-box` is a plain list of key messages:

```yaml
summary-box:         # BMJ Global Health: global-health-in-practice, commentary
  - ...              # 3-4 single-sentence key messages
```

The filter warns about sections the profile does not have and about a
`summary-box` for an article type without one.

By default the summary box goes directly after the abstract. To put it
somewhere else, add an empty placeholder div where you want it:

```markdown
::: {#bmj-summary-box}
:::
```

### Required statements

Put the end-of-manuscript statements inside a `.bmj-statements` div. Text
inside this div is left out of the word count. See `template.qmd` for the
BMJ wording of the competing interests, transparency and licence statements.

```markdown
::: {.bmj-statements}
**Contributors:** ... JD is the guarantor. The corresponding author attests that ...

**Funding:** ...
:::

# References

::: {#refs}
:::
```

You can also add the class `.no-wordcount` to any other div to leave it out of
the word count.

### Figures

BMJ asks for figures as separate high-resolution files: TIFF, EPS, JPEG or
PDF, at least 300 dpi, or 1200 dpi for line art. A multi-part figure must be a
single composite file. With `bmj-docx` (the default `bmj.figures: separate`),
each labelled figure (`{#fig-...}`) is handled as follows:

1. It is removed from the body of the Word document. Cross-references such as

   `@fig-flow` still read "Figure 1".
2. Its image file is copied to `<document-name>-figures/figure-1.pdf` (or

   `figure-1a.png`, `figure-1b.png` and so on for multi-part figures) for
    upload.
3. Its caption is listed under **FIGURE LEGENDS** at the end of the

   manuscript, or at a `::: {#bmj-figure-legends}` placeholder if you add one.

The filter warns about formats BMJ does not accept, such as PNG, and about
multi-part figures. Computed figures (R, Python) are written as vector PDF for
`bmj-docx` (`fig-format: pdf`), so the exported files can be uploaded as they
are.

To keep figures in the text, for example for a co-author draft, set
`bmj.figures: inline` together with `fig-format: png`. Word cannot display
PDF images.

**Figures in all three formats.** Refer to a static figure without a file
extension, as `template.qmd` does with `![...](figures/participant-flow)`.
Then provide `participant-flow.pdf` (used by `bmj-pdf` and `bmj-docx`) and
`participant-flow.svg` (used by `bmj-html`). Each format picks its file
through `default-image-extension`.

### Options

All options are optional and go under the `bmj` key:

```yaml
bmj:
  journal: the-bmj           # journal profile; see "Journal profiles"
  article-type: research     # article type within the profile
  word-limit: 4000           # warn above this many words in the main text (default: profile)
  abstract-word-limit: 300   # warn above this many words in the abstract (default: profile)
  box-title: Key messages    # heading at the top of the summary box (default: profile)
  box-headings:              # summary box section headings (default: profile)
    known: What is already known
  figures: separate          # separate (docx default) | inline (pdf and html default)
  export-figures: true       # copy figure files for upload
  figure-dir: my-figures     # default: <document-name>-figures
  flatten-tables: true       # docx: plain tables instead of Quarto's layout table
  word-count: true           # show the word count on the title page
  page-breaks: true          # docx/pdf default; page breaks after the title page and abstract
  title-page: true           # docx/pdf default; html uses Quarto's title block
```

To set an option for one format only, put the `bmj` key under that format.
Format-level values take precedence over the top-level `bmj` key, and the two
are merged key by key:

```yaml
bmj:
  word-count: false          # all formats
format:
  bmj-pdf: default
  bmj-docx:
    fig-format: png
    bmj:
      figures: inline        # Word only: keep figures in the text
```

### Word count

The main-text count starts at the beginning of the body and stops at the
first of these: the reference list (`::: {#refs}`), a heading with the id
`references`, or a heading with the class `.appendix`. The abstract is counted
separately. The filter warns when a count is over the journal profile's limit
or your own (`word-limit`, `abstract-word-limit`).

| Counted | Not counted |
|---|---|
| Headings | Title page |
| Paragraphs, lists and block quotes | Abstract (counted separately) |
| Citations, as they appear in the output ("[1]") | Summary box |
| Cross-references, as they appear in the output ("Figure 1") | Reference list, and anything after it or after an `.appendix` heading |
| | Tables and their captions |
| | Figures and their captions |
| | Statements in a `.bmj-statements` div (acknowledgements, contributors, funding, competing interests and so on) |
| | Any div with the class `.no-wordcount` |
| | Footnotes |
| | Superscript text |
| | Equations |
| | Code, inline and in blocks |
| | Raw TeX or HTML |

Words are counted as Microsoft Word counts them, so the result matches Word's
count of the same text in the .docx:

- Words are separated by spaces, including no-break spaces, and by en and em
dashes, so "15–27" is two words.
- A run of punctuation on its own, such as "-" or "&", is a word.
- Citations count as they appear in the output: "[1]" is one word and
"[2–4]" is two. Without a bibliography, each citation counts as one word.
- Cross-references count as the text they show, so "Figure 1" is two words
in every format.

Word counts each Chinese, Japanese or Korean character as a word; the filter
does not, as manuscripts are written in English.

## Editor support (Quarto Wizard)

The extension ships `_extensions/bmj/_schema.yml` and
`_extensions/bmj/_snippets.json` for
[Quarto Wizard](https://m.canouil.dev/quarto-wizard/), which adds completion,
validation and hover documentation in VS Code and Positron.

- **Schema:** the `bmj` options are described for `bmj-pdf`, `bmj-html` and
`bmj-docx`, with each format's own defaults. Completion and validation apply
when you write the options under a format (`format: bmj-docx: bmj: ...`).
A top-level `bmj` key still works but is not checked by the editor.
- **Snippets:** type the prefix in a Quarto document, or insert a snippet
from the Quarto Wizard explorer. Quarto Wizard shows the prefixes as
`tetra4rnav-bmj:<prefix>`.

| Prefix | Inserts |
|---|---|
| `front-matter` | Complete YAML header: title, author, structured abstract, keywords, summary box and the three formats |
| `author` | One author entry with ORCID, email, job title and affiliation |
| `abstract` | Structured abstract headings |
| `summary-box` | "What is already known / What this study adds" metadata |
| `summary-box-global-health` | *BMJ Global Health* research summary box (`known`, `adds`, `implications`) |
| `key-messages` | Summary box as a plain list of key messages |
| `journal` | `journal` and `article-type`, with the word-limit overrides commented out |
| `options` | The `bmj` options block |
| `statements` | `.bmj-statements` div with the required statements, then the reference list |
| `summary-box-placeholder` | `::: {#bmj-summary-box}` placeholder |
| `figure-legends-placeholder` | `::: {#bmj-figure-legends}` placeholder |
| `figure` | Labelled figure without a file extension |

## Customising the Word styles

`_extensions/bmj/bmj-reference.docx` is generated from Pandoc's default
reference document by `scripts/build-reference-docx.py`. It uses 12 pt Times
New Roman, double spacing, A4 paper with 2.54 cm margins, line numbers and a
page-number footer. To change it, edit the script and run:

```bash
python scripts/build-reference-docx.py
```

The HTML styles are in `_extensions/bmj/bmj.scss`. The example flow diagram in
`figures/` (PDF and SVG) is produced by `scripts/make-example-figure.py`.

## Preview site (GitHub Pages)

`.github/workflows/publish.yml` renders `template.qmd` with Quarto 1.7.24 (the
minimum version) and with the current release. On pushes to `main`, it
publishes the HTML, PDF and Word output to GitHub Pages. To enable this in a
fork, go to **Settings > Pages** and set **Source** to **GitHub Actions**.

## Other BMJ journals

The template follows the general BMJ Author Hub guidance, and its
[journal profiles](#journal-profiles) cover *The BMJ* (research articles) and
*BMJ Global Health*. For a journal without a profile, such as *BMJ Open*,
choose the closest profile, override its limits and box headings, and adjust
the abstract headings and the statements to match the journal's instructions
for authors. *BMJ Case Reports* requires its own Word template.

The profiles check word limits, the summary box and the corresponding-author
rules only. Other requirements, such as limits on tables, figures and
references, abstract headings and required statements, are not checked.

### Adding a journal

A journal profile is a YAML file in `_extensions/bmj/journals/`. Adding a
journal needs no change to `bmj.lua`.

1. Copy `_extensions/bmj/journals/the-bmj.yml` to

   `_extensions/bmj/journals/<journal>.yml`. The file name, without `.yml`,
    is the value of `bmj.journal`. Use lower-case letters, digits and hyphens
    only; the filter does not read other names.
2. Fill in the fields described below from the journal's instructions for

   authors. Write every value out in full: profiles do not inherit from each
    other, even where journals share a rule.
3. In `_extensions/bmj/_schema.yml`, add the journal to the `journal` enum

   under `bmj-pdf`, and any new article types to the `article-type` enum.
    `bmj-html` and `bmj-docx` refer to the same definitions, so one edit
    covers all three formats. For a new box section, add its key under
    `box-headings` too, so that editors offer it.
4. Render a test document with `bmj: journal: <journal>` and each

   `article-type`. Check that the warnings name the journal and that the
    summary box has the expected headings. A mistake in a profile stops the
    render with a message that names the file and the field.
5. Add the journal to the table under [Journal profiles](#journal-profiles),

   with the date you checked the values against the author guidelines in the
    **Checked** column. Record the date there, not in the profile file. When
    you recheck a profile later, update its date.

Fields of a profile file:

```yaml
name: BMJ Global Health          # display name used in messages
default-article-type: research   # used when bmj.article-type is not set

article-types:                   # one entry per value of bmj.article-type
  research:
    label: original research articles  # plural noun used in messages
    source: https://...          # URL of the author guidelines
    abstract-word-limit: 300     # optional; omit for no abstract check
    abstract-guidance: ...       # optional; replaces "no more than N words"
                                 # in the abstract warning
    word-limit: 5000             # optional; omit for no main-text limit
    single-corresponding: false  # true: warn about more than one
                                 # corresponding author and show only the first
    orcid-corresponding: false   # true: warn when a corresponding author
                                 # has no ORCID iD
    box:                         # optional; omit for no summary box
      key: summary-box           # metadata key that holds the box content
      title: ...                 # optional heading at the top of the box
      sections:                  # optional; each section is a list of bullets
        - key: known             #   under summary-box.known, and so on
          title: What is already known on this topic
```

Without `sections`, the box's metadata key holds a plain list of bullets.
Write strings that contain a colon in quotes.

## License

The code and template are released under the [MIT License](LICENSE).

`_extensions/bmj/bmj.csl` is the BMJ style from the
[Citation Style Language styles repository](https://github.com/citation-style-language/styles).
It is licensed under
[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/), and its
authors are listed in the file.
