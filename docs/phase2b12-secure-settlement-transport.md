# Phase 2B-12 — Secure settlement breakdown transport

Completed locally on 2026-11-09 using isolated Auth, Firestore and Functions
emulators and synthetic records only. The transport and application binding remain
disabled outside explicit debug emulator testing. Nothing was deployed. This phase
adds no financial writes, posting changes, allocation persistence, migrations or
double-entry activation.

## Transport and authority

The existing trusted callable client already restores Firebase Authentication,
refreshes the ID token, uses the established Functions region and translates
callable responses. Existing cash reads are client Firestore projections; existing
trusted settlement callables perform business operations. Neither is a compatible
route for an administrator-only, verified, multi-page breakdown. One new callable,
`getSettlementBreakdown`, therefore provides three strict version-1 operations:
`start` with company/representative/settlement IDs, `page` with an opaque token,
and `authorizePdf` with the final export token. Financial inputs and extra fields
are rejected. No parallel ledger, new screen or business-operation endpoint was added.

`functions/src/trusted/settlement_transport.ts` reuses Phase 2B-8/9/10 recovery,
source inventory, exact reconciliation and detail-page construction. Its only
adapter extension is an internal SDK document-version witness collected from
reads already performed. The economic digest and existing page schema remain
unchanged. Internal witness and quota diagnostics never enter the response.

Each operation checks current Firebase Auth user existence, disabled status and
refresh-token revocation against `auth_time`; then the trusted current user
profile must be active, approved and an administrator in the requested company.
Company identity/active state, representative company/role/identity and posted
settlement company/representative/identity must match. Client roles, balances and
account mappings are never authority. Authorization is checked before work and
again after evidence validation; Auth is checked immediately before returning
sensitive results. Firebase revocation uses its normal seconds-based timestamp
semantics. Recorded actors are provenance, not proof of historical authorization
or physical handover.

The callable additionally requires the explicit server test flag, Functions
emulator marker, loopback Auth emulator, exact demo token audience/issuer and the
existing resolved Firestore guard: default database, exact
`demo-fatoora-phase2b7` project and matching loopback, SSL-off SDK settings. Each
read-only transaction independently verifies its underlying SDK client before
reading. Default production/staging configuration cannot enable this transport.

## Snapshot and token guarantees

The initial verified financial report is read in one SDK read-only transaction.
All detail pages are frozen from that report and retained in bounded process RAM.
Subsequent transactions do **not** claim to reuse that historical snapshot.
Instead, each delivery checks complete source membership and exact SDK
create/update versions against the original witness, inside a fresh read-only
transaction whose reads must share one read time. This includes metadata-only,
document-ID-ordered pages across cash movements, invoices, receipts, returns,
expenses and settlements, plus the original configuration, balances, profiles and
recovery evidence. Insertions, deletions, changed-and-restored values, new heads
and changed permissions invalidate the session. Current financial data is never
substituted into old pages. Even unrelated or post-cutoff company source changes
conservatively require a restart.

HMAC-SHA256 tokens bind the requesting UID and authentication time, company,
representative, settlement, schema, original report/snapshot roots, version-witness
digest, random session ID, page/purpose and absolute five-minute expiry. A random
process key and nonce provide integrity; constant-time signature comparison and
canonical signature encoding reject tampering. Tokens are not encrypted or
authorization substitutes. Every delivery still rechecks authority and evidence.
Only the next page and the most recent page retry are accepted. Concurrent or
out-of-order/forked requests fail; a lost acknowledgment can safely retry the same
input token. A new session supersedes that user's old session. Cold starts,
instance rerouting or cache loss reject tokens and require an explicit restart;
they never rebuild a different report under an existing token.

The versioned wire envelope preserves existing exact decimal-unit strings,
source IDs/numbers/paths, timestamps and actor evidence. Incomplete coverage has a
distinct response with no totals or export token. Complete coverage with unknown
historical openings can expose clearly blocked observed evidence, with totals
withheld. Cash reconstruction remains separate from source allocation. No FIFO,
invoice funding attribution or historical zero-opening assumption is introduced.

## Bounds and practical cost

| Boundary | Limit |
| --- | ---: |
| Original inventory / financial attempts | 16,000 source documents / 1 attempt |
| Detail / metadata query pages | 64 rows / 128 document versions |
| Session lifetime / final PDF permit | 5 minutes / at most 15 seconds |
| Retained sessions / concurrent work | 4 / 2 |
| Serialized retained cache / one session | 64 MiB / 24 MiB |
| Entire response / token | 1 MiB / 4,096 characters |
| Requests per UID / starts per UID | 64/minute / 2/minute |
| Process requests / quota subjects | 128/minute / 256 |
| Session requests / charged read work | 512 / 1,000,000 units |
| Process charged read work | 500,000 units/minute |

Whole response envelopes, including labels/tokens, are size-checked before any
page is delivered. Admission accounting reserves the initial maximum scan and
charges metadata queries before their RPC, including failed work. Excess evidence,
large immutable identities or over-budget sessions fail closed; no truncated
totals are certified. Retained byte limits measure serialized evidence, not exact
JavaScript heap usage. Function settings constrain one instance, concurrency two,
512 MiB and 60 seconds per request; they were not deployed.

Measured on this Windows host with real Firestore emulator reads and synthetic
mixed invoices, receipts, refunds, expenses and settlements:

| Invoice movements, plus workflow evidence | Pages | First page | Remaining pages + PDF permission | Retained bytes | Charged read units |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 16 | 2.205 s | 12.636 s | 2,841,623 | 59,917 |
| 3,000 | 47 | 7.633 s | 139.804 s | 8,472,709 | 336,474 |

Bulk measurements use an injected Auth-user provider; they include real
Firestore reconciliation/version scans, but exclude real Auth provider network
latency, native SDK refreshes and PDF rendering. A separate actual Auth-emulator
ID-token → Functions callable → Firestore run delivered two pages and a fresh PDF
permit in 1.754 seconds, with 175,618 page-response bytes, excluding sign-in/setup.
These are emulator observations, not cloud latency, billing or capacity promises.
Conservative charged admission units differ from billable reads and aggregate
index work. See `output/phase2b12-performance.json` and
`output/phase2b12-callable-performance.json`.

Revalidation is deliberately O(company history) per delivered page and export.
That yields roughly quadratic work over a complete large history. Company-wide
invalidation also needs a quiet window; busy companies can force repeated
restarts. The tested 3,000-movement sequence fit the five-minute session on this
host. The 16,000-document inventory ceiling is not a promise that every such
history fits response, session or time budgets. Process-local quotas do not
provide distributed abuse protection. These limitations require explicit review
before staging; relaxing verification or silently omitting data is not a remedy.

## Existing Flutter interface and PDF

The financial repository now constructs a typed authenticated source through the
existing trusted callable client only after centralized emulator routing succeeds.
The marker binds the default Firebase app and exact demo project; the repository
rechecks its gate on every request. `FATOORA_SETTLEMENT_TRANSPORT_TEST=true` also
requires `FATOORA_ENV=test`, debug mode and a permitted local host. Ordinary GetX
bindings continue to provide no fixtures. Injection remains available for tests;
fixture reports cannot be used as authenticated reports or PDF permits.

The existing settlement panel, card/details integration, formatter and PDF service
consume the shared source interface. Strict response validation pins scope,
roots, labels, expiry and page sequence, checks exact units and clears displayed
rows/totals after fatal permission, integrity or expiry failures. Loading,
incomplete/blocked, retry and explicit restart states are preserved. An explicit
load-all control fetches sequential bounded pages; it stops on failure. UI display
still renders one detail page at a time. No new route or business action exists.

PDF generation uses the same completely assembled validated report. After
rendering, a fresh server authorization/version check is required immediately
before bytes are handed to the existing print/share service. Expiry during
rendering or revocation blocks delivery. Already delivered, printed or downloaded
data cannot be revoked retroactively; checks establish authority at their final
validation point, not an impossible lock on subsequent business activity.

Arabic document numbers use Arabic shaping while exact numeric units, IDs and
UTC times retain readable direction. Existing styling and financial calculations
remain intact. All test output explicitly says authenticated **emulator** evidence
and synthetic data; it makes no financial-certification or allocation claim.

Android test builds use `com.fujika.fatoora.settlementtest`, a distinct test label,
no native Google-services configuration, removed Firebase/FCM initialization
providers and disabled FCM auto-init. Test release/profile/staging tasks reject
before signing. A normal debug build still uses the existing package/configuration.
The final test APK was built and inspected, not installed or run against cloud
services. See `output/phase2b12/native-test-isolation.json`.

## Verification evidence

| Check | Result |
| --- | --- |
| New backend transport suite | 27/27 passed, no skips |
| Existing backend regressions | 1,087 unique cases passed across correct isolated emulator contexts |
| Complete Flutter suite | 664/664 passed, no skips; real emulator HTTP bridge enabled |
| Explicit enabled client-gate suite | 2/2 passed |
| Backend build / lint | `tsc` / `tsc --noEmit` passed |
| Flutter analysis | No issues |
| Android | Final isolated debug APK built; normal debug built; test release rejected as expected |
| PDF exact-content audit | All four verified/blocked Arabic/English PDFs passed |
| PDF render/bounds/font audit | Four PDFs, 42 pages, zero violations |
| Long-name/document PDF stress | Two PDFs, 42 pages, zero violations |
| Responsive presentation | Arabic/English at 320 px with 2× text, 768 px and 1,366 px; no widget overflow |

The initial combined existing-backend run passed 1,085/1,087; two bootstrap Auth
tests used the legacy `demo-fatoora-test` namespace while that run's Auth emulator
was started for the settlement demo project. The entire 18-case bootstrap suite
then passed on separate fresh legacy-project emulators with synthetic-only input.
Thus 1,069 other cases plus all 18 bootstrap cases were verified, with no unresolved
failure. The new real-Auth case was strengthened and rerun to include actual
`revokeRefreshTokens`, not just injected token-validity dates.

Coverage includes scope/enumeration failures, disabled/deleted/revoked users,
approval/company changes before delivery, real ID tokens and issuer/audience
rejection, token corruption/canonical encoding/expiry/replay/concurrency, all source
mutation classes, exact historical gaps, 1,000/3,000 movements, 16,001 draft-source
bound rejection, oversized multibyte identities, lost acknowledgments and unchanged
financial records. Existing posting, source/recovery/reconciliation, permissions,
refund/expense/receipt/cancellation and currency regressions were included.

Immutable captures from actual local callable responses back the presentation/PDF
fixtures. The actual Dart HTTP bridge verifies live local Auth/Functions protocol;
widget/PDF tests inject those captured responses. This does not certify native
Firebase SDK device end-to-end behavior, a physical printer, or 3,000-row PDF device
latency. Visual review covered all four final PDF contact sheets, detailed Arabic
tables/blocked cover/actor registry, long Arabic document numbers and responsive
screens. Evidence is under `output/phase2b12/`, PDFs under `output/pdf/phase2b12/`,
and test logs under `output/phase2b12-*.log`.

## Reproduce locally

Use Java 21, installed dependencies and explicit loopback ports. In the workspace:

```powershell
npm.cmd --prefix functions run build
node functions/test/helpers/prepare_settlement_transport_emulator.js
$env:FATOORA_SETTLEMENT_READ_TRANSPORT='phase2b12-emulator-only'
firebase.cmd emulators:start --only auth,firestore,functions --project demo-fatoora-phase2b7 --config build/phase2b12-emulators.json
```

In another shell, set `FIRESTORE_EMULATOR_HOST=127.0.0.1:8192` and
`FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9098`, then run
`npm.cmd --prefix functions run test:settlement-transport`. The prepared shim loads
only this read callable, avoiding unrelated write-trigger execution. Restarting
the shim invalidates sessions. Run the legacy bootstrap suite separately against
Auth/Firestore started with `--project demo-fatoora-test`, using
`FATOORA_SYNTHETIC_TESTS_ONLY=1`; never import a production export.

After the backend captures exist, set `SETTLEMENT_EMULATOR_INTEGRATION=1` for
`flutter.bat test --no-pub --concurrency=4`. Use
`SETTLEMENT_AUTH_PDF_DIR=output/pdf/phase2b12` and
`SETTLEMENT_TRANSPORT_WIDGET_DIR=output/phase2b12/widgets` when deliberately
regenerating presentation evidence. Enabled-gate tests and an isolated APK require
`--dart-define=FATOORA_ENV=test --dart-define=FATOORA_SETTLEMENT_TRANSPORT_TEST=true`.
They are not deployment commands. PDF audit tools are
`test/support/check_pdf_rendering.py` and
`test/support/check_settlement_pdf_evidence.py --transport` (PyMuPDF required).

## Remaining risks and exact staging gates

Historical opening gaps, incomplete movement coverage, mutable/missing source
references and currency conflicts remain explicit blocked states. This read
transport cannot fix those records or prove invoice funding allocations.

The smallest next batch is **security and staging acceptance of this read path**,
including native SDK/device UI and PDF testing with synthetic staging data. It
requires all of the following before any staging deployment:

1. Separate owner authorization for staging access/deployment and an explicitly
   reviewed extension of hard demo-only server, SDK and native build guards. A
   flag alone must not bypass those guards. Retain a default-off rollback switch.
2. Security review of real Auth JWT verification, current profile/company scope,
   revocation/final delivery, TLS, callable/App Check policy, IAM/service account,
   response provenance and uniform errors; exercise them in the approved target.
3. Decide and accept process-local sessions, one-instance routing/cold-loss
   behavior and abuse controls, or separately approve a shared nonfinancial cache
   and distributed quotas. No financial records may be written for sessions.
4. Approve read budgets, latency, memory and conservative invalidation under
   realistic concurrent business activity. Optimize only with reviewed evidence
   coverage guarantees; do not weaken snapshot validation to reduce costs.
5. Validate native SDK auth restoration/refresh, revocation between pages,
   existing pair-card visibility, pagination/restart and Arabic/English PDF
   delivery on representative devices; measure realistic PDF size/time and
   printing. Confirm legacy documents remain blocked rather than miscertified.
6. Rerun affected security/posting/UI regressions and record acceptance and
   rollback evidence. Preserve current posting, journal-off state and immutable
   completed settlements. Allocation policy/persistence, backfill and production
   activation remain separate approvals.

No staging gate was executed against staging in this phase.
