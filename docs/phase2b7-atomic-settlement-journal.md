# Phase 2B-7: atomic settlement journal persistence

Scope approved 2026-11-08: the first durable double-entry posting, **only** for
representative-to-company cash settlement, in isolated synthetic emulators.
This extends [Phase 2B-6](phase2b6-pending-settlement-evidence.md) under the
[approved architecture](phase2a-firestore-accounting-architecture.md).

## Boundaries and implementation

`settlement_journal_persistence.ts` supplies internal
`persistSettlementJournalTransaction(db, uid, request, expectedEvidence?, options?)`
and caller-owned `prepareSettlementJournalPersistence(tx, ...)`. Neither appears
in `src/index.ts`, callable registration or a live writer call site.

Persistence fails closed unless **all** conditions hold:

* Explicit per-invocation `enableEmulatorPersistence:true` (default false).
* Exact SDK project `demo-fatoora-phase2b7`, default database and loopback emulator.
  Both the supplied database and transaction's actual SDK client must resolve to
  `127.0.0.1`, the selected port and `ssl:false`, before any reads. Merely changing
  an environment variable after creating a remote client cannot enable it.
* For new postings, the approved configuration-mode book also explicitly has
  `settlementJournalEmulatorEnabled:true`; its normal `journalPostingEnabled`
  remains **false**. No real configuration is created, inferred or enabled.

The existing settlement writer now exposes a read-plan/write-closure seam,
`prepareCashSettlementWrite`. Its callable retains its original signature,
authorization, numeric arithmetic, validation order, IDs, replay contract, cash
ledger helpers and fields. The atomic adapter calls that same plan **once**;
it does not duplicate cash construction or run a second nested transaction.
Only atomic mode strengthens source/movement creates and attaches an additive
`accounting` reference binding. The legacy transfer writer already used create
preconditions and remains unchanged.

The existing journal identity/economics, exact-decimal helpers, pending validation
and committed-source/legacy validators are shared. Request normalization is now
also shared with recovery; it does not establish authorization. No dependency,
Rules, index, Flutter, live Function export or unrelated posting change is needed.

Files changed:

| File | Change |
|---|---|
| `functions/src/trusted/settlement_journal_persistence.ts` | New isolated atomic adapter, durable envelope/recovery, SDK metadata and default-off guards. |
| `functions/src/trusted/record_cash_settlement.ts` | Shared transaction write plan; original callable uses unchanged defaults. |
| `functions/src/trusted/settlement_journal_intent.ts` | Share the existing deterministic identity function. |
| `functions/src/trusted/settlement_pending_evidence.ts` | Share pure request normalization and the existing bounded canonical codec. |
| `functions/src/trusted/settlement_preflight.ts` | Export the existing legacy-projection validator internally for recovery. |
| `functions/test/settlement_journal_persistence.test.js` | New 98-case synthetic transaction/security/reconciliation suite. |
| `functions/test/firestore.rules.test.js` | Extend client denial to request/audit/outbox/seal/lane targets; no Rules change. |
| `functions/package.json` | Add `test:settlement-persistence`; no dependencies or lockfile changed. |
| This document and the two Phase 2A architecture/integration documents | Contract, evidence and completion links. |

## Exact transaction contract

Every SDK attempt creates a fresh document cache and validates current approved
company-admin authority. The company must be active. Source lookup uses the
existing deterministic company-scoped `settlement_<key>` path.

For an unposted source, reviewed Phase 2B-6 evidence is mandatory. Inside the
**same** transaction, rebuild and compare that evidence, including current cash
head SDK versions, mappings/holders, policy/binding/currency/scale, accounting
period, lock, configuration revisions and target absence. Stale review is never
discarded or silently rebased during an SDK retry.

Additional explicit configuration is required:

| Configuration | Supported contract |
|---|---|
| Book journal definition | Pinned `settlementJournalDefinitionId` and `settlementJournalDefinitionRevisionId`. |
| `journal_definitions/{id}` | Scoped, approved, active immutable revision; action `rep_to_company_cash`, matching currency/scale, explicit `numberingPolicy:source_identity`. Its SDK creation/update times must match and predate or equal the book pin's version. A missing definition, an overwritten revision or an unsupported numbering policy blocks. |
| Book lanes | Explicit integer `postingLaneCount` from 1 through 64 and `postingLaneSchemaVersion:1`. No default lane count. |

Definition IDs identify journal rules; the deterministic journal entry ID
identifies this posting. Lane sequences are integrity order, not invented fiscal
document numbering. All fixtures supply explicitly approved synthetic mappings
and definitions; none are company accounting policy defaults.

Amounts are positive exact scale-3 unit strings, balanced with BigInt. The
prospective before/after values must also round-trip through the existing numeric
writer and agree with its arithmetic. Rounding, overflow, insufficient cash and
nonrepresentable numeric results reject. Business timestamps must additionally
round-trip at Firestore's microsecond precision; sub-microsecond nanos reject
**before writes**, rather than silently altering the business date or hash.

After every read completes, the transaction does the following:

| Artifact | Persistence |
|---|---|
| Existing settlement, representative OUT, company IN | Exactly one each, original IDs/amounts/metadata; immutable `create` in atomic mode. |
| Existing legacy financial transfer row | Exactly one original row via the existing mapper/writer; immutable `create`. |
| Two existing cash positions | Existing `writeCashBalance` operations, matching exact before/after effects and reciprocal movement IDs. |
| `journal_entries/{intentId}` | One create-only header with exactly two embedded balanced lines, currency/scale, mapped account revisions/treasury dimensions, source/event, period/date and journal-definition references. |
| `events/{intentId}` | Immutable pending evidence snapshot, actual posting kind, semantic event hash, definition witness, journal digest, reconciliation effect manifest and predecessor/lane references. The pending snapshot remains pending evidence with null future clocks. |
| `source_keys/{intentId}` | Immutable economic-action binding to journal/event/request and exact semantic/preflight digests. |
| `request_keys/{actorScopedHash}` | Immutable original result and complete request identity; no expiry. |
| `audit_events/{intentId}` | Immutable posting actor and all source/journal/event/digest references. |
| `outbox/{intentId}` | Immutable reconciliation/projection intent, effect digest and event references. No delivery, notification or external side effect is enabled. |
| `posting_contracts/settlement-v1` | Created only once, binding book currency/scale, lane count/schema and journal schema. |
| Book contract binding | Initialized with that seal in the first commit; prevents a missing seal from appearing to be an unused book on another lane. It is never a per-post counter. Later changes must preserve this binding. |
| One `posting_lanes/lane_XX` | Atomic sequence/hash/head update; lane is selected deterministically from the entry identity and configured count. Existing head must have matching scope, contract/hash/sequence and actual SDK commit witness. |

There are ten immutable financial/audit/result artifacts per settlement, two
mutable cash positions and one lane. First posting also creates the seal and
initializes its book binding: **15 writes**; subsequent postings use **13**.
The seal prevents an approved-looking monetary/lane reconfiguration from using
an empty lane to reinterpret an already initialized book.

The event reconciliation manifest contains original source/legacy paths, both
cash-leg/position paths, exact holder before/after effects, journal path, equal
debit/credit totals, conserved total cash and an effect digest. Settlement moves
cash custody; it creates no sale, tax, receipt, expense, inventory movement or
company cash gain. The compatibility transfer and journal are linked representations
of one action, not additive financial activity.

## Durable identity, recovery and failure behavior

Journal/event/source identity retains Phase 2B-4's company/book/source/action hash.
Actor-scoped request IDs additionally bind the admin and original settlement key.
Amount, full date, notes, representative or actor changes conflict for the same
committed source. The owning adapter captures request/evidence before asynchronous
work and SDK retries.

After current authorization, an existing atomic source is recovered **before**
today's cash, representative eligibility, mapping or open-period checks. Recovery
follows the source's original immutable book binding, even after an active-book
switch. An older successful result remains recoverable after subsequent cash
activity, lane advancement, period close or account/representative deactivation.
Admin revocation or inactive company still blocks access.

Recovery validates the complete source/cash/legacy/journal/event/key/result/audit/
outbox set, scoped deterministic paths, original request/evidence, all digests,
reciprocal links, actor/display snapshots and original cash equations. It rebuilds
the committed intent and complete legacy transfer projection using existing
validators/mappers. Legacy numeric metrics are compared as exact units; the
journal codec still forbids floating-point amounts. Immutable records must have
SDK `createTime == updateTime`, and all settlement artifacts must share the
original source's actual SDK creation time. Seal witnesses must precede the event.
Missing or altered records reject without reconstruction or repair.

An old legacy-only settlement without an atomic journal binding blocks this new
adapter; it is never implicitly backfilled. Its existing callable replay behavior
remains unchanged. Phase 2B-5's older source-key schema remains a separate
committed-preflight contract: Phase 2B-7 does **not** fabricate its commit-dependent
digests before commit. Atomic source recovery uses the complete new envelope.

Same-key concurrent requests converge on one committed result. Different-key
requests using the same reviewed cash versions can leave one stale; the loser
must explicitly re-prepare. All attempted creates and balance/lane writes roll
back together on a failure. Lost acknowledgements recover the durable original
result; no compensating entry, new key or second cash transfer is generated.

The isolated emulator can return exact gRPC code 3 `Transaction is invalid or
closed.` for a contending document read. The pinned SDK otherwise retries only a
differently worded expired-transaction code 3. This helper normalizes **only that
exact read error** into numeric ABORTED for the SDK's bounded fresh-attempt retry.
Original expected evidence remains mandatory. Other invalid-argument errors stay
fatal; no broad invalid-argument retry or business-validation bypass is used.

## Timestamp and commit evidence

Business/accounting date, SDK read observation and resolved server recording
fields remain separate. New immutable accounting records use a server transform
for `recordedAt`, while embedded `committedAt` remains **null**. Digests exclude
unknown future recording/commit values. Stored recording times may not exceed
their independent SDK create-time witness; equality is not assumed.

The owning transaction returns a staged result until the SDK commit succeeds.
It then performs a **recovery-only** read transaction and returns original source
SDK `createTime`, stored source `postedAt` and journal `recordedAt` independently.
That observation cannot stage another posting if the source is missing. A failed
post-commit observation is a recoverable acknowledgement failure, not evidence
that the posting did not commit. Actual durable commit evidence remains SDK
metadata; no financial record receives a guessed timestamp or a post-commit patch.

## Verification evidence

All execution uses the standalone loopback emulator at `127.0.0.1:8192` and
synthetic UUID company fixtures. The new adapter additionally enforces the exact
demo project. No cloud/Firebase-project CLI, deployments, data-maintenance command,
historical correction or real-project access is used. Adversarial corruption and
missing-document probes affect synthetic fixtures only; they never repair records.

| Verification | Result |
|---|---|
| Focused atomic suite | **98 passed, 0 failed/skipped**, including exact balancing/custody, complete references, safe replay, same/different-key concurrency, SDK retry, lost acknowledgement, post-commit observation failure, rollback, forged/stale review, missing/rewritten records, book seal/marker integrity, shared controls and legacy compatibility. |
| Complete backend regression suite | **920 passed, 0 failed/skipped**, including the 98 new tests, original 192 journal-intent / 85 committed-preflight / 135 pending-contract tests, existing cash/settlement metadata, authorization, customer reassignment, returns/refunds, receipts, inventory, reconciliation, reporting and audit regressions. Run directly with `node --test --test-concurrency=1` over `test/*.test.js`; no database-maintenance/reset runner was invoked. |
| Client Rules isolation | Passed within the regression suite: **200 denied operations** over ten accounting/configuration targets for admin, representative, inactive and unauthenticated clients. Existing Rules are unchanged. |
| Build / lint | **Passed**: TypeScript `tsc` and `tsc --noEmit`, Node **22.21.1**. |
| Fresh posting bounds | **28 document reads, 15 writes, zero queries** measured for the first mutating attempt. Continued posting uses 13 writes. Independent post-commit recovery adds bounded read-only observation. Hard per-attempt ceilings: 48 unique document reads / 16 writes; embedded lines and the existing canonical codec bound payloads. No cloud load/latency certification is claimed. |
| Source integrity | **424 baseline files checked**. Only the four existing settlement-related TS files and package test script changed among that baseline. All 373 Flutter files, live Function exports, common/cash/financial-ledger helpers/mappers, Firestore Rules/indexes, Firebase configuration and dependency lockfile remain byte-identical. |
| Workspace integrity | Passed tracked/new-file whitespace checks. The generated synthetic lifecycle snapshot was restored byte-for-byte. Only the documented implementation/tests/docs remain changed. |

Raw evidence lives in ignored `build/phase2b7/`: `atomic.log`, `regression.log`,
`source-boundaries.json` and emulator log. All tests used isolated synthetic
namespaces; no real users, financial history or cloud projects were accessed.
No Flutter rerun was needed because every Flutter source file is unchanged.
The dedicated emulator was stopped after verification. No critical blocker
remains for this emulator-only phase.

## Remaining boundaries and next phase

The durable posting is still disconnected from live posting and all UI/readers.
This phase proves settlement **deltas** against explicit existing cash positions;
it does not invent opening journals, certify full-book GL-to-cash totals or journal
legacy history. Live activation requires reviewed opening/coverage decisions and
a coordinated integration preventing unjournaled legacy posting in an active book.

Real currency/fiscal/mapping/definition/numbering approvals, trusted configuration
administration, production load/latency and IAM/archive protection remain outside
this phase. The runtime emulator guard intentionally depends on pinned SDK client
metadata and must fail closed after incompatible SDK changes. Admin SDK principals
can bypass client Rules; create-only commands and rewrite detection are not
absolute protection against a privileged operator recreating all evidence.

Smallest safe next phase: an internal **read-only atomic-settlement recovery and
reconciliation contract**, bridging legacy preflight and atomic envelopes, checking
holder journal deltas against cash effects and lane-prefix completeness. Keep
activation disabled; do not add another economic operation, opening/backfill,
production integration or Flutter screen. Phase 2B-7 stops here.
