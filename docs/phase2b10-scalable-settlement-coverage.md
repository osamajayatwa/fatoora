# Phase 2B-10 — scalable settlement breakdown and coverage integrity

Approved 2026-11-09, extending the existing
[Phase 2B-9 source-evidence contract](phase2b9-settlement-source-evidence-breakdown.md).
Scope remains internal, default-off, emulator-only and strictly read-only. No new
ledger, source/financial write, callable, UI, allocation persistence, migration,
deployment, production/staging access or journal activation.

## Implementation

`settlement_breakdown.ts` now pages the same six company collections to their
ends inside **one SDK read-only transaction**. It still calls the existing
`analyzeSettlementSourceEvidence` and atomic settlement recovery seam. Source
validators, exact money/timestamp helpers, company-scoped paths and original
settlement/cash records remain authoritative; no parallel accounting is built.

The larger inventory codec shares the existing canonical implementation in
`settlement_pending_evidence.ts`, using a separate read-only profile. The strict
pending/journal codec retains its original default limits, serialization bytes
and digests. Source validation caches invoice/reference/allocation evidence and
indexes collection/refund/reversal candidates by invoice, avoiding repeated
whole-company searches. Recorded invoice receipt/return links are also checked
reciprocally. Referenced documents retain their recorded numbers and dates,
in addition to IDs, paths and SDK versions.

The existing internal entry point accepts optional bounded `pageSize` and
`readBudget` resource controls. These cannot grant authority or exceed hard
ceilings. Its schema-2 result preserves the prior financial/source fields and
adds a snapshot coverage manifest, resource observations and current authority
observation. Stored financial records and live writer behavior do not change.

## Coverage proof and concurrency

1. Check today's approved active company administrator, profile identity,
   company and representative membership. Preserve historical eligibility
   semantics: an inactive representative can still be inspected by an authorized
   company administrator. Resolved supplied/transaction clients must pass the
   existing exact synthetic-project/default-database/loopback/SSL-off guard.
2. Derive a named settlement cutoff from its actual SDK creation/commit witness;
   business-date presentation remains separate. Preview cutoffs cannot exceed
   observation time. Capture request/resource settings before async work.
3. Obtain a **bounded independent count** for each collection in the same SDK
   transaction. Its query limit is remaining document budget plus one; excessive
   cardinality blocks before reading an arbitrarily large collection.
4. Read explicit projected pages ordered by document ID, continuing with the
   actual last document snapshot. Validate strictly progressing UTF-8 document
   IDs, scope, page size, duplicate/backward cursors and document versions.
5. Require every query/aggregate/document read to share the original SDK read
   time. A collection is complete only after an actual terminal page and exact
   agreement with its independent count. Exact multiples require a subsequent
   empty terminal page. Page witnesses bind the collection, cursor endpoints,
   ordered IDs and actual SDK create/update versions.
6. Run the shared exact source/chain reconstruction only after **all six**
   collections are complete. Then recheck current viewing authority in a fresh
   read-only snapshot before delivery. This gate never substitutes newer
   financial records into the original report. Mid-scan revocation denies access.

The manifest includes count witnesses, page witnesses, shared read time,
completed collections, scanned count and a snapshot digest. The financial
`evidenceDigest` excludes physical page boundaries and observation clocks: two
page sizes over unchanged source evidence produce the same economic digest.
The snapshot digest also binds read time/page plan and distinguishes separate
observations even when economics are identical.

Concurrent inserts behind an already passed cursor, source mutations ahead of
it and new settlements cannot enter only part of an old report. They appear in
the next fresh complete report. A lost/expired snapshot, permission failure,
count disagreement or malformed page rejects; it never falls back to unrelated
fresh pages. At most five fresh full attempts retry only the existing narrowly
recognized contention errors. No partially completed result is certified.

## Explicit limits and failure states

| Bound | Contract |
|---|---|
| Inventory | Up to **16,000 returned documents total** across the six collections, not 64 per collection. Caller may lower the budget. |
| Pages | Default **128**, permitted 16–256 documents. At most **256 query calls**, including count queries. Small pages can exhaust query budget before document budget. |
| Additional gets | At most 64 cached document gets in the financial attempt; a successful final authority gate reads three current documents. |
| Payload | 64 KiB per retrieved document and 32 MiB per attempt, checked after retrieval. Projections exclude invoice item/search payloads. |
| Source references | At most **2,048** per source/list and distinct linked-document list. Larger histories are blocked, never truncated. |
| Canonical inventory | 300,000 nodes, 16,000 array elements, 16 MiB encoded value; original safe-integer/plain-JSON/string/depth checks remain. Strict stored accounting profile stays 4,096 nodes, 64 elements and 64 KiB. |
| Time | 45-second cooperative attempt/verification budget. Transport/SDK failures remain failures; this is not a production latency SLA or RPC cancellation guarantee. |

The whole company is inventoried to catch missing legs and malformed holder/date
fields that a filtered representative/date query could omit. Work grows with
company history. Counts also use bounded queries; aggregate index work/billing
is distinct from returned document counts. Observations count logical SDK calls
and returned payloads, not hidden transport retries or certified cloud cost.
Reported successful-attempt statistics do not hide the `attempt` number; retry
work is additionally bounded by five attempts.

There are three separate outcomes:

- Complete inventory and valid history: `verified_cash_reconstruction`, exact
  opening/carry/before/transfer/remaining/current totals.
- Complete inventory but missing/inconsistent historical evidence: `blocked`,
  explicit issues, `totals:null`; unknown opening/carry remains null.
- Incomplete coverage: `blocked`, `snapshotCoverage.complete:false`, explicit
  document/query/time budget reason, opening `not_evaluated_incomplete_coverage`
  and unverifiable carry. It does not claim the opening was historically absent.

Payload/codec/transport/integrity/permission failures can reject without a report.
No failure repairs, backfills, writes a balance or certifies a partial sum.

Thousands of records are supported; history is not unbounded. Companies beyond
the bounded complete-inventory envelope need a separately reviewed snapshot/job
or immutable archival coverage/checkpoint protocol. They must not be enabled by
arbitrary date filters, a larger UI page or invented zero opening. No checkpoint,
coverage seal, continuation state or cache is persisted in this phase.

## Financial and historical meaning

The Phase 2B-9 opening, source, holder, exact cash-chain, reciprocal settlement,
refund and expense validations remain in force. Partial/repeated settlements
leave aggregate carry. Refunds reduce the verified original paying holder;
customer-credit returns and pending/personal expenses do not consume collected
cash. An invoice's initial collection and each later receipt are counted once,
regardless of how many stored receivable allocation annotations they contain.

Complete present storage coverage is **not proof of all past existence**. A
missing opening, coherent privileged history recreation or deleted net-zero
cycle cannot be disproved by present counts. Currency evidence must still cover
the actual ledger; a settlement-only or late binding does not establish old
ledger currency. Mutable source bodies are current versions, with post-cutoff
versions marked, not archival source contents. Physical handover and original
historical profile authority are not certified. SDK versions/hashes are evidence
and integrity checks, not signatures or new financial relationships.

## Shared screen/PDF detail contract, without UI changes

`settlement_breakdown_presentation.ts` supplies pure internal
`settlementBreakdownDetailPage` and `verifySettlementBreakdownDetailPages`.
They are views/DTO checks over an already authorized report, never endpoints or
authorization mechanisms. There are no additional database reads or writes.

Each fixed 64-row detail page carries both report and snapshot digests, ordered
offset/index, expected count, continuation, cutoff, status, exact totals and
source/provenance rows. It presents only movements through the settlement cutoff;
later observed cash activity stays outside that historical detail sequence.
Current balance remains separately labeled in the header.

The assembler requires every page exactly once in order, consistent headers and
roots, row/page checksums, unique representative-held rows, commit order and
cutoff compliance. For a verified report it also reconciles the complete detail
cash sum with remaining cash. Missing/reordered/edited/duplicate/mixed-snapshot
pages reject. Complete but historically blocked evidence can show observed rows,
always with null certified totals and its issues. Incomplete inventories cannot
produce detail pages. Checksums do not make arbitrary client DTOs authoritative;
future transport must retain server origin and current authorization.

Existing presentation inspected, unchanged:
`cash_movements_screen.dart` / `_SettlementPairCard`, shared
`cash_movement_presentation.dart`, `financial_repository.dart` and
`cash_report_pdf_service.dart`. Current pair cards and cash PDFs use available
cash snapshots; those list/date pages are not full settlement coverage proofs.
Do not feed a truncated movement list into the new report as complete evidence.

Smallest safe display batch: a shared Dart DTO/formatter plus fixture-backed
details in the **existing settlement pair card and cash PDF**, consuming this
same verified/blocked page/header contract. Show source ID/number, holder,
business/commit dates and gaps, and require complete pages before a complete PDF
export. Choose/review an authorized backend transport separately before live
wiring; this internal emulator-only module is not currently callable by Flutter.
No allocation policy is needed merely to display a cash-position explanation.

## Allocation policy and legacy cutover options for review

**Simplest safe default: retain aggregate cash settlements with a complete cash
explanation, without invoice allocation.** Label details as cash-position evidence,
not “invoices paid by this settlement.” This already serves detailed audit/display.

If explicit allocation is later required, the smallest policy is administrator
selection of actual eligible cash movements, with approved policy/version,
company/currency/holder/cutoff, exact units and immutable reviewed source versions.
Stored invoice receivable allocations remain annotations of one receipt, not
additional cash. Source availability must account for explicit prior consumption,
refunds, expenses and reversals; current refund reference lists do not themselves
provide per-source consumption amounts. Resolve those outflow/availability rules
before any allocation intent or persistence. No FIFO or date-proximity inference.

Legacy cutover choices, none implemented:

1. **Recommended:** retain historical settlements unallocated; start prospective
   explicit allocation only from an approved cutover. A *verified* carry may be
   an explicitly evidenced aggregate legacy pool, never invented invoice lots.
2. Leave legacy cash entirely outside source-level allocation and allow only
   verified prospective source evidence; reconcile an explicit unallocated pool.
3. Use historical source allocations only where independent approved immutable
   evidence actually exists. Reconstruction/backfill would require separate
   authorization and proof; current dates/balances are insufficient.

Unknown opening/carry cannot become a zero or an approved pool by assumption.
The Phase 2B-9 immutable identity, availability, idempotency, concurrency, exact
conservation, audit and reversal requirements still apply. These are review
options, not an adopted policy or implementation.

## Verification and performance

All execution uses standalone Firestore emulator 1.21.0 on `127.0.0.1:8192`,
synthetic demo projects and synthetic data. Large fixtures batch source definitions
but give every movement and its position a distinct real atomic SDK commit;
they do not invent SDK timestamps or rewrite movements to fabricate ordering.

| Invoice cash movements + mixed workflow evidence | Returned inventory documents | Supplemental document gets | Query calls (count + page) | End-to-end breakdown | Detail assembly |
|---|---:|---:|---:|---:|---:|
| 100 | 217 | 9 snapshot + 3 current authority | 6 + 6 | 486 ms | 2 pages, 14 ms |
| 1,000 | 2,017 | 9 + 3 | 6 + 20 | 1,423 ms | 16 pages, 130 ms |
| 3,000 | 6,017 | 9 + 3 | 6 + 52 | 3,973 ms | 47 pages, 351 ms |

These are final single-run loopback measurements, not production latency, load,
billing or maximum-ceiling certification. Payloads were approximately 193 KB,
1.72 MB and 5.13 MB. Setup time (1.4/2.1/4.2 seconds) is excluded from breakdown
timing; authority recheck is included. Detail generation/assembly uses zero
additional database reads. Full-company scanned rows, aggregate queries and
supplemental gets are separately reported rather than treating each page as one
document read. The 16,000-document ceiling is a safety bound, not a measured
throughput promise.

| Verification | Result |
|---|---|
| Final focused coverage suite | **21 passed, 0 failed/skipped**. Includes 100/1,000/3,000 cash movement histories with mixed existing workflow evidence; one invoice with 1,000 receipt references; Unicode/case/punctuation cursors, exact full-page/empty-terminal boundaries and exact budget edges; independent count disagreement, skipped/duplicate/backward/cross-company pages, snapshot mismatch/expiration, query permission failures, concurrent behind-cursor inserts/ahead-cursor mutations/settlements, current authority revocation, document/query/reference ceilings, missing openings/chain gaps/duplicates/currency conflicts, strict codec compatibility and complete/mixed/corrupt screen/PDF detail sequences. |
| All existing backend regressions | **1,061 passed, 0 failed/skipped**, including the 60 Phase 2B-9 business-source cases and Phase 2B-7/8 persistence/recovery, intent/preflight/pending, exact arithmetic, refunds, expenses, receipt cancellation, cash reconciliation, client Rules denial, reporting, audit and permissions. Direct serial Node test run; no maintenance/reset runner. **1,082 total cases** across the two runs. |
| TypeScript build / lint | **Passed**, `npm.cmd run build` and `npm.cmd run lint` (`tsc` / `tsc --noEmit`), Node 22.21.1. |
| Financial/workflow boundaries | Zero adapter writes; no root/callable export or UI, Rules, index, dependency/lockfile, posting or journal activation change in this phase. Existing uncommitted Phase 2B-7–9 work is preserved. |

Evidence: `output/phase2b10-performance.json`, `output/phase2b10-focused.log`,
`output/phase2b10-regressions.log` and `output/phase2b10-emulator.log`.
Whitespace checks pass; the regression-generated tracked synthetic lifecycle
snapshot is restored, and the emulator is stopped after verification.
Phase 2B-10 is complete within the stated read-only coverage and volume bounds.
Live transport, screen/PDF changes, allocation decisions/persistence and workflow
activation remain separate approvals.
