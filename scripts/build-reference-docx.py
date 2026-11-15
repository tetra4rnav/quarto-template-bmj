#!/usr/bin/env python3
"""Build the Word reference document used by the `bmj-docx` format.

The file is derived from Pandoc's default ``reference.docx`` so that every
style Pandoc relies on is present. The script then adjusts the styles to
match BMJ manuscript conventions:

* Heading hierarchy "BOLD CAPS, bold lower case, Plain text, Italics"
  (BMJ Author Hub, "Formatting your paper").
* 12 pt Times New Roman, double line spacing, A4, 2.54 cm margins.
* Continuous line numbers and a centred page number in the footer, so that
  reporting-guideline checklists can refer to page/line numbers.
* A bordered ``BMJ Box`` paragraph style for the "What is already known on
  this topic / What this study adds" summary box.

Usage (from the repository root)::

    python scripts/build-reference-docx.py

Requires Quarto (for its bundled Pandoc) on the PATH.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "_extensions" / "bmj" / "bmj-reference.docx"

FONT = "Times New Roman"
SIZE = 24  # half-points -> 12 pt
LINE_DOUBLE = 480  # 240 = single

RFONTS = (
    f'<w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}" '
    'w:eastAsiaTheme="minorEastAsia" />'
)

# styleId -> (pPr inner xml, rPr inner xml). ``None`` leaves the part as is.
STYLES: dict[str, tuple[str | None, str | None]] = {
    "BodyText": ('<w:spacing w:before="0" w:after="240" />', ""),
    "FirstParagraph": (None, None),
    "Compact": ('<w:spacing w:before="0" w:after="0" />', None),
    "Title": (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="0" w:after="240" />',
        '<w:b /><w:bCs /><w:sz w:val="28" /><w:szCs w:val="28" />',
    ),
    "Subtitle": (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="0" w:after="240" />',
        '<w:b /><w:bCs />',
    ),
    "Author": ('<w:spacing w:before="0" w:after="0" />', ""),
    "Date": ('<w:spacing w:before="0" w:after="240" />', ""),
    "AbstractTitle": (
        '<w:keepNext /><w:spacing w:before="240" w:after="0" />',
        '<w:b /><w:bCs /><w:caps />',
    ),
    "Abstract": ('<w:spacing w:before="0" w:after="240" />', ""),
    # BMJ heading hierarchy: BOLD CAPS, bold lower case, Plain text, Italics
    "Heading1": (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="240" w:after="0" />'
        '<w:outlineLvl w:val="0" />',
        '<w:b /><w:bCs /><w:caps /><w:sz w:val="24" /><w:szCs w:val="24" />',
    ),
    "Heading2": (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="240" w:after="0" />'
        '<w:outlineLvl w:val="1" />',
        '<w:b /><w:bCs /><w:sz w:val="24" /><w:szCs w:val="24" />',
    ),
    "Heading3": (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="240" w:after="0" />'
        '<w:outlineLvl w:val="2" />',
        '<w:sz w:val="24" /><w:szCs w:val="24" />',
    ),
    "Heading4": (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="240" w:after="0" />'
        '<w:outlineLvl w:val="3" />',
        '<w:i /><w:iCs /><w:sz w:val="24" /><w:szCs w:val="24" />',
    ),
    # Numbered reference list: "1<tab>Author ..." with a hanging indent
    "Bibliography": (
        '<w:tabs><w:tab w:val="left" w:pos="567" /></w:tabs>'
        '<w:spacing w:before="0" w:after="0" /><w:ind w:left="567" w:hanging="567" />',
        None,
    ),
    "Caption": ('<w:spacing w:before="0" w:after="240" />', ""),
    "TableCaption": ('<w:keepNext /><w:spacing w:before="240" w:after="0" />', ""),
    "ImageCaption": ('<w:spacing w:before="0" w:after="240" />', ""),
    "BlockText": ('<w:spacing w:before="0" w:after="240" /><w:ind w:left="567" w:right="567" />', ""),
}
for level in range(5, 10):
    STYLES[f"Heading{level}"] = (
        '<w:keepNext /><w:keepLines /><w:spacing w:before="240" w:after="0" />'
        f'<w:outlineLvl w:val="{level - 1}" />',
        '<w:i /><w:iCs /><w:sz w:val="24" /><w:szCs w:val="24" />',
    )
for level in range(1, 10):
    # Character styles linked to headings: drop theme fonts/colours too.
    STYLES[f"Heading{level}Char"] = (None, STYLES[f"Heading{level}"][1])
STYLES["TitleChar"] = (None, STYLES["Title"][1])
STYLES["SubtitleChar"] = (None, STYLES["Subtitle"][1])

BOX_BORDER = (
    '<w:pBdr>'
    '<w:top w:val="single" w:sz="8" w:space="6" w:color="000000" />'
    '<w:left w:val="single" w:sz="8" w:space="6" w:color="000000" />'
    '<w:bottom w:val="single" w:sz="8" w:space="6" w:color="000000" />'
    '<w:right w:val="single" w:sz="8" w:space="6" w:color="000000" />'
    '</w:pBdr>'
)

NEW_STYLES = f"""
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="BMJBox">
    <w:name w:val="BMJ Box" />
    <w:basedOn w:val="BodyText" />
    <w:qFormat />
    <w:pPr>{BOX_BORDER}<w:spacing w:before="0" w:after="0" /><w:ind w:left="170" w:right="170" /></w:pPr>
    <w:rPr />
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="BMJBoxHeading">
    <w:name w:val="BMJ Box Heading" />
    <w:basedOn w:val="BMJBox" />
    <w:next w:val="BMJBox" />
    <w:qFormat />
    <w:pPr><w:keepNext /></w:pPr>
    <w:rPr><w:b /><w:bCs /></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="BMJFrontMatter">
    <w:name w:val="BMJ Front Matter" />
    <w:basedOn w:val="BodyText" />
    <w:qFormat />
    <w:pPr><w:spacing w:before="0" w:after="0" /></w:pPr>
    <w:rPr />
  </w:style>
"""

DOC_DEFAULTS = f"""<w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        {RFONTS}
        <w:sz w:val="{SIZE}" />
        <w:szCs w:val="{SIZE}" />
        <w:lang w:val="en-GB" w:eastAsia="ja-JP" w:bidi="ar-SA" />
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="0" w:line="{LINE_DOUBLE}" w:lineRule="auto" />
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>"""

FOOTER_XML = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:p>
    <w:pPr><w:jc w:val="center" /><w:spacing w:line="240" w:lineRule="auto" /></w:pPr>
    <w:r><w:fldChar w:fldCharType="begin" /></w:r>
    <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate" /></w:r>
    <w:r><w:t>1</w:t></w:r>
    <w:r><w:fldChar w:fldCharType="end" /></w:r>
  </w:p>
</w:ftr>
"""

SECT_PR = """<w:sectPr>
      <w:footerReference w:type="default" r:id="rIdBmjFooter1" />
      <w:footnotePr>
        <w:numRestart w:val="eachSect" />
      </w:footnotePr>
      <w:pgSz w:w="11906" w:h="16838" />
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="709" w:footer="709" w:gutter="0" />
      <w:lnNumType w:countBy="1" w:restart="continuous" />
    </w:sectPr>"""


def style_block_re(style_id: str) -> re.Pattern[str]:
    return re.compile(
        r'(<w:style\b[^>]*w:styleId="' + re.escape(style_id) + r'"[^>]*>)(.*?)(</w:style>)',
        re.DOTALL,
    )


def strip_part(body: str, tag: str) -> str:
    body = re.sub(rf"<w:{tag}\s*/>", "", body)
    return re.sub(rf"<w:{tag}>.*?</w:{tag}>", "", body, flags=re.DOTALL)


def restyle(styles: str, style_id: str, ppr: str | None, rpr: str | None) -> str:
    pattern = style_block_re(style_id)
    match = pattern.search(styles)
    if not match:
        raise SystemExit(f"style {style_id!r} not found in reference.docx")
    head, body, tail = match.groups()
    if ppr is not None:
        body = strip_part(body, "pPr")
    if rpr is not None:
        body = strip_part(body, "rPr")
    body = body.rstrip()
    if ppr is not None:
        body += f"\n    <w:pPr>{ppr}</w:pPr>"
    if rpr is not None:
        body += f"\n    <w:rPr>{rpr}</w:rPr>"
    return styles[: match.start()] + head + body + "\n  " + tail + styles[match.end():]


def transform_styles(styles: str) -> str:
    styles = re.sub(r"<w:docDefaults>.*?</w:docDefaults>", DOC_DEFAULTS, styles, flags=re.DOTALL)
    for style_id, (ppr, rpr) in STYLES.items():
        styles = restyle(styles, style_id, ppr, rpr)
    # Remove any remaining theme fonts / theme colours so everything is black
    # Times New Roman, as expected by editors.
    styles = re.sub(r"<w:rFonts\b[^>]*Theme[^>]*/>", "", styles)
    styles = re.sub(
        r'<w:color w:val="[0-9A-Fa-f]{6}" w:themeColor="accent1"[^>]*/>', "", styles
    )
    return styles.replace("</w:styles>", NEW_STYLES + "</w:styles>")


def transform_document(document: str) -> str:
    if 'xmlns:r="' not in document:
        document = document.replace(
            "<w:document ",
            '<w:document xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ',
            1,
        )
    new, count = re.subn(r"<w:sectPr>.*?</w:sectPr>", SECT_PR, document, flags=re.DOTALL)
    if count != 1:
        raise SystemExit("could not locate the body sectPr in document.xml")
    return new


def transform_rels(rels: str) -> str:
    rel = (
        '<Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/footer" Id="rIdBmjFooter1" Target="footer1.xml" />'
    )
    return rels.replace("</Relationships>", rel + "</Relationships>")


def transform_content_types(ct: str) -> str:
    override = (
        '<Override PartName="/word/footer1.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.wordprocessingml.footer+xml" />'
    )
    return ct.replace("</Types>", override + "</Types>")


def default_reference_docx(dest: Path) -> None:
    subprocess.run(
        ["quarto", "pandoc", "-o", str(dest), "--print-default-data-file", "reference.docx"],
        check=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "reference.docx"
        default_reference_docx(source)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(source) as zin, zipfile.ZipFile(
            OUTPUT, "w", compression=zipfile.ZIP_DEFLATED
        ) as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename == "word/styles.xml":
                    data = transform_styles(data.decode("utf-8")).encode("utf-8")
                elif item.filename == "word/document.xml":
                    data = transform_document(data.decode("utf-8")).encode("utf-8")
                elif item.filename == "word/_rels/document.xml.rels":
                    data = transform_rels(data.decode("utf-8")).encode("utf-8")
                elif item.filename == "[Content_Types].xml":
                    data = transform_content_types(data.decode("utf-8")).encode("utf-8")
                zout.writestr(item, data)
            zout.writestr("word/footer1.xml", FOOTER_XML)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
