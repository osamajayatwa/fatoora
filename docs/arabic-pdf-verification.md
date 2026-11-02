# Arabic PDF rendering verification

Verified locally on 2026-10-31. **Resolved across the tested cases. Deployed to production Hosting on 2026-10-31 after user authorization.**

## Coverage and results

| Check | Evidence | Result |
| --- | --- | --- |
| Arabic repertoire | All 36 standard letters and their 119 contextual forms, plus 16 extended letters / 50 forms | Pass in Cairo Regular and Bold |
| Shaping | Each isolated, final, initial, and medial form actually emitted to a PDF; all eight lam-alef ligatures; vowel marks | Pass |
| Customer names | 14 cases: varied letters, hamza variants, diacritics, a long company name, English before/after Arabic, and scripts joined without a space | Pass in Arabic and English layouts |
| Generators | Invoice, receipt, sales return, quotation, customer statement, cash report; 168 generated documents | Pass |
| Serialized fonts | 20,786 encoded entries: PDF advance widths and subset glyph geometry compared with the original Cairo font metrics | Pass |
| Independent rendering | 72 representative documents plus an eight-page glyph atlas: 104 pages rendered with MuPDF | No missing glyphs or glyphs outside the page |
| Visual inspection | Glyph atlas, 72 name crops across all six generators, and full layouts for critical mixed/long-name cases | No overlapping/compressed name letters found |
| Checks | 24 focused Flutter tests; analyzer; production web compilation | Pass |

## Root causes corrected

- Missing isolated presentation-form mappings, including yeh and alef wasla. Missing forms now use the corresponding base glyph; alef maksura retains its dotless outline.
- The PDF library's subsetter could substitute another outline when Unicode aliases shared a glyph. Aliases now share one encoded glyph entry.
- Invoice names beginning with English inside a mixed-script token could bypass Arabic shaping. Customer-name rendering now uses the shared Arabic-aware text path while preserving alignment.
- Long customer-statement subtitles could exceed the page width. The existing header now constrains and wraps its title/subtitle.

Original font files, font sizes/weights, colors, borders, and customer records were not changed. Tests use synthetic snapshots and assert names remain unchanged after export.

## Review artifacts

- [Glyph and name atlas](../output/pdf/arabic-glyph-audit.pdf)
- Name crops: [invoice](../output/pdf/arabic-review-invoice.png), [receipt](../output/pdf/arabic-review-receipt.png), [return](../output/pdf/arabic-review-return.png), [quotation](../output/pdf/arabic-review-quotation.png), [statement](../output/pdf/arabic-review-statement.png), [cash report](../output/pdf/arabic-review-cash.png).
- [Name matrix and glyph-check counts](../output/pdf/arabic-audit-manifest.json), [independent render results](../output/pdf/arabic-render-verification.json).

## Reproduce

```powershell
flutter test --no-pub --dart-define=PDF_AUDIT_DIR=tmp/pdfs test/app_pdf_assets_test.dart test/pdf_services_settings_test.dart test/invoice_pdf_layout_test.dart test/app_pdf_direction_test.dart
python -m pip install PyMuPDF
python test/support/check_pdf_rendering.py tmp/pdfs --render-dir tmp/pdf-rendered
flutter build web --release --no-pub --dart-define=FATOORA_ENV=production
```

The font assertions inspect exported PDF font streams, not just successful file generation. The independent Python check guards the long-name header regression by checking actual glyph coordinates and rendering every saved page.

Scope: the tested Cairo repertoire and generated layouts above. A physical iPhone/Safari viewer was not exercised; the PDFs were inspected in MuPDF and the web release compiled successfully. This is not a claim about every character in all Unicode Arabic-related blocks.

## Production deployment

- Site: https://fatoora-6b192.web.app
- Firebase Hosting version: `df142c2290fbf731`.
- Production web rebuild and Hosting deployment succeeded. Functions, rules, and indexes were not deployed.
- Live `index.html`, `flutter_bootstrap.js`, and `main.dart.js` returned HTTP 200 and matched the local release build by SHA-256.
- [Deployment verification](../output/pdf/hosting-deployment-verification.json).
