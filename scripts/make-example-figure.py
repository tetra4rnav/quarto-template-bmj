#!/usr/bin/env python3
"""Write the example participant flow diagram used by template.qmd.

Produces ``figures/participant-flow.pdf`` (for bmj-pdf and bmj-docx; PDF is
one of the figure formats BMJ accepts) and ``figures/participant-flow.svg``
(for bmj-html). Both are drawn directly, so no third-party Python packages
are needed. template.qmd refers to the figure without an extension and each
format picks the right file through ``default-image-extension``.

Usage (from the repository root)::

    python scripts/make-example-figure.py
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "figures" / "participant-flow.pdf"

WIDTH, HEIGHT = 432, 300  # points (6 x 4.17 inches)

# (x, y, width, height, lines of text); y is the bottom edge
BOXES = [
    (96, 240, 240, 44, ["Adults registered with 12 participating", "general practices (n=48 210)"]),
    (250, 166, 170, 56, ["Excluded (n=6135):", "  Previous diagnosis (n=4902)", "  Incomplete records (n=1233)"]),
    (116, 104, 200, 32, ["Included in cohort (n=42 075)"]),
    (24, 18, 170, 44, ["Exposed", "(n=9812)"]),
    (238, 18, 170, 44, ["Unexposed", "(n=32 263)"]),
]

ARROWS = [
    ((216, 240), (216, 136)),  # main flow down to cohort box
    ((216, 194), (250, 194)),  # side branch to exclusions
    ((216, 104), (216, 84)),
    ((109, 84), (323, 84)),
    ((109, 84), (109, 62)),
    ((323, 84), (323, 62)),
]

FONT_SIZE = 10
LEADING = 13


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def arrow_head(x: float, y: float, direction: str) -> str:
    s = 4
    if direction == "down":
        pts = [(x, y), (x - s, y + 2 * s), (x + s, y + 2 * s)]
    else:  # right
        pts = [(x, y), (x - 2 * s, y + s), (x - 2 * s, y - s)]
    (x0, y0), (x1, y1), (x2, y2) = pts
    return f"{x0} {y0} m {x1} {y1} l {x2} {y2} l h f\n"


def content_stream() -> bytes:
    ops = ["0.8 w 0 0 0 RG 0 0 0 rg\n"]
    for x, y, w, h, lines in BOXES:
        ops.append(f"{x} {y} {w} {h} re S\n")
        top = y + h - 8 - FONT_SIZE
        for i, line in enumerate(lines):
            ops.append(
                f"BT /F1 {FONT_SIZE} Tf {x + 8} {top - i * LEADING} Td ({escape(line)}) Tj ET\n"
            )
    for (x0, y0), (x1, y1) in ARROWS:
        ops.append(f"{x0} {y0} m {x1} {y1} l S\n")
    # arrow heads where a line ends at a box
    for (x0, y0), (x1, y1) in ARROWS:
        if x0 == x1 and y1 in (136, 62):
            ops.append(arrow_head(x1, y1, "down"))
        elif y0 == y1 and x1 == 250:
            ops.append(arrow_head(x1, y1, "right"))
    return "".join(ops).encode("latin-1")


def build_pdf() -> bytes:
    stream = content_stream()
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {WIDTH} {HEIGHT}] "
            "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
        ).encode("latin-1"),
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        b"<< /Title (Participant flow) /Producer (make-example-figure.py) >>",
    ]
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R /Info {len(objects)} 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode()
    return bytes(out)


def build_svg() -> str:
    """Same drawing as SVG for the HTML preview (y axis points down)."""

    def fy(y: float) -> float:
        return HEIGHT - y

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
        f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-label="Flow of participants through the study">',
        '<rect width="100%" height="100%" fill="#ffffff" />',
        '<g fill="none" stroke="#000000" stroke-width="0.8">',
    ]
    for x, y, w, h, _ in BOXES:
        parts.append(f'<rect x="{x}" y="{fy(y + h)}" width="{w}" height="{h}" />')
    for (x0, y0), (x1, y1) in ARROWS:
        parts.append(f'<line x1="{x0}" y1="{fy(y0)}" x2="{x1}" y2="{fy(y1)}" />')
    parts.append("</g>")
    parts.append('<g fill="#000000">')
    for (x0, y0), (x1, y1) in ARROWS:
        s = 4
        if x0 == x1 and y1 in (136, 62):
            pts = [(x1, y1), (x1 - s, y1 + 2 * s), (x1 + s, y1 + 2 * s)]
        elif y0 == y1 and x1 == 250:
            pts = [(x1, y1), (x1 - 2 * s, y1 + s), (x1 - 2 * s, y1 - s)]
        else:
            continue
        coords = " ".join(f"{px},{fy(py)}" for px, py in pts)
        parts.append(f'<polygon points="{coords}" />')
    parts.append("</g>")
    parts.append(
        f'<g font-family="Helvetica, Arial, sans-serif" font-size="{FONT_SIZE}" fill="#000000">'
    )
    for x, y, w, h, lines in BOXES:
        top = y + h - 8 - FONT_SIZE
        for i, line in enumerate(lines):
            text = line.replace("&", "&amp;").replace("<", "&lt;")
            parts.append(
                f'<text x="{x + 8}" y="{fy(top - i * LEADING)}" xml:space="preserve">{text}</text>'
            )
    parts.append("</g></svg>\n")
    return "\n".join(parts)


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(build_pdf())
    svg = OUTPUT.with_suffix(".svg")
    svg.write_text(build_svg(), encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} and {svg.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
