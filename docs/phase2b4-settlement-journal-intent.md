# Phase 2B-4: settlement journal intent

Approved scope, 2026-11-04 (Asia/Amman): offline, pure settlement-only intent
construction/validation. No connection to posting, Firestore writes, endpoints,
policy/account creation, migration or UI changes.

## Contract and boundaries

The current mapping already debits `company_cash` and credits
`rep_cash:<representativeId>`. These are legacy ledger keys, not approved chart
account IDs. The new intent uses those existing keys plus explicitly supplied
chart-account revisions and mandatory treasury/holder dimensions. It is exposed
through the existing financial-ledger mapping module; the legacy mapping and
settlement writer remain unchanged.

Inputs are a company/book scope, an explicit monetary-policy revision, exactly
two account mappings, the complete Phase 2B-3 settlement snapshot and exactly
its two committed movement snapshots. The policy must declare one uppercase
currency and scale 3 (the supported current cash source precision). There is no
default currency, book, chart account or policy. Missing stored currency requires
an explicit `legacyCurrencyBindingId` supplied with the policy; any stored
currency/scale must agree. This is a caller-provided evidence reference, not
proof of approval by this offline module. Future trusted integration must read
and authorize the real policy/binding and account revisions in its transaction.

Account mappings explicitly name company/book/currency/scale, mapping/account revision IDs,
chart account ID, asset/cash-control/posting status, the existing ledger key,
treasury account ID, holder type and holder UID. Both sides must be active
posting cash assets. Required treasury/holder dimensions distinguish the two
positions even if a reviewed mapping explicitly uses one shared chart control
account. Shared account revisions must agree; missing, swapped, duplicate or
ambiguous mappings reject. No illustrative account codes become configuration.

Amounts use existing exact-decimal helpers: BigInt internally, canonical unit
strings in the JSON-compatible result, never floating-point arithmetic or a
balancing adjustment. Decimal strings must fit scale/range exactly. Legacy
numbers additionally require the existing safe, exact numeric round-trip check;
no rounding repairs missing/excess precision or unsafe source values.

All source IDs, company references, operation/settlement identities, OUT/IN
directions, reciprocal links, actual holders, source references, amount matches,
nonnegative before/after balances and exact balance equations must agree.
Phase 2B-3 metadata version, writer, cash method and explicit seller/collector
absence are required. Creator/initiator/poster snapshots must match this existing
synchronous admin flow. Business and committed timestamps are preserved as
`{seconds, nanoseconds}` with full precision; unresolved server sentinels and
guessed dates reject. This phase accepts resolved Timestamp-shaped evidence,
not date strings or clock-generated replacements.

Output is one deeply frozen, bounded JSON-compatible intent with two ordered
lines: company cash debit, representative cash credit. Each line has one
positive unit side and a zero opposite side, the same company/book/currency/
scale, explicit mapping/dimensions and its original movement/counterpart IDs.
The envelope retains source identity, both movement snapshots, committed
balances, actor provenance and timestamps. It creates no cash or ledger effect.

Intent identity is SHA-256 of a versioned JSON tuple of company, book,
`settlements`, original settlement ID and `rep_to_company_cash` action. Payload
changes never create a new identity for that action. Line IDs derive from the
intent ID and fixed debit/credit roles. A canonical sorted-key payload digest
binds normalized evidence, policy/mapping revisions and lines, including the
original persisted provenance timestamps. There is no builder execution clock,
randomness or request-dependent timestamp in the digest.

The builder optionally compares a caller-supplied prior intent: identical
canonical payload returns the same intent; a different payload conflicts. The
validator independently rebuilds from evidence and rejects any changed line,
digest, identity or additional field. Neither function remembers calls or claims
exactly-once persistence. A future atomic source-key/create-precondition protocol
must enforce deduplication across processes and concurrent requests.

## Verification and completion

Completed locally, **2026-11-04, Asia/Amman**. Only Phase 2B-4 is implemented.

### Exact public interface

Both functions are re-exported by `trusted/financial_ledger_mappings.ts`:

```ts
buildSettlementJournalIntent(input, priorIntent?): SettlementJournalIntent
validateSettlementJournalIntent(candidate, input): SettlementJournalIntent
```

`validate` reconstructs and returns the frozen expected intent; it does not
validate only the supplied totals/hash. Invalid evidence/candidates reject with
`invalid-argument`; a canonically different supplied prior intent rejects with
`already-exists`. Inputs and previous results are never mutated. Without a
caller-supplied prior intent there is no stored replay/conflict knowledge.

| Input field | Exact shape |
| --- | --- |
| `companyId`, `bookId` | Explicit nonempty bounded single identifiers; no default-company or active-book lookup. |
| `policy` | `companyId`, `bookId`, `revisionId`, `currency`, `moneyScale: 3`, optional `legacyCurrencyBindingId` (required if any source document lacks currency). |
| `mappings[]` | Exactly two records: `companyId`, `bookId`, `currency`, `moneyScale: 3`, `mappingRevisionId`, `accountId`, `accountRevisionId`, `accountType: asset`, `control: cash`, `active: true`, `postingAllowed: true`, `requiresTreasuryDimension: true`, `ledgerAccountKey`, `treasuryAccountId`, `holderType`, `holderUid`. |
| `settlement` | Phase 2B-3 posted settlement snapshot, including original idempotency key, representative/account/movement identities, amount, source/actor metadata and resolved timestamps. Optional explicit book/source/reference fields must agree when present. |
| `movements[]` | Exactly the original `_rep_out` and `_company_in` snapshots; input order is immaterial. All stored source/reference identities, directions, accounts, holders, currencies/scales when present, provenance, dates and balances are validated. |

| Output field | Exact meaning |
| --- | --- |
| `schemaVersion: 1`, `id`, `companyId`, `bookId`, `action: rep_to_company_cash` | Deterministic source identity in a single company/book. Identity tuple is `[1, companyId, bookId, 'settlements', settlementId, 'rep_to_company_cash']`; `id = settlement_intent_<SHA256(canonical tuple)>`. |
| `currency`, `moneyScale: 3`, `amountUnits` | Explicit single currency and positive canonical integer-unit string, bounded to 30 digits using the existing helper. |
| `policy` | Normalized supplied policy/binding evidence with its revision. |
| `source` | `collection: settlements`, original `id`, `path`, `number`, `status: posted`, `operationId`, `idempotencyKey`, `salesRepId`, `repMovementId`, `companyMovementId`, `sourceCashAccount/Id`, `destinationCashAccount/Id`, `settlementDate`, `updatedAt`, `provenance`. |
| `movements[]` | OUT then IN evidence: `id`, `path`, `companyId`, `settlementId`, `operationId`, `sourceCollection/Id/Number`, `referenceId/Number`, `type/movementType: settlement_to_admin`, `direction`, `counterpartMovementId`, `cashAccount`, `treasuryAccountId`, `holderType/Uid`, `salesRepId`, `amountUnits`, `balanceBeforeUnits`, `balanceAfterUnits`, `currency`, `moneyScale: 3`, `date`, `movementDate`, `provenance`. These are existing evidence, never commands to create movements. |
| `lines[]` | Exactly company debit then rep credit. Each has `id: <intentId>_debit/credit`, `companyId`, `bookId`, `currency`, `moneyScale: 3`, `account` (the full explicit mapping), `debitUnits`, `creditUnits`, `cashMovementId`, `counterpartMovementId`. |
| `payloadDigest` | SHA-256 hex of the complete normalized payload excluding this digest field, using recursively sorted object keys and ordered arrays. Monetary values are strings; timestamp integer fields retain nanoseconds. |

`provenance` on source and movements contains `settlementMetadataVersion: 1`,
`postingSource: recordCashSettlement`, `paymentMethod: cash`, `createdBy`,
`sourceCreatedBy`, `postedBy` actor snapshots (`uid`, `name`, `role: admin`),
`createdAt`, `postedAt`, and the empty seller/collector fields with their
`not_applicable` statuses. All timestamps are `{seconds, nanoseconds}`; all
resolved source commit timestamps must agree, as the current writer guarantees.
Stored representative names are not used to infer a holder or upstream seller.

### Changed files and checks

| Files changed in this phase | Purpose |
| --- | --- |
| `functions/src/trusted/settlement_journal_intent.ts` (new) | Settlement-only builder, strict source/mapping validation, deterministic identity/digest, optional replay comparison and frozen result. Uses existing exact-decimal and ledger-account-key helpers. No Firestore client, clock, randomness or I/O calls. |
| `functions/src/trusted/financial_ledger_mappings.ts` | Re-export the offline API/types; no existing mapping implementation or invocation changed. |
| `functions/test/settlement_journal_intent.test.js` (new) | Offline positive, negative, boundary, source isolation, coherent replay conflict and forged-candidate tests. Reuses the committed Phase 2B-3 fixture and SDK Timestamp values without a connection. |
| `functions/package.json` | Add `test:settlement-intent` build-and-focused-test command. No dependency changes. |
| `docs/phase2b4-settlement-journal-intent.md` (new) | Input/output contract, invariants, verification and remaining gates. |
| `docs/financial-modernization-strategy.md`, `docs/phase2a-firestore-accounting-architecture.md`, `docs/phase2a-inventory-cash-integration.md` | Link the approved completion and next bounded proposal. |

| Check | Result |
| --- | --- |
| `npm.cmd --prefix functions run test:settlement-intent` | **192 passed, 0 failed/skipped**. Covers debit/credit direction and exact balance, minimum/maximum units, malformed/unsafe/excess amounts, missing/conflicting mappings, shared-control dimensions, company/book/holder/currency isolation, missing/inconsistent movement pairs, all provenance, deterministic replay and coherent conflicting retries, forged balanced/unbalanced/duplicate journals even with recomputed digests, source immutability and compatibility with the existing settlement mapping. |
| Offline backend regression: `settlement_journal_intent`, `financial_ledger`, `exact_decimal`, `cash_reconciliation`, `integrity_reconciliation` test files, serial execution | **338 passed, 0 failed/skipped**, including the 192 focused tests. `FIRESTORE_EMULATOR_HOST` removed; no emulator, database, credentials, reset or maintenance command used. |
| TypeScript build / lint | **Passed**: `npm.cmd --prefix functions run build` and `run lint` (`tsc`, `tsc --noEmit`). |
| Source boundaries / whitespace | Other trusted source-file hashes match their Phase 2B-3 contents, including the settlement writer and cash helper. New API has no call site in the writer or endpoint exports. `git diff --check` passed. |

Ignored logs are under `build/phase2b4/`. No Flutter tests were required: Flutter
files and workflows are unchanged. Earlier workspace changes remain intact.

### Accounting invariants and remaining gates

- One source action in one company/book has one stable intent ID and two stable
  line IDs, independently of amount, retries, mapping input order or decimal
  spelling. Changed material evidence retains the source ID and changes the
  payload digest; prior-intent comparison rejects it.
- Exact company-cash debit equals exact representative-cash credit. There is no
  revenue, expense, tax, FX, opening plug, extra journal line or new cash leg.
- Holder/treasury dimensions are verified against the source pair and mappings;
  creator, seller and collector never supply cash-holder identity. Shared chart
  controls retain two distinguishable validated treasury positions.
- All before/after values are provided evidence, never synthesized openings.
  Both movement equations and nonnegative physical cash positions are required.
- Work is bounded to two movements, two mappings, two lines and a 64 KiB canonical
  payload, with structural limits on candidate validation. No cloud performance
  claim or persistent exactly-once guarantee is made.

Actual company `bookId`, monetary-policy revision, legacy currency binding,
chart cash-account IDs/revisions and mapping approvals remain unresolved. None
has been created or inferred; all examples/tests are synthetic. Supplied IDs,
flags and digests demonstrate internal consistency, not authenticity or current
authorization. A future trusted transaction must read/validate real revisions,
membership, book/period/maintenance gates and source paths.

This module deliberately requires **resolved, committed source timestamps**.
The current writer's `FieldValue.serverTimestamp()` sentinels cannot be passed
to it while writes are staged. An approved precommit evidence/timestamp contract
is a prerequisite to new atomic settlement/journal posting; do not fill in the
clock or relax validation as an integration shortcut.

**Smallest safe next proposal:** a settlement-only trusted transaction preflight
adapter with emulator tests, resolving actual book/policy/binding/account
revisions and checking source-key/replay conflicts through existing authorization.
Define and prove the precommit timestamp/evidence contract there. After that,
separately scope the single atomic source-key/journal/event/cash commit and its
rollback/concurrency tests. No live persistence wiring is included in Phase 2B-4.

No production access, deployment, reset, migration, historical correction,
journal persistence or connection to live posting occurred. Stop at Phase 2B-4.
