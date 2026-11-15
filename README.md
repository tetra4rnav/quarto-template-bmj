# BMJ format for Quarto

A [Quarto](https://quarto.org) journal format for preparing manuscripts for
*The BMJ* and other BMJ journals.

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
| Structured abstract with no references, 250-300 words | Moved to the start of the body as an **ABSTRACT** section (Word and PDF). The filter warns about citations in the abstract or a word count over the limit |
| Manuscripts show results, not code | Code is hidden by default (`echo: false`) |
| "What is already known on this topic / What this study adds" box | Built from `summary-box` metadata as a bordered box |
| Word count for the main text, excluding abstract, references, tables, boxes and figures | Shown on the title page and printed in the render log |
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

The format warns when there is no corresponding author, more than one, or
when the corresponding author has no email address or ORCID iD. The BMJ
requires an ORCID iD for the corresponding author of research articles.

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
  figures: separate          # separate (docx default) | inline (pdf and html default)
  export-figures: true       # copy figure files for upload
  figure-dir: my-figures     # default: <document-name>-figures
  flatten-tables: true       # docx: plain tables instead of Quarto's layout table
  word-count: true           # show the word count on the title page
  abstract-word-limit: 300   # warn above this many words
  page-breaks: true          # docx/pdf default; page breaks after the title page and abstract
  title-page: true           # docx/pdf default; html uses Quarto's title block
```

### Word count

The count covers headings and paragraphs of the main text up to the
reference list. It leaves out the abstract, tables, figures, captions, code,
citations, footnotes, the summary box and `.bmj-statements`. Treat it as a
close estimate of Word's own count.

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

The template follows the general BMJ Author Hub guidance and the research
article requirements of *The BMJ*. Other BMJ journals, such as *BMJ Open* and
*BMJ Case Reports*, have different article types, abstract headings and boxes.
Adjust the abstract headings, the summary box and the statements to match the
journal's instructions for authors. *BMJ Case Reports* requires its own Word
template.

## License

The code and template are released under the [MIT License](LICENSE).

`_extensions/bmj/bmj.csl` is the BMJ style from the
[Citation Style Language styles repository](https://github.com/citation-style-language/styles).
It is licensed under
[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/), and its
authors are listed in the file.
