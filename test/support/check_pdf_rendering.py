"""Independent PDF render/bounds check; requires PyMuPDF.

Run after the Dart PDF audit with PDF_AUDIT_DIR=tmp/pdfs:
    python test/support/check_pdf_rendering.py tmp/pdfs --render-dir tmp/pdf-rendered
"""

import argparse
import json
from pathlib import Path

import pymupdf


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf_dir", type=Path)
    parser.add_argument("--render-dir", type=Path)
    args = parser.parse_args()
    if args.render_dir:
        args.render_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(args.pdf_dir.glob("*.pdf"))
    assert files, "No audit PDFs found"
    pages = 0
    for source in files:
        with pymupdf.open(source) as document:
            for number, page in enumerate(document):
                pages += 1
                if args.render_dir:
                    page.get_pixmap(matrix=pymupdf.Matrix(1.6, 1.6)).save(
                        args.render_dir / f"{source.stem}-{number}.png"
                    )
                for span in page.get_texttrace():
                    for rune, glyph, _, bounds in span["chars"]:
                        x0, y0, x1, y1 = bounds
                        context = f"{source.name} page {number + 1} U+{rune:04X}"
                        assert rune != 0xFFFD and glyph != 0, context
                        assert -1 <= x0 and -1 <= y0, (context, bounds)
                        assert x1 <= page.rect.width + 1, (context, bounds)
                        assert y1 <= page.rect.height + 1, (context, bounds)
    result = {"pdfs": len(files), "pages": pages, "outOfBoundsOrMissingGlyphs": 0}
    (args.pdf_dir / "render-verification.json").write_text(
        json.dumps(result, indent=2), encoding="utf-8"
    )
    print(json.dumps(result))


if __name__ == "__main__":
    main()
