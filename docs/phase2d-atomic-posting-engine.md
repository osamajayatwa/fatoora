# Phase 2D — Shared atomic posting engine

2026-11-10, Asia/Amman. Implements the next foundation subphase after
[Phase 2C](phase2c-accounting-configuration.md). Local synthetic acceptance only;
no deployment, live posting, opening import or company active-book switch.

## What is implemented

- `accounting_journal.ts`: shared immutable journal contract and validation,
  exact unit strings/BigInt, bounded canonical evidence hashing, economic action
  identity and Asia/Amman accounting dates from explicit business timestamps.
- `accounting_transaction.ts`: one-attempt document cache, reads-before-writes,
  company/book isolation, declared domain write targets, resolved emulator guard,
  immutable record envelopes and transaction/document/byte budgets.
- `accounting_posting.ts`: trusted adapter protocol, current authorization,
  configuration/account/period/definition checks, immutable monetary/lane seal,
  source/request deduplication, canonical journals/events, atomic audit/outbox,
  committed lane prefixes, lost-acknowledgement recovery and request aliases.
- `accounting_settlement.ts`: the first domain adapter. It uses the existing
  `prepareCashSettlementWrite` plan for all six original domain effects. It adds
  exact-unit evidence and validates the existing numeric bridge against BigInt
  results. It does not introduce another cash ledger or balance writer.

Public commands never accept debit/credit lines or account selections. The
shared journal contract supports 2–256 lines; a synthetic three-line revenue/tax
intent and the full line capacity are tested independently. Settlement produces
Dr company cash / Cr representative-held cash; no revenue/expense/tax is invented
for the transfer. Other business adapters remain Phase 2E/3 work.

## Integration and default-off boundary

The existing `recordCashSettlement` callable selects the foundation adapter only
when `FATOORA_ACCOUNTING_ENGINE_EMULATOR=true`. Both the public selection and
internal posting/recovery functions still require explicit per-call opt-in and
the resolved SDK project **demo-fatoora-phase2d**, default database, loopback
transport with TLS off, and exact emulator host/port. Setting a flag or changing
the environment after constructing a remote client cannot bypass this boundary.
The actual transaction's SDK client is independently checked too.

The default callable retains its existing numeric request/response contract and
single posting implementation. There is no extra posting callable/root export
and no UI activation. The existing cash/ledger/settings screens remain usable
under their current contracts. The exact posting API is an isolated foundation
contract for later workflow/UI integration, not an activated production feature.

A new synthetic foundation call supplies:

| Field | Meaning |
|---|---|
| `companyId`, `bookId` | Explicit target; no company fallback |
| `operationId` | Stable business action, independent of request retries; source ID is `settlement_{operationId}` |
| `idempotencyKey` | Actor-scoped durable request identity |
| `expectedConfigurationDigest` | Pinned Phase 2C configuration hash |
| `salesRepId` | Actual cash custodian, validated against the current company profile |
| `amount` | Positive decimal string with at most three fractional digits |
| `settlementDate` | Explicit `{seconds, nanoseconds}` at exact microsecond precision |
| `notes` | Bounded optional source explanation |

## Book/configuration evidence

Posting requires an inactive, locked `reconstruction` book with the explicit
synthetic-engine gate, while `journalPostingEnabled` stays false. The book's
configuration digest, revision links, currency/scales and local timezone must
match immutable Phase 2C revision/policy/mapping documents. The draft must have
documented required settings/evidence. An active journal definition must authorize
the source/action/control types. Actual account projections must match the
configured posting-account snapshots. Group/inactive/foreign/mixed-currency
accounts reject.

The configured opening date is a lower business-date boundary. Exactly one open
configured period must cover the Asia/Amman date. Posting reads the period and
authority inside its transaction, so changes conflict with a concurrent post.
Configuration editing stays blocked by the reconstruction/locked book contract;
account/period `used` markers are initialized once rather than written on every
subsequent posting.

No command in 2D approves real policy, creates an opening or activates a book.
Acceptance fixtures explicitly construct **synthetic-only** treasury openings
after saving a Phase 2C draft. These are not historical financial acceptance.
Unreviewed draft policy is never relabelled as approved. Production promotion,
approval lifecycle and complete opening reconciliation remain future gates.

## Atomic posting and recovery

Economic identity is company/book/source-system/type/stable-source/action. The
semantic digest includes trusted source revision, dates, exact input and pinned
configuration; it excludes request identity and the current retrying actor.
Request identity is separately scoped to the authenticated actor and book.
Two genuine identical transactions with different source IDs remain distinct.

All reads finish before the existing source/cash writer and shared engine writes
are applied in one Firestore transaction. The transaction creates the immutable
source, two cash legs, compatibility ledger row, canonical journal, event,
source key, original request result, audit and outbox, while updating the two
treasury positions and one posting lane. The event contains the complete exact
domain-effect manifest and account/definition/configuration snapshots/links.
The compatibility row is a linked reporting projection; it does not cause a
second financial posting.

The first post seals currency/scales/timezone/lane count once. Each subsequent
event verifies the selected lane's previous immutable event, sequence, hash and
SDK commit metadata. A missing seal cannot initialize a fresh lane after history
already exists. There is no global per-post book counter.

Matching request/action retries return the original result after current
authorization. Another request key for the same action creates only an immutable
alias receipt; it cannot move cash again. Changed economic intent or request-key
reuse for another action conflicts. The original receipt stays linked to its
original actor; a different current administrator can recover it without
reactivating the original actor.

Recovery verifies immutable journal/event/source/request/audit/outbox records,
the original configuration and monetary seal, content digests and atomic SDK
creation times. All immutable domain effects must still match their manifest.
It does not rerun present-day account activity, cash eligibility, representative
status or period-open checks for an already committed action. Missing/changed
evidence fails closed. Recovery with no committed source never posts anything.

The command's first callback result is staged only. A separate authorized
recovery observes the committed artifacts before success is returned, including
the SDK-observed commit timestamp. Neither business time nor server-recorded
time is substituted for the commit observation.

## Exact treasury bridge and limits

Current settlement sources still have legacy numeric fields. The adapter uses
canonical unit strings for journals, new cash evidence and all new arithmetic;
it proves each numeric input/output equals those exact units before committing.
The compatibility bridge remains limited to three decimals and the existing
checked numeric conversion range. The shared journal itself supports the full
30-digit exact-unit range. Larger real settlement values need completion of the
treasury migration in 2E rather than a weakened conversion check.

Existing positions must already have currency/scale, exact amount, actual holder,
account sequence and an immutable atomic head linked to this book's synthetic
opening or canonical posting event. Missing history never becomes zero. Cash
before/after equations and combined company-owned cash conservation are checked.
A later legacy writer that leaves exact evidence stale blocks the next foundation
posting; integration of every treasury caller belongs to 2E/3.

Guards enforce 600 document reads, 400 writes, 512 KiB serialized documents,
4 MiB serialized write data, bounded evidence depth/node counts and declared
company/book paths. Queries, cross-book references, undeclared business writes,
deletes and cached reads after writes reject. These are application budgets,
not a cloud throughput proof or an exact accounting of index/network billing.
The local index manifest exempts embedded journal/effect/semantic evidence.

## Verification and remaining work

Local suites cover journal balancing/precision/control dimensions, full line
capacity, source/request identities, actor changes, Amman midnight, concurrent
submissions/outflows, SDK retries, lost acknowledgement, interruption/atomicity,
corrupted/missing evidence, period/configuration locks, exact cash heads, resolved
transport isolation, scope/budget enforcement and existing callable selection.
Client Rules denial coverage includes every new authority/evidence collection.

Verification results:

- **158 foundation tests passed** against an independently exported staged
  backend, including the 68 Phase 2C cases. Its standalone TypeScript build passed
  with only the dependencies included in the proposed commit.
- **228 existing financial-ledger, trusted-transaction, settlement preflight and
  settlement persistence regressions passed** in the working tree.
- The extended **client Rules denial test passed** for reads/lists/writes/deletes.
- **28 Flutter settings/auth/retry tests passed**, both in the working tree and
  against independently exported staged UI sources with installed dependencies.

The staged snapshot excludes unrelated uncommitted settlement-transport,
platform/deployment and other working-tree changes. Evidence logs stay local in
`output/phase2d/`; synthetic acceptance does not certify live financial history.

Run backend transaction tests only with the dedicated loopback emulator selected:

```text
npm --prefix functions run test:accounting-posting
npm --prefix functions run test:accounting-configuration
```

Phase 2E is next: shared customer open-item/allocation, treasury and quantity-only
inventory controls. Phase 2F supplies domain-aware corrections and period
close/reopen commands. Phase 2G supplies report/reconciliation acceptance. There
is no general manual control-account journal, generic reversal, importer,
valuation/COGS or production activation in this implementation.
