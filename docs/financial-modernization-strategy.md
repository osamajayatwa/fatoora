# Fatoora financial modernization strategy

Phase 1 baseline, refined by Phase 2A through **2026-11-04, Asia/Amman**. Working repository:
`C:\src\fatoora`; `C:\src\fatoora_platform` is reference only.

## Decision, authorization and evidence

Rebuild the financial domain around complete double-entry accounting, then
replace the existing Firestore business dataset using a validated historical
Excel import. Legacy collection names, numeric models, posting functions and
v3 ledger compatibility are **not permanent constraints**.
The [2026-11-04 inventory/cash refinement](phase2a-inventory-cash-integration.md)
requires physical inventory without purchase costs, informational reference-selling
estimates, freely editable invoice selling prices and detailed traceable cash.
Extend existing functions/models/repositories/screens; no duplicate pages,
competing endpoints or parallel business implementations. Preserve required
business behavior, original evidence and traceability rather than defective
schemas or historical accounting classifications.

This document supersedes the future strategy in section 8 of the
[integrity audit](audits/inventory_financial_integrity_audit.md#8-modernization-strategy).
That audit's historical findings and test evidence remain valid within their
recorded scope. [Financial Ledger architecture](financial-ledger.md) describes
the current implementation, not the target accounting system.

Phase 1 audit/requirements, Phase 2A design and the separately approved
Phase 2B-1 helper, Phase 2B-2 cash-read, Phase 2B-3 settlement-metadata and
Phase 2B-4 offline settlement journal-intent and Phase 2B-5 read-only settlement
transaction-preflight completions are documented here. The owner
has fixed **Firestore + Firebase Authentication + Cloud Functions** as the stack.
The [Phase 2A architecture](phase2a-firestore-accounting-architecture.md) refines
the target and records the bounded Phase 2B results. Phase 2B-3 adds metadata to
new settlement documents through the existing writer. No GL engine persistence,
importer, historical import, production access, deployment, reset or destructive
operation is performed or authorized by these design documents. Every later implementation phase needs its own scope authorization;
production deletion, deployment and other destructive operations each require
separate explicit approval of the concrete operation.

Evidence is local source, rules, tests and existing audit artifacts, not a live
database inspection. No historical Excel files were supplied or found in the
repository scan excluding generated build/dependency directories. Historical
completeness, live balances and deployed behavior remain **unverified**. The
previous synthetic reconciliation is not historical acceptance.

## 1. Current workflow audit and behavior to retain

The [detailed flow register](audits/inventory_financial_integrity_audit.md#2-transaction-flow-register)
provides individual variants and known defects. The following register maps the
current source boundaries to mandatory replacement behavior. All referenced
backend files are under `functions/src/trusted/`; approval means existing
business authorization unless explicitly described as a proposed future policy.

| Workflow / current evidence | Required behavior in the replacement |
|---|---|
| Draft invoices and quotations: invoice/quotation repositories, `firestore.rules`, `confirm_invoice.ts` | Draft create/edit/delete and quotation conversion have no financial/stock effect. Confirmation validates persisted source, customer access and totals; posts once atomically. Preserve numbers, due dates, snapshots, discounts, tax, payment state and quotation links. |
| Warehouse and representative sales: `confirm_invoice.ts`, `custody.ts` | Admin warehouse and rep own-custody sources remain distinct. Tracked stock leaves the actual source; repeated product lines remain distinct. Custom/legitimately untracked lines have no stock movement; free tracked lines still move stock. An entirely zero-total invoice is currently rejected. Retain shortage, invalid-tracking, cross-company and partial-posting guards. |
| Initial payments: `confirm_invoice.ts`, `financial_ledger_mappings.ts` | Customer owes gross less original payment. Cash follows the proven company/rep account. Preserve `initialPaidAmount` and original account evidence; mutable `paidAmount` includes later collections and cannot reconstruct initial cash by itself. |
| Collections: `create_receipt.ts` | Cash, bank, check and CliQ retain distinct meanings. Cash follows actual collector; noncash uses identified bank/clearing. New receipts cannot exceed positive customer debt. Oldest due date, invoice date, then ID defines new allocation order. Receipts can pay opening debt without a fabricated invoice. Preserve actual historical allocations rather than running today's allocator over old data. |
| Receipt cancellation: `cancel_receipt.ts`, Phase 3 document | Admin-only linked inverse; restore allocations and customer debt, reverse original cash/clearing effect only with safe provenance/dependencies. Keep original receipt, cancellation reason/actor/time and original amount. Already-cancelled replay creates nothing. Current bounded allocation and dependency guards must have replacement coverage. |
| Sales returns: `confirm_sales_return.ts` | Link original invoice **line**, cap cumulative quantity/money, allocate discount/tax residuals cumulatively. Return stock to proven original source under eligibility rules. Support receivable reduction, customer credit and verified cash refund separately. A free-line return can be stock-only. Missing OUT provenance and unsafe/mixed-account cash refunds block. |
| Expenses: `expenses.ts`, expense rejection rules | Admin company-cash expenses post immediately; rep submissions remain inert until approval. Approved collected-cash expenses reduce rep cash; personal-funded expenses create rep payable without reducing company/rep collected cash. Rejected/pending expenses do not enter finalized totals. Preserve category, funding, approval and reimbursement status. |
| Rep cash settlement: `record_cash_settlement.ts`, `cash_ledger.ts` | Admin-only equal rep OUT/company IN; conserve combined cash; verify available balance and replay identity. Never classify settlement as revenue or a second collection. |
| Customer opening and correction: `post_opening_balance.ts`, `update_opening_balance.ts` | Positive debt and negative customer credit, no cash. Original and signed corrections remain traceable and occur once. Replace mutable original display metadata with immutable opening plus linked corrections. Reconstruct old originals using debit/credit plus adjustments. |
| Company cash opening: `post_company_cash_opening_balance.ts` | One evidenced opening, no income. Existing hard-coded authorized identity/date is a legacy control to replace with reviewed opening policy; it is not the new history boundary. |
| Stock creation/adjustment: `inventory.ts` | Item opening and warehouse IN/OUT retain quantity, notes, actor and identity. Existing `correction` means IN, not an absolute count. Preserve quantity-only operations without purchase-cost requirements; require documented physical purpose and approved count differences; do not treat historical inbound as a proven purchase. |
| Warehouse/custody transfers: `confirm_inventory_transfer.ts` | Equal source/destination quantities, company ownership retained, no sale/purchase; atomic shortage checks. Preserve both movement IDs and actual locations/custodian. Product deactivation must not erase balances/history. |
| Customer creation/reassignment/access: `customer_profiles.ts`, `customer_assignment.ts`, `customer_queries.ts`, Phase 4 documents | Original creator, current responsible user, historic seller, collector, cash holder and stock custodian are different roles. Assignment changes access/current portfolio, not historical sale attribution or debt. Current rep can see the complete customer statement; another rep's original documents remain restricted. Creator fallback applies only to evidenced legacy unversioned ownership; do not grant access from ambiguous assignment-like fields. |
| Reports/statements/exports: `dashboard_reporting.ts`, `financial_ledger*_reporting.ts`, financial/customer/operational/ledger repositories | Retain authorized customer statements, dated openings/running balances, current portfolio receivables, historic rep sales, actual cash/custody, expense/payable totals, search, pagination and full-scope PDF/Excel exports. Reports must declare book, scope, currency, date boundaries and freshness. Retain Arabic/English and RTL/LTR output. |
| Trusted posting/security/retry: `common.ts`, `exact_decimal.ts`, `financial_ledger.ts`, `pending_posting_keys.dart`, `firestore.rules`, audit triggers | Backend authorization, tenant ownership, no direct client financial writes, atomic effects, collision rejection and durable retry/readback. Keep exact arithmetic; remove binary numeric storage as an accounting requirement. Audit/outbox intent must become atomic with posting. |
| JoFotara: retained disabled callable and source snapshots | No exported active submission workflow exists. Preserve known government references/status as evidence; import must not submit/re-submit invoices or interpret acceptance as accounting posting. |

Retain the current [role and invoice rules](phase1-sales-rep-permissions.md):
approved reps can perform their authorized quotation/invoice/receipt/return
workflows without resurrecting obsolete permission flags. Both roles can use
nonnegative prices (no catalog-price comparison) and valid discounts; custom-only
invoices are supported. Preserve the documented 100-line invoice/transfer
capacity, positive quantities, valid discount/tax bounds and positive invoice
total within a measured atomic budget. Customer creation still honors
`allowSalesRepCreateCustomers`; customer opening operations check current
assignment. Keep no-negative-stock and cash-availability guards. New approval
controls or changes to these business capabilities must be explicit reviewed
policy decisions, not accidental losses during refactoring.

Absent operations are requirements gaps, not behaviors silently supplied by the
rebuild: purchases/AP, general posted-invoice/expense reversal, customer advances,
rep reimbursement, bank/check/CliQ clearance or dishonour, Visa/card lifecycle,
owner drawings/capital, rep-to-rep stock transfer, multi-location count approvals,
period close/reopen and source-cost valuation. Classify evidence for these if it
exists; implementing new workflows needs a later approved scope. The owner has
chosen physical quantity inventory without purchase costs. Cost valuation and
COGS are not current prerequisites for sale/return/stock workflows or their
historical import. Keep them unrecorded, without fabricated zero/selling-price
costs or profit. Reference-price estimates are informational reporting only.

Current v3 entries are equal debit/credit pairs with gross sales credited to
sales, no separate output-tax liability and no inventory-asset/COGS journals.
Catalog stock times **current** cost is not historical valuation. Existing
BigInt intermediates still persist three-decimal `number`/`double` values.
Asynchronous audit/reporting triggers and mutable customer/cash/stock totals
are insufficient foundations for complete accounts. These components may be
replaced, not preserved as accounting truth.

## 2. Firestore accounting architecture

The [Phase 2A design](phase2a-firestore-accounting-architecture.md) is the
canonical detailed target: Firestore remains the sole business database,
Firebase Authentication supplies identity and Cloud Functions owns trusted
posting. The database choice is settled; no database replacement is proposed.
Legacy collection schemas, numeric models and posting logic can be replaced
within Firebase while recognizable business workflows and original evidence
remain intact. The Phase 1 register above records current behavior; Phase 2A
explicitly designs new advances/owner/clearing operations without enabling them.

The design specifies:

- Company-scoped chart/accounts, periods, immutable embedded-line journals,
  source/action uniqueness, request aliases and linked reversals.
- Exact unit strings/BigInt, one atomic event spanning documents, GL, AR/credit
  items, treasury, physical stock, audit and outbox; no independent dual writes.
- Separate company ownership/location/custody, treasury holder, seller and current
  customer assignment, with exact subledger-to-GL controls.
- Partitioned posting prefixes and immutable report generations for consistent
  GL, trial balance, openings and exports, with explicit indexes and permissions.
- Proposed accounting treatments, policy recommendations/tradeoffs, bounded
  transaction budgets and a smaller Phase 2B-1 extension of existing exact-decimal helpers.

These are specified controls, not an implemented engine or proven cloud
throughput. Company accounting/tax/fiscal/financial-opening decisions and real historical
source completeness remain pending. Future implementation must prove atomic
limits, concurrency, authorization and reconciliation in isolated Firebase tests.

## 3. Historical replacement and safety boundary

The [Excel import specification](excel-migration-specification.md) is part of
Phase 1: evidence/coverage, normalized schema, opening boundary, deterministic
planning, reconciliation and isolated rehearsal requirements. It is a contract
for later implementation, not an existing validated importer. Excel is the
intended transaction source; approved Firestore exports, documents, bank/cash
evidence and stock counts may supplement/verify gaps. Legacy totals are evidence
to compare, not automatically correct control totals.

Before any eventual reset, create a dated, access-controlled backup of the
existing Firestore database, including all subcollections and root `items`, plus
an inventory/backup of required application configuration: company settings,
ownership/role mappings, counters, templates/numbering, rules/indexes, deployed
function/build versions, environment/project routing, storage attachments and
references, and required IAM/service configuration. Preserve secret references
and recovery instructions securely; never copy secret values into reports or Git.
Record export cutoff/consistency method, counts, hashes, retention, restore steps
and a verified isolated restore. A Firestore export alone does not constitute
backup of the whole application. Backup execution requires authorized access;
it has not occurred in Phase 1.

| Scope | Proposed eventual treatment; no deletion list approved |
|---|---|
| Business transactions, movements, balances and v3 ledger | Replacement candidates only after evidence reconciliation, retention/archive, restore proof and explicit reset approval. Source/archive remains recoverable and referenceable. |
| Search, summaries, account-activity states, reporting caches | Rebuild from the accepted new book; never import as additional financial events. Disable obsolete writers/triggers before cutover. |
| Root `items`, company documents/settings/counters | Mixed master/configuration scope: explicitly classify every path and owner. No broad root/company deletion; missing company IDs do not imply safe ownership. Preserve or import reviewed masters and initialize numbering without collisions. |
| Audit and assignment history | Preserve restricted immutable archive and required active links. Do not erase the audit trail as a convenient business reset. |
| Firebase Authentication, `/users`, user preferences, memberships/roles/claims | Protected by default. Preserve identities/UID links and independently validate company access. No account deletion/recreation or reset implied. Profile business fields need a separately reviewed field-level migration. |
| Storage, Hosting, functions, secrets, IAM, integrations and other non-business resources | Outside the reset; configuration/attachments backed up as required. Any independently justified change needs its own approval. |

Prefer an isolated new dataset/book and a controlled active-book switch over an
in-place wipe. Replaced collection schemas need not remain writable/readable by
old clients forever: preserve archive/reference resolution and deny obsolete
posting routes at cutover. One report scope reads one accepted book; never sum
legacy and replacement postings for the same history. Freeze writes at the
final cutoff or use a separately designed, reconciled delta process; do not
assume imported Excel includes transactions entered after export.

Before activation, abandon only disposable isolated candidates. After any new
live posting, preserve events and reconcile a controlled cutback/compensation;
switching to stale legacy data would lose activity. No reset/delete command or
production apply procedure is supplied by Phase 1 or Phase 2A.

## 4. Phases and acceptance

| Phase | Deliverable and exit gate | Current state |
|---|---|---|
| **1: audit/design/requirements only** | Workflow register, accounting contract, proposed mappings, import/reconciliation specification, protected/reset scope and unresolved decision register. Owner/accountant review records approved decisions before implementation. | Baseline prepared; policies/source completeness pending. Firebase-only platform decision confirmed by the owner. No historical financial acceptance claimed. |
| **2A: Firestore accounting design** | Collections, posting/security/period/reporting contracts, all operation mappings, policy tradeoffs and bounded Phase 2B proposal. | [Design documented](phase2a-firestore-accounting-architecture.md); no engine implementation. |
| **2B-1: exact amount helper extension** | Extend existing TS/Dart helpers with string/unit APIs, independent scales, cumulative allocations and shared tests; preserve existing adapters with a fail-closed numeric round-trip guard. | [Completed locally, 2026-11-04](phase2a-inventory-cash-integration.md#6-phase-2b-1-implementation-and-verification): 375 backend / 535 Flutter regression tests passed. No posting/schema/deployment change. |
| **2B-2: detailed cash ledger read contract** | Extend existing cash model/repository/screen/details/PDF with exact stored values, separate identities, honest unknowns and full-scope reporting; preserve read authorization and pagination. | [Completed locally, 2026-11-04](phase2a-inventory-cash-integration.md#7-phase-2b-2-cash-read-contract-implementation-and-verification). Read/presentation only; no posting/schema/data/deployment changes. |
| **2B-3: cash settlement metadata integrity** | Explicit trusted initiator/poster, actual holder/account identities, reciprocal pair links and versioned provenance on newly posted settlement documents; retain financial behavior and atomicity. | [Contract and local verification, 2026-11-04](phase2b3-cash-settlement-metadata.md). Existing workflow only; no GL engine, historical changes or deployment. |
| **2B-4: settlement journal intent** | Pure settlement-only exact debit/credit intent, explicit policy/account dimensions, strict source validation and deterministic replay/conflict checking. | [Completed offline, 2026-11-04](phase2b4-settlement-journal-intent.md). No persistence or live posting connection; company policies/mappings remain unresolved. |
| **2B-5: settlement transaction preflight** | Internal read-only Firestore transaction adapter, approved configuration/evidence resolution, current cash-head checks, exact intent and distinct source/transaction/commit timestamp roles. | [Completed locally, 2026-11-04](phase2b5-settlement-preflight.md). Emulator-only verification; no journal writes or live posting/callable connection. |
| 2 remainder: accounting foundation | Later separately scoped Firestore transaction/idempotency/period/reversal proof, then existing open-item/treasury integration and quantity-only inventory controls. | Not started; no blanket implementation authorization. |
| 3: existing workflow integration | Incremental extensions of the registered functions/models/repos/screens, detailed cash and reference-selling estimates with quantity-only stock. Preserve behavior/access; no duplicate business flows. New unsupported operations have explicit scope. | Not started. |
| 4: importer/reconciler and rehearsal | Implement the specification only after architecture is accepted; real files validated, independent controls reconciled, retry/crash/restore and complete isolated reimports pass. | Not started. |
| 5: reviewed cutover proposal | Concrete backup/restore proof, classified resource allowlist, frozen cutoff/delta, signed reconciliation, client/trigger shutdown, rollback and production plan. Separate explicit approvals before deployment/reset/destruction. | Not started; not authorized. |

Unresolved decisions have owners and blocking gates: owner + accountant confirm
functional currency/scales, COA/control mappings, tax/discount policy, fiscal
calendar/recognition and close/reopen, customer-credit
presentation, owner-purpose classifications and opening/YTD treatment before
real posting acceptance. Engineering validates the Phase 2A Firestore transaction
budgets before posting/workflow acceptance; the database decision is no longer
pending. Data custodian + accountant provide
files, identity/ownership crosswalks, independent control totals, completeness
attestation, missing-history resolutions and opening/cutoff before Phase 4
promotion. Owner approves any later production operation separately. Unknown
amounts, physical quantities, cash ownership or cutoff overlap cannot be waived
into a PASS. Unrecorded cost/COGS is an explicit scope exclusion, not a sale or
quantity-import blocker. Independently reconcile selling estimates where price
evidence exists; never use them to certify inventory cost or profit.

Phase 1 validation: local workflow/source/rules/export review completed;
documentation links/anchors and whitespace checked; existing offline
`node --test functions/test/integrity_reconciliation.test.js`: **11 passed,
0 failed**. This is synthetic legacy-checker regression evidence only. No new
accounting/import engine, real workbook validation, historical reconciliation,
backup/restore rehearsal or deployed-system verification was performed. No
application/backend code or reference-repository files were changed.

Read-only reference principles: `fatoora_platform/docs/architecture/003-accounting-inventory-import.md`
and `006-accounting-core.md`; their implemented features, start date, approvals,
currency scales and policies do not become this repository's requirements by
association. Phase 2A uses these only as accounting-principle references; their
backend/storage implementation is not a proposal for Fatoora. Firestore technical
references are linked alongside the relevant Phase 2A design decisions.
