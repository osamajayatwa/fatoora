# Phase 2B-15 — Settlement security and activation readiness

2026-11-10, Asia/Amman. **Security implementation and closed staging deployment
complete; HOLD for feature activation and positive financial acceptance.**
The owner authorized staging security/configuration, one scoped deployment and
controlled activation, with no financial writes. The owner selected future normal
workflow records after an approved opening/currency cutover for later acceptance.
That selection documents a policy direction; no opening, book or cutover was written.

## Delivered and deployed

- Added an opaque staging read capability pinned to `fatoora-original-staging`,
  its default database, TLS SDK transport and `default_company`. Only read-only
  SDK transactions qualify. The atomic persistence guard remains emulator-only.
  The existing breakdown, recovery, exact arithmetic, snapshot witnesses and page
  contracts are reused. No ledger, allocations or posting path was added.
- Created `fatoora-settlement-reader` with precisely
  `datastore.databases.get`, `datastore.entities.get`, `datastore.entities.list`
  and `firebaseauth.users.get`. The existing staging deployer can act as this
  identity. Existing writer identities and their permissions were preserved.
- IAM v3 analysis confirms seven tested financial/Auth write permissions are
  **CANNOT_ACCESS**. Read allow grants are present, but inherited deny-policy
  visibility is incomplete. An actual runtime canary independently passed all
  four required read operations, using three security-document reads and one
  Auth get, with no financial reads or write probe. A failed canary prevents
  financial transport work for that process. No impersonation grant was added.
- Enabled staging App Check and IAM policy-analysis APIs. The callable enforces
  App Check, exact staging JWT audience/issuer, current Auth revocation and the
  existing current approved company-administrator checks. A 16 KiB raw-body cap
  precedes financial work; the callable framework has already parsed/validated
  protocol/authentication before the handler runs.
- Added a server-owned security control at
  `internal_read_controls/settlement_breakdown`: explicit enable switch, maximum
  three UIDs, exact app IDs/company, revision and at most 24-hour activation.
  It is read afresh before/after successful work. Its SDK update version is bound
  into signed sessions, so even reusing a visible revision invalidates sessions.
  Permission/control failure removes the user's retained sessions. Existing
  five-minute expiry, snapshot checks, pagination, PDF reauthorization and limits
  remain in force. Client Rules deny this root collection by default.
- Deployed **only `getSettlementBreakdown`**, revision
  `getsettlementbreakdown-00001-wiz`, using the dedicated read entry and identity:
  Node 22, **1 CPU**, 512 MiB, concurrency 2, maximum one instance, 60-second
  timeout. Public callable invocation still requires Firebase Auth and App Check.
  The financial security control is **false**. All 35 existing function revisions,
  source references and runtime identities are unchanged.
- Sealed source archive SHA-256:
  `86ab772a0e00c4d2ae44f7b31a8fd44da56f25a507e26d7fe0cb035d84b2b779`.
  Private artifact/operation evidence is retained in
  `.staging/fatoora-original-staging/settlement-read-release/`.
  An initial create was rejected for fractional CPU with concurrency 2; its
  candidate was preserved, absence of the function confirmed, then a separate
  corrected candidate was sealed. No existing function was replaced.
- Prepared a default-off Flutter staging switch, pinned SDK bootstrap, real
  reCAPTCHA Enterprise/Android Play Integrity integration and staging provenance
  for the existing details/PDF. The emulator switch and injected fixtures remain
  restricted; no fixture fallback exists. App Check tokens use SDK refresh rather
  than forcing a new attestation for every detail batch. Production stays off.
  Web and staging Android debug builds passed with the switch off. **No Hosting
  release, phone installation, UI activation, Rules/index deployment or journal
  activation was performed.** The final controller gate adjustment still permits
  only the explicit staging build in release and excludes injected factories.

## Verification

- **347 distinct affected backend cases passed across targeted runs:** 260
  persistence/recovery/breakdown/coverage, 27 original transport, 27 batch,
  8 pilot-control and 25 staging capability/runtime checks. The initial combined
  run used the wrong working directory for two evidence-output tests; these and
  their after hook passed when rerun correctly. An unnecessary optional-access
  async yield exposed a concurrency regression; it was corrected, and all 27
  batch tests passed. Counts do not include the failed file-hook as a test case.
- **35 local cloud-tool scope guards passed**. They reject production, financial
  writes, broad deployments, unsafe roles, arbitrary control activation, unrelated
  endpoint policies and unbounded reads. TypeScript build and lint passed.
- **683 Flutter tests passed**, including isolated callable/Auth integration,
  large immutable captures, exact DTOs, responsive widgets and bilingual PDFs.
  The explicit staging build configuration/gate run passed **20** cases.
  Flutter analysis passed. Only three compatible App Check packages were added;
  existing FlutterFire versions and backend dependency lock remained unchanged.
  A final local check discovered an all-NUL Flutter lockfile. It was restored
  from the unchanged Git baseline, then resolved offline to exactly the same
  three App Check additions. Other source text scanned clean. The final affected
  controller wiring check and 25 staging-unit checks passed after repair.
- **8 synthetic PDFs / 110 pages** passed independent rendering, bounds and
  missing-glyph checks. Exact units, totals, actors and document references passed
  content checks for both four-document fixture sets. These are local synthetic
  results, not certification of staging financial history.
- Runtime canary passed for the deployed revision. Three live denial probes
  returned HTTP 401 / UNAUTHENTICATED: anonymous without attestation, the existing
  signed-in staging admin without attestation, and that admin with a forged token.
  Responses were 66 bytes; observed request latencies were 754/509/526 ms.
  These are denial-path samples, not financial latency percentiles.
- Final bounded financial digest matches the pre-change baseline:
  `54cc6348af6b8159d9cf5117dc2369fe15f94ed64710bc663e589e5b55e0aa58`.
  No staging financial record changed. One existing-admin sign-in changed Auth
  login metadata only. Production requests, financial writes, backfills and
  historical corrections: **zero**. Original synthetic fixture/evidence files
  were restored; this run's immutable captures are retained separately.

## Activation HOLD and next acceptance gates

1. **Attestation registration:** API availability/default configuration is not
   proof of a registered provider. The web Enterprise configuration has no site
   key. Android reports the default `NO_INTEGRITY` device setting, which is not an
   accepted pilot policy. Register the staging-only web domains/site key and
   approved native package/signing certificate/provider policy. Verify genuine
   attestation and invalid/missing-token rejection without a debug-token bypass.
2. **Financial cutover:** staging still has no book, settlement, verified opening
   or approved currency binding. It contains one movement, one balance, two
   invoices and a customer-credit return; no receipts or expenses. Company active
   and book prerequisites are missing. Keep historical opening unknown, never
   zero. A new binding cannot retroactively predate legacy movements. Specify a
   prospective, persisted cutover/opening contract and its reconciliation proof
   before authorizing financial setup. Do not rewrite or silently exclude legacy
   history; until supported authoritative evidence exists, breakdown stays blocked.
3. **Controlled acceptance:** after those prerequisites, verify actual target
   ownership and all source coverage; select one current admin and a short expiry,
   rotate the control revision, build/publish only the pinned staging client, and
   test real attestation, revocation between pages, kill-switch behavior, PDF
   authorization and Arabic/English desktop/mobile display. Use ordinary future
   workflows for financial cases only after explicit financial authorization.
4. **Operational acceptance:** measure real cold/warm first/complete/PDF latency,
   reads and sustained requests with evidenced records. Sessions and quotas remain
   process-local and disposable; cold/rerouted tokens fail closed and quota resets
   prevent claiming a durable global billing cap. Accept this bounded pilot model
   or separately design a nonfinancial durable admission boundary.

The next authorized acceptance phase has completed its available closed-security
checks only. It has **not** passed positive financial/UI/native/PDF acceptance.
A phone is unnecessary for finishing this security phase; use the separate
staging package for native acceptance after these gates are resolved.

## Read costs and rollback

Phase 2B-13 financial read measurements remain the baseline, not a new cloud
benchmark. Each successful staging request adds two security-document reads;
the runtime canary adds three reads once per cold process and one Auth RPC.
For 3,000 movements / eight batches plus PDF, projected units are approximately
**60,382 cold / 60,379 warm**, versus 60,361 previously. At the Phase 2B-14 nam5
model of $0.06/100,000 reads, that is about **$0.03623** per complete view, excluding
Auth, App Check assessments, compute, network, retries and restarts. All-company
history scans still amplify cost; process read-work counters are not exact bills.
The three denial probes did not reconstruct a financial breakdown.

Rollback/kill: retain or set the control **false**, rotate its revision on every
closure/reactivation, verify page/PDF denial, then remove invocation on only the
new callable or deploy its closed gate if needed. Keep the client switch off.
No financial restore or old backend rollback is required. Hosting was unchanged;
do not restore any old writer archive, Rules or ledger. Never reset financial
history. Already downloaded PDFs cannot be revoked retroactively.

References: [App Check enforcement](https://firebase.google.com/docs/app-check/cloud-functions),
[Flutter providers](https://firebase.google.com/docs/app-check/flutter/default-providers),
[IAM analysis](https://docs.cloud.google.com/policy-intelligence/docs/reference/policytroubleshooter/rest/v3/iam/troubleshoot).
