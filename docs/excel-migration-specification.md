# Historical Excel migration specification

Phase 1 requirements, refined through **2026-11-04, Asia/Amman**. Companion to the
[financial modernization strategy](financial-modernization-strategy.md).
Status: **specified, not implemented or validated against historical files**.
No production import, reset, backup or deployment is authorized here.

Phase 2A refinement: the [Firebase-only accounting design](phase2a-firestore-accounting-architecture.md)
fixes Firestore/Auth/Cloud Functions and the target posting/reporting contracts.
The specification below remains evidence-dependent. No historical files have
been validated and no importer has been implemented.

The [2026-11-04 inventory/cash requirements](phase2a-inventory-cash-integration.md)
settle the accepted operating scope: physical quantities and known financial
movements, without purchase costs/COGS. Missing costs do not quarantine a valid
sale, physical movement or quantity opening. Inventory cost/COGS remains
`not_recorded`, not zero. Reference-selling estimates are independently labelled
information; missing reference price flags estimate coverage, not operational
import eligibility. Never certify complete profit from this limited scope.

For advances/unapplied receipts, the Phase 2A design extends the customer-credit
control: distinguish liability principal from any already-recognized unapplied
advance-tax entitlement. Match each to its own GL/tax evidence, while statements,
allocation and refund limits use the evidenced gross customer entitlement. The
required legal tax bridge remains a company/accountant decision, never inferred
from a workbook payment label.

## 1. Evidence inventory and completeness

Retain original workbooks unchanged, access-controlled and hashed with SHA-256.
For each file record custodian, source system/company, export time/cutoff,
date range/timezone, filters/representative scope, workbook date system, sheets,
used/hidden rows and columns, row counts, currency, original cell types and
formula/cache presence. Scan every sheet, including hidden/filtered rows; never
treat the currently visible worksheet as the complete dataset. Record blank,
subtotal and footer rows as such, not as omitted transactions.

Every row receives exactly one disposition: canonical source, corroborating
reference, non-posting history, duplicate alias, non-data row or quarantined.
Each disposition links evidence and reason. No silently skipped rows. Distinguish
missing data from an explicitly attested zero. Files alone do not attest that all
transactions were exported; reconcile sequence gaps, export scope and independent
closing evidence. A source custodian must state known omissions.

### Current exports are evidence, not a ready import schema

Reviewed code:
[operational workbook](../lib/features/operational_report/data/services/operational_report_excel_service.dart),
[operational queries](../lib/features/operational_report/data/repositories/operational_report_repository.dart),
[accounting workbook](../lib/features/financial_ledger/data/services/financial_ledger_excel_service.dart),
[accounting export reader](../lib/features/financial_ledger/data/repositories/financial_ledger_repository.dart).

| Available report family | Useful evidence | Coverage limitation / required supplement |
|---|---|---|
| Operational Sales / Sales Returns | Line quantities, price/discount/tax, document numbers, dates, party/rep names, return's original line ID and source type | Repeated header totals are not additive line values. No universal stable invoice/customer/rep IDs, original stock movement/cost links or proven initial-payment snapshot. Current paid/outstanding values are not a collection history. |
| Operational Receipts | Number, amount/method, cash destination, related invoice numbers, total allocated/unallocated, cancellation/original amount | No stable receipt/customer/collector IDs or per-invoice allocation amounts. Cancelled rows can have zero effective amount: retain original plus reversal evidence, not a zero-value substitute. |
| Operational Expenses | Date/amount/category, funding, status, payer/rep names and approval/rejection metadata | No stable expense/payer/approver IDs, treasury movement linkage or independent purpose/owner classification. Pending/rejected rows are not posted expenses. |
| Accounting Journal / Sales Details | Source, reference, customer, rep and line IDs, paired accounts/amounts and product snapshots | Derived from incomplete v3 accounting and selected filters/period. Not proof of inventory costs, movements, allocations, tax liabilities or complete history. |
| Accounting GL / Summary | Derived openings, totals, running balances and warnings | Same underlying book as Journal; not independent corroboration. GL brought-forward balances are report projections, not extra opening events. |
| Required but not established by those reports | Known financial opening accounts/open items, treasury evidence, physical stock/custody movements, transfers/settlement pairs, ownership history and stable crosswalks | Obtain approved supplemental evidence for required monetary/quantity scope. Purchase costs are not required for that scope; any genuine cost evidence stays separately archived. Do not invent missing transactions, allocations, stock or opening balances. |

Create a coverage matrix by company, domain, date interval, location/rep and
currency. Classify each cell **complete**, **partial**, **absent** or
**conflicting**, with evidence, independent expected counts/totals, unresolved
questions and reviewer. Retain original document references even if a row can
only remain non-posting history. Quarantine uncertain identity/value/ownership
instead of guessing from names, phone numbers or current catalog metadata.

## 2. Opening boundary and anti-duplication policy

Approve a coherent reconstruction boundary **B**, final cutoff **C**, and an
as-of/timezone convention. Opening represents state immediately before B;
post only in-scope economic events in **[B, C]**. State snapshots must name their
as-of instant; a snapshot at C is not an opening before B. Earliest usable
history is evidence-dependent; do not inherit the reference platform's start date.

Choose and document one treatment for each non-overlapping scope:

1. **Reconstruction:** independently evidenced opening before B plus complete
   chronological events B through C. A zero opening needs evidence, not a default.
2. **Approved opening at a later boundary:** when earlier history is incomplete,
   carry independently supported known financial balances and physical openings
   at that boundary. Earlier documents remain reference-only and cannot post
   their revenue, cash, expenses or stock effects again. Historic P&L/stock flows
   before the boundary remain uncertified.

Mixed domain boundaries require an explicit reconciled bridge for every crossing
relationship; default to one company/book boundary. Otherwise block the plan.
An invoice before B collected after B references an opening open item and its
archived invoice; it does not repost that invoice. A later return of a pre-B sale
needs original quantity/return and monetary evidence and an approved opening
bridge; it does not require cost evidence in quantity-only mode.

The opening package contains **approved known financial account balances**,
receivable and
customer-credit open items, AP/rep payables where evidenced, each cash/bank/
clearing account, and owned quantity by location/custodian,
tax/other assets/liabilities/equity as evidenced and in the accepted scope.
Record unprovided cost/other financial
coverage explicitly; do not claim a complete financial-position statement.
Detail explains control totals;
it does not post another copy of those controls. Define midyear YTD reporting or
prior-period retained earnings explicitly. Never put accumulated sales into both
opening balances and reconstructed sales. No unexplained equity/suspense plug
or reference/invoice selling price may fill unrecorded cost or force agreement.

| Overlap risk | Mandatory treatment |
|---|---|
| Sale on multiple sheets or repeated product rows | One header/event; stable distinct lines; assert repeated header values agree. Sum line values once and header values once. |
| Invoice payment + receipt + cash/customer movement + v3 Journal | Pick one canonical economic source/component, link all representations as aliases/evidence. Initial payment and genuinely later receipts remain separate. Do not import derived movements/journal as extra collections/revenue. |
| Opening fields + opening transaction + GL brought-forward + opening correction | One approved baseline. Use immutable original debit/credit plus proven corrections to derive as-of balance; do not add edited signed/display amount and corrections again. Derived GL openings are comparison-only. |
| Expense + cash movement + reimbursement/settlement | Expense once; cash settlement/reimbursement reduces the proper asset/liability once and does not create another expense. |
| Return credit + refund + inverse receipt | Preserve each distinct linked economic component; do not apply the same customer credit/cash reversal twice. |
| Warehouse + custody + transfer pair + item opening/current quantity | Opening once per location/quantity scope; equal transfer OUT/IN, ownership unchanged. Current quantity is a control, not another receipt. Selling estimates never create GL/opening values. |
| Original Journal + derived GL + source documents | Source-driven posting is the default. If only ledger evidence exists, use a separately reviewed exclusive evidence route for that scope. Never post both source-derived and legacy journal entries for the same event. |

## 3. Normalized import contract

Workbook column names need not match this schema. A versioned adapter maps
actual sheets/cells into canonical records; original cell evidence is retained.
Fields below are mandatory when the relevant event exists. Unsupported or
unrecoverable fields are explicit null/unknown with a blocking reason where
they affect identity, known money, physical quantity, access or allocation.
Cost is not a required field; unknown reference prices affect estimate coverage
only. Such exclusions are declared, never silently converted to zero.

| Record | Required fields / relationships |
|---|---|
| Manifest | Schema/adapter version; source system/company/book; B/C and timezone; file hashes/sheet counts/filters; approved currency/scales/policy/mapping versions; source coverage, control evidence and approval references. |
| Common provenance | Stable source/economic ID, source type/revision, original document number/ID, workbook hash/sheet/row/cell references, raw/canonical hashes, business date, original creation time if known, accounting date, actual import/posted timestamps separately. Historical unknown actor/time must stay unknown; importer identity is separate. |
| Party and actor crosswalks | Stable source customer/supplier/rep/owner ID -> target ID; company; original spelling/number aliases; actor -> preserved Firebase UID where established; creator, current assignee and dated assignment evidence separately. Inactive/historical actors can retain restricted reference identities without recreating Auth users or granting access. |
| Product/location masters | Source/target item IDs, unit/base-unit conversion, tracking at event time, active/deleted status, company ownership, warehouse/location and rep-custodian IDs. Reference selling price/revision/as-of evidence is separate from invoice price; unknown price is explicit, not a quantity/sale blocker. Item name/code alone is not a unique key. |
| Invoice header + lines | ID/number, customer, seller, creator, dates/due date, lifecycle; line ID/index, item/custom/untracked type, unit/quantity, unit price, discount basis/amount, tax basis/rate/amount and totals; header totals; original issue source and movement links. Repeated product lines must not collapse. |
| Initial-payment component | Stable component ID, invoice link, amount, date, actual account/method/collector, supporting receipt/movement aliases. Zero must be explicit/evidenced. Current `paidAmount` minus incomplete receipts is not acceptable reconstruction. |
| Receipt + allocations | ID/number, customer, collector/actor, date, amount, method and exact treasury/instrument account; one row per allocation with receipt ID, target invoice/line or opening-item ID, amount, original allocation order/date where known; unallocated amount and purpose; lifecycle and cancellation source/reason/date/actor. |
| Return + refund | Return ID/number/date/status, original invoice/line, quantity and cumulative monetary residuals, tax/credit/debt/refund split, original physical issue/movement/destination; actual refund event/account/evidence separately. No original issue-cost requirement in quantity-only mode. |
| Expense/payable | Stable ID, amount/date/currency, category and reviewed business/owner purpose, payer/rep UID, funding account or personal source, state, approval/rejection history, payable/reimbursement links. |
| Cash settlement/instrument | Event ID, source/destination account/holder, amount/date, paired movement IDs, actor/state, linked receipt/payment/clearing/dishonour references where supported. Unknown payment methods cannot default to cash. |
| Physical stock movement | Stable movement/event/line ID, item/base quantity, IN/OUT, company owner, source/destination location/custodian, business date/order, transfer pair/source, original issue/return links and explicit opening-quantity evidence. No cost-pool/cost-value requirement or manufactured cost journal. |
| Opening/control package | Evidenced financial account debit/credit balances, matched open items/treasury and physical quantity openings, as-of time, independent statement/count/document references, reviewer and earlier-history/YTD treatment. State cost/COGS and any other unverified financial coverage explicitly; no complete-statement claim or fabricated cost opening. |
| Resolution/alias registry | Stable missing-ID assignment or duplicate alias, affected evidence, reason, reviewer/date and before/after normalized hash; conflicts retained. No unresolved relationship is silently filled by import order. |

Parse numeric cells from their decimal lexical representation into exact units;
text decimals use declared locale, separator and scale. Preserve IDs/leading
zeros as text. Reject NaN/infinity, ambiguous separators, overflow, precision
loss, inconsistent signs and unsupported currencies. Already-lost Excel numeric
precision cannot be recovered by formatting; require independent source evidence.
Normalize Arabic/Western digits only through recorded deterministic rules.

Handle 1900/1904 workbook dates explicitly, reject invalid/ambiguous serials or
dates, preserve date-only meaning and Asia/Amman business boundaries rather than
guessing host timezone. Do not execute macros, formulas or external links. Formula
cells require an approved frozen value with provenance and independent validation;
an absent/stale cached result blocks affected values. Rendering a rounded cell is
not evidence for its exact stored amount.

Validation requires consistent line/header totals, tax/discount arithmetic under
the confirmed policy, valid companies/foreign keys, stable unique IDs, valid
lifecycle/as-of states, paired transfers, available cash/stock and chronology,
allocation sum + unallocated = receipt amount, no over-allocation/over-return,
and physical quantity/source provenance; costs are not a sale/quantity gate.
Do not replay current FIFO allocations as if they
were observed historical links. Missing historic assignment may leave financial
evidence restricted and block operational access readiness until resolved.

## 4. Deterministic, resumable and idempotent import

The future importer must produce a reviewable dry-run plan without target
writes. All data, policy, mapping, identity and resolution versions are pinned.

1. Inventory/hash originals; map raw rows and completeness evidence. Normalize
   and validate masters, identities and event dependencies without posting.
2. Resolve duplicates and missing identities in a persistent reviewed crosswalk.
   Prefer original system IDs. If absent, approve a collision-checked composite
   identity or assign a stable registry ID once. File name/hash, row position,
   amount/date or person name alone cannot establish economic uniqueness.
3. Give each complete economic action a root key equivalent to
   `company/book/sourceSystem/sourceType/stableSourceId/action`;
   deterministic component/line IDs belong to that root's immutable effect
   manifest. Sale, initial payment and physical stock from one confirmation commit as one
   complete event, not independently retryable partial postings. Distinct real
   refunds, allocations and reversals have their own linked action identities.
   Enforce uniqueness in the target authority across **all batches and retries**.
   Importer/request IDs, workbook hashes and adapter/mapping versions are not
   duplicate-avoidance namespaces. The same event in another file is an alias,
   not a new event.
4. Hash canonical semantic payloads with policy/mapping versions and stable
   line IDs; exclude file position, processing time and run metadata. Same key
   + same payload resolves to the original result; same key + different payload
   is a conflict. Correcting a posted import uses an approved linked correction,
   never a new key, overwrite or replacement batch that posts it again.
5. Build a deterministic dependency order: opening/masters, then chronological
   economic events with original sequencing and stable-ID tie breakers. A
   receipt follows its charge; a return follows its issue; a transfer pair is
   indivisible. If equal-date order changes physical stock or allocation eligibility and source sequence is
   unknown, quarantine rather than choose a financially convenient order.
6. Generate expected known journal/AR/treasury/physical-stock effects, counters and row
   dispositions. Hash the complete plan and inputs. Approval pins that hash;
   any input/policy/resolution change invalidates approval. Human approval does
   not resolve unknown amounts or unexplained differences.
7. In a separately authorized isolated import, route each complete event through
   the same trusted posting/invariant boundary as ordinary business events.
   Claim identity, write all effects, audit and result atomically. Bounded chunks
   can contain whole events; never split one economic event. Workers use
   appropriate locking/serialization; no concurrent live posting into the book.
8. Persist checkpoints only as execution progress. After interruption/lost commit
   acknowledgement, recover the economic identity/result before replay. Target
   committed events, not an external checkpoint, determine what already posted.
   Authentication/authorization still applies on retry and result recovery.
9. Reconcile independently and retain the report. Candidate book is not active
   until the entire approved scope passes and has separate promotion approval.
   No automatic emails, notifications, government submission or external payment
   effects may run during replay; outbox projection consumption remains scoped
   and idempotent. Do not feed imports into legacy posting triggers.

Planned artifacts: `manifest.json`, coverage/control tables, row dispositions,
identity/alias/resolution registry, canonical records, `validation.json`, immutable
posting plan + hash, execution results/checkpoints, `reconciliation.json` and
review record. Every reported difference links source cells, target IDs and
expected/actual exact strings. Artifacts contain sensitive business data and
must remain access-controlled, outside public build output and source control.

## 5. Independent reconciliation engine requirements

Implement a separate offline/read-only engine, not a wrapper around posting
builders or their expected output. Compare three evidence layers: original
source + approved opening/independent controls, canonical import plan, and
persisted target book/subledgers/projections. Two sheets derived from the same
ledger are one evidence source. A balanced trial balance cannot detect an
entirely omitted sale. External bank/cash evidence, source document registers,
customer confirmations and stock counts are needed to establish
completeness, not only internal consistency.

Use exact arithmetic for calculations **and serialized results**. Report by
company/book/currency, account, customer, original seller, collector/cash holder,
product, warehouse/custodian, day/period and source type; never net currencies or
allow opposite discrepancies to cancel. Separate historical seller activity
from current assigned portfolio. Financial dates use declared half-open report
ranges and the approved business timezone/cutoff.

| Independent control | Required comparison |
|---|---|
| Evidence coverage | Every file/sheet/row disposition accounted for; unique document/line counts, numbered-document gaps/voids, statuses and source totals vs registers/attested controls. Every unexplained gap blocks affected completeness. |
| Journal / trial balance | Every monetary event posts exactly once with expected account/component/date/dimensions; every entry balances; period debits/credits and closing balances match approved controls. Assets = liabilities + equity including current earnings; no forced balancing line. |
| Sales / tax / expenses | Header/line net, discounts, tax and gross independently agree with source registers. Approved expenses only; distinguish liability recognition and later reimbursement. Opening/YTD and imported movements do not overlap. |
| Customer / AR / customer credit | Opening debit/credit items + sales - receipts - returns + refunds/corrections = signed closing debt, with credit applications cancelling between controls. Sum debit open items = AR control; sum credit principals = credit-liability controls, with advance-tax entitlement reconciled separately where applicable. Each allocation consumes its gross receipt/credit and eligible charge exactly once; retain unallocated/opening debt explicitly. |
| Treasury / rep payable | Per account opening + evidenced inflows - outflows = closing vs GL and independent bank/cash/instrument evidence. Invoice initial cash is not mutable paid-to-date. Settlements conserve company-owned cash; personal expense/payable/reimbursement reconciles without double expense. |
| Inventory quantity | Per product/location/custodian opening + IN - OUT = closing vs target and independent count/cutoff bridge. Warehouse + custody = company-owned stock, including inactive/deleted products. Transfers sum to zero for company quantity; sale/return provenance and cumulative caps agree. |
| Reference-selling estimate / cost scope | Recalculate per-item available quantity x evidenced reference selling price at declared quantity/price basis, separately from invoice amounts and GL. Missing price makes estimate partial/unavailable without failing valid quantity/financial scope. Inventory cost/COGS is not recorded or certified, never fabricated from selling price or treated as known zero. |
| Reports / ownership / integrity | Full and filtered statements, exact date openings/running balances, dashboards and exports vs target GL/subledgers at one watermark; historical references, current customer access and original rep/collector/custodian links retained. No cross-company or obsolete-book leakage. |

Machine result: **PASS** only when checks, completeness evidence and all required
domains of the explicitly declared operating scope pass with zero unexplained
differences; excluded cost/COGS remains unrecorded and full profit is unavailable; **FAIL** for known discrepancies,
invalidity or duplicates; **BLOCKED** for missing/ambiguous evidence or pending
policy. Emit exact expected/actual/difference, severity, source/target pointers,
rule/version, coverage and unresolved decisions. Approved normalization must be
explicit and reconciled, not hidden by a tolerance. No automatic repairs, plugs,
waivers to PASS or production write mode.

The existing [offline legacy checker](../functions/scripts/integrity_reconciliation.js)
is useful baseline evidence, not this engine: it consumes legacy numeric
thousandths, serializes some results as Number, checks only its known collections,
has no complete valuation/tax/AP model and relies on supplied history coverage.
Its synthetic PASS cannot certify Excel completeness or target accounting.

## 6. Isolated rehearsal and promotion gates

Later tests must use the dedicated Firebase Emulator Suite or an explicitly
authorized separate Firebase staging project, synthetic identities and no production credentials,
project aliases, endpoints or triggers. Verify isolation before any write; deny
network side effects. Restore and real-data rehearsal require separately
authorized protected copies, not permission inferred from synthetic testing.

Required acceptance cases:

- Same files imported twice; duplicate event across files/batches; reordered rows,
  sheets and renamed files; changed payload under the same key; missing-ID collision.
  Prove exact event/journal/balance counts remain unchanged on replay.
- Crash before/after commit/checkpoint, lost acknowledgement, concurrent workers,
  competing receipt/return/transfer and period closure; no partial or duplicate effects.
- Decimal midpoint, overflow/excess precision, Arabic digits/locale, malformed dates,
  formula/cache loss, hidden/filtered rows, repeated header totals, repeated product
  lines and a full return whose split financial amounts require a final residual;
  quantity x reference-price rounding independent of actual invoice price.
- Opening plus reconstructed-history overlap, duplicate opening corrections,
  partial/credit/cash sale with later receipts, opening-debt collection, cancelled
  receipt, paid/unpaid/free-line return, actual refund, stock/cash settlement,
  personal expense and separately evidenced reimbursement.
- Missing transaction/physical stock movement/initial payment/allocation/ownership,
  unknown method, negative stock, unbalanced journal and cross-company link:
  block affected required-scope promotion; never manufacture missing effects.
- Missing purchase costs do not block legitimate sale/return/transfer/quantity
  import; produce no invented inventory-cost/COGS entry. Unknown reference price
  affects estimate coverage only. Verify invoice prices cannot rewrite catalog
  reference prices or physical quantities.
- Two clean isolated reimports produce identical canonical plans, economic IDs,
  exact ledger/subledger totals and reconciliation results. Audit import timestamps
  may differ; business identity and amounts may not.
- Independent control totals plus intentionally omitted, duplicated and wrongly
  classified but balanced transactions prove the engine detects more than balance.
  Restore backups/configuration into isolation and verify counts, hashes, references,
  access, reports and recovery before a production proposal.

Promotion requires confirmed architecture/policies, complete accepted source
operating scope, zero unexplained known-financial/physical-quantity differences, reproducible rehearsal,
reviewer sign-off and restore evidence. Production also requires a reviewed
cutoff/freeze or reconciled delta, disabled obsolete writers/clients, one active
book and a recovery plan preserving any post-cutover activity. None of these
gates implies permission to delete data, deploy, reset Auth or proceed to another
phase. Protected resources and backup/reset approval boundaries are specified
in the [strategy](financial-modernization-strategy.md#3-historical-replacement-and-safety-boundary).
