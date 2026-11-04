# Phase 2B-3: cash settlement metadata integrity

Scope: newly posted representative-to-company settlements through the existing
`recordCashSettlement` callable and trusted Firestore transaction only. No GL
engine, historical edits, migration, deployment or production access.

## Contract defined before implementation

Existing persistence is retained verbatim:

- Settlement: deterministic `id=settlement_<idempotencyKey>`, company, number,
  posted status, amount, `salesRepId/Name`, `repMovementId`, `companyMovementId`,
  settlement business date, notes, idempotency key, `createdByUid/Name/Role`,
  server `createdAt/updatedAt`.
- Each movement: deterministic `<settlementId>_rep_out` or `_company_in` ID,
  company, type/movementType `settlement_to_admin`, positive amount,
  reference ID/number, `sourceCollection=settlements`, source ID/number,
  settlement ID, empty customer identity, date/movementDate, notes,
  `createdByUid/Name/Role`, server `createdAt`, cash account, direction and
  committed `balanceBefore/After`. OUT `salesRepId` is the representative;
  IN `salesRepId` remains empty and its legacy `salesRepName` remains unchanged.
- Both cash balance documents and the existing financial ledger projection keep
  their current fields, amounts and write behavior.

Minimal additions (all trusted server values; request metadata is ignored):

| Documents | Added fields | Meaning |
| --- | --- | --- |
| Settlement and both movements | `settlementMetadataVersion: 1`, `postingSource: recordCashSettlement`, `operationId: <settlementId>` | Versioned writer provenance and company-scoped operation correlation; no separate audit event is claimed. |
| Settlement and both movements | `sourceCreatedByUid/Name/Role`, `postedByUid/Name/Role` | Authenticated approved company admin initiates and posts synchronously. These equal the existing `createdBy*` snapshot. The representative is never inferred from this actor. |
| Settlement and both movements | `postedAt` | Server commit timestamp, distinct from the requested settlement business date. |
| Settlement and both movements | `paymentMethod: cash` | Verified method of this existing cash transfer. |
| Settlement and both movements | `sellerId/Name: ''`, `sellerIdentityStatus: not_applicable`, `collectorUid/Name: ''`, `collectorIdentityStatus: not_applicable` | This transfer establishes neither an original seller nor a collection actor. No upstream collection attribution is invented. |
| OUT movement | `treasuryAccountId: rep_<salesRepId>`, `holderType: representative`, `holderUid: <salesRepId>`, `counterpartMovementId: <companyMovementId>` | Identity comes from the validated representative and the actual balance state read in the transaction. |
| IN movement | `treasuryAccountId: company_cash`, `holderType: company`, `holderUid: <companyId>`, `counterpartMovementId: <repMovementId>` | Company holder is an organization, not the initiating admin. |
| Settlement | `sourceCashAccount: rep_cash`, `sourceCashAccountId: rep_<salesRepId>`, `destinationCashAccount: company_cash`, `destinationCashAccountId: company_cash` | Actual source/destination balance document identities, scoped by the existing company path. The existing rep identity and movement IDs link to both holders and balance snapshots. |

Amounts retain existing numeric three-decimal JOD rounding. There is no new
money representation or recalculation: both legs use the same existing rounded
amount and existing balance arithmetic. Before/after snapshots describe commit
order, not running balances ordered by business date.

All additions are in the same existing transaction, after all reads. No added
reads, queries, documents or writes. Keys, validation, replay comparison, account
paths, locks, permission checks and transaction retry behavior remain unchanged.
Replays return without enriching or modifying any historical document, including
settlements that predate this metadata version.

Phase 2B-2 compatibility: the model preserves additive raw fields and already
reads `sourceCreatedBy*`, `postedBy*`, `holder*`, `treasuryAccountId`,
`counterpartMovementId`, `operationId` and `paymentMethod`. Existing repositories,
cash screen/detail projection and PDF need no replacement or schema change.
Seller/collector stay unavailable. Legacy documents retain their prior decoding.

## Verification and completion

Completed locally, **2026-11-04, Asia/Amman**. Only Phase 2B-3 is implemented.

| Files changed in this phase | Purpose |
| --- | --- |
| `functions/src/trusted/record_cash_settlement.ts` | Add the above metadata to the existing three documents. Reuse `cash_ledger.ts` state references/identities without modifying the shared helper or other posting workflows. |
| `functions/test/trusted_transactions.test.js` | Ten settlement metadata tests plus helpers; optional export of actual synthetic committed movements for Flutter compatibility verification. |
| `test/cash_read_contract_test.dart` | Decode the actual writer payload; verify holders, exact amounts/balances, company/rep read scopes, role separation, pair grouping, raw metadata round-trip and bilingual shared screen/PDF detail projection. |
| `test/pdf_services_settings_test.dart` | Export the actual paired writer payload through the existing English/Arabic cash PDF builder. |
| `test/fixtures/cash_settlement_metadata.json` | Durable synthetic writer payload with stable fixture identities, so both new Flutter tests also run without a backend or environment override. |
| `docs/phase2b3-cash-settlement-metadata.md` | Pre-implementation persisted/additive contract, final evidence and next bounded proposal. |
| `docs/phase2a-inventory-cash-integration.md`, `docs/financial-modernization-strategy.md`, `docs/phase2a-firestore-accounting-architecture.md` | Link this separately approved implementation and update the next proposal. Prior phase evidence is retained. |

All earlier workspace edits are retained. No application reader/repository,
controller, screen or PDF implementation change was needed for this phase.

| Check | Result |
| --- | --- |
| Focused backend `node --test --test-name-pattern='^settlement metadata' test/trusted_transactions.test.js` | **10 passed, 0 failed/skipped**. Exact matching OUT/IN and balance equations, trusted custody/actor/source metadata, untouched unrelated account/history, cash reconciliation, duplicate/conflicting requests, legacy replay, real commit-precondition rollback and same-key retry, SDK automatic ABORTED retry, concurrent same-key and distinct-key attempts, shared company balance contention, unauthorized/cross-company/inactive-holder rejection, reconciliation lock, mismatched/missing balance and orphan-leg rejection. |
| All `functions/test/*.test.js`, serial file execution on dedicated loopback emulator `127.0.0.1:8087` | **385 passed, 0 failed/skipped**, including the ten new tests, trusted operations, callable auth, Rules, receipt cancellation, expenses/refunds, inventory integrity, exact decimal helpers, financial ledger/reporting and cash reconciliation. Only synthetic test namespaces; no reset/maintenance CLI was invoked. |
| Affected Flutter regression: cash read, cash screen/controller, cash calculator/index manifest, PDF services, financial model compatibility, financial ledger/phase13/posting calculator and exact decimal suites | **195 passed**. `SETTLEMENT_METADATA_FIXTURE_PATH` selected the actual emulator-committed OUT/IN payload exported by the backend test. |
| Durable fixture with environment override removed, both `Phase 2B-3` Flutter tests | **2 passed**. Normal standalone test execution retains the same compatibility coverage. |
| TypeScript `npm.cmd --prefix functions run build` and `run lint` | **Passed** (`tsc`, `tsc --noEmit`). |
| Final `flutter analyze --no-pub`, Dart formatting and `git diff --check` | **Passed**, no analysis issues or whitespace errors. |

Logs and the optional actual-writer JSON are ignored under `build/phase2b3/`.
The complete backend run used `node --test --test-concurrency=1` with every test
file, directly; it did not invoke the suite wrapper's namespace reset step.
The existing synthetic lifecycle snapshot generated by the regression was
restored byte-for-byte to its original tracked content.

## Remaining gaps and smallest next batch

- Historical settlements are neither audited nor enriched on replay; missing old
  metadata remains unavailable. This phase does not certify historical balances
  or deployed behavior.
- Existing three-decimal Number storage, aggregate precision and separate-read
  reporting limitations remain. No new exact-string money schema or atomic
  reporting snapshot is introduced.
- `operationId` and writer/version fields provide transaction provenance, not a
  separate audit-event collection, GL journal, external handover receipt or
  upstream seller/collector evidence. A settlement cannot establish the origins
  of fungible representative cash.
- No cloud load/cost claim is made. The change adds document fields only, with
  zero extra reads/queries/documents/writes; existing shared-account contention
  and Firestore retry behavior remain.

**Smallest next proposal, requiring separate scope approval:** settlement-only
pure journal-intent validation in the existing `financial_ledger_mappings.ts`,
using existing exact-decimal units. Validate one company-cash debit and one
representative-cash credit of equal positive amount, verified company/account
identities and the source/movement/actor envelope. Prove rejection of unequal,
wrong-company, wrong-holder or missing-source intents without changing current
posting output. Keep it stateless and local; no GL engine persistence, new
endpoint/page, other posting workflow, migration or deployment in that batch.

No production access, deployment, business database reset, historical backfill,
migration or double-entry GL engine implementation occurred. Stop at Phase 2B-3.
