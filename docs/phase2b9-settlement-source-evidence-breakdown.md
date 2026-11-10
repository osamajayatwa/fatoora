# Phase 2B-9 — settlement source evidence and breakdown

Approved 2026-11-09, following [Phase 2B-8](phase2b8-settlement-recovery-reconciliation.md).
This completes a bounded internal **read-only cash reconstruction**, not settlement
allocation or workflow activation. All execution is isolated, synthetic emulator
work. No callable, UI, posting change, backfill, deployment or real-project access.

## Implementation and contract

- `functions/src/trusted/settlement_breakdown.ts`: internal
  `settlementBreakdownTransaction(db, viewerUid, request,
  {enableEmulatorBreakdown:true})`, exported `SettlementCashBreakdown` type, owning
  read-only transaction, authority/isolation, currency evidence, bounded inventory
  and atomic-envelope composition.
- `functions/src/trusted/settlement_source_evidence.ts`: pure source validation,
  exact movement equations, source/reciprocal references, holder identity,
  committed account ordering, opening/carry and cutoff reconstruction.
- `functions/test/helpers/settlement_breakdown_fixture.js` and
  `functions/test/settlement_breakdown.test.js`: synthetic opening/configuration
  fixtures and existing trusted business writers, plus adversarial probes.
- Package script `test:settlement-breakdown`; no dependency or lockfile change.

Request: `{companyId, salesRepId, settlementId}` for a completed settlement, or
`{companyId, salesRepId, committedThrough:{seconds,nanoseconds}}` for a read-only
cash preview. Exactly one cutoff mode is required. A settlement cutoff is its
actual SDK creation/commit witness, never its business date or caller timestamp.
A future preview cutoff rejects. Request identity is captured before async work.

Every attempt checks today's active, approved company administrator, profile
path identity, active company and representative membership. An inactive
historical representative remains inspectable by an authorized administrator.
Other company data and representative access are denied. The existing shared
guard restricts supplied **and actual transaction SDK clients** to exact project
`demo-fatoora-phase2b7`, default database and selected loopback emulator with SSL
disabled. Default is off, before any database transaction starts.

SDK transactions use `{readOnly:true}`; create/set/update/delete are trapped.
There is no write plan or caller-owned posting seam. At most five attempts retry
ABORTED or the exact pinned emulator invalid/closed read error, with fresh
authorization and snapshot each time. Other errors propagate. Named atomic
settlements reuse `prepareCommittedSettlementRecovery` in the **same** read-only
snapshot; corrupt/missing envelope evidence blocks the breakdown. Legacy
settlements remain legacy cash evidence without invented journals. This composes
the durable envelope validator; it does not claim a separate full journal-history
audit of every preceding settlement.

Existing helpers reused: cash balance IDs, trusted authorization, preflight/shared
exact money/timestamp/ordering functions, checked exact-decimal sums, bounded
canonical codec/digests and persisted settlement recovery. Existing
`cash_reconciliation_common.analyzeCashRecords` is cross-checked on a synthetic
complete lifecycle. Its numeric rounding and unsupported cancellation type do
not control the new exact result. No reconciliation apply/maintenance runner is
used by the new adapter.

## Output and exact accounting

Successful reports say `status:verified_cash_reconstruction`; incomplete evidence
says `status:blocked`, has explicit issue codes/paths, and **`totals:null`**.
Authorization, transport, unsupported configuration and hard payload failures
reject without exposing a financial result. Collection overflow returns a
blocked incomplete inventory, rather than a truncated successful page.

Returned evidence includes:

- One row per actual representative cash movement, plus excluded other-holder
  rows. Rows retain authoritative ID/path, source/number, SDK create/update
  witnesses, recording and business times, exact signed/before/after units,
  holder/treasury identity, movement/source creators, original invoice sellers,
  collector and posting actor with their evidence basis. Explicit recorded
  provenance is retained separately; absent physical collector identity stays
  unknown. No current profile name is substituted for a historical snapshot.
- Stored receivable allocations and their unallocated receipt residual; original
  invoice and refund collection reference versions; reciprocal settlement and
  reversal IDs. Reference versions after the cutoff are explicitly marked.
- Separate committed ordering and business-date presentation ordering, and IDs
  through the cutoff. A backdated later commit cannot alter earlier account
  ordering or enter an earlier cutoff merely because of its business date.
- Opening state, previous settlement/carry witness, exact activity since carry,
  cash before the selected settlement, transfer, remaining cash **at that cutoff**,
  and independently reconciled current balance. Later activity may change current
  balance and the inventory digest, while the intact target's transfer/cutoff
  result stays fixed. A repeat over unchanged evidence returns the same digest.
- Non-cash/unpaid sources, separately unresolved sources with missing cash
  evidence, bounded issues and coverage/configuration/observation metadata.
  `allocation.status:not_implemented`, `settlementSourceAllocations:null` and
  `receivableAllocationsAreSettlementAllocations:false` are explicit.

Only positive exact scale-3 movements are accepted; arithmetic uses existing
checked BigInt helpers, without rounding reconstructed values. Each equation and
adjacent account balance must agree exactly. SDK commit order must be strictly
increasing within a representative account; same-commit ambiguity fails rather
than sorting economically by arbitrary IDs. Current balance/head amount, holder,
recording time and atomic SDK version must agree. Completed settlements and
movements must have unchanged SDK create/update witnesses. Both settlement legs
must exist, be reciprocal, share their source's SDK commit and conserve cash.

Example from existing writers, in exact units:

| Representative activity | Units |
|---|---:|
| Recorded opening | 100111 |
| Partial invoice collection | +10000 |
| One receipt across two invoices | +25000 |
| Actual cash refund | -10000 |
| Approved collected-cash expense | -3125 |
| Previous partial settlement | -20000 |
| Verified carry after previous settlement | **101986** |
| Subsequent receipt | +2009 |
| Cash before selected settlement | **103995** |
| Selected transfer | -5111 |
| Remaining cash | **98884** |

The 25,000-unit receipt has stored receivable allocations of 20,000 and 5,000;
it still contributes **25,000 once**. Its allocation details, invoice totals,
legacy ledger rows and journals are never additional cash inflows.

## Verified source coverage

| Source | Validation and treatment |
|---|---|
| Recorded opening | Existing `opening_balance` cash schema, self source reference, explicit immutable declaration, recorded admin creator, immutable SDK witness, positive IN and zero before balance. It must be the first account movement through the cutoff. Another opening cannot restart history. This verifies recorded ledger evidence, not physical cash or an external historical attestation. |
| Initial/partial invoice cash | Posted invoice; original `initialPaidAmount` and `initialCashAccount`, payment type, amount within original total, source number/date/customer, deterministic movement and reciprocal `cashMovementIds`. Current accumulated `paidAmount` is not counted again. |
| Subsequent receipts | Actual collector determines custody. One declared cash movement, exact receipt amount, stored invoice allocation/detail agreement, customer and reciprocal invoice references. Allocation sum cannot exceed receipt; residual remains explicitly unallocated to invoices. Bank/check/cliq receipts add no cash. |
| Cash refunds | Confirmed cash-return source, paid portion, reciprocal return/invoice IDs and actual refund movement. Every declared collection must precede the refund, reference its original invoice and have the same paying holder. Complete eligible collection coverage and cumulative exact invoice cash caps are checked using already stored receivable allocations. Mixed holders fail; this does not create per-collection refund consumption allocations. |
| Customer-credit/debt reductions | No physical cash movement. Partial returns reduce debt before any paid portion can become a cash refund. A credit-only return with a cash claim is inconsistent. |
| Expenses | Only approved/posted cash-funded amounts count, from the actual company or representative account. Source creator remains separate from approving/posting admin. Pending expenses and personal-cash payable approvals do not reduce collected cash. |
| Previous/current settlements | One rep OUT contributes to rep cash; company IN is separately verified/excluded from rep totals. Partial/repeated settlements leave aggregate carry. Source, both legs, references, holders, timestamps, amounts, actors and optional accounting bindings agree. Completed sources cannot be rewritten. |
| Adjustments/cancellation | Existing receipt cancellation requires exactly one original IN and linked, later, equal OUT on the same cash holder, with cancellation source/version/actor and reciprocal IDs. Original and inverse are each counted once. No generic approved cash-adjustment writer exists; unsupported adjustments block instead of inventing a policy. |

Company cash can legitimately retain the invoice salesperson in `salesRepId`.
It is always held by the company. Representative custody requires the verified
representative cash account; seller, creator, collector, approver and viewer are
not interchangeable. A refund after a full settlement cannot silently use company
cash to fund an empty original representative account. Existing workflow guards
remain unchanged, including cancellation dependencies and mixed refund holders.

## Bounds and historical limitations

Six company-scoped projected scans cover cash movements, invoices, receipts,
returns, expenses and settlements. Each is limited to **64 rows plus one overflow
sentinel**; at most **64 cached document gets** supplement them. Queries are
unfiltered by date/holder so malformed/missing holder/date fields cannot silently
exclude cash evidence. They enumerate declared source effects as well, detecting
a missing cash leg that a movement-only scan would miss. No collection-group
scan, unbounded query, pagination, custom index or cloud credential discovery.

Per-source reference lists and distinct linked-document evidence are limited to
32. Projected/full retrieved documents are capped at 64 KiB each and 1 MiB per
attempt after retrieval; existing canonical structural/range limits also apply.
This is deliberately a small complete-company inventory. Larger companies need
a separately designed complete snapshot/coverage protocol, not silent truncation
or unsupported claims about latency/cost at cloud scale.

**Unknown opening is never zero.** Initial legacy balances, a first collection
whose before value is zero, or a previous settlement's after value do not supply
a missing opening attestation. Such carry remains unverifiable and all certified
totals are suppressed. Synthetic representative opening records are test evidence;
this phase introduces no representative opening writer or historical correction.

Currency must be explicit on cash records/balances, or supported by an immutable,
approved book-pinned `currency_bindings/{revision}` with company/book identity,
`sourceCollection:cash_movements`, `scope:company_cash_ledger`, currency/scale and
matching revision ID. The book pin is `cashEvidenceCurrencyBindingId`. The binding
must predate legacy cash evidence; a later declaration or settlement-only binding
cannot establish old whole-ledger currency. This is a read-only evidence contract,
not a new configuration write or an inferred accounting default. Missing real
evidence blocks; no real configuration is created.

Source bodies are current mutable versions, not retrieved archival snapshots.
Missing references, changed inconsistent source fields, source/chain gaps,
duplicate IDs/logical actions, missing/rewritten cash evidence, currency mismatch
and unverifiable heads are explicit blockers. SDK witnesses/hashes do not prove
physical handover, original profile authorization or privileged whole-history
authenticity. Coordinated deletion/recreation of a coherent history or net-zero
missing cycles cannot be disproved without an independently retained coverage
anchor. This phase certifies neither those facts nor full journal history or
other-holder historical balances. Its scope is the representative cash chain and
the settlement pair within the complete bounded inventory.

## Future immutable allocation requirements

Cash reconstruction and receivable allocations do **not** establish which cash
lots were consumed by a settlement. A verified carry is an amount, not surviving
invoice ownership. No FIFO, date-window matching or invoice attribution is used.

A future approved allocation contract must pin:

1. Explicit approved policy revision, company/book/currency/scale, cash holder,
   settlement identity, SDK cutoff/ordering and immutable economic-action key.
2. Explicit selections of authoritative source movements and exact unit amounts,
   source/reference versions, approved origin/carry and refund/reversal evidence.
   A receipt's stored invoice allocations must never multiply its cash units.
3. A defined cutover for older unallocated settlements/refunds/expenses. Unknown
   source consumption must stay an unknown pool; it cannot become freshly
   available invoice cash or an invented source document.
4. Immutable allocation ID/version, original request key/result, selection digest,
   reviewer/posting actor, server recording time and actual SDK commit witnesses.
5. Atomic source-availability/consumption controls, unique allocation/source keys,
   replay/concurrency protection and explicit approved reversal rules. No unit
   may be consumed twice across settlements, refunds or reversals.
6. Exact per-source conservation and settlement allocation totals; gap-free
   account/source coverage; immutable audit links; fail-closed recovery and
   reconciliation. Allocation must not post a second cash movement or journal.

Nothing above is persisted or activated in Phase 2B-9. The smallest next step is
approval of the allocation policy and legacy cutover rules, then a separately
scoped **read-only allocation-intent builder with explicit selections and pinned
versions** in synthetic emulators. Presentation can consume this breakdown's
verified/blocked states and evidence bases after its own approval, without
displaying unproven invoice-to-settlement attribution.

## Verification

All database work uses standalone emulator 1.21.0 at `127.0.0.1:8192`, demo
projects and synthetic fixtures. Setup/corruption tests write only disposable
synthetic data; the new adapter is strictly read-only. No production/staging
access, deployment, backfill, reset runner or application workflow change.

| Check | Result |
|---|---|
| Final focused suite | **60 passed, 0 failed/skipped**. Actual existing workflows cover partial/repeated/full settlements, verified/unknown carry, initial/partial invoice cash, multiple-invoice/unallocated receipts, refunds before/after settlement and debt-first returns, company versus rep cash, original seller versus reassigned collector, approved/pending/personal expenses, cancellation/dependencies, mixed holders, exact fractional units, source/chain gaps, unsupported adjustments/reversals, duplicate movements, immutable completed records, currency/opening gaps, permission failures, concurrency, bounded retries/revocation, payload/query/reference limits and atomic-envelope compatibility/corruption. |
| Existing backend regressions | **1,001 passed, 0 failed/skipped**, using direct `node --test --test-concurrency=1` over all existing test files except the separately run new focused file. Includes Phase 2B-7/8 persistence/recovery, intent/preflight/pending, cash reconciliation, invoices/receipts/refunds/expenses, reassignment, receipt cancellation, client Rules denial, reporting, audit and permissions. **1,061 cases total** across both runs. |
| Build / lint | **Passed**: `npm.cmd run build` and `npm.cmd run lint` (`tsc` and `tsc --noEmit`), Node 22.21.1. |
| Measured lifecycle reads | **9 cached document gets, 6 bounded projected queries, 21 scanned rows, zero writes.** Read-only SDK options, write traps, unchanged persisted data/versions and deterministic unchanged-snapshot digests are tested. |
| Boundaries / workspace | No root/callable export, Rules/index/Flutter change, posting integration, allocation implementation or journal activation. Existing uncommitted Phase 2B-7/8 work is preserved. Regression-generated tracked synthetic lifecycle output is restored. Diff whitespace checks pass. Emulator is stopped after verification. |

Evidence logs: `output/phase2b9-focused.log`, `output/phase2b9-regressions.log`,
`output/phase2b9-emulator.log`. Phase 2B-9 is complete within this internal,
synthetic, read-only scope. Historical gap repair, allocation policy/persistence,
presentation and business-workflow activation remain separate approvals.
