"""Offline semantic audit of the four Phase 2B-11 synthetic PDF fixtures.

Requires PyMuPDF. Complements check_pdf_rendering.py and visual review; does not
authenticate financial evidence or inspect any Firebase environment.
"""

from collections import Counter
import argparse
import json
from pathlib import Path
import re
import unicodedata

import pymupdf


def compact(text):
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", text))


def money(units, currency, signed=False):
    value = int(units)
    absolute = abs(value)
    number = f"{absolute // 1000}.{absolute % 1000:03}"
    return ("+" if signed and value >= 0 else "") + currency + (
        "-" if value < 0 else ""
    ) + number


def reference_present(reference, content):
    # Physical PDF subrows can cross a page, interleaving a repeated header or
    # other columns between reference fragments. Test every retained fragment.
    return all(compact(reference[start:start + 40]) in content
               for start in range(0, len(reference), 40))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transport", action="store_true", help="Audit authenticated synthetic emulator captures")
    parser.add_argument("--directory", type=Path, help="Optional isolated output directory for the current verification run")
    parser.add_argument("--fixtures-dir", type=Path, default=Path("test/fixtures"), help="Immutable synthetic captures used for this run")
    args = parser.parse_args()
    if args.transport:
        fixtures = {state: json.loads((args.fixtures_dir / f"settlement_transport{suffix}_emulator.json").read_text(encoding="utf-8"))
                    for state, suffix in (("verified", ""), ("blocked", "_blocked"))}
        directory, prefix = Path("output/pdf/phase2b12"), "settlement-authenticated"
    else:
        fixtures = json.loads((args.fixtures_dir / "settlement_details.json").read_text(encoding="utf-8"))
        directory, prefix = Path("output/pdf/phase2b11"), "settlement"
    if args.directory is not None:
        directory = args.directory
    results = []
    for state in ("verified", "blocked"):
        pages = fixtures[state]["pages"]
        rows = [row for page in pages for row in page["rows"]]
        header = pages[0]
        for language in ("en", "ar"):
            path = directory / f"{prefix}-{state}-{language}.pdf"
            with pymupdf.open(path) as doc:
                content = compact("\n".join(page.get_text() for page in doc))
                assert header["evidenceDigest"] in content
                assert header["snapshotDigest"] in content
                expected = Counter(money(row["signedUnits"], header["currency"], True) for row in rows)
                for amount, occurrences in expected.items():
                    assert content.count(amount) == occurrences, (path, amount, occurrences)
                for row in rows:
                    for reference in (row["id"], row["source"]["path"], row["sourceNumber"]):
                        if reference:
                            assert reference_present(reference, content), (path, reference)
                    for actor in (row["sourceCreator"], row["movementCreator"], row["collector"], row["postingActor"]):
                        if actor["uid"]:
                            assert compact(actor["uid"]) in content, (path, actor["uid"])
                    for reference in row["referencedDocuments"]:
                        assert reference_present(reference["path"], content), (path, reference["path"])
                if state == "verified":
                    for value in header["totals"].values():
                        assert money(value, header["currency"]) in content, (path, value)
                else:
                    # No certified opening/carry/before/remaining values leak from
                    # the sibling verified fixture into the blocked presentation.
                    for key in ("carryUnits", "cashAvailableBeforeUnits", "remainingUnits"):
                        value = fixtures["verified"]["pages"][0]["totals"][key]
                        assert money(value, header["currency"]) not in content, (path, key)
                results.append({"file": path.name, "pages": len(doc), "movementRows": len(rows)})
    (directory / "content-verification.json").write_text(
        json.dumps({"verified": True, "documents": results}, indent=2), encoding="utf-8"
    )
    print(json.dumps({"pdfs": len(results), "sourceReferencesAndExactAmounts": "passed"}))


if __name__ == "__main__":
    main()
