# Phase 2B-13 — Settlement performance and read-cost optimization

Local verification date: 2026-11-10. Only isolated Firebase emulators and synthetic
data were used. No cloud project access, deployment, financial correction,
allocation persistence, backfill or accounting activation occurred. The existing
hard demo-project, loopback, debug and default-off transport gates remain intact.

## Actual bottleneck

Phase 2B-12 already built and cached the financial breakdown once. It did **not**
rerun reconciliation on every page. Its expensive repeated work was the complete
current-version inventory required before each 64-row response: approximately
6,000 source documents, read through 52 sequential metadata queries, repeated for
47 detail deliveries and PDF authorization. Cached pages alone could not remove
these checks without weakening evidence invalidation.

The pinned original compiled transport was measured against the exact same
company/document IDs and SDK versions later used for the optimized runs. The
baseline hash is in `output/phase2b13/baseline.json`. The original 3,000-movement
path completed in 133.9–137.9 seconds, with 295,767 document read results and 2,548
ordinary query RPCs per complete report and PDF permission. This reproduces the
earlier approximately 147-second observation without treating that older run as
the current comparison baseline.

Internal, opt-in asynchronous profiling now separates source scans,
reconciliation, recovery when applicable, evidence hashing, page construction,
cache serialization, delivery decoding, database authority and Auth-provider
time. The test RPC wrapper independently counts transactions, point/batch reads,
ordinary/aggregate queries, returned data sizes, response JSON bytes and CPU time.
No timing, SDK witness, quota data or profiling endpoint was added to the wire.
Nested stage times and concurrent RPC durations must not be added as if they were
disjoint wall time.

## Focused implementation

1. **Bounded version inventory.** Each collection's verified original cardinality
   is known. A current query limited to that cardinality **plus one sentinel**
   proves whether membership is unchanged. Its returned count must match exactly,
   every document ID/create/update version must match the original witness, and
   all reads must share the fresh transaction's anchor read time. All six
   metadata-only queries execute concurrently in that one transaction. Missing
   supplemental witnesses are checked as absences; they are not counted as
   existing collection documents. Empty collections, insertions after the last
   ID, deletions, replacements and restored-value rewrites fail closed.
2. **Bounded delivery batches.** The same callable accepts transport version 2 and
   delivers up to six **existing version-1 detail pages**, with a maximum entire
   response of 1 MiB. Version 1 remains supported. No new business endpoint,
   financial DTO or ledger exists. Each batch has strict boundaries, count,
   continuation and digest; each inner page retains its original checksum and
   pinned financial/snapshot roots. HMAC tokens also bind the delivery version.
   Middle-of-batch, mixed-version and out-of-order continuations reject; the last
   complete batch can be retried deterministically after a lost acknowledgment.
3. **Immutable compact cache.** Sessions retain immutable serialized page strings
   and their digests, not the full financial object graph. Only pages actually
   being delivered are decoded. Exact JSON size admission uses measured page
   bytes and serialized envelope bytes, including UTF-8 labels, tokens, brackets
   and commas. It does not decode the whole history again just to size responses.
   The session's version-inventory index is reused for subsequent coverage checks.
4. **Initial work.** The source reader uses its already supported maximum
   256-document inventory page size; detail pages remain 64 rows. A shared pure
   page factory indexes the immutable report once. One redundant intermediate
   authority pass is removed from complete starts; initial authorization, the
   adapter's current-authority check, witness-bound authority and final authority
   and Auth revocation checks remain. Incomplete starts still recheck authority
   before returning their nonfinancial notice.
5. **Existing Flutter flow.** An optional batch-source interface feeds the existing
   GetX controller. A batch is added atomically using the existing exact page and
   cash-chain validator; a late failure rolls back the entire batch. No unconsumed
   prefetch cache is introduced. The panel shows the first newly delivered page
   and retains existing page selection, actions and navigation. PDF creation and
   its fresh authorization-after-render check are unchanged. Fixtures never
   become authenticated accounting authority.

All financial reconstruction, source identities, source-document references,
account ordering, decimal units, currencies, opening/carry proof and verified/
blocked states remain governed by the existing recovery and breakdown modules.
Unknown openings remain unknown. Completed settlements are not modified, and no
invoice-funding allocation is inferred from cash history.

## Snapshot, authorization and resource guarantees

Pages always come from the original verified report. Fresh transactions do not
pretend to share its historical read snapshot: they prove current membership and
version equivalence before serving frozen evidence. A changed source, head,
configuration, relevant profile or durable recovery witness invalidates the
session. Conservative company-wide invalidation, including unrelated/post-cutoff
source changes, is retained.

Every request still checks current Auth existence/disabled status/token revocation
and current approved administrator/company/representative/posted-settlement
ownership before and after sensitive work. Authorization is never cached as
authority. A batch is one authorized delivery, containing already delivered
logical pages, rather than future pages silently retrieved from a client cache.
Known invalidation clears client rows/totals; a PDF always requires a new server
check. Already downloaded or printed data cannot be revoked retroactively.

The five-minute absolute token/session lifetime, 15-second maximum PDF permit,
MAC verification, random process key, cold-loss rejection, request/start quotas,
two-work concurrency limit, four-session limit, 24 MiB/session and 64 MiB total
serialized cache bounds, 16,000-source-document ceiling, one-million charged
read-work units/session and 500,000/minute/process limits remain unchanged. Work
for all parallel queries is reserved before RPCs are issued. Failed parallel
queries are drained before the concurrency slot is released. Oversized evidence
or exhausted limits fail closed rather than certifying a prefix.

Serialized bounds are not a claim that JavaScript heap usage equals JSON size.
The large-history core also passed with a 256 MiB V8 old-space limit. Real function
memory/cold-start behavior still needs acceptance with multiple concurrent users;
the SDK and a simulated client share the benchmark process.

## Before/after measurements

Mixed fixtures include invoice collections, receipts, a cash refund, an approved
expense, opening/carry balances, a previous partial settlement and current
transfer. Seed time is excluded. Complete-run times include all detail deliveries,
full exact assembly verification and fresh PDF permission, but exclude generating
PDF bytes. Bulk timing uses real Firestore emulator reads and an injected Auth-user
provider; real Auth/Functions protocol is checked separately in regressions.

| Invoice movements + mixed evidence | Logical pages | Before | After, median / sampled p95 | After deliveries | Document read results | Ordinary query RPCs |
| --- | ---: | --- | --- | ---: | ---: | ---: |
| 3,000 | 47 | 134.411 s median; 137.871 s sampled p95 | 12.866 / 13.379 s | 8 | 295,767 → 60,349 | 2,548 → 82 |
| 4,000 | 63 | Expired before completion | 19.364 / 19.503 s | 11 | 104,454 | 108 |
| 6,000 | 94 | Rejected by original session read-work admission bound | 16.440 / 16.509 s | 16 | 216,629 | 154 |

For 3,000 movements this is approximately **10.4× faster**, **79.6% fewer document
read results** and **96.8% fewer ordinary query RPCs**. There are still six
aggregate queries during initial verification. The old 4,000-movement experiment
recorded expiry after 313.1 seconds and 38 successful deliveries; it did not
deliver a complete certifiable report. Its failing benchmark assertion initially
expected only the old admission failure, and the harness now classifies an
observed baseline expiry separately. No optimized security regression is waived
by that baseline-only classification. Failed-baseline read counts are incomplete;
charged admission units are recorded instead of pretending to know its bill.

| Delivery latency | Before 3,000 | After 3,000 | After 4,000 | After 6,000 |
| --- | ---: | ---: | ---: | ---: |
| First response, median / sampled p95 | 8.437 / 9.652 s | 7.153 / 7.576 s | 9.566 / 9.639 s | 7.486 / 7.606 s |
| Subsequent response, p50 / p95 | 2.618 / 3.082 s | 0.649 / 0.693 s | 0.807 / 0.873 s | 0.522 / 0.578 s |
| Subsequent response samples | 138 | 21 | 30 | 45 |
| PDF permission, median | 2.558 s | 0.639 s | 0.800 s | 0.486 s |

An after response can contain several logical pages. First-response payload is
therefore larger: the maximum measured response is approximately 914 KB, still
below the unchanged 1 MiB cap. Total exact JSON response bytes for 3,000 movements
are essentially unchanged: 7,141,771 before and 7,144,378 after. The optimization
saves verification work, not source detail. First mobile delivery on a slow link
must be assessed separately.

The single-page control using optimized queries completed a 3,000-movement report
in 18.829 seconds but still returned 295,714 document read results. Thus query
concurrency removes latency while batching provides the material read savings.
That control is one observation, not a population latency percentile.

The optimized 3,000-movement median initial stages were approximately 4.263 s for
source scans, 0.710 s for exact reconciliation, 0.495 s for evidence hashing,
0.517 s for page construction, 0.042 s for cache serialization, 0.011 s for first
batch decoding, 0.089 s across database authority passes and 0.600 s for current
version validation. Auth-provider timing in these bulk runs is an injected local
provider, not a cloud Auth cost. No subsequent delivery reran reconciliation.
Auth-provider calls per complete 3,000-movement report fell from 146 to 28.
Measured outer response JSON serialization totaled approximately 46 ms before
and 41 ms after (medians); this was not the original bottleneck. SDK-data JSON
measurement overhead is recorded separately and is included in these profiled
wall times.

Each main case has three fresh-session runs on an already running emulator/SDK.
Startup samples are small and descriptive; percentiles use nearest rank. Java/V8
warmup, GC and host state are visible: the later 6,000 case was faster than some
earlier 4,000 runs. These are not cloud capacity, monotonic scaling or cold-start
SLA claims. Cold session/key loss, warm-page retry and expiry were tested as
separate correctness cases. Raw observations and stage distributions are in
`output/phase2b13/*-performance.json` and `summary.json`.

## Billing exposure and remaining limits

The emulator does not produce a Firestore bill. The separately reported model
counts document read results, empty-query minimums and initial aggregate batches.
For a complete 3,000-movement view plus PDF permission, that model is **295,779 →
60,361 read-operation units**; after values for 4,000 and 6,000 are 104,468 and
216,647 respectively. The transport's more conservative admission charges are a
different resource-control quantity, not billing data. Per 1,000 complete 3,000-
movement views, the modeled exposure is approximately 295.8 million versus 60.4
million read units, before retries, platform/Auth operations and network costs.

Field projection saves transferred fields but does not make each document a
fractional read. Aggregate pricing has per-1,000-index-entry batches and minimums;
see [Firestore billing](https://firebase.google.com/docs/firestore/pricing) and
[aggregation documentation](https://firebase.google.com/docs/firestore/query-data/aggregation-queries).
No dollar amount is asserted without the approved database region, pricing,
actual query/billing measurements and workload. SDK retry behavior, cold rerouting,
failed/abusive requests, egress and Functions duration can increase actual cost.

There is still a complete metadata scan per **delivery batch** and export. Under
the current data model, deleting or rewriting an arbitrary old document cannot be
detected by checking only balance heads, mutable business timestamps, aggregate
counts or an asynchronous listener. Constant-read invalidation would require a
separately reviewed, trusted atomic revision/invalidation contract covering every
writer and deletion. None was invented in this phase. No extra financial or
control-record writes were introduced to obtain these gains.

Company-wide changes can still force restart. Process-local cache/key/quota loss
still requires restart; no distributed session service is added. The 16,000-
document ceiling does not promise every possible history fits byte/time/read
limits. That ceiling covers all six company-wide source collections, not just the
selected representative. A larger company inventory remains explicitly incomplete
even when the selected representative's history is small. Historical missing openings, incomplete source links, source mutations
and currency conflicts remain explicit blockers. Large-history device PDF
rendering/printing is not certified by transport delivery timings.

## Verification and reproduction

| Verification | Result |
| --- | --- |
| Affected backend recovery/source/transport/security/posting suites | 786 passed; zero failures or skips |
| New batch suite within that total | 27 passed |
| Main optimized performance cases | Three datasets; three fresh sessions each; complete exact assembly/PDF permission verified |
| Memory control | 6,000 movements completed with 256 MiB V8 old-space limit; observed heap approximately 95 MB and RSS 249 MB |
| Complete Flutter suite | 680 passed; zero failures or skips; large captures and real emulator HTTP bridge enabled |
| Explicit enabled client gates | 2 passed |
| TypeScript build / lint | `tsc` / `tsc --noEmit` passed |
| Flutter analysis | No issues |
| Android compilation | Isolated debug APK built; test package, absent native Firebase auto-init and absent Google app ID verified; not installed |
| Existing Arabic/English PDF regression output | Four documents / 42 pages; exact amounts, references, bounds and glyph checks passed |
| Responsive presentation | Arabic/English, 320 px with 2× text, 768 px, 1,366 px; no overflow; first delivered page selected |

Cold-loss/expiry, warm retry, simultaneous requests, global concurrency admission,
malformed replay floods, corrupt tokens, mixed delivery versions, middle-group
tokens, missing/duplicate/modified pages, UTF-8 byte-limited groups, role/Auth
revocation, same-count replacements, restored-value rewrites, current balance/
configuration changes and missing atomic witnesses were exercised. Parallel query
failure drainage was verified. Existing transaction accounting, company-versus-
representative holders, refunds, receipts, expenses, cancellation, historical
openings and currency regressions remained included. The separate real-Auth case
passed again after restarting the isolated emulators; it is already part of the
786-case count, not an additional distinct test.

Five Dart runs on each identical large capture measured JSON decoding, versioned
source validation and atomic exact assembly: 3,000 movements took 1.267 s median /
1.581 s sampled p95; 6,000 took 3.214 / 3.292 s. JSON decoding alone took 0.144 s
and 0.351 s medians respectively. Subsequent batch processing p95 was 244 ms
(35 samples) and 254 ms (75 samples). These are debug host CPU measurements with
injected token-free synthetic wire envelopes, excluding network, native Firebase
SDK/Auth refresh, layout and PDF rendering. Such synchronous validation can pause
frames; native-device responsiveness remains an explicit acceptance item, not a
claimed frame-rate guarantee. The actual Dart HTTP bridge separately assembled
both transport versions and obtained fresh PDF permissions through local
Auth/Functions. An independent actual Auth-emulator protocol run delivered two
version-1 pages and PDF permission in 1.698 s, excluding sign-in/setup.

Visual review checked the captured Arabic tablet/mobile and English desktop
panels. Evidence is in `output/phase2b13/widgets/`; the existing PDF artifacts were
checked without changing their layout. Logs are under `output/phase2b13-*.log`,
raw/summary measurements and a machine-readable manifest under
`output/phase2b13/`. Pre-phase synthetic output and immutable fixture files were
restored byte-for-byte after tests; fresh protocol captures remain in ignored
test-build storage. No staging or production environment was used.

The emulator setup from Phase 2B-12 is reused: Java 21,
`node functions/test/helpers/prepare_settlement_transport_emulator.js`, then
`firebase emulators:start --only auth,firestore,functions --project demo-fatoora-phase2b7 --config build/phase2b12-emulators.json`,
with server flag `FATOORA_SETTLEMENT_READ_TRANSPORT=phase2b12-emulator-only`.
Only the read callable is loaded, not unrelated write triggers.

Tests use `FIRESTORE_EMULATOR_HOST=127.0.0.1:8192` and
`FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9098`. Use
`npm --prefix functions run test:settlement-transport`. Performance is explicit:
set `SETTLEMENT_PROFILE_MODE=optimized`, optionally
`SETTLEMENT_PROFILE_COUNTS=3000,4000,6000` and `SETTLEMENT_PROFILE_REPEATS=3`, then
`npm --prefix functions run test:settlement-performance`. Baseline mode requires
the pinned original Phase 2B-12 compiled module; it must never substitute the new
implementation and label it baseline. The local ignored copy/hash is retained.
Fixtures are seeded once and reused by ID across measurements without changes.
On a fresh/restarted emulator, remove only the ignored
`build/phase2b13-fixtures.json` ID manifest before starting a **new** comparison;
its old IDs refer to the previous in-memory emulator. Generate both comparison
modes against that new seed, rather than silently mixing fixture generations.
The IDs used for the reported measurements are preserved in
`output/phase2b13/fixture-manifest.json`.

The bounded-memory run uses `node --max-old-space-size=256 --test` with the same
performance test, `SETTLEMENT_PROFILE_MODE=bounded-memory`, count 6,000 and one
repeat. Summaries are regenerated by
`python test/support/summarize_settlement_transport_profile.py`. Dart profile
captures are synthetic and token-free under ignored `build/phase2b13-captures`;
`SETTLEMENT_PROFILE_CAPTURE_DIR` explicitly enables their client profiling test.
No fixture is bundled into production bindings.

## Exact gates before staging

The next batch is separately approved **read-path security/staging acceptance**,
not posting or allocation activation. All Phase 2B-12 gates still apply:

1. Obtain explicit owner authorization for staging access/deployment, and review a
   narrowly pinned staging extension of server, Auth audience/issuer, SDK,
   native-package and presentation-provenance gates. Retain default-off rollout
   and rollback; setting the existing emulator flag must not enable cloud access.
2. Review current administrator/company/representative/settlement scope, real JWT
   verification, revocation, final PDF delivery, TLS, App Check policy and least-
   privilege read-only service-account/IAM behavior in the approved target.
3. Accept process-local cache/routing/cold-loss and quota behavior, or separately
   approve a nonfinancial shared session/quota design. Test rollback and version-
   mixed clients. Do not add financial writes for session management.
4. Measure actual cloud reads/query plans/retries, Auth calls, egress, cold/warm
   p50/p95, memory at concurrency two and realistic multi-admin load. Set approved
   workload/cost limits. Verify source changes during delivery still invalidate
   all later batches; do not trade evidence integrity for fewer reads.
5. Exercise native Firebase SDK auth restoration/refresh and revocation between
   batches on representative devices, current card/navigation/actions, slow-link
   first delivery, Arabic/English large-text layout, and realistic-volume PDF
   rendering/printing. Verify unknown historical evidence remains blocked.
6. Record affected posting/security/UI regressions, security acceptance and
   operational rollback evidence. Preserve completed-settlement immutability,
   existing financial workflows and the disabled accounting lane. Allocation
   policy/persistence, historical backfill and production activation remain
   separate approvals.

No staging gate requiring staging access was executed here.
