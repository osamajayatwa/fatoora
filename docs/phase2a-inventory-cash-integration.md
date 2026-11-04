# Phase 2A refinement: quantity inventory and detailed cash ledger

Owner requirements, **2026-11-04, Asia/Amman**. This refines the
[architecture](phase2a-firestore-accounting-architecture.md),
[strategy](financial-modernization-strategy.md) and
[Excel specification](excel-migration-specification.md). It removes the prior
costing prerequisite and narrows implementation to existing integration points.
Firebase remains the platform. Sections 1-5 record the design baseline;
sections 6-7 record the separately approved Phase 2B-1 arithmetic and
Phase 2B-2 cash read/presentation implementations. Section 8 links the separately
approved Phase 2B-3 additive settlement metadata implementation.
Section 9 links the separately approved Phase 2B-4 offline journal intent.
Section 10 links the separately approved Phase 2B-5 transaction preflight.
No GL engine, production data, reset or deployment changes are made.

## 1. Four separate measures

| Measure | Source and permitted effects |
|---|---|
| Physical stock | Exact quantities by company/item/warehouse/rep custody from approved openings and real IN/OUT/transfer/return/count movements. Sale confirmation deducts actual line quantity once; price edits do not change quantity. Missing purchase cost is irrelevant to eligibility. |
| Estimated selling value | Available quantity x item **reference selling price**. Start from `ItemModel.price` / `items.price`; label this informational estimate, with quantity/price basis, revisions/as-of time and coverage. It is neither inventory cost, cash, revenue nor profit and never creates a journal. |
| Actual sales | Immutable confirmed invoice line selling prices, discounts/tax and quantities; editable by both approved admins and reps under existing numerical rules, without a catalog-price comparison or new price-approval flag. Initial payments and later collections are separate evidence. |
| Inventory cost / COGS | **Not recorded in the current operating scope.** No cost-pool reads/writes, invented zero-cost journals, selling-price substitution or automatic COGS. Any later evidence-based costing module requires a separate requirement/policy/implementation phase. |

Changing invoice unit price affects actual invoice totals/payment validation,
never `items.price`, warehouse/custody balance or the reference price of unsold
stock. Posting that invoice still deducts its quantity. Explicit authorized item
reference-price edits may change estimates but never reprice historical invoices,
change stock, restate cash or post accounting. A missing reference price makes
that estimate unavailable/partial; it does not block a valid sale. Zero price is
valid when explicitly recorded, not a substitute for missing data.

Example: custody 10, reference price 5.000; sell 3 at 7.000 -> custody 7,
remaining estimate 35.000, invoice net 21.000 before any discount/tax. Editing
the draft price to 9.000 changes invoice net to 27.000; the same sale still
leaves 7 at reference 5.000. No purchase cost or profit is inferred.

Quantity-only transfer/receipt/count/physical return has no cost journal in this
scope. Sales/returns still post their known revenue/tax/AR/payment components
in balanced double entry, atomically with physical movements. Shortage, invalid
tracking, wrong company/custodian, over-return and duplicate guards remain.
Return quantity and revenue/tax residual provenance is required; issue-cost
provenance is not required when costing is not recorded.

Reconcile physical quantities independently: opening + IN - OUT = closing for
each item/location/custodian; warehouse + all custody = company-owned quantity;
transfer legs conserve quantity. Sum quantities only within compatible units.
Estimated totals sum per-item estimates after exact multiplication/declared
rounding, not actual invoice prices or a total quantity across different units.
Include inactive/archived items with remaining stock where authorized, using
known price evidence or an explicit unavailable estimate rather than dropping stock.

Reports state `costCoverage=not_recorded`; inventory cost, COGS, gross margin and
complete profit/financial-position conclusions are unavailable. This does not
block daily sales, physical inventory, cash/AR reconciliation or acceptance of
their declared scope. A balanced monetary TB is not proof of unrecorded inventory
value. Never present selling-value estimates as a balance-sheet inventory asset
or sales less incomplete expenses as established profit.

## 2. Existing source findings and integration points

Reviewed local source on 2026-11-04; no production inspection or runtime
verification. Reuse these implementations and their routes/callables:

| Existing integration | Required extension / observed limit |
|---|---|
| `functions/src/trusted/confirm_invoice.ts`, `confirm_sales_return.ts`, `confirm_inventory_transfer.ts`, `inventory.ts`, `custody.ts` | Keep the single existing posting chain and physical guards. Invoice confirmation currently has no purchase-cost prerequisite; preserve that behavior. Item creation currently normalizes a `costPrice` field and emits a cost-based `inventoryValue`; optional/legacy cost metadata must not become a workflow gate or selling estimate. |
| `lib/features/items/data/models/item_model.dart`, invoice models/forms/calculators | Existing reference `price` and invoice line price remain distinct. Preserve free admin/rep invoice pricing and current screens; do not copy invoice prices back to the catalog. |
| `lib/features/rep_inventory/data/models/rep_inventory_balance_model.dart`, `data/repositories/rep_inventory_repository.dart`, `controllers/rep_inventory_controllers.dart`, `view/screens/rep_inventory_screens.dart` | Extend existing rows/summary with clearly named estimated selling value and basis/coverage. Current summary exposes count/quantity, not this estimate. Reuse scoped paging and owner validation. |
| `functions/src/trusted/operational_search_projection.ts`, `dashboard_reporting.ts` | Existing `inventoryValue` uses stock x catalog cost, not the requested measure. Add an explicit selling-estimate field/view through existing reporting; never silently reuse that cost-labelled field. Guard delayed updates with current revisions; report quantity/price freshness. |
| `functions/src/trusted/cash_ledger.ts` and the existing invoice/receipt/return/expense/settlement/cancellation callers | One canonical cash-leg contract and holder resolver inside this existing helper; write money movement, balance, source, GL and audit in the caller's transaction. Retain current callable names. No second posting service or independently fired money trigger. |
| `lib/features/financial/data/models/cash_movement_model.dart` | Preserve and expose before/after balances, method, holder, creator vs poster vs seller, and reversal/transfer links. Backend already writes some of these fields, but the current model omits them. Invalid direction/amount/time must not silently become IN/zero/now in trusted reporting. |
| `lib/features/financial/data/services/cash_ledger_calculator.dart` | Current legacy fallback infers cash effects from creator role. Restrict readiness to verified holder/account evidence; ambiguous history stays flagged. New calculations use exact units and a resolved treasury account, not creator/seller. |
| `lib/features/financial/data/repositories/financial_repository.dart`, `controllers/cash_movements_controller.dart`, `view/screens/cash_movements_screen.dart`, `view/widgets/cash_movement_presentation.dart`, `data/services/cash_report_pdf_service.dart` | Extend existing detail rows/expanders, paging, totals and PDF. Reuse existing opening/summary callables. No duplicate cash page, competing read endpoint or client source-document query per row. |

The architecture's book paths describe logical accounting records, not a mandate
to duplicate business collections. Keep existing invoices/receipts/returns/
expenses/settlements, `cash_movements`/`cash_balances`, stock/custody movements
and their repositories as the integration surfaces. Add journal/period/audit
records where needed and source links to those records. Accounting snapshots
are evidence, not a second business document lifecycle. When replacing internal
posting, each existing command calls one selected implementation; old/new books
must not both post the same source. Existing trusted authorization and business
user context remain the single access resolver; extend them rather than maintain
competing role policies. Future internal shape changes still need explicit scope.

## 3. Detailed movement contract

Each real treasury account leg has a stable `(economicEventId, componentId,
accountId, legId)` identity, linked to one source posting and GL effect. Store
positive exact amount units plus explicit direction and currency/scale. Proposed
field names extend the existing model rather than prescribe a new collection:

| Fields | Meaning / validation |
|---|---|
| `movementType`, `sourceCollection/sourceId/sourceNumber`, explicit invoice/receipt/return/expense/settlement IDs | Real economic type and durable references; original invoice and actual collection links retained for returns/refunds. Document references remain usable after archive/import. |
| `businessDate`, `recordedAt`, `accountingDate`, `accountSequence` | Transaction date, trusted committed/server timestamp, accounting period date and per-account committed ordering. Never replace missing historical timestamps with the current time. |
| `customerId` or counterparty ID/type/name snapshot | Customer, representative, vendor or owner as applicable; unrelated sources can be explicitly not-applicable, not fabricated customers. |
| `sourceCreatedByUid`, `createdByUid`, `postedByUid`, `approvedByUid`, name/role snapshots | Original document creator, movement initiator, actual trusted confirmation/cancellation actor and approver are separate. A server/import actor does not replace historical creator. Unknown legacy roles remain unknown. |
| `salesAttribution`, `responsibleRepId`, `collectorUid` | Original invoice seller(s), responsible representative for this operation and actual collector. Multi-invoice receipt allocations retain original sellers/amounts without duplicating the actual cash leg. Customer's current assignee is separate from all three. |
| `treasuryAccountId`, `accountKind`, `cashAccount`, `holderType`, `holderUid` | Verified actual company/rep cash holder (rep UID mandatory), or identified bank/clearing account. Derive from the validated balance/account and persisted funding/refund source, never just `createdByRole` or `salesRepId`. Rep-held cash is company-owned money in rep custody. |
| `paymentMethod`, `amountUnits`, `direction`, `balanceBeforeUnits`, `balanceAfterUnits` | Actual method, exact account leg and its resulting balance. Invoice cash/partial/credit is payment state, not bank/card method; return refund type is not payment method. Preserve signed customer-balance fields separately. |
| `transferId`, `counterpartMovementId`, `reversesMovementId`, `cancelledSourceId`, `originalCollectionSourceIds`, journal/event IDs | Matched account legs and corrections with unique provenance. An opposite amount alone is insufficient to match a transfer/reversal. |
| `notes`, `reason`, `auditEventId`, `schemaVersion`, `sourceDigest`, completeness status | Traceable explanation and immutable audit linkage; read permissions apply to source links and audit detail. Server validates limits and masks inaccessible source detail. |

Per account: `after = before + signed amount`, using exact units. Commit the
position and its sequence with the movement in the same transaction. Captured
after-balance is the balance in **committed account order**. A date-sorted report
may show a separate calculated running balance from its evidenced opening;
backdated rows must not pretend the stored after-balance is that date-order
running balance. Label the distinction and use one consistent watermark/scope.

Historical fields may be recovered only from approved linked evidence. Missing
holder/amount/opening evidence blocks the relevant reconciliation, not stock
sales because costs are absent. Missing display notes can be flagged without
fabricating a value or falsely certifying traceability. No history rewrite or
backfill is authorized by a UI/model enhancement.

## 4. Movement coverage and reconciliation

| Operation | Required treasury behavior |
|---|---|
| Cash / partial invoice | One IN for evidenced initial paid amount, to actual account holder; credit-only invoice creates no cash IN. Later receipts do not repeat initial payment or revenue. |
| Subsequent receipt | One actual collection leg per account received, with allocation links to invoices/opening debt. Preserve collector vs original seller. Bank/check/CliQ remains bank/clearing; never increment physical cash. |
| Return / refund | Customer-credit-only return creates no cash OUT. Actual refund creates OUT from verified funded/refundable account and links original collection(s), return and original invoice. Cancellation actor does not change historical holder. |
| Expense | Actual company/rep collected-cash funding creates OUT from that holder only on posting/approval. Pending/rejected or personal-funded expense creates no company/rep-collected-cash OUT; personal funding recognizes payable, later evidenced reimbursement creates OUT once. |
| Settlement / transfer | Exactly one source OUT and destination IN with common transfer identity and reciprocal account links; both commit together. A company-side IN still identifies the settlement rep without falsely making that rep the company account holder. No revenue/expense; combined owned cash unchanged. |
| Cancellation / reversal | Keep original leg(s) and append authorized linked inverse(s) to their original accounts, with dependency/funds checks, creator/poster and reasons. Count original plus inverse once each; do not exclude original and subtract inverse again. |
| Opening / known financial adjustment | One approved evidenced account opening or linked adjustment with counterpart GL treatment; not a new sale, collection or transfer. No default zero when history exists. |

Physical cash totals exclude bank/clearing and no-cash financial events. Existing
cash-screen details may expose methods/noncash source links with explicit account
labels; they must not manufacture cash rows for unpaid credit or a payable.
Settlement display grouping preserves both legs and each account after-balance;
it never hides a leg outside the current page or changes totals.

Independently reconcile, per company/currency/account/holder:
approved opening + all IN - all OUT = account position = mapped GL cash balance.
Each rep's statement equals that rep's cash position and GL dimension; company
cash plus all rep-held cash equals the company-owned physical cash control.
Match transfer pairs separately so an internal transfer cannot inflate external
collections or income. Preserve separate bank/clearing controls. Never combine
seller KPIs with holder cash, or certify totals from only loaded rows.

Keep existing cursor paging, stale-request guards and authorized full-export
paths. Capture denormalized display snapshots during trusted posting; batch/cache
bounded item-price reads for estimates, with revision/freshness markers. Global
summary estimates require the full authorized scope at a declared quantity/price
basis, not page sums. Price-change projection fanout, if needed, is bounded,
idempotent reporting work; it must not mutate cash/GL or block posting.

## 5. Smallest next batch and required tests

**Phase 2B-1: extend the existing exact-decimal helpers with string/unit APIs.**
Use `functions/src/trusted/exact_decimal.ts` and
`lib/core/finance/exact_decimal.dart`, retaining their existing numerical
adapters until callers are separately upgraded. Add no parallel amount library,
posting endpoint or business flow. A small shared synthetic vector fixture and
focused backend/Dart tests prove exact parse/format, sums, quantity x reference
price and before/after cash arithmetic. No database or UI behavior changes in
this first batch. Journal-intent validation follows as a separate small slice
integrated into `financial_ledger.ts`, not a competing posting implementation.

Acceptance: canonical signed units/decimal strings, declared independent scales
and bounded sizes; zero/midpoint/negative/residual/excess-scale/overflow cases;
the 10/3/5.000/7.000 example above; the same vectors agree in TS and Dart; valid
zero reference price differs from unknown; existing number-adapter callers and
tests remain equivalent. Reuse `test/exact_decimal_test.dart`; add backend cases
to existing integrity tests or a focused helper test. Run TypeScript lint/build
and relevant existing arithmetic tests only; no cloud, emulator or credentials
are needed for this pure helper batch. Its approved implementation and results
are recorded below.

Subsequent bounded slices, each with its own implementation scope:

1. Cash detail read contract: extend `CashMovementModel`, existing repository
   decoding, row presentation and PDF to expose already-stored fields and honest
   unknowns; preserve paging/authorization and test missing/invalid fields.
2. Cash write/GL contract: extend `cash_ledger.ts` and its existing callers, not
   callable names; prove account/creator/seller separation, atomicity, replay,
   concurrent spend/collection and linked cancellation/transfer reconciliation
   using isolated emulators before enabling new accounting effects.
3. Rep estimate: extend the existing balance model/repository/controller/screen
   and reporting projection with exact reference-selling estimates; verify full
   summary scope, freshness, price independence and zero extra financial writes.

Required integration regressions before the corresponding slices are accepted:
no-cost sale/return/transfer; free admin/rep invoice price changes; zero/custom
lines; missing reference price; quantity shortage/over-return/retry/concurrency;
admin confirming a rep draft; admin approving rep-cash expense; admin collecting
an old rep's customer; reassignment without seller/holder rewrite; partial then
later receipt; unpaid credit; bank/check/CliQ; refund to actual original holder;
both settlement legs; cancellation replay and downstream-use rejection; missing
opening/holder; exact GL and per-holder controls; backdated balance ordering;
filtered/paged totals and grouped transfer pages; Arabic/English/RTL details,
access denial and full PDF/export scope. Extend existing `cash_phase11`,
`cash_ledger_calculator`, receipt/return/expense/permission/rep-inventory tests
and backend integrity/cancellation suites. Do not claim them run in a docs-only update.

Documentation validation on 2026-11-04: **PASS**, six documents / 35 local
links and anchors, whitespace, `git diff --check`, existing integration-path
checks and removal of the prior mandatory-cost/parallel-helper requirements.
Runtime tests were not run because this update changes documentation only.

## 6. Phase 2B-1 implementation and verification

Completed locally on **2026-11-04** after explicit owner approval. Only the
existing arithmetic helpers and tests changed; trusted posting callers, persisted
amount semantics, screens/controllers, routes, schemas/rules/indexes and callable
exports were not changed. No real data or production endpoints were accessed.

Modified code: `functions/src/trusted/exact_decimal.ts`,
`lib/core/finance/exact_decimal.dart` and `test/exact_decimal_test.dart`.
Two new files are justified: `functions/test/exact_decimal.test.js` supplies
backend helper regressions/properties, and `test/fixtures/exact_decimal_cases.json`
is the single set of **107 shared vectors** consumed by both runtimes. No new
amount library, business feature, dependency or posting endpoint was introduced.

Both helpers now expose matching `parseUnits`, `formatUnits`, `rescaleUnits`,
`multiplyUnits`, `divideUnits`, `percentageUnits`, `sumUnits` and
`allocateCumulativeUnits` APIs. Values are BigInt unit integers; callers serialize
with `toString()` and keep scales separately. Scales 0-6 and 30-digit unit bounds
are technical limits, not an adopted currency/unit policy. Multiplication/division
use independent input/output scales and one final half-away-from-zero round;
percentage output keeps the input amount scale. Strict parsing rejects excess
fractional precision, whitespace, exponent notation, ambiguous/non-ASCII input
and oversized strings before conversion. Source adapters must normalize any
other approved input explicitly. Tax/discount and stock eligibility rules remain
with existing business callers, including editable/zero invoice prices and no costs.

**Confirmed defect:** safe-integer checking alone did not protect the numeric
output adapter: units `9007199254740991` returned `9007199254740.99`, which decoded
as units `9007199254740990`. Both signs now fail closed with `invalid-argument`
(TS) / `FormatException` (Dart) when the three-decimal result cannot round-trip.
Normal adapter rounding/order stays unchanged. A pre-change 10,000-operation
legacy corpus retains SHA-256
`6cd9ef81e9d6c0d018e99c4630b170a8b8725029fe9ab4f40261bcc8c503280b`.

The prior helper also lacked an exact string/mixed-scale entry point and reusable
cumulative allocation. These are capability gaps addressed without migrating live
callers. Independent rounding of three `0.998 / 3` shares remains `0.999` in the
legacy prorater by design; the new original-total cumulative API instead returns
`333, 332, 333` units, totalling `998`. Replaying an interval returns the same
result; persisting/authorizing consumed ranges and preventing duplicate writes
still belongs to the trusted posting transaction. No idempotency persistence was added.

| Verification | Evidence / limit |
|---|---|
| Before correction | New numeric-loss regression failed in both languages: Node 0 passed/1 failed; Flutter's four existing tests passed and the new fifth failed. |
| Focused backend | **114 passed**, including all shared vectors, independent quotient/remainder oracles, 2,000 seeded arithmetic cases, 1,000 seeded split/allocation cases, replay/coalescing/conservation properties and 10,000 legacy operations. |
| Focused Flutter VM | **116 passed** against the same vectors and equivalent seeded arithmetic/allocation rules; final test-loader cleanup rechecked. |
| Full backend regression | **375 passed, 0 failed/skipped**, isolated loopback Firestore emulator `127.0.0.1:8085`, synthetic test namespaces only. Includes pricing/free lines, no duplicate/concurrent effects, returns/refunds/receipts, expenses, cash settlements, permissions and existing reconciliation. |
| Full Flutter regression | **535 passed**, including existing invoice, receipt, expense, cash, returns, inventory, permissions, reports and UI tests. |
| Dart JavaScript target | **107 shared vectors passed**, using a generated ignored build harness reusing the Dart evaluator, compiled with `dart compile js -O1` and executed on Node/V8. The full headless Flutter/Chrome runner stalled at loading and was stopped; browser UI acceptance is not claimed. |
| Build/static checks | TypeScript `npm run build` and `npm run lint` passed; `flutter analyze --no-pub` reported no issues; Dart formatting and whitespace checks passed. |

Focused reproduction: build TypeScript, then
`node --test functions/test/exact_decimal.test.js` from the repository root;
`flutter test --no-pub test/exact_decimal_test.dart`. Existing backend suites
require a dedicated loopback emulator; never run them with production credentials
or endpoint fallback. Runtime logs and the one-time JavaScript harness are under
ignored `build/phase2b1/`. The existing synthetic snapshot regenerated by backend
tests was restored to its pre-test content; no historical artifact update is included.

Remaining risks: persisted legacy values/callers still use three-decimal
Number/double adapters; information already lost before entering a helper cannot
be recovered. Extreme formerly accepted lossy outputs now reject, deliberately.
The new exact APIs do not automatically upgrade invoice/cash/return callers or
change their calculation order. Cumulative quantities must share one base-unit
scale and original immutable total; sums require one scale/currency. Callers
validate that metadata and must persist eligibility/retry state.
This phase proves arithmetic, not complete accounts, imports or cloud performance.

**Smallest next batch:** the existing cash detail read contract in section 5:
extend `CashMovementModel`, existing repository decoding and current cash-row/PDF
components to preserve stored balances, payment/source/reversal references and
explicit unknowns. Keep account holder distinct from creator/seller; add focused
decoding, account-scope, pagination, presentation and export regressions. Do not
change money posting, create an endpoint/page or start double-entry persistence
in that next batch. This was the Phase 2B-1 stop boundary; the separately
approved read implementation is recorded below.


## 7. Phase 2B-2 cash read contract implementation and verification

Completed locally on **2026-11-04** after explicit owner approval. This phase
extends the existing cash screen and export. It changes no posting writer,
callable endpoint, Firestore schema/rule/index, journal, historical document or
balance. No production access, reset, migration or deployment occurred.
Phase 2B-1 arithmetic and its persisted three-decimal JOD semantics are reused.

| Existing files changed | Purpose |
|---|---|
| `lib/features/financial/data/models/cash_movement_model.dart` | Preserve stored details, nullable dates, exact amount/balance units, verified holder, distinct role aliases and trace-gap detection. |
| `lib/features/financial/data/models/financial_dashboard_snapshot.dart` | Keep nullable exact reported cash summaries separate from compatibility numeric fields. Other dashboard behavior is retained. |
| `lib/features/financial/data/repositories/financial_repository.dart` | Decode within approved company/rep scope; retain existing queries/cursors; export complete authorized pages using the same full-scope reported balances as the screen. |
| `lib/features/financial/controllers/cash_movements_controller.dart` | Deduplicate repeated page IDs and retain exact/full-scope summaries when appending details. |
| `lib/features/financial/view/widgets/cash_movement_presentation.dart` | One shared UI/PDF detail projection, selectable existing-screen details and exact, unique settlement pairing. |
| `lib/features/financial/view/screens/cash_movements_screen.dart` | Extend current cards/table with actual account IDs, distinct stored-rep attribution, detail expansion and explicit summary scope. Preserve date controls and existing settlement workflow. |
| `lib/features/financial/data/services/cash_report_pdf_service.dart` | Full authorized report, exact values, all available detail fields, explicit missing fields, independently directed RTL/LTR labels/values and paginated detail blocks. |
| `lib/core/localization/financial_translations.dart`, `lib/core/pdf/app_pdf_localization.dart` | Shared Arabic/English field, type, method, unavailable and balance-scope labels. Reuse existing financial-ledger account translations. |
| `test/cash_phase11_test.dart`, `test/pdf_services_settings_test.dart` | Extend existing screen/controller and bilingual/long-report regressions. |
| New: `test/cash_read_contract_test.dart` | Focused model/repository/presentation contract tests, including offline SDK query fakes; no new application implementation or dependency. |

**Read semantics.** Missing/invalid money, direction and dates no longer silently
become zero, IN or the current time. Display uses exact units and never formats
through a double. Excess precision, nonfinite and unsafe numeric values remain
unavailable; exact decimal-string fixtures preserve large values without changing
persisted semantics. Available stored before/after balances are shown verbatim;
an inconsistent exact before +/- amount equation is flagged, never repaired.
Those balances describe commit order, not business-date running balances.

A representative holder is established from `cashAccount=rep_cash` and the stored
account rep ID, with conflicting holder metadata treated as ambiguous. Company
cash remains distinct even when a company movement has sales-rep attribution.
Creator, seller, collector and posting actor are separate fields. Legacy aliases
are source-specific: invoice movement `createdBy*` identifies its original creator,
not the confirming actor; receipt `createdBy*` identifies its creator/collector;
expense `createdBy*` identifies the approver/poster, not the original submitter.
Refund `salesRepName` is not assumed to name its cash holder. Explicit identity
pairs never borrow another identity's name. The raw stored rep remains visibly
labelled as source-dependent. Unknown collector/actor/source creator stays unavailable.
Payment states such as partial, credit or cash-refund are not guessed as methods.

Existing date filters, company paths, representative `salesRepId` + `rep_cash`
constraints, server ordering and document cursors are retained. Defense-in-depth
decoding rejects cross-company or wrong-holder rep results. There are no per-row
source lookups. Screen summaries and PDF use full-scope reported openings/closings
and server aggregates, never loaded-page balances. Admin opening/closing is
explicitly company cash; IN/OUT covers all authorized accounts and includes both
transfer legs as cash movements, not revenue/expense. Rep balances remain separate.
Full export traverses all existing authorized pages (tested beyond 200 rows).
A unique equal-amount rep-OUT/company-IN settlement pair may be displayed together;
both rows remain present. Ambiguous, unequal or off-page counterparts stay single.

**Historical and reporting limits.** Some documents lack collector/posting actor,
source creator, holder, method, original invoice, cancellation/counterpart or audit
references. Only stored/verified legacy facts are shown; there is no backfill or
source enrichment. Existing Firestore `orderBy(date)` excludes documents without
that field; displaying them requires a separately scoped data/read strategy.
Existing balance projections must be ready; missing responses are unavailable.
Legacy Number/double storage and aggregate responses can already have lost
precision. Reporting calls are separate reads, not a single atomic as-of snapshot;
concurrent writes may advance projections between calls. This phase does not
certify historical completeness or GL reconciliation and adds no running balance.

Verification uses synthetic/offline fixtures and a dedicated loopback Firestore
emulator (`127.0.0.1:8086`), never real business data. Logs and rendered QA artifacts
are ignored under `build/phase2b2/`. The PDF skill workflow rendered English/Arabic
exports and inspected their layout; extracted text independently retained the
large exact amount, full ISO timestamps and reversal/source references.

| Check | Result |
|---|---|
| Focused cash/model/repository/controller/index/PDF suites | **48 passed**: missing/invalid fields, explicit identities, holder conflicts, methods, refunds/cancellations, unique transfers, authorized scopes, date reset, stale pages, duplicate retry, full 205-row export, unavailable openings, 320px/2x English/Arabic detail and existing long bilingual PDFs. |
| Full Flutter regression | **557 passed**, including existing invoice, receipt, return, expense, inventory, permissions, dashboard and report suites; final run confirmed after the PC interruption. |
| Backend rules, financial-ledger, cash-reconciliation and exact-decimal suites | **191 passed, 0 failed/skipped**, isolated synthetic emulator namespaces. Backend sources were unchanged. |
| Static/build checks | `flutter analyze --no-pub`: no issues. `npm run lint` and `npm run build`: passed. Whitespace checks passed. |

**Smallest next proposal (not implemented/authorized here):** narrowly extend the
existing `record_cash_settlement.ts` paired movement metadata through its current
`cash_ledger.ts` integration. Record explicit actor, holder and counterpart
identities for newly created settlement legs only, using the existing callable,
transaction, keys and UI. Do not combine this with a GL engine or historical
backfill. Before approval, specify the exact additive fields and compatibility
contract. Acceptance: identical financial amounts/balances, one equal OUT/IN pair,
explicit company/rep holders, matching settlement/counterpart IDs, honest seller/
collector absence, atomic failure, replay/concurrency protection, permission
regressions, existing read/PDF compatibility and local emulator-only verification.
Production deployment still requires separate explicit approval. Stop at Phase 2B-2.

## 8. Phase 2B-3 cash settlement metadata integrity

The owner separately approved Phase 2B-3 on 2026-11-04. The
[exact metadata contract and completion evidence](phase2b3-cash-settlement-metadata.md)
record the bounded change to newly created settlement pairs. The existing
callable, `cash_ledger.ts` balance states, trusted transaction, amount arithmetic,
idempotency and account isolation are retained. Existing repositories, cash
screen and PDF consume the additions through the Phase 2B-2 read contract.
The earlier section 7 stop boundary remains the historical Phase 2B-2 result.
No GL engine, unrelated posting changes or historical enrichment is included.

## 9. Phase 2B-4 settlement journal intent

The owner separately approved Phase 2B-4 on 2026-11-04. The
[exact offline intent contract and completion evidence](phase2b4-settlement-journal-intent.md)
record the pure settlement-only builder/validator, explicit monetary-policy and
account-dimension requirements, deterministic identity/conflict behavior and
offline tests. It reuses the existing financial-ledger mapping architecture and
exact-decimal helpers. Settlement posting, cash balances and application workflows
remain unchanged. No journal persistence or live posting integration is included.

## 10. Phase 2B-5 settlement transaction preflight

The owner separately approved Phase 2B-5 on 2026-11-04. The
[exact preflight contract and emulator evidence](phase2b5-settlement-preflight.md)
record the internal read-only transaction adapter, explicit approved book/policy/
mapping/period/binding resolution, original atomic source and current-position
checks, deterministic retry conflicts and separate recorded/read/commit times.
No financial posting code, cash balances, original source, endpoint or Flutter
workflow is modified by preflight. Missing real configuration remains blocked.
The pending-settlement timestamp/evidence contract remains a prerequisite to
separately approved atomic journal persistence; no future commit time is guessed.
