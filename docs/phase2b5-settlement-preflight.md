# Phase 2B-5: settlement transaction preflight

Approved scope, 2026-11-04 (Asia/Amman): an internal read-only Firestore
transaction adapter for committed Phase 2B-3 settlements and the Phase 2B-4
journal intent. No callable, posting integration, accounting persistence or
configuration creation. All new configuration below is a required read contract,
not installed company configuration. Missing or unapproved records block.

## Preflight contract

`preflightSettlementTransaction(firestore, uid, input)` owns a Firestore
transaction. `prepareSettlementPreflight(transaction, firestore, uid, input)`
performs the same reads inside a caller-owned transaction, **before any writes**.
Neither function writes. Input names only `companyId`, original `settlementId`,
optional `expectedBookId` and optional `expectedPreflightDigest`; no client
amounts, actors, chart accounts, balances or timestamps are accepted.

Use the existing approved-user resolver and require the current caller to be a
company admin. Resolve the active book through the company record, never through
a default company or a caller-selected alternate book. Validate current approved
representative membership independently of creator/seller identities.

Required scoped records (`C=companies/{companyId}`, `B=C/books/{activeBookId}`):

- `C`: `id`, `active: true`, `activeBookId`.
- `B`: scoped `id/companyId`, `revisionId`, `approvalStatus: approved`,
  `active: true`, `mode: configuration`, `settlementPreflightEnabled: true`,
  `journalPostingEnabled: false`, explicit `currency`, `moneyScale: 3`,
  `policyRevisionId`, `settlementMappingRevisionId`, `settlementPeriodId`.
- `B/policy_revisions/{policyRevisionId}`: scoped `id/companyId/bookId`,
  `revisionId` matching ID, approved status, currency/scale matching the book,
  `accountingDateBasis: settlement_business_date`, optional
  `legacyCurrencyBindingId`. Missing source currency requires the binding.
- `B/currency_bindings/{legacyCurrencyBindingId}`, when referenced: scoped
  ID/revision, approved status, `sourceCollection: settlements`,
  `postingSource: recordCashSettlement`, `settlementMetadataVersion: 1`,
  matching currency/scale. No guessed JOD policy.
- `B/settlement_mappings/{settlementMappingRevisionId}`: scoped ID/revision,
  approved status, explicit `companyCashAccountId/RevisionId` and
  `representativeCashAccountId/RevisionId`. These are chart controls, not one
  chart account per representative.
- Referenced `B/chart_accounts/{id}`: scoped ID/revision, approved, active posting
  cash assets with `accountType: asset`, `control: cash`,
  `requiresTreasuryDimension: true` and matching currency/scale. Pinned account
  revisions must match. An explicitly shared control retains distinct verified
  treasury/holder dimensions.
- Referenced `B/periods/{settlementPeriodId}`: scoped ID/revision, approved,
  `status: open`, explicit resolved `startsAt/endsAt`; accounting date lies in
  `[startsAt, endsAt)`. No period/date search or calendar inference.
- Existing `C/maintenance_locks/cash_reconciliation`: absent/inactive permits
  reads; active or malformed lock state blocks.
- Original settlement, deterministic OUT/IN movements, the existing deterministic
  financial-ledger projection and both cash balance records must exist and agree.
  Representative identity comes from the source account plus validated user.
- Both current cash positions require consistent identity, exact amount,
  `lastMovementId` and resolved `updatedAt`. Validate their pointed-to movement's
  exact balance equation and account/holder attribution. The balance document's
  SDK update time must equal the head document's SDK creation time; their stored
  server-recorded timestamps must also agree with each other. These two clock
  values need not equal each other.
  If later cash activity advanced the position, validate that head; do not demand
  that historical settlement after-balances equal current positions. This is
  bounded head validation, not full-history reconciliation.
- `B/source_keys/{intent.id}` is read without reserving it. An existing binding
  must match `schemaVersion: 1`, scope, source collection/ID/action, `intentId`,
  `payloadDigest` and `preflightDigest`. Matching means binding evidence only;
  it does not prove a journal exists. A conflicting binding blocks.

The adapter passes validated snapshots and mappings to both Phase 2B-4 builder
and validator. Output includes their unchanged frozen `intent`, resolved
period/revision context, exact current position/head evidence, source-key
path/state, deterministic `preflightDigest` and read/update timestamp witnesses.
The digest binds intent, original SDK source commit time, configured
book/policy/binding/mapping/account/period revisions and period boundaries.
Account revisions are already bound by the Phase 2B-4 intent. It excludes read time, mutable cash head and
request identity; these are revalidated on every invocation. An expected digest
or existing source binding mismatch rejects a conflicting retry. No binding is
created; concurrent identical preflights perform no financial operation.

## Timestamp and transaction strategy

- `accountingDate`: original settlement business timestamp under the explicit
  approved date-basis policy, checked against the selected open period.
- `sourceRecordedAt`: the original stored `postedAt` server transform, preserved
  by the Phase 2B-4 intent. It is resolved after the source transaction, but is
  **not assumed to equal the SDK commit metadata**.
- `sourceCommittedAt`: original settlement snapshot `createTime`, independently
  supplied by Firestore. Source settlement, both movement documents and the
  existing legacy ledger row must share that SDK creation time, witnessing their
  original atomic creation. Stored recorded time must not exceed it.
- `transactionReadTime`: Firestore snapshot `readTime` observed in this read
  transaction. It is server-provided snapshot time, not source business time,
  a future execution timestamp or a journal commit timestamp.
- `journalCommittedAt: null`: no journal has been written. Never substitute a
  read time, `Timestamp.now()` or a fabricated value for a future server commit.

Callbacks keep all state local, batch/cache bounded document reads, perform no
queries, external effects or writes, and propagate Firestore failures. SDK
retries re-read everything. Returned witnesses are observations, not a permit to
post later without revalidation in the eventual atomic transaction. The
committed-evidence builder still rejects unresolved server timestamp sentinels;
this phase does not pretend that it can process a not-yet-committed settlement.

## Completion evidence

Completed locally, **2026-11-04, Asia/Amman**. Only Phase 2B-5 is implemented.

### Exact result and error contract

`SettlementPreflight` is deeply frozen and contains:

| Field | Meaning |
| --- | --- |
| `schemaVersion: 1`, `mode: committed_settlement_read_only`, `preparedByUid` | Internal preparation identity and current authorized admin. The source's original initiator/poster remains in its intent, independently. |
| `intent` | Unchanged Phase 2B-4 two-line journal-intent contract with exact unit strings, original source/leg/holder/actor identities and resolved recorded timestamps. |
| `preflightDigest` | SHA-256 hex of `[1, intent.id, intent.payloadDigest, sourceCommittedAt.seconds, sourceCommittedAt.nanoseconds, bookRevisionId, policyRevisionId, mappingRevisionId, bindingRevisionId-or-null, periodId, periodRevisionId, startsAt.seconds, startsAt.nanoseconds, endsAt.seconds, endsAt.nanoseconds]`. No volatile clock, cash head or requesting-admin identity enters this digest. |
| `context` | `bookRevisionId`, `policyRevisionId`, `mappingRevisionId`, `legacyCurrencyBindingRevisionId` (or null), `period: {id, revisionId, startsAt, endsAt}`. |
| `positions[]` | Representative then company: `path`, exact `amountUnits`, `lastMovementId`, stored `updatedAt`, stored `headRecordedAt`, SDK `headCommittedAt`. Source committed before/after balances remain unchanged inside `intent.movements`. |
| `sourceKey` | Deterministic scoped `path` and `state: absent` or `matching_binding`. No reservation, journal lookup, accounting write or posted-result claim. |
| `timestamps` | `accountingDate`, `sourceRecordedAt`, `sourceCommittedAt`, `transactionReadTime`, `journalCommittedAt: null`; all available timestamps preserve `{seconds, nanoseconds}` without Date conversion. |
| `observations[]` | Each unique adapter-read document path with SDK `readTime` and `updateTime` (null for an absent document). The existing authorization resolver's profile read is additional and is not duplicated in this array. |

Existing authorization errors remain `unauthenticated`/`permission-denied`.
Missing/unapproved configuration, inconsistent ownership/positions/periods and
unsupported state block with `failed-precondition`. The unchanged intent builder
can reject malformed source evidence with `invalid-argument`. Expected-digest
or existing binding conflicts return `already-exists`. Firestore transaction
errors propagate; no exception triggers an alternative write path.

The emulator exposed a real clock distinction during verification: stored server
transforms and SDK commit timestamps were different. The implementation neither
rounds nor adds a tolerance to make them equal. It preserves both and compares
only timestamps with the same semantic role. Legacy financial-ledger `postedAt`
continues to mean its existing business-date alias; it is not used as source
commit metadata. Phase 2B-4's resolved source timestamp contract is retained.

### Files changed

| File | Change |
| --- | --- |
| `functions/src/trusted/settlement_preflight.ts` (new) | Internal owning/caller-owned transaction adapters, approved-record resolution, exact source/current-position/legacy-row checks, two-line intent build/validation, version/digest observations and explicit timestamp roles. |
| `functions/test/settlement_preflight.test.js` (new) | Loopback-emulator-only synthetic configuration and real-writer fixtures, read-only assertions, failures/replays/contention and timestamp checks. No test project reset is required. |
| `functions/package.json` | Add `test:settlement-preflight`; no dependency changes. |
| `docs/phase2b5-settlement-preflight.md` (new) | Exact read/result/timestamp contracts, verification and next gates. |
| `docs/financial-modernization-strategy.md`, `docs/phase2a-firestore-accounting-architecture.md`, `docs/phase2a-inventory-cash-integration.md` | Link the separately approved completion. |

The settlement writer, cash helper, journal-intent builder/validator, existing
financial-ledger mappings, endpoint exports and Flutter sources are unchanged.
Source hashes are checked against the Phase 2B-4 workspace; earlier edits remain
intact. No replacement business workflow or application screen was added.

### Verification

Verification used only dedicated loopback Firestore emulator `127.0.0.1:8089`
and synthetic test namespaces. The focused suite guards the loopback address
before initializing Admin and uses UUID-isolated fixtures in
`demo-fatoora-phase2b5`. No production credentials, access or changes were used.

| Check | Result |
| --- | --- |
| `FIRESTORE_EMULATOR_HOST=127.0.0.1:8089 npm.cmd --prefix functions run test:settlement-preflight` (PowerShell environment assignment) | **85 passed, 0 failed/skipped**. Includes valid and shared-control preparation; exact units/account attribution; missing/unapproved/malformed configuration; company/book/currency isolation; incomplete source/legacy/head evidence; stale or malformed positions; source timestamp/atomic creation checks; duplicate/concurrent requests; source-binding and expected-digest conflicts; automatic ABORTED retry; account deactivation across retry; transport failure; caller-owned read-before-write failure; original callable/writer/replay compatibility and no financial changes. |
| Every `functions/test/*.test.js`, direct `node --test --test-concurrency=1` | **662 passed, 0 failed/skipped**, including the 85 focused tests, 192 intent tests, existing trusted transactions, authorization/Rules, cash reconciliation, inventory, returns, receipts/cancellation, expenses, decimal helpers, financial ledger/reporting and maintenance regressions. No production or maintenance CLI was invoked; synthetic test setup/cleanup stayed on loopback. |
| TypeScript build / lint | **Passed**: `npm.cmd --prefix functions run build`, `run lint` (`tsc`, `tsc --noEmit`). |
| Source boundaries / whitespace | All pre-existing trusted source files match their pre-phase SHA-256 hashes. No new API reference appears in the writer or callable exports. `git diff --check` passed. |

Ignored logs and source-boundary evidence are in `build/phase2b5/`. The synthetic
lifecycle snapshot generated by the existing regression was restored byte for
byte to its original tracked contents. No Flutter files were changed in this
phase, so no Flutter tests were necessary.

The supported flow uses at most **20 document reads including authorization**
(17 adapter observations plus one auth read for a typical current-head source;
up to two extra heads after later activity). Shared chart controls and explicit
source currency reduce reads. The adapter additionally enforces a hard 24 unique
document budget plus the one existing authorization read. Reads are batched and
cached only within each transaction attempt. There are **zero queries and zero
writes** in preflight. No cloud load/performance certification is claimed.

### Unresolved decisions and next boundary

Actual company active book, approved currency/scale/binding, chart controls,
mapping revisions, fiscal period boundaries and approval administration remain
owner/accountant decisions. The new records are a required read schema, not
created or approved configuration. They exist only in synthetic emulator fixtures
in this phase; a missing record stays blocked. Only configuration-mode books
with preflight explicitly enabled and journal posting disabled are supported.

This is bounded verification of committed evidence and current heads, not a
historical backfill or complete cash-chain reconciliation. Rebuilt/annotated
positions or separately recreated legacy evidence lacking the required atomic
witness block; no balance
is repaired or invented. Stored fields are trusted protected source evidence;
SDK metadata independently witnesses document creation/update, not the origin
or authenticity of every individual historical field.

Results are observations at a transaction attempt, not durable reservations or
approval tokens. Every eventual accounting commit must re-read authorization,
gates, configuration revisions, source keys and affected positions atomically.
Matching source bindings do not prove that a journal/event exists. Request-key,
immutable journal/event/audit/outbox persistence and live GL integration remain
unimplemented.

**Smallest next batch:** define a pending-settlement intent/evidence contract and
prove it in the emulator, with economic/configuration digests independent of an
unknown future commit timestamp. Keep trusted transaction observation,
accounting date and server commit fields separate. This is the remaining
prerequisite before separately approving a settlement-only atomic
journal/event/source-key plus existing cash-effects commit. Do not pass staged
`FieldValue.serverTimestamp()` values or invented resolved times to the current
committed-evidence builder. No journal persistence is implemented in Phase 2B-5.

No production access, deployment, production reset/change, historical migration,
backfill, journal persistence or callable/UI integration occurred. Stop at Phase 2B-5.
