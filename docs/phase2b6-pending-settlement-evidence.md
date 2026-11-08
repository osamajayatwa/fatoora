# Phase 2B-6: pending settlement evidence and timestamp contract

Implemented 2026-11-08. Scope: internal read-only evidence for a **not-yet-posted**
representative-to-company cash settlement. This completes the prerequisite named
in [Phase 2B-5](phase2b5-settlement-preflight.md). No journal persistence, callable,
writer integration, deployment, cloud access or historical correction is included.

## Implementation and boundaries

`functions/src/trusted/settlement_pending_evidence.ts` provides
`pendingSettlementEvidenceTransaction(db, uid, request, expectedEvidence?)` and
caller-owned `preparePendingSettlementEvidence(tx, db, uid, request, expectedEvidence?)`.
Both return `{evidence, observation}`. Neither is exported through `src/index.ts`
or called by existing posting code. All reads must precede caller-owned writes.

The existing settlement writer remains byte-identical. Shared pure journal
economics were extracted from the Phase 2B-4 builder; the committed builder uses
the same identity, validated dimensions and balanced lines. Shared configuration,
mapping, current-cash and bounded transaction-reader checks were extracted from
Phase 2B-5. Its committed-source schema and preflight digest are retained.
The new helper never forges a committed source to invoke the committed builder.

Only an authenticated, currently approved active company admin can prepare
evidence. The representative must independently be active, approved and in that
company. The company/book, approved pinned policy/mapping/chart revisions, open
period and reconciliation lock are re-read in each attempt. Books must remain
in `configuration` mode with settlement preflight enabled and journal posting
**disabled**. No configuration is created or approved by this phase.

## Immutable evidence

The request accepts only company, legacy idempotency key, representative, exact
amount, resolved settlement business timestamp, optional notes and optional book
constraint. Caller-supplied accounts, currency, actors or committed timestamps
are rejected. Amounts use existing BigInt scale-3 helpers, persistable canonical
unit strings, and the unchanged legacy numeric adapter's exact range. Excess
precision is rejected rather than rounded. Pending cash must stay nonnegative.
The prospective exact results must also equal the unchanged writer's rounded
numeric addition/subtraction. A representable operand/result alone is insufficient:
the boundary fixture proves a one-mill difference when subtracting 0.040 from
9,007,199,254,740.990. Pending evidence blocks this case; legacy posting is not
silently modified.

The deeply frozen, JSON-only evidence contains:

* Stable source path/ID/operation, legacy display number/key, notes, trusted admin
  and representative names/identities. Seller/collector remain explicitly not
  applicable; the admin's identity never establishes cash custody.
* Explicit currency/scale and policy, book/mapping/binding/period revisions, full
  mapped account revisions and company/representative treasury dimensions.
* Company debit and representative credit for exactly equal positive units.
  Shared chart cash controls retain separate treasury/holder dimensions.
* Both current balance/head witnesses and exact prospective OUT/IN effects,
  including before/after units, paths and reciprocal movement IDs. The sum of
  physical cash before and after is equal. Settlement is a transfer, not sales,
  revenue, tax, collection, expense or inventory activity.
* Sorted SDK document versions and deterministic target paths for the legacy
  settlement, two cash movements, legacy transfer row, source key, journal and
  event. All seven targets must be absent. Even matching-looking existing targets
  reject a pending claim; committed-result recovery is deliberately unsupported.

Current balances must equal their pointed movement's after value and satisfy
its exact balance equation and company/account/holder dimensions. Balance SDK
`updateTime` must equal head SDK `createTime`; stored `updatedAt` and head
`createdAt` are compared separately. Unknown legacy cash currency requires the
existing explicit approved binding; explicitly stated conflicting currency blocks.
This validates current heads, not the complete historical cash chain.

## Identity and digest contract

Identity is the existing Phase 2B-4 SHA-256 tuple:
`[1, companyId, bookId, "settlements", settlementId, "rep_to_company_cash"]`,
prefixed `settlement_intent_`. The legacy source is `settlement_<key>`; movement
and line IDs retain existing deterministic suffixes. Amount/date/notes/config
changes do not create another identity for the same source action. A different
company, book or source has a different identity. A new legacy key denotes a
different source; this phase does not invent upstream action deduplication.

Digests use bounded canonical JSON (ordinal sorted object keys, ordered dense
arrays, safe-integer numbers, plain data only) and SHA-256:

| Digest | Bound data |
|---|---|
| `requestDigest` | Schema, company/source ID, representative, exact units, full business timestamp, normalized notes and authenticated initiator UID. |
| `economicDigest` | Schema, trusted source metadata, shared journal economics and full accounting date. |
| `configurationDigest` | Schema, revision/period context, policy, mapped accounts and SDK versions of all observed configuration and authorization/profile records, including an absent maintenance lock. |
| `preflightDigest` | Schema/mode, economic/configuration digests, both positions and known commit witnesses, prospective cash effects, all observed versions and target paths. |

SDK `readTime` and unknown future commit values are excluded from those hashes.
Absence uses `{path, updateTime:null}`. Snapshot versions reject same-revision
edits and ABA changes, not merely declared revision strings. An identical request
against unchanged records yields identical evidence across retries and parallel
calls; fresh observation clocks can differ.

Optional expected evidence is captured as bounded plain JSON before asynchronous
reads, never treated as trusted input. The owning adapter also captures the
request before SDK retries. Every attempt rebuilds from trusted reads. Different
request digest gives `already-exists`; changed configuration/preflight evidence
gives `failed-precondition`; otherwise complete canonical equality is required
(`invalid-argument` for tampering/extra fields). Copied hashes cannot authorize
changed evidence. Limits: 4,096 nodes, depth 16, 64 array elements/object keys,
2,048-character string values and 64 KiB encoded evidence; accessors, symbols,
sparse arrays, sentinels, cycles and class instances reject.

Digests are not signatures, authorizations or durable reservations. Independent
pending readers may prepare different payloads for the same source identity.
The expected-evidence comparison detects that conflict; no winner is persisted.

## Timestamp contract

| Value | Meaning and source |
|---|---|
| `evidence.timestamps.accountingDate` | Resolved settlement business date with nanoseconds; must be in the approved period `[startsAt, endsAt)`. It may differ from transaction time. No local-clock period selection. |
| `observation.transactionReadTime` / document `readTime` | Actual SDK observations for this attempt; company read witness is identified explicitly. Never used as committed time. |
| Position `headRecordedAt` / `updatedAt` | Existing resolved server timestamp fields; independently retained. |
| Position `headCommittedAt` / `balanceCommittedAt` | Existing SDK head `createTime` / balance `updateTime`, not a document's claimed timestamp. |
| Pending source/journal `RecordedAt` and `CommittedAt` | All **null**. No source or journal has been posted by this helper. |

The future atomic writer must use server transforms for recorded fields and
obtain actual commit metadata only from trusted SDK results or subsequent trusted
snapshots. A transform cannot know the future SDK commit result. Do not require
recorded transform time to equal SDK commit time, replace it with read/business
time, pre-resolve a sentinel, or append a guessed commit timestamp to this frozen
evidence. The emulator demonstrates separate recorded and SDK clocks; the
contract does not assume that every environment produces a numeric difference.

After a real settlement is subsequently posted by the unchanged existing writer,
Phase 2B-5 validates its genuine recorded/commit metadata and the same journal
identity/lines. The original pending evidence remains immutable with null future
clocks. It cannot be relabeled as a committed result.

## Future atomic persistence boundary

A separately approved adapter must recheck current authorization, configuration,
period/lock, keys and cash heads **inside the same transaction as all writes**,
compare expected evidence and use create preconditions for immutable targets.
It must preserve existing source/cash/legacy effects and atomically bind the
source key, journal, event and the architecture's required request result,
audit/outbox and lane effects. It must implement currently-authorized committed
replay/lost-ack recovery separately from pending preparation. No persistence code,
enabled feature switch, new workflow or partial dual-write path is supplied here.

## Local verification

Tests run against the standalone loopback Firestore emulator at
`127.0.0.1:8191`; new fixtures use `demo-fatoora-phase2b6` and UUID synthetic
companies. Existing regression suites use only their synthetic namespaces on the
same isolated emulator. No cloud credentials, Firebase project CLI, deployment,
production/staging reads or business-data maintenance were used.

The focused suite covers exact conservation, custody, mapped dimensions,
immutable evidence, canonical tampering, timestamp witnesses/unknown clocks,
nanosecond period boundaries, identical/concurrent/retried preparation, request
conflicts, stale configuration/cash/ABA versions, permission revocation,
non-posting gates, all target collisions, read-before-write transaction ordering,
real writer races and subsequent committed-source equivalence. Collision tests
seed invalid synthetic target documents solely to prove rejection, not journals
or accounting postings.

Typical preparation: **22 unique observed documents plus one duplicate existing
authorization read (23 document reads)** in 11 batched reads plus authorization;
shared controls/explicit currency can reduce this. The shared hard budget is
24 unique observed documents plus authorization. There are **zero queries and
zero writes** in the adapter, and caches are local to each transaction attempt.
This is a boundedness check, not cloud latency/load certification.

| Check | Result |
|---|---|
| Final pending contract suite | **135 passed, 0 failed/skipped** (`test/settlement_pending_evidence.test.js`). Includes both legacy arithmetic compatibility and structural input bounds. |
| Explicit client accounting isolation | **1 passed**: 100 denied get/list/set/update/delete operations across admin, representative, inactive and unauthenticated clients for configuration/source-key/journal/event targets. No Rules changes. |
| Existing backend/Rules/financial regressions | **686 passed** in the complete 814-test run (the other 128 were the pending suite before its final additions). Covers the 192 original intent and 85 committed-preflight tests, authorization, reassignment, original seller returns/refunds, receipts/cancellation, cash, inventory, reconciliation, reporting and existing posting. Unaffected evidence reused after changes confined to the new pending module/tests. |
| TypeScript build/lint | **Passed** (`tsc`, `tsc --noEmit`), Node **22.21.1**. No dependency changes. |
| Scope/integrity | **Passed**: 422 baseline files checked; only the intent/preflight extraction and package test script changed among them. All 373 Flutter files, live settlement writer, common/cash/financial posting helpers, Function exports, Rules, indexes, Firebase configuration and dependency lockfile remain byte-identical. No live call site added. |
| Workspace artifacts | **Passed**: generated synthetic lifecycle snapshot restored byte-for-byte; tracked and new-file whitespace checks clean. |

This covers **822 distinct final test cases** using the unchanged 686 regression
results plus the final 135 pending tests and new Rules test. Raw logs and SHA-256
boundary evidence are in ignored `build/phase2b6/` (`regression.log`,
`pending-final.log`, `accounting-rules.log`, `source-boundaries.json`). No Flutter
rerun was needed because every Flutter file is unchanged. All isolated emulator
processes started for this phase were stopped after verification.

## Remaining risks and smallest next phase

No durable reservation or exactly-once accounting persistence exists. Client
Rules/IAM cannot protect against a privileged Admin SDK bug; this internal
helper grants no endpoint or client access. Company fiscal/currency/configuration
approvals and full historical cash reconciliation remain separate prerequisites.
Existing legacy writer rounding and date/notes replay behavior remain unchanged;
the pending contract is stricter and is not yet connected to that writer.

Smallest safe next phase: a separately authorized **emulator-only settlement
atomic persistence adapter**, composed with the existing writer's transaction,
including all required source-key/journal/event/request/audit/outbox/lane effects
and lost-ack/replay proof. Keep it unexported, feature-gated and disconnected
from live posting until its own acceptance. No other economic action or UI
feature should be included. Phase 2B-6 stops here.
