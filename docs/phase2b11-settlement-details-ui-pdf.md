# Phase 2B-11 — settlement details UI and PDF

Approved 2026-11-09. Presentation only, using the existing Flutter/GetX cash
settlement card, desktop details sheet, design system and cash PDF service.
The [Phase 2B-10](phase2b10-scalable-settlement-coverage.md) verified detail page
contract is unchanged. No backend, endpoint, posting, allocation, cash calculation,
binding, production/staging access or deployment is added in this phase.

## Contract and financial safeguards

`settlement_details.dart` implements typed immutable page, movement, participant,
source-reference, timestamp and assembled-report DTOs. It rejects unsupported or
extra fields, noncanonical money, wrong holders/company paths, invalid versions,
currency/scale errors, malformed counts/continuations and modified checksums.
The backend canonical SHA-256 codec is independently reproduced in Dart and
checked against backend-generated fixture pages. Amounts remain canonical integer
strings / `BigInt`, using the existing `ExactDecimal` helpers at scale three.
No financial value passes through `double` or implicit rounding. Display preserves
nine timestamp fractional digits, separately from business dates.

The assembler pins company, representative, settlement, report digest, snapshot
digest, cutoff and shared header. Each page must arrive once, in sequence. It
checks unique movement IDs and committed ordering; verified histories must form
an exact balance chain. At completion it independently checks the recorded opening,
the previous settlement/carry witness, net intervening activity, current transfer
and remaining cash. Failed additions leave previous valid pages intact. Final
reconciliation runs once; normal page validation works only on the new page.
Page limits remain 64 rows, 16,000 rows / 250 pages, with bounded JSON structure,
strings and bytes. These are safety ceilings, not device performance promises.

Totals stay unavailable until the entire sequence is complete and verified.
Partial, failed, unknown-opening and incomplete-coverage states cannot export a
certified total or a partial PDF. Complete but historically blocked reports can
export an explicitly blocked observed-history PDF with all summary totals withheld.
Unknown openings and carries stay null; they never become zero. Every synthetic
PDF, including a verified reconstruction, explicitly disclaims financial
certification and live connectivity.

Page checksums detect corruption and mixed observations; they do **not**
authenticate a server, prove viewing permission or reconstruct missing history.
Current observed account balance is separately labeled; through-cutoff movement
rows do not imply that later activity belongs to that historical settlement.

## Existing interface and PDF

The existing controller accepts an optional **final, synthetic-fixture-only**
dependency. No application binding provides it, the fixture is not an app asset,
and release builds reject injection. The existing screen additionally requires
administrator/company/settlement matches. Normal users and existing live flows
receive no new panel or action. No HTTP/Firebase implementation or transport
abstraction is invented.

An injected panel embeds in the existing pair card and desktop representative
OUT-movement sheet. It uses existing surfaces, typography, colors and GetX local
state; there is no new screen or route. It renders only the current 64-row page.
Validated prior pages remain revisitable without additional reads. Loading,
retry, incomplete coverage, historical blocking and verified states are explicit.
Rapid loads serialize; late completions after disposal cannot publish results.

One bilingual formatter supplies exact summary and row labels to UI/PDF. Rows
retain source numbers/IDs/paths, business and SDK commit dates, signed amounts,
actual cash holder, source/movement creators, collector, original seller and
posting/approval actor. Linked invoice references and recorded receivable
annotations remain evidence, not settlement allocations. No FIFO, invoice funding
claim or allocation persistence is introduced. Document references remain in the
DTO for future authorized navigation; no navigation access is inferred from them.
Current source versions later than cutoff are explicitly marked.

The cash PDF service gains a separate complete-detail entry point; its existing
cash report stays unchanged. PDFs reuse existing embedded Cairo assets, company
header/footer and summary styling. A summary cover precedes repeated-header audit
tables. Physical subrows retain long references/names without ellipsis or row
clipping. A participant key registry preserves full names, IDs and recorded roles
without repeating long names in every transaction. Those keys identify people
only. Arabic columns reverse, Arabic labels retain RTL, and exact money, IDs and
timestamps retain readable LTR. All preview configuration is explicitly synthetic;
no business-settings resolver reads live data.

## Evidence and verification

`test/support/generate_settlement_detail_fixtures.js` uses the existing pure backend
source analyzer and page builder. It creates no Firebase client and performs no
financial writes or database access. The resulting immutable fixture includes
72 movements / two pages: recorded opening, cash/partial invoices, a later receipt
with an evidenced invoice, representative-paid refund, approved cash expense,
previous and current settlements, and differing seller/creator/collector/approver
identities. Separate fixtures omit the opening or report incomplete coverage.

Exact fixture economics (JOD): opening **100.000**, prior-settlement carry
**109.875**, activity since carry **0.065**, before current settlement **109.940**,
transfer **10.000**, remaining **99.940**. Receipt annotations do not add cash;
company transfer legs are not representative receipts. Missing-opening fixtures
retain observed rows but certify none of these aggregate amounts.

| Check | Result |
|---|---|
| Focused Dart/controller/widget/PDF suite | **55 passed**: 29 DTO/controller cases, six PDF cases and 20 widget cases. |
| Full existing Flutter suite, including new cases | **628 passed**, no failures/skips. Includes existing cash, receipts, returns, expenses, ledger, permissions, shared UI and PDF regressions. |
| Flutter analysis | **No issues found**. |
| Final PDF-only run after pagination polish | **Six passed**, embedded Arabic font widths/outlines verified. |
| Independent final PDF render/bounds audit | Four deliverable PDFs, **68 pages**, zero missing glyphs or page-bound violations. Two long-text stress PDFs add **42 pages**, also zero violations. |
| Independent PDF content audit | All four deliverables retain exact signed movement amount counts, source/movement references, participant IDs and both evidence digests. Verified summaries match exact units; blocked summaries withhold carry/before/remaining amounts. |
| Visual review | Arabic/English summary, transaction/continuation, participant legend and blocked pages; responsive captures at 320/768/1366 px, normal/2× text, long bilingual names. Actual Cairo and Material icon fonts and existing app theme are loaded for captures. |
| Scope check | No live reads, transport, backend changes, financial writes, financial activation or production binding introduced. Earlier uncommitted Phase 2B-7–10 work is preserved. |

Integrity tests cover missing, duplicate, changed and mixed-snapshot pages;
self-consistently rehashed bad equations, duplicate movement IDs, broken chains
and false carry witnesses; exact 30-digit amounts/negative mills; immutable input;
concurrent loads, retry and disposal; missing openings and incomplete coverage.
Widget tests exercise existing mobile card and desktop sheet injection, source
reference expansion, suppression of premature totals and administrator/company/
target guards. PDF stress cases include 1,500-character unbroken document numbers,
600-character identifiers and long Arabic names without silent truncation.

Evidence:

- `output/phase2b11-focused-final.log`, `output/phase2b11-regressions.log`,
  `output/phase2b11-analysis.log`, `output/phase2b11-pdf-final.log`.
- `output/pdf/phase2b11/`: four synthetic verified/blocked English/Arabic PDFs,
  `render-verification.json` and `content-verification.json`.
- `output/phase2b11/widgets/`: 38 captures, including `showcase-en.png`,
  `showcase-ar.png`, and narrow 2× text captures.
- `output/phase2b11/final-pdf-rendered/`: final rendered pages and review images.
- Long-text audit: `output/phase2b11/stress-render-verification.json`; selected
  stress renders are alongside the final PDF review images. Temporary stress
  PDFs/render directories were removed after review; the command below recreates them.

Reproduce with installed Node/Flutter and PyMuPDF (the rendering dependency is
tooling only; Flutter and backend dependency manifests are unchanged):

```powershell
node test/support/generate_settlement_detail_fixtures.js
$env:SETTLEMENT_PDF_DIR='output/pdf/phase2b11'
$env:SETTLEMENT_PDF_STRESS_DIR='tmp/pdfs/phase2b11'
$env:SETTLEMENT_WIDGET_DIR='output/phase2b11/widgets'
flutter test --no-pub test/settlement_details_test.dart test/settlement_details_pdf_test.dart test/settlement_details_widget_test.dart --concurrency=1
flutter analyze --no-pub
flutter test --no-pub --concurrency=4
python test/support/check_pdf_rendering.py output/pdf/phase2b11 --render-dir output/phase2b11/final-pdf-rendered
python test/support/check_pdf_rendering.py tmp/pdfs/phase2b11
python test/support/check_settlement_pdf_evidence.py
```

No emulator is needed for this presentation-only phase: data is immutable,
synthetic and offline. Phase 2B-10 emulator coverage remains its separately
recorded backend evidence; it was not rerun or extended here.

## Limitations and smallest safe next phase

This feature is deliberately unavailable in production. Device print/share dialogs,
real printer behavior and maximum-volume/device PDF latency are not certified by
fixture rendering. The largest rendered normal history is 72 movements; inherited
backend volume limits do not imply a Flutter PDF throughput guarantee. Historical
openings, deleted evidence, mutable source versions and unproven source allocation
limitations from Phase 2B-10 remain unchanged. Recorded identity is not proof of
physical cash handover or historical identity authorization.

The next batch should approve and implement **one authenticated read-only
transport** for the existing breakdown/page contract. First define the authorized
boundary, administrator/company/representative access, revocation checks and
failure responses. Preserve a single server-verified snapshot with pinned report/
snapshot roots, expiry and bounded page delivery; do not rerun an independent
financial snapshot for each client page. Define how a page session stays bound to
the current principal and how authorization is rechecked before delivery/export.
Untrusted checksums alone must never grant access. Keep the source reader's
emulator/default-off guards until activation is separately authorized.

Test that transport on isolated emulators with synthetic data, including expiry,
revocation, mixed snapshots, retries and resource ceilings. Then inject it into
this existing presentation and validate realistic-volume device/PDF performance
before enabling a production binding. Allocation, posting, historical backfill and
double-entry activation remain separate approvals. Phase 2B-11 implements none of
those next-phase actions.
