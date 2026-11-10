# Phase 2B-8 — settlement recovery and reconciliation

Approved 2026-11-09. Scope: internal read-only verification of the isolated
[Phase 2B-7](phase2b7-atomic-settlement-journal.md) persisted contract and inspection
of existing source flows for a future settlement breakdown. No endpoint, UI,
allocation, posting activation, correction, deployment or real Firebase access.

## Implementation and authority

`functions/src/trusted/settlement_recovery.ts` exports internal
`recoverSettlementTransaction(db, viewerUid, originalRequest, reviewedEvidence?,
{enableEmulatorRecovery:true})`. It has no root export or business call site.
Default-off and resolved SDK transport checks run before a transaction: exact
synthetic project `demo-fatoora-phase2b7`, default database, selected loopback
emulator port, SSL disabled. Both supplied and actual transaction clients must
pass the shared Phase 2B-7 guard.

The SDK transaction uses `{readOnly:true}`. Its restricted reader rejects
create/set/update/delete and unplanned queries. No write plan is exposed.
It composes the existing persisted-envelope validator through a new recovery-only
seam; a missing source always rejects without entering the posting branch.
Live writer behavior and its existing actor-bound replay remain unchanged.

Every attempt requires an active, approved company administrator and active
company, with path identity checks. An independent company administrator can
verify the original request: durable identity stays bound to the original actor,
not the viewer. Deactivating the original actor does not deny another authorized
reviewer; revoking today's viewer denies access.

Request/evidence are captured before asynchronous work. At most five read-only
attempts retry ABORTED or the pinned emulator's exact invalid/closed transaction
read failure. Each attempt uses fresh authorization, snapshot and cache;
unrelated failures propagate. Original `result` and SDK `commit` witnesses remain
deterministic after retries/lost acknowledgements. Observation time and current
positions may change between recoveries.

## Independent verification

The reused durable validator checks original settlement, both movements, legacy
transfer, journal, event, source/request keys, audit and outbox: deterministic
scoped identities, complete links, request conflicts, provenance, record/event/
effect/journal digests, exact units, immutable create/update witnesses and common
atomic commit metadata.

The separate verifier reconstructs evidence from authoritative settlement and
cash records with existing exact-decimal, journal-intent, preflight and
cash-position validators. It does not derive expectations solely from the
writer's artifact builder. Additional independent checks cover:

- Both journal lines, amount, mapped controls and separate treasury holders;
  balanced debits/credits and conservation of total cash custody.
- Original pending source/actor/display snapshots, deterministic targets,
  business date, period bounds, pending null clocks and timestamp contract.
- Recomputed economic, configuration and preflight digests, complete sorted
  version set, target-absence witnesses, policy/mapping/binding/account revisions.
- Original before positions reconstructed from actual predecessor movements:
  exact cash equations, holder/path identity, immutable SDK versions, recorded
  clocks and original position versions. Today's balance cannot invent an old
  before balance.
- Current representative/company balances against actual current heads and
  atomic SDK versions. Later legitimate cash activity is supported; stale
  balances, missing/replaced heads and backward heads reject.
- Original immutable journal definition, approved scope/currency/action/numbering
  contract and SDK version; book seal binding, deterministic lane, genesis or
  immediate predecessor hash/sequence, current lane/head identity and SDK witness.
- Duplicate/partially linked source, movement, transfer and accounting evidence
  using bounded company/book-local reference-only queries.

Unchanged configuration versions are checked against raw stored fields.
Missing/recreated witnesses reject. Changed mutable configuration is explicitly
reported as `changed_since_posting`; past raw contents are not claimed to have
been independently retrieved. Closing periods, deactivating accounts/reps,
switching active books or advancing lanes does not reinterpret an original
committed result. Configuration approval evidence remains commit-bound evidence.

Bounds: **64 unique document reads and nine queries per attempt**. Queries use
reference-only projections and expected-count-plus-one sentinels, totaling at
most 19 result documents. No collection-group or unbounded scan; any read error
or exhausted bound fails closed. Shared chart control accounts work through
distinct treasury dimensions and deduplicated configuration reads.

## Transaction verification versus historical reconciliation

Every result says `scope:transaction` and `historicalReconciliation:not_performed`.
It verifies the named transaction, immediate predecessors, linked duplicate
probes and current heads. It does not enumerate every intervening cash movement,
lane event, other book, or orphan with missing/false source references.

Existing `cash_reconciliation_common.js` read-only `analyzeCashRecords` remains
useful for complete supplied histories. Its legacy numeric totals/rounding and
source coverage do not certify exact journals or source allocations. A synthetic
test proves a locally valid settlement can coexist with missing opening history
that this utility flags. The recovery adapter never invokes its apply/maintenance
path. Existing regressions may exercise reconciliation on disposable synthetic
fixtures; no database-maintenance/reset runner is used.

Full historical clearance needs complete scan boundaries, opening/carry evidence,
exact-unit totals, all books/lanes/source coverage, orphan detection and gap-free
chain checks. Configuration version witnesses are not an archive of old raw
configuration. Hashes are integrity checks, not signatures: arbitrary privileged
recreation of a whole coherent history, physical handover and authenticity beyond
trusted SDK/storage cannot be proven here. No historical data is certified.

## Settlement-breakdown findings

| Existing flow | Verified behavior / existing references | Breakdown implication or gap |
|---|---|---|
| Invoice cash (`confirm_invoice.ts`) | Admin-created invoice collections enter company cash; rep-created collections enter representative cash. Invoice/source/reference IDs, deterministic cash ID, business date and before/after values exist. | Invoice salesperson alone does not establish custody. Later receipts are separate collections; do not count invoice total and receipt cash again. |
| Receipt cash (`create_receipt.ts`) | Actual collector determines custody: admin → company; representative → collector. Receipt `cashMovementIds`, `invoiceAllocations`, `invoiceAllocationDetails` and invoice `receiptIds` exist. Seller/reporting ownership can differ after reassignment. | Receivable allocations are not settlement allocations. Unallocated customer credit needs an explicit residual. Shared customer/seller/date cannot prove an invoice link. |
| Actual cash refund (`confirm_sales_return.ts`) | Resolver groups direct collection and cash-receipt allocations by original collection account/rep. `applyCashChange(...,"out",...)` reduces that holder's available cash. Original rep collector cash is reduced even after reassignment; admin collection reduces company cash. Missing/multiple collection holders or insufficient current cash block. Return `originalInvoiceId`, `originalCollectionSourceIds`, refund account/rep and cash ID exist. | The movement list does not contain exact per-movement refund consumption. It cannot prove which collection lot funded a refund or earlier settlement. Mixed holders require customer credit in the current flow. |
| Partial returns | Remaining debt is reduced before the paid portion can become cash refund/customer credit. Customer credit causes no cash outflow. | Never deduct the entire return value from representative cash. Refund after an earlier settlement still follows original collection holder and available cash; no automatic company-funded custody reassignment exists. |
| Expenses (`expenses.ts`) | Admin expenses leave company cash immediately. Rep `rep_collected_cash` expenses reduce that rep's cash on approval. Pending expenses do not reduce cash. Approved `personal_cash` creates a payable without a cash movement. Funding/source/movement IDs and before/after values exist. | Count actual approved cash movements once. Pending expenses and personal reimbursements are not already paid from collected cash. No settlement-to-expense allocation exists. |
| Settlement (`record_cash_settlement.ts`) | Any positive amount within rep cash is allowed. One rep OUT/company IN updates both positions atomically. IDs, reciprocal references, treasury holders, original request, provenance and before/after evidence exist. | Partial settlement leaves the remainder in the rep position. Repeated settlements consume an aggregate balance, without choosing invoices/receipts/refunds/expenses. No allocation table exists. |
| Previous balances | Positions aggregate prior cash activity without resetting at settlement date. Existing reconciliation recognizes opening-balance movements; legacy initialized positions can lack complete history. Business date can differ from commit order. | Previous balance is an amount, not a proven source-lot relationship. Do not invent receipts/invoices from a balance snapshot or infer consumed collections from a date window. |

Inspection covered the named modules, `cash_ledger.ts`, settlement intent/preflight/
pending/persistence and reconciliation utilities. Synthetic regressions verify
actual collector versus historical seller, mixed refund holders, debt versus paid
portions (`reassignment_returns.test.js`), admin refund custody, cash lifecycle,
partial settlements/concurrency (`trusted_transactions.test.js`), expense,
receipt-cancellation and reporting behavior. This phase does not certify or
change the refund resolver's legacy source completeness/allocation arithmetic.

Missing evidence: exact-unit source allocations; immutable allocation version,
actor and references; availability after refunds/expenses/prior consumption;
evidenced opening/carry residuals. Multiple receipt movement references must not
multiply one invoice allocation. Invoice totals, receipt allocations, cash
movements, legacy transfers and journals represent different views of an action;
summing all of them would double-count it.

Future allocations should consume actual cash movements under the same company,
currency, holder and cutoff. Each unit can be consumed once. Refunds, expenses,
prior settlements and explicit unknown carry must reconcile to exact available
units. Validate per-source and settlement totals with BigInt, stable IDs and
concurrency controls. FIFO/manual attribution requires an approved explicit policy
and stored allocation. Unsupported historical links stay unknown. **No allocation
policy or implementation is introduced here.**

## Verification

Standalone emulator 1.21.0 on `127.0.0.1:8192`, synthetic demo projects and fixtures
only; existing Phase 2B-7 fixture construction is shared by both suites. No real
project, credential discovery, production/staging data, deployment or maintenance
runner. Synthetic setup/corruption writes affect only emulator fixtures; recovery
itself writes nothing.

| Check | Result |
|---|---|
| Final recovery suite | **81 passed, 0 failed/skipped**, including lost acknowledgements, concurrent recovery/cash activity, retries/revocation, independent reviewer, exact accounting, shared controls, display fallbacks, missing/rewritten artifacts, corrupt heads/lanes, duplicate links, permissions/isolation and legacy-only rejection. Five rehashed-envelope probes preserve SDK witnesses to test false internal digest, scope/version, original balance and timestamp evidence independently of overwrite detection. |
| Existing backend regressions | **920 passed, 0 failed/skipped**. Full direct `node --test --test-concurrency=1` run: **997 passed**, comprising those 920 and 77 recovery cases. Final focused run includes four additional forgery cases, for **1,001 distinct covered cases** across the runs. No source changes followed these successful runs. |
| TypeScript build / lint | **Passed**, `npm.cmd run build` and `npm.cmd run lint` (`tsc` / `tsc --noEmit`), Node 22.21.1. |
| Rules / business compatibility | Passed within existing regressions, including denied accounting client operations, original cash/settlement behavior, reassignment/refunds, receipt cancellation, expenses, reporting, reconciliation, audit and journal intent/preflight/pending/persistence. No Rules/index/Flutter changes in this phase. |
| Measured base recovery | **27 unique document reads**, **9 bounded reference-only queries**, **zero writes**. Successful probes return ten references; the hard sentinel ceiling is 19. Read-only SDK options, write traps and unchanged stored versions are tested. |

Evidence: `output/phase2b8-focused.log`, `output/phase2b8-regressions.log` and
`output/phase2b8-reviewer-regressions.log`. `git diff --check` passes. The existing
regression-generated tracked synthetic lifecycle snapshot is restored after the
run; unrelated pre-existing Phase 2B-7 work is preserved. Emulator is stopped
after verification. This completes Phase 2B-8 within its read-only scope; full
historical clearance and workflow activation remain unapproved and unimplemented.

## Smallest safe next batch

Separately approve a **bounded read-only source-evidence inventory and settlement
breakdown contract** using synthetic emulators: actual holder movements, existing
document references, exact units, duplicates, refunds/expenses/prior-settlement
consumption, unknown opening/carry and coverage gaps. Specify immutable evidence
needed for later allocation and historical configuration/sequence coverage before
claiming full reconciliation. No automatic historical matching, allocations,
posting integration, UI or activation follows from this phase.
