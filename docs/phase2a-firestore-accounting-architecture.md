# Phase 2A: Firebase accounting architecture

Design only, **2026-11-03, Asia/Amman**. Firestore is the sole business database,
Firebase Authentication supplies identity, and Cloud Functions owns trusted
business/accounting operations. This platform decision is fixed. No alternative
database, accounting engine implementation, import, reset or deployment is in
scope of that design phase. The separately approved Phase 2B-1 helper, Phase 2B-2 cash read,
Phase 2B-3 settlement metadata, Phase 2B-4 offline settlement intent and
Phase 2B-5 read-only transaction preflight work are
recorded in section 8; subsequent implementation still needs its own scope.

This refines the [strategy](financial-modernization-strategy.md) and
[Excel specification](excel-migration-specification.md). Reuse the Phase 1
workflow audit; do not repeat it or treat the reference platform's policies as
approvals. The design below governs target details where Phase 1 was provisional.
Current application behavior and data remain unchanged.

**Owner refinement, 2026-11-04:** the [inventory/cash integration requirements](phase2a-inventory-cash-integration.md)
settle physical inventory without purchase costs, informational reference-selling
estimates, free invoice pricing, complete cash detail and reuse of existing
screens/functions/models. Cost accounting is not recorded in this operating
scope; missing costs must not block sales, returns or stock workflows. The
refinement supersedes the previous costing prerequisite and parallel-helper proposal.

## 1. Authority, precision and chart of accounts

One legal company has one active accounting book. Reconstruction/test books are
isolated and cannot receive ordinary live commands. All business posting enters
a typed Cloud Functions command -> authorization -> domain validation -> one
Firestore transaction. No financial effect is posted by a client or by a
document-change trigger. Operational documents, stock custody, treasury and GL
are distinct records linked by the same immutable posting event.

Use canonical decimal strings at API boundaries and **integer-unit strings** in
Firestore; parse/compute with TypeScript BigInt and Dart BigInt. Never convert
monetary, reference-price estimate or quantity values through Number/double, numeric increments or
floating-point aggregate queries. Safe bounded numeric counters are permitted
for sequence/line counts, not amounts. Persist schema/unit scale with the book;
currency/scales cannot change after first posting.

Recommended policy for review: JOD with 3 monetary decimal places, reflecting
current app precision; quantity and input unit-price capacity up to 6 decimals,
with a declared scale per unit. Confirm actual currencies/units first. Currency,
quantity and rate scales are separate. Use at most 30 decimal digits for stored
unit integers initially; validate intermediate sizes/ranges too. Normalize zero,
reject excess scale, exponent notation, NaN and ambiguous input. Import-only
normalization can accept a reviewed source conversion with its exact difference.
Use half-away-from-zero at approved line/tax/allocation boundaries, preserving
cumulative/final residuals; never an epsilon or a balancing plug.

`chart_accounts` has stable IDs, unique normalized codes reserved transactionally,
name/code snapshots on posted lines, parent, type, normal side, posting/group
status, active/dating revision and required dimensions. Validate an acyclic,
same-company hierarchy. Parent/group accounts cannot receive entries; no account
deletion after use or mutation of its used type/control semantics. Classification
changes require reviewed new accounts/mapping or presentation revisions, not
rewritten posted lines. Account revision,
deactivation, mapping and approval commands conflict with posting that read the
affected records. Dated tax/account mappings cannot overlap: serialize changes
through a per-code revision document, not a race-prone absence query.

Illustrative account families, **not approved company account codes**:

| Family | Posting accounts / required controls |
|---|---|
| Assets | Company cash; rep-held company cash; bank; cheque/digital/card clearing; trade AR; eligible input-tax receivable; other evidenced assets. Inventory-cost accounts are reserved for a separately approved future cost scope, not fed selling estimates. |
| Liabilities | AP; rep/employee reimbursement payable; unapplied receipts/advances; return/customer credits; output tax; evidenced owner loans/other liabilities. |
| Equity | Owner capital, retained earnings, current earnings presentation and drawings/distributions according to legal form. No unexplained opening-equity plug. |
| Income / contra income | Net sales, sales returns/approved discounts, separately classified other income. Cash collection and stock transfer are not income. |
| Expense | Classified operating expenses. COGS/stock-value losses are not recorded without a separately approved evidenced cost scope. Reimbursement/settlement is not another expense. |

Customers and representatives are dimensions/subledgers, not a new chart account
for every person. Control accounts require the relevant customer, treasury
account or payable reference and can only be posted by that domain. Inventory
cost references apply only in a separately approved future cost scope.
Manual journals cannot bypass AR, treasury, tax or allocation controls; they cannot value physical stock from selling prices.
Each company is balanced independently; group access never grants posting rights.
Single functional currency initially; unsupported currencies/FX block posting
until separately designed and approved.

## 2. Collection design

`C = companies/{companyId}`, `B = C/books/{bookId}`. IDs are stable opaque IDs or
SHA-256 of canonical length-delimited identity tuples, not concatenated display
names or sequential document IDs. Path scope and redundant company/book fields
must agree on every reference. No implicit `default_company` in new accounting.

| Path below C or B | Authority and principal fields |
|---|---|
| Existing `/users`, trusted user context and company configuration | Extend the existing single authorization resolver for company capabilities/status/revision and active-book/maintenance gates. Company membership evolution must not create a competing role policy. Auth UID alone is not authority; profiles remain protected. |
| Existing `C/customers/{id}`, root `items/{id}` and location/custody metadata | Reuse current masters/repositories, validating company scope and stable source IDs. Current item `price` is reference selling price; invoice price is separate. New metadata can clarify ownership/unit/location without a duplicate catalog or inventory flow. |
| `B` and `B/policy_revisions/{id}` | Mode `configuration/reconstruction/live/read_only`, confirmed immutable currency/scales, fiscal/calendar and dated mappings, fixed posting-lane count/schema; inventory mode `quantity_only`, cost coverage `not_recorded`. Cost availability is not an ordinary business-posting gate. |
| `B/chart_accounts/{id}`, `account_codes/{hash}`, `journal_definitions/{id}` | COA, code uniqueness and account/journal rules/numbering. Current master revisions are mutable only through trusted controls; posted snapshots are immutable. |
| `B/periods/{id}` | Explicit date range, fiscal year, `open/closing/closed`, revision, close watermark/reconciliation and approval references. A fiscal-calendar revision document governs non-overlap. |
| Existing invoices/quotations/returns/expenses and their draft/state fields | Preserve the existing draft/approval/confirmation lifecycle and repositories, using compare-and-set revision/posting bindings. Posted amount snapshots stay immutable; no parallel draft or business-document collection/lifecycle. |
| Existing business documents + `B/events/{id}` | Reuse original source collections/IDs. Immutable accounting event holds source snapshots/links, economic action/digest, known policy versions, actor/approver/import origin, business/accounting dates, committed timestamp, lane/sequence and effect manifest. Snapshot is evidence, not another business workflow. Quantity-only events can have no journal. |
| `B/journal_entries/{id}` | One immutable header **with bounded embedded `lines[]`**: journalDefinitionId/period/date, source event, line IDs, account snapshots, debit/credit unit strings, currency, required dimensions and reversal links. `journalEntryId` identifies this entry, distinct from its journal definition. No later appended lines. This is canonical GL authority. |
| `B/source_keys/{hash}`, `request_keys/{hash}` | Unique economic action -> committed event/result/digest; actor-scoped request key -> same action/digest. Create preconditions, no expiry for financial deduplication. Compare full tuples as well as hashes. |
| `B/posting_lanes/{lane}` | Per-lane last committed sequence/hash. Proposed fixed 16 lanes selected by event hash; initial count is a benchmarkable engineering choice, not a company accounting policy. No book-wide counter on every post. |
| `B/open_items/{id}`, `open_item_positions/{id}`, `party_positions/{id}`, `allocations/{id}` | Immutable original AR/AP/credit items and allocation/unallocation events; mutable exact remaining/control positions updated atomically. Party positions distinguish AR debit, advance/unapplied and return-credit liabilities. Original seller and actual collector remain separate. |
| Existing `C/cash_movements/{id}`, `C/cash_balances/{id}` and reviewed account metadata | Extend the current canonical money legs/positions with exact account/holder identity, payment method, before/after units, creator/poster/seller and transfer/reversal links. Reuse `cash_ledger.ts` in existing callers; no parallel treasury movement writer/store. Bank/clearing, if surfaced, is tagged separately from physical cash. |
| Existing warehouse stock, `C/rep_inventory_balances/{id}`, invoice/return quantity limits | Atomic exact quantity per company/item/location/custodian; retain cumulative return quantity and monetary residual limits. No cost-pool dependency or cost requirement. Reference selling estimates are separate rebuildable reporting fields. |
| Existing `C/stock_movements/{id}`, `C/rep_inventory_movements/{id}` | Keep canonical immutable quantity legs, original source/line/transfer/return references, tracking and actual custody. Event manifest links their IDs/counts/digests; no second physical movement system. Deterministic evidence chunks, only if needed later, are accounting provenance and commit with the source event. |
| `B/audit_events/{id}`, `outbox/{eventId}` | Immutable transactional audit and projection intent. Mutable delivery status is separate from immutable intent. Audit covers posting plus master/policy/period/access/correction commands. |
| `B/projection_tasks/{id}`, `projection_receipts/{id}`, `gl_rows/{rowId}` | Rebuildable deterministic work/chunk completion and one GL row per canonical journal line, carrying lane/sequence/account/date/dimensions. Never a second posting authority. |
| `B/report_generations/{id}`, `report_chunks/{id}`, `report_heads/current` | Immutable ready report generation at a source watermark, exact account/day/month/period summaries and opening snapshots; atomically published head pointer. Building/failed generations are never presented as final. |
| `C/import_batches/{id}` and protected import/archive paths | Pinned input/plan hashes, row dispositions, identity/alias crosswalks, resolutions, checkpoints, reconciliation and approval records. Original Excel/exports in restricted Firebase Storage with hashes/references; no financial posting via upload triggers. |

Embedded journal lines make the entire entry immutable/atomic in one document;
queryable `gl_rows` are derived. Limit initial journals to 256 lines and 512 KiB
per document, with preflight rejection and no hidden truncation. These are
proposed application budgets below Firestore's 1 MiB document limit, not proof
that every valid document already fits. Exempt embedded arrays/maps from indexes.
Large operational/inventory evidence can use deterministic bounded chunks **in
the same transaction**, not later append operations to a posted journal.

## 3. Posting, concurrency and immutability

### Posting protocol

1. Callable authenticates the Firebase UID and validates request shape/size.
   Resolve company/book, persisted source/action/revision and approved intent;
   never trust supplied role, total, stock holder, import flag or ledger lines.
   Require current membership/capabilities, active company, company access and
   current customer/document ownership through the existing trusted resolver. Validate App Check where supported;
   it supplements authorization, not replaces it.
2. In the transaction, read authorization/configuration gates and source/request
   keys first. After current authorization, a matching committed action returns
   its original result even if its period has since closed; it does not rerun
   today's stock, balance or account-activity checks. For an unposted action,
   read source/draft, pinned policy/current mapping controls, referenced
   accounts/journal and open period, the selected lane, and all required
   open-item, treasury, physical stock and return-limit records. No cost reads
   or cost-policy approval are required for quantity-only inventory.
   **Complete all reads before writes.** Recovery cannot bypass current authorization.
3. Recompute the full intent from trusted snapshots. Validate one currency,
   exact debit = credit, at least two nonzero journal lines, one positive side
   per line, valid dimensions, source state, allocations and cash/physical-stock
   bounds. Legitimately zero-money stock activity creates an event without a
   zero-value journal. No generic client-controlled control-account journal.
4. Economic key = company/book/source system/source type/stable source ID/action.
   A sale, initial-payment and physical stock effect share one confirmation event;
   component/line IDs live in its manifest. Refunds, allocations and reversals
   have their own genuine linked action IDs. Never derive identity solely from
   amount/date/payload: two identical genuine receipts can both be valid.
5. Same economic key + same canonical semantic digest returns the original
   result; different digest conflicts. Another request key cannot repost the
   action. Request-key reuse for a different action/digest conflicts. Canonical
   hashing pins schema/source revision, account/policy versions, ordered stable
   lines and dimensions, excluding retry key, import file position and execution
   timestamps. Approval binds that digest; changed intent invalidates approval.
6. Create source key, event, frozen document, complete journal, all inventory/
   treasury/open-item/allocation effects, audit/outbox and result together;
   update source binding, exact control positions and the lane sequence/hash
   in that transaction. Transactional human numbering is per journal/fiscal
   scope if required; its contention is measured separately from event lanes.
7. Lost acknowledgement resubmits/retrieves the same identity. SDK contention
   retries rerun the entire callback without external side effects, changing
   IDs, notifications or government submissions. Permanent validation/conflict
   errors do not become new request keys. Bounded retry exhaustion is a visible
   recoverable error, never permission to write balances manually.

Two receipts compete on the same customer/open-item positions; stock issues on
the same physical stock position; refunds/returns on original eligibility counters;
cash outflows on the same treasury position. These records must serialize.
Do not shard an authoritative spendable balance and lose its no-overspend check.
Nonnegative physical cash and stock remain required; bank overdraft, if ever
allowed, needs an explicit separate account policy. Missing positions with
existing history block posting rather than start at zero.

Period close writes the period/gate read by every affected post; account,
membership, source revision and policy changes similarly conflict with readers.
Firestore supplies commit-time serializability, but business invariants and
referential checks are our responsibility. There are no server-side foreign-key
or journal-balance constraints supplied by this design. [Firestore transaction isolation](https://firebase.google.com/docs/firestore/transaction-data-contention).

Immutability is enforced by create-only trusted commands, no client writes,
restricted runtime/deployment IAM and tests. Admin SDK bypasses Firestore Rules:
Rules cannot prevent a privileged backend bug/operator from rewriting history.
Audit includes before/after master revisions, source/digest and linked reversals;
per-lane event hash chains plus restricted archived checkpoints/backups provide
tamper evidence, not absolute protection from a principal controlling both.
No ordinary maintenance overwrite/delete route is allowed. [Firebase security boundaries](https://firebase.google.com/docs/firestore/security/rules-fields).

### Bounds and throughput

Initial proposed preflight ceilings: 400 document writes, 600 document reads,
4 MiB estimated request footprint including index effects, 512 KiB per document
and 256 journal lines. They are test targets, not Firebase platform limits.
Confirm actual serialized/index sizes and SDK behavior before release; use
margin. Firestore documents a 10 MiB request limit, 270-second transaction limit
and 60-second idle expiration; transaction documentation also describes a
20-second lock deadline. Keep callbacks short and network-free apart from their
Firestore reads/writes. [Quotas](https://firebase.google.com/docs/firestore/quotas),
[transactions](https://firebase.google.com/docs/firestore/manage-data/transactions).

Group GL lines only by identical account and required legal/reporting dimensions;
retain product/line provenance in the existing source/stock records. Chunked evidence
keeps 100-product sales/transfers feasible without one GL write per product.
Before replacing these workflows, prove existing 100-line capacity, including
distinct products, transfers with 200 positions and return counters; no cost-pool
writes are part of that budget. If a valid
case exceeds the budget, redesign its bounded representation before release;
do not reduce capacity silently or split its financial posting into partial commits.

Hot products, company cash and journal numbering remain natural contention
points. Sixteen lanes distribute unrelated posting and avoid a company-wide
sequence bottleneck; they do not make one hot balance infinitely scalable.
Measure retries, p95/p99 latency, read/write/index fanout and Functions cost on
representative skew/load before agreeing production throughput targets. The
emulator cannot certify cloud throughput. Partition/numbering changes require a
versioned Firestore protocol review; no alternative database is proposed.

## 4. Accounting treatment and business workflows

Below, G = approved gross, N = net of discounts, T = tax, P = original payment,
No purchase-cost or COGS component is required in the current operating scope.
Tax-point/recognition decisions below remain
pending; confirmation must represent the approved recognition event. A draft or
quotation never recognizes revenue. Each row includes its operational subledger
effects and applicable authorization; related sale/payment/stock components
commit together. New advance/owner/instrument commands are designed here but
remain unavailable until their own implementation and policy approval.

| Operation | Correct proposed journal and linked behavior |
|---|---|
| Credit sale | Dr AR G; Cr net sales N; Cr output tax T where due. Create customer charge/open item; stock issue separately linked in the same event. Preserve original seller regardless of customer reassignment. |
| Cash / partial sale | Same sale, plus Dr actual company/rep treasury P; Cr AR P through the linked payment/allocation component. Outstanding = G - P. Payment state cash/partial/credit is not a bank/card method; original payment account must be evidenced. |
| Physical stock sale | Quantity OUT from the actual warehouse/rep custody; no inventory-cost/COGS journal in this scope. Sale revenue/tax/AR/payment still posts atomically with quantity. Free tracked lines still move stock; legitimate custom/untracked lines do not. Missing tracked movement provenance blocks a return, but missing issue cost does not. |
| Receipt paying charges/opening debt | Dr real cash/bank/clearing; Cr AR for applied amount. Preserve original allocations. For unapplied amount, Cr unapplied-receipt liability instead; future application Dr liability/Cr AR, with no new cash/revenue. Signed customer debt reduces immediately via AR or credit liability. |
| Large receipt / allocations | One complete receipt can recognize funds plus an explicit unapplied liability atomically. Bounded subsequent allocations are separate complete events with source/target limits; no partial cash posting. Normal oldest-due allocation stays automatic within budget. Larger pending allocation must be visible/recoverable before enabling this variant, not silently marked fully allocated. |
| Customer advance / overpayment | Explicit approved command: Dr actual treasury; Cr customer advance liability, not revenue or negative AR. Apply later Dr advance liability/Cr AR with immutable links. Existing ordinary receipt guard against exceeding positive debt stays until this explicit flow exists. Advance tax, if due on receipt, needs the reviewed treatment described below. |
| Receipt cancellation / dishonour | Domain-aware inverse of original cash/clearing/AR/liability effects and allocations, with original account/instrument evidence and no unsafe downstream consumption. Keep original receipt plus linked reversal; an already cancelled retry changes nothing. A cleared cheque is not cancelled as if still in physical cash. |
| Sales return | Dr sales returns N_r and eligible output-tax reversal T_r; Cr AR only for eligible unpaid charge, Cr customer-credit liability for paid excess. Original-line/cumulative quantity, tax/discount and return-credit limits prevent duplicates/over-credit. |
| Physical return | Quantity IN to the proven original source/approved return location with cumulative sold/returned limits and condition evidence. No cost/COGS journal or original-cost prerequisite in quantity-only mode. Revenue/tax credit and actual refund remain separate known financial effects. |
| Refund / customer credit | Dr evidenced customer-credit/advance liability; Cr verified actual treasury. Application to debt: Dr liability/Cr AR. No second sale reversal or collection. Cap refunds against verified refundable funds/credit and prior refunds; mixed/unknown accounts need explicit resolution. |
| Company / rep-collected-cash expense | Dr classified expense plus recoverable input tax only if evidenced/eligible; Cr actual company/rep cash. Admin immediate and rep pending -> approved/rejected flows retain their business behavior; pending/rejected create no posted expense/cash. |
| Rep personal-funded expense | Dr expense/eligible input tax; Cr rep reimbursement payable. Later reimbursement Dr payable/Cr actual treasury. Never reduce collected cash on initial recognition or record the expense twice. |
| Representative collections / settlements | Rep-held cash is a company asset with holder dimension, not representative revenue or automatically personal liability. Rep -> company settlement Dr company cash/Cr rep-held cash with paired treasury legs; total company cash unchanged. |
| Other internal cash/bank transfers | Dr destination treasury/Cr source treasury, with fees as a separately evidenced expense. Match both actual accounts/instruments; no revenue, customer receipt or expense merely because cash changed holder. |
| Warehouse <-> rep custody, later rep <-> rep | Paired equal quantity legs; same company ownership, no cash/revenue/expense or cost journal. Reference-price estimates may move with quantity between holders, never through GL. Later rep-to-rep command needs explicit scope within existing transfer components, not unrelated postings. |
| Physical receipt / evidenced purchase | A stock IN needs quantity, ownership, actual location/source and reason, not purchase cost. A separately evidenced supplier bill/payment follows its approved financial classification without fabricating item costs or a purchase from a quantity-only IN. |
| Stock count / damage | Approved counted-minus-book quantity difference or documented loss updates physical stock with provenance. No invented monetary loss/gain or value adjustment. Reference-price estimate changes are informational, not journals. Any later actual cost write-down is separate scope. |
| Owner withdrawal / capital | Confirmed sole-owner/partner drawing: Dr drawings/owner equity; Cr actual treasury. Contribution Dr treasury/Cr capital; repayment of proven owner loan Dr payable/Cr treasury. Company/shareholder withdrawals may instead be a receivable, loan or lawful distribution: legal form/purpose decides. Never classify from `other` expense or name keywords. |
| Openings / historical corrections | Approved known-financial opening balances and matched open-item/cash/physical-quantity detail once at the boundary, with unrecorded cost/other unverified coverage disclosed. Earlier transactions included in opening remain reference-only. Correct posted errors through linked approved events/current open correction period or reviewed restatement plan; never edit originals or casually reset opening. |

**AR invariant:** GL AR = remaining debit charge items; GL customer-credit
liabilities = their remaining liability principals by class. With invoice-point
tax, signed customer debt = AR debit minus those liabilities. When tax was already
recognized on a still-unapplied advance, retain that separate tax entitlement:
gross customer credit = liability principal + its unapplied advance-tax component;
signed debt = AR debit minus gross credit. Reconcile principal to credit-liability
GL, and the tax component to original tax events/approved bridge, not twice to
the same control. Gross receipt = applied to AR + unapplied principal + any
recognized tax. Application consumes gross entitlement once, Dr advance principal
and the approved tax bridge/previous-tax offset, Cr AR gross, alongside the
invoice tax calculation. Refund consumes the corresponding principal/tax rights
under approved refund rules. Both require the dated tax mapping; an unknown
bridge blocks the operation. Applying credit preserves signed debt; refund
reduces gross credit and increases signed debt.
Historical receipt links are retained; new allocations use due date, invoice date,
then stable ID. Never infer historical FIFO links from today's open items.

**Reversal invariant:** reverse the complete economic event, including eligible
allocations, treasury and physical inventory effects, not just GL lines. A full safe
reversal uses exactly opposite original monetary lines, original snapshots and
linked compensating subledger effects (no cost effects in quantity-only mode);
partial returns/refunds use their distinct
domain rules. Atomically claim a reversal identity and check prior returns,
allocations/refunds and remaining eligibility; block dependent/unsafe reversals.
No generic journal reversal may bypass those checks. Keep original and reversal
immutable with separate dates/reasons/approvals; a further correction is another
reviewed linked event, not a deleted reversal.

## 5. Policy recommendations and remaining decisions

All recommendations below require recorded company/accountant confirmation
before relevant real posting, not a configurable flag that silently approves them.

| Decision / owner / gate | Recommendation and material tradeoff |
|---|---|
| Currency, quantities and rounding / owner + accountant / before first real post | Confirm JOD/3 monetary decimals and actual units; support up to 6 quantity/unit-price decimals, explicit round points and residuals. Exact unit strings lose native numeric aggregation/sorting convenience; use exact projections and tested sortable keys instead. Reject unsupported currencies. |
| Inventory operating mode / owner / settled 2026-11-04 | Physical quantity only; purchase costs are not recorded and must not gate sale/return/receipt/transfer workflows. Do not substitute reference or invoice prices for cost. Cost/COGS and artificial profit are outside current acceptance. |
| Representative informational value / owner / settled 2026-11-04 | Available quantity x item reference selling price, explicitly labelled estimate. Invoice price remains freely editable by admin/rep and cannot update reference price or quantities. Missing reference price flags estimate coverage, not sale eligibility. Use declared quantity/price snapshot basis; never post estimate changes to GL. |
| Quantity chronology / operations / before import | Reconcile physical movements, openings, transfers and sold/returned quantities with source order where needed; retain shortage/concurrency guards. Do not impose cost-pool chronology on ordinary quantity-only sales. Missing real movement history still needs evidence; missing cost does not. |
| Tax / accountant / before taxable posting | Dated tax codes, inclusive/exclusive price basis, exemptions, rounding and recoverability with explicit account mappings and documentary evidence. Confirm legal tax points, rates and refund rules; do not infer current rates or treat all legacy gross as revenue. Recognition/delivery vs invoice timing must be explicit. |
| Advance tax / accountant / before advances | Base mapping assumes tax at invoice/recognition. If tax is due on advance receipt, split gross into net advance and tax then; later invoice/application must credit/bridge already recognized tax exactly once. Persist the tax-event identity and gross entitlement. Block advances until this complete mapping is confirmed; no guessed double taxation or tax-free default. |
| Fiscal periods / owner + accountant / before real posting | Recommend calendar fiscal year with monthly periods if legally appropriate; Asia/Amman date boundaries; forbid ordinary posting to closed periods. `open -> closing` freezes affected dates, captures watermark, requires subledger/TB/source/tax reconciliation before `closed`. Failure stays blocked; reopen requires authorized independent review/reason/audit. Year-end earnings carry-forward is governed once, not automatic duplicate opening revenue. |
| Opening / data custodian + accountant / before import promotion | One evidenced boundary for known financial balances/open items/cash and physical stock quantities; cost is not required or invented. State unverified financial coverage and avoid complete-statement claims. Confirm YTD/retained earnings treatment. A large opening package may consist of approved independently balanced known-financial events with exact detail/control mapping in an inactive book; no partial activation or duplicate detail postings. |
| Corrections and approvals / accountant + owner / before posting adapters | Append compensations in an approved open period; specialist decides material prior-period restatement/tax correction. Keep original business date and evidence. Recommend independent approval for manual journals, opening, policy/period changes, stock counts, owner flows and historical corrections; retain normal admin/rep workflow capabilities through explicit policies. |
| Treasury / owner + accountant / before cash/advance adapter | Real account/holder mapping, no negative physical cash, explicit clearing/dishonour/fees, gross advances/customer credits vs AR, refunds and rep reimbursements. New advance/owner/card flows are separate actions, not reinterpretations of existing payment-state labels. |

Cost accounting is deferred, not estimated as zero. Monetary journals/TB and
cash/AR controls cover recorded financial events; inventory cost, COGS and full
profit/financial-position conclusions remain explicitly unavailable. This does
not block physical inventory/sales or their independently reconciled import
scope. A future cost module needs separate evidence and approval; do not revive
it through a mandatory policy flag or infer profit from selling estimates.

## 6. Security and future companies

- Deny all direct client writes to new accounting, money, stock, allocation,
  policy, membership, import and report-authority paths, including admin clients.
  Preserve existing safe draft/client reads under their current Rules boundaries;
  introduce no competing endpoints to replace a functioning scoped query.
  Keep default-deny recursive rules. Extend existing scoped repositories, financial
  opening/summary callables and read Rules; new journal/period data uses those
  reviewed boundaries, not a parallel cash/report API.
- Functions verify current membership/capability and company/book on every
  command/read/page. Read membership in posting transactions so concurrent
  revocation conflicts. Claims/UID alone cannot select another company, role or
  historical document; company admin is not platform admin. Use runtime IAM
  and a reviewed writer module boundary because Admin SDK bypasses Rules.
- Keep current assignment-based customer access and complete authorized
  statements, original-document rep restrictions, actual collector/holder and
  original seller attribution. Expose authorized DTOs; Rules cannot redact
  sensitive fields inside a readable journal document. Reps do not get the
  company GL, costs or another rep's full documents through a statement export.
- Distinct capabilities: operational posting, accountant/manual journal,
  approval, period control, company policy, import preparation/apply and report
  access. Server role-to-capability mappings are explicit and audited; no
  self-escalation, arbitrary `importMode` parameter or reuse of a production
  admin session in test. Every retry and exported artifact rechecks access.
- Company-scoped paths and IDs on all masters/references, no shared catalog
  without explicit ownership. Cross-company references reject. Future group
  reporting reads only separately authorized companies and never nets different
  legal books; intercompany posting requires a separately designed workflow.
- Firebase Auth UIDs, protected user profiles/preferences, Storage attachments
  and required configuration stay outside any business reset. Maintain a reviewed
  crosswalk for historical/inactive actors without recreating Auth users or
  granting them access. Production reset/backup/retention/recovery boundaries
  remain those in the strategy; none are executed in this phase.

## 7. Reporting, indexes and reconciliation

### Consistent GL, TB and reports

No asynchronous live aggregate is accounting authority. GL derives from immutable
journal lines; TB groups exact debits/credits by posting account, showing opening,
movement and closing/net side. Closed-year earnings treatment is explicit. A
balanced TB is necessary but insufficient: omitted/duplicate balanced events
must also fail source/subledger reconciliation.

Each event increments exactly one lane sequence **in its posting transaction**.
No reserved gaps: lane sequence represents a committed prefix, including
stock-only events. Read all lane states in one read-only transaction to capture
`W = {lane: committedSequence}`. Backdated events receive later sequence, never
rewrite an earlier snapshot. Every report/export/cursor carries book, currency,
schema, filters, dates/timezone and this watermark/generation.

Outbox workers deterministically create GL and operational movement rows from
canonical events; completion receipts are idempotent per event/generation/chunk.
Workers may retry or arrive out of order; manifest count/hash validation detects
missing/extra rows. A recovery scanner enumerates lane prefixes to find missing
tasks even if a trigger was missed. Triggers are at-least-once and unordered,
so they never post accounting or increment money without deduplication.
[Firebase trigger delivery](https://firebase.google.com/docs/functions/firestore-events).

Build an **immutable report generation at W** from canonical prefixes, or from
the previous ready generation plus exact new-event deltas, including backdated
dates. Copy-on-write summary chunks may reuse unchanged prior chunks; the ready
manifest pins every chunk/version. Publish the head only after all required
events/GL rows and exact reconciliation checks through W complete. Do not apply
events after W into that generation. A newer rolling dashboard aggregate cannot
supply openings for an older report. Failed/incomplete generation stays hidden;
serve the last ready snapshot with visible freshness or return not-ready.

Exact account/day/month summaries and closed-period openings support GL/TB
without rescanning full history. For mid-day or filtered scopes, combine the
same-generation opening with bounded immutable row queries; arbitrary filters
without summaries use a scoped Functions report job, not an unbounded client
download. A job reads source rows only through W. Current operational spend
positions are not historical report balances. Rebuildable rankings can use
tested fixed-width sortable exact-unit keys; amounts remain unit strings.
Firestore `sum()` ignores strings; it is not the money aggregation engine.
[Aggregation behavior](https://firebase.google.com/docs/firestore/query-data/aggregation-queries).

GL pages query each lane with account/scope and date range plus `laneSeq <= W[lane]`,
then merge deterministic ordered streams. Sort by accounting date, lane/sequence,
line ID; state that this is stable report order, not a global statutory posting
sequence. Signed cursors bind all lane positions, W, company/book/actor and filters;
recheck access on every page. Preserve whole journal entries for journal views;
account GL views legitimately show the selected account lines. Full exports use
the same pinned snapshot as totals, including date boundaries and openings.
Arabic/English/RTL output and familiar workflow labels remain acceptance criteria.

### Query/index contract (proposed, not deployed)

All normal queries start at a company/book collection path. Exact key reads need
no composite. Collection-group/report jobs remain backend-only and must add
company/book constraints. Indexes below are logical field order; include stable
document-ID tie breakers and measured ASC/DESC variants only when used.

| Query | Required equality / ordered fields |
|---|---|
| Event recovery / watermark delta | `events`: laneId ==; laneSeq ASC, document ID. |
| Journal page | `journal_entries`: laneId ==, optionally journalDefinitionId/periodId ==; accountingDate ASC, laneSeq ASC, document ID; apply laneSeq watermark bound. |
| GL account/date | `gl_rows`: laneId ==, accountId ==; accountingDate ASC, laneSeq ASC, lineId ASC, document ID; laneSeq <= W. |
| Customer/seller/collector statements | Dedicated scoped rows: laneId ==, customerId/sellerId/collectorId == as relevant; accountingDate ASC, laneSeq ASC, row ID. Do not conflate those scopes. |
| Open-item allocation | `open_item_positions`: customerId ==, kind ==, state == open; dueDate ASC, originalDate ASC, document ID. Position updates conflict in posting; a prepared allocation plan pins item revisions and party position. |
| Operational stock/cash history | Dedicated movement rows: product/location/custodian or treasuryAccountId == plus laneId ==; businessDate ASC, laneSeq ASC, row ID; same watermark for reconciled reports. |
| Import/execution work | batch/state and bounded shard/cursor; no whole-company scan inside a posting transaction. |

Exempt unit strings, embedded journal/evidence arrays/maps, large notes/snapshots,
digests and unused timestamp fields from single-field indexing; keep only queried
metadata and the explicit composites. No Cartesian filter-key fanout. Indexed
sequential fields and hot keys still need load validation; use hashed IDs and
lane-leading composite queries, not sequential document IDs. [Firestore scaling/index guidance](https://firebase.google.com/docs/firestore/best-practices).
Missing-index errors fail visibly; never fall back to client-side full-book scans.

### Independent controls and Excel readiness

The [Excel specification's independent controls](excel-migration-specification.md#5-independent-reconciliation-engine-requirements)
remain mandatory: source/coverage totals vs plan vs persisted accounting and
subledgers, per company/customer/holder/location/product/period. GL AR matches
debit items; liabilities match advances/unapplied/credits; treasury matches
actual accounts and paired settlement legs; physical warehouse plus custody
quantities match the independent movement reconstruction. Reference-selling
estimates reconcile to their own declared price/quantity basis, never inventory
GL. Cost/COGS is `not_recorded`, not a blocker or assumed zero.
Audit/outbox/projection manifests match canonical event counts and
digests. Advance-tax entitlements reconcile separately from liability principal
so gross customer credit and tax controls both agree. Validate full and filtered
outputs at W. No offsetting differences across
owners/products/accounts may hide a discrepancy.

Import preserves immutable files/row dispositions, reviewed identity aliases,
original references and actor/assignment/physical-stock provenance; preserve any
genuine cost evidence separately without making it a requirement or posting it.
Map the prior
specification's component keys to child IDs under the atomic root action above;
root source uniqueness and immutable complete manifests prevent two workbook
representations from posting the same sale/payment/physical movement twice. Plan hash pins all
policy/identity/schema versions. Historical dates use controlled reconstruction
periods, with no external outbox effects. Checkpoints never override committed
source identities. No importer, assumed source schema, presumed zero opening,
cost, transaction, relationship or historical acceptance is supplied here.

Use a clean isolated Firestore book/project for future rehearsals. Extend
existing function/repository/model/screen integration points as defined in the
[refinement](phase2a-inventory-cash-integration.md); do not add duplicate pages,
callables or parallel business implementations. One accepted
book switch eventually replaces old business collection readers/writers; no
permanent compatibility layer or summing old/new ledgers is required. Preserve
numbered documents, customer ownership, original seller, collector, custody and
full statements through typed adapters/new exact models. Existing pages, drafts,
quotation conversion, admin/rep actions and PDFs/Excel stay recognizable; add
explicit advance/unapplied-credit/approval states only when implemented/tested.
Old posting triggers/clients must be disabled before an approved cutover.

## 8. Phase 2B: smallest independently testable batch

Status 2026-11-04: the owner separately approved Phase 2B-1; its helper-only
implementation and local evidence are in the [completion record](phase2a-inventory-cash-integration.md#6-phase-2b-1-implementation-and-verification).
The separately approved [Phase 2B-2 cash read contract](phase2a-inventory-cash-integration.md#7-phase-2b-2-cash-read-contract-implementation-and-verification) is also complete.
The separately approved [Phase 2B-3 settlement metadata contract](phase2b3-cash-settlement-metadata.md)
extends the existing settlement writer only; its local evidence and remaining gaps
are recorded separately.
The separately approved [Phase 2B-4 settlement journal intent](phase2b4-settlement-journal-intent.md)
is complete offline. Explicit company policies and account mappings remain
prerequisites; the intent is not connected to journal persistence or live posting.
The separately approved [Phase 2B-5 settlement transaction preflight](phase2b5-settlement-preflight.md)
validates approved configuration and committed source/current-position evidence
inside a read-only transaction. Its timestamp contract preserves recorded server
fields independently of SDK commit metadata; no unknown future commit is invented.
The architecture below remains the design boundary, not an implemented engine.

**Phase 2B-1: extend existing exact-decimal helpers with string/unit APIs.**
Use `functions/src/trusted/exact_decimal.ts` and
`lib/core/finance/exact_decimal.dart`, existing arithmetic tests and one shared
synthetic vector fixture. Retain current numeric adapters until callers are
upgraded in separately tested slices. No parallel amount library or business
posting path; no Firestore, endpoint, UI or production changes in this batch.

The [integration plan and required tests](phase2a-inventory-cash-integration.md#5-smallest-next-batch-and-required-tests)
define acceptance, existing cash/rep inventory integration points and subsequent
small read/write/report slices. Prove exact parse/format/range/rounding and
quantity x reference price / before-after cash equations in TS and Dart, with
hand-worked vectors and existing-adapter equivalence. Journal-intent validation
and persisted transaction/idempotency proof follow in separately bounded steps
inside the existing financial posting helpers. An offline helper PASS is not
proof of the accounting engine or historical data.

## 9. Phase 2A acceptance and stop boundary

| Design gate | Result / limitation |
|---|---|
| Firebase-only stack and protected resources | Defined; Firestore/Auth/Functions fixed. No engine, Auth reset, production read/write, deployment or infrastructure change performed. |
| Accounting/workflow coverage | COA/journals/GL/TB/periods/reversals/audit and all requested economic operations mapped; Phase 1 behavior retained. New advance/owner/instrument capabilities remain design-only. |
| Atomicity/security/report integrity | Concrete source identity, exact units, transaction/read conflicts, balances, immutable envelope, Rules/IAM boundary, watermark/generation and index contracts specified. Runtime proof remains future work. |
| Policy and historical evidence | Quantity-only mode, reference-selling estimate and free invoice prices are settled owner requirements. Tax/fiscal/financial-opening decisions and source quantity/cash/ownership evidence remain pending. Cost/COGS is not recorded; no profit certification is claimed. |
| Scalability | Bounds, query shapes and contention points identified; max-size/load/cost targets require later measurement. No cloud performance certification from this document. |
| Helper completion / next batch | Section 8 links completed Phase 2B-1 through Phase 2B-5 evidence. The next proposal is a pending-settlement evidence/timestamp contract with emulator proof before atomic accounting persistence, subject to separate approval. Phase 2B-5 creates no journals and has no live call site. |

The 2026-11-03 design-only validation remains historical evidence. Current
Phase 2B-1 arithmetic/runtime results are in the linked completion record;
the accounting engine remains unimplemented. Phase 2B-2 read/presentation results
are in section 7 of that record; section 8 links the Phase 2B-3 completion. No importer, real-data reset or
deployment follows from this completion.
