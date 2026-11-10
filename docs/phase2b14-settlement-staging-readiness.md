# Phase 2B-14 — Settlement breakdown staging readiness

2026-11-10, Asia/Amman. **Decision: HOLD for deployment/activation. Preparation
and bounded read-only inspection are complete.** Target inspected:
`fatoora-original-staging / 5438538531`, `(default)` database, configured company
`default_company` only. No staging business/configuration writes, synthetic
transactions, deployment, activation, production access or permission probes
against production were performed. Application/posting code is unchanged.

## PASS evidence

- **Regression count explained and closed:** Phase 2B-12 = 1,087 existing cases +
  27 transport cases = **1,114**. Phase 2B-13 reran **759** of those and added 27
  batch cases = **786**. The remaining **355** were omitted from that targeted
  run, not deleted. All 355 now passed on fresh local Auth/Firestore emulators,
  with zero failures/skips. This includes 114 exact-decimal, 58 Rules, 15 receipt-
  cancellation, 12 ledger, 8 audit and other authorization/integrity cases.
  Together with unchanged Phase 2B-13 evidence, **1,141 distinct backend cases**
  are verified; no original case remains uncovered. The old Phase 2B-12 bootstrap
  namespace issue is resolved by this fresh `demo-fatoora-test` run. Case/file
  identities are in `output/phase2b14/regression-counts.json`.
- **Target/inspection guards:** 22 local checks passed, including the 14 new
  inspection guards. Production, other projects/companies, mutation, callable
  invocation, sign-in, unbounded/offset reads and unreviewed projections reject
  before an SDK request. Older scripts that fingerprint protected projects,
  deploy, repair or seed staging were not run.
- **Dependencies:** fresh locked production `npm audit` reports zero findings.
  Runtime dependencies, overrides, Node engine and lockfile match the sealed
  deployed candidate; Flutter dependency definitions/lockfile also match prior
  verified evidence. All **35 current staging revisions** match the cached exact
  runtime inspection: Node 22, Admin 12.7.0, Functions SDK 5.1.1, Firestore 7.11.6,
  explicit Framework 3.5.1 with no injected framework. No dependency upgrade or
  artifact deployment was performed.
- **Local financial/security/presentation evidence reused:** all eight feature
  component SHA-256s in the Phase 2B-13 manifest still match. Its 786 backend and
  680 Flutter passes, clean build/lint/analysis, 6,000-movement bounded-memory
  test, Arabic/English responsive widgets and exact PDF checks remain applicable.
  This is local evidence, not live staging feature acceptance.
- **Existing rollback baseline:** current Hosting release remains
  `1794140590220000`, version `9c820eb4da13e96b`; all 41 sealed local Hosting assets
  re-hash correctly. Current Rules remain
  `a96acaef-4431-4f95-9af6-08fb9ea67625`. Existing reviewed patched rollback evidence
  is retained. Nothing was rolled back.

## Exact HOLD blockers

1. **There is no staging-capable settlement read path yet.** The callable is
   absent from staging. Current server flags, JWT audience/issuer and resolved SDK
   guards allow only `demo-fatoora-phase2b7` loopback emulators. Flutter repository,
   default-app marker, debug-only source and emulator provenance also reject
   staging. Production remains disabled. A flag alone cannot enable staging.
   Importantly, `assertSettlementRecoveryEmulator` shares the atomic persistence
   isolation guard: **do not add staging to that shared write guard**. A separately
   reviewed, project-pinned **read-only** execution context/adapter and matching
   staging client provenance/gate are required while the write guard stays intact.
2. **The configured staging company lacks required evidence.** Current projected
   company data has `id`, but no explicit `active: true` or `activeBookId`; the
   required `books` collection has no documents. No approved book/currency binding
   can therefore be resolved. There is no explicit cash opening and no settlement
   target. These facts prevent complete recovery/breakdown acceptance. Do not
   assume opening zero, derive currency from UI defaults, or retroactively create
   evidence. A new binding created after legacy cash would not satisfy the existing
   pre-dating check. History/cutover policy and any future setup need separate
   authorization; they were not implemented here.
3. **Read-only runtime authority is not ready.** Existing functions use the default
   compute service account and have project `roles/datastore.user`, which permits
   writes ([role permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/firestore)). Reusing or changing that writer identity is inappropriate for this
   read-only addition. A dedicated, least-privilege read principal and verified
   `firebaseauth.users.get` access are required ([Auth-reader permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/firebaseauth)). No project-level Auth-reader role
   was observed for the current runtime; inherited/effective Auth permissions were
   not proven. No IAM changes or production isolation probes were attempted.
4. **Cloud abuse/operability acceptance remains open.** Approve App Check policy,
   selected administrators, staging-only switches, raw request-size rejection and
   kill-switch behavior. Current read/request limits are process-local; restarts
   reset quotas and cold/rerouted tokens fail closed. Accept that availability
   model or approve a separate nonfinancial session/quota design. Do not claim a
   global billing cap from process counters or billing alerts.
5. **Positive acceptance data is missing under the no-write boundary.** There are
   no receipts, cash refunds, expenses, prior/current settlements or carried-
   settlement evidence in the inspected company. Existing records cannot support
   those acceptance scenarios. Other test-company namespaces were not queried or
   substituted for this single-company scope. No synthetic staging transactions
   or historical repairs were created.
6. **Live staging/native presentation and performance are unproven.** The hosted
   application predates the local feature, the endpoint is absent and guards stay
   closed. Actual staging breakdown latency, native SDK restoration/revocation,
   slow-link delivery and large-history PDF generation/printing cannot be
   accepted without the separately authorized read path and valid evidence.

## What the read-only inspection actually found

The projected inventory used 19 budgeted requests, returned 13 documents and
101,814 JSON bytes in 21.4 seconds, plus its project-identity verification.
Separate project-pinned reads checked current Hosting/Rules metadata. These are
prerequisite observations at recorded read times, **not** a shared financial
snapshot, balance reconciliation or feature-latency benchmark.

| Required source/evidence | Existing `default_company` observation |
| --- | --- |
| Administrator profiles | 3 active approved admin profiles, among 8 company profiles; live Auth status is not inferred from profiles |
| Book/currency configuration | No book; no active-book pointer; no resolvable approved currency binding |
| Opening/carry proof | No explicit cash-opening candidate; carried balance is unknown, never zero by default |
| Cash movements / cash balances | 1 / 1; currency/scale evidence missing on both; modern holder metadata missing on the movement |
| Invoices | 2 confirmed/financially posted: 1 cash, 1 credit; neither supplies currency/scale evidence |
| Receipts | 0 |
| Returns | 1 customer-credit return; no positive cash refund; it must not reduce cash |
| Expenses | 0 |
| Settlements | 0; no paired movement or atomic settlement target to inspect |

Legacy metadata absence does not automatically require rewriting a record:
existing compatibility rules can use appropriate authoritative evidence. That
evidence is currently unavailable. The inspection did not claim that orphaned
subcollections or all other namespaces are absent. Detailed observations and read
times are in `output/phase2b14/staging-inspection.json`.

## Remaining read amplification, cost and latency

Let `N` be **all company source documents** across the six inventory collections,
and `B` the number of bounded detail responses. A quiet complete view plus one PDF
permission costs roughly `N × (B + 2)` document reads, plus bounded authority/
configuration reads and initial aggregates. Each retry, extra export or restarted
session adds work. Heads or aggregate counts alone cannot detect rewritten or
deleted old evidence, so no verification was bypassed.

The inspected database is **Standard / nam5**, not regional `us-central1` merely
because Functions run there. Gross read projections below use USD **$0.06 per
100,000 reads**, before free quota/discounts, from the official
[nam5 pricing example](https://firebase.google.com/docs/firestore/billing-example?hl=en).
They exclude Auth, Functions compute, network, retries, restarts and extra exports;
they are not a cloud invoice. [Billing rules](https://firebase.google.com/docs/firestore/pricing)
also include aggregate minimums and index-entry charges.

| Synthetic invoice movements + mixed evidence | First response estimated read units / gross USD | Complete + PDF permission units / gross USD | Initial / complete median seconds |
| --- | --- | --- | --- |
| 3,000; 47 pages / 8 deliveries | 12,081 / $0.00725 | 60,361 / **$0.03622** | 7.15 / 12.87 |
| 4,000; 63 pages / 11 deliveries | 16,083 / $0.00965 | 104,468 / **$0.06268** | 9.57 / 19.36 |
| 6,000; 94 pages / 16 deliveries | 24,087 / $0.01445 | 216,647 / **$0.12999** | 7.49 / 16.44 |

Times reuse the independently verified Phase 2B-13 emulator samples: three new
sessions per case on a warm emulator/SDK, not cloud latency. The first response
may contain six existing 64-row pages. Complete sampled p95s were 13.38 / 19.50 /
16.51 seconds; samples are descriptive, not SLAs. No staging feature call or
guard-bypassing financial benchmark was run. At 1,000 complete views, gross read
exposure is approximately $36.22 / $62.68 / $129.99 respectively. Actual counts,
invoice mix and company-wide coverage must be measured during authorized pilot
acceptance. Cost inputs are in `output/phase2b14/cost-projection.json`.

### Enforceable limits and unresolved enforcement gates

| Existing coded control, retained | Limit |
| --- | --- |
| Company inventory / source projection | 16,000 documents; 64 KiB/document; 32 MiB initial attempt |
| Initial source verification / function request | 45 s / 60 s |
| Session / final PDF permission | 5 minutes / at most 15 seconds |
| Entire response / logical detail / delivery | 1 MiB / 64 rows / at most 6 pages |
| Opaque token / strict request schema | 4,096 characters; only scope IDs or signed token, no client totals/roles |
| UID requests / starts | 64/minute / 2/minute |
| Process requests / concurrent work | 128/minute / 2 |
| Retained sessions / serialized memory | 4; 24 MiB/session; 64 MiB total |
| Session requests / charged read work | 512 / 1,000,000 units |
| Process charged read work | 500,000 units/minute |
| Proposed function shape for later approval | 1 instance, concurrency 2, 512 MiB, Node 22, `us-central1` |

These are logical admission controls, not exact billable-read or physical-heap
caps, and do not survive process replacement. All enforcement remains active in
emulators; no staging deployment exists to enforce it there yet. Before approval,
add/test an explicit small raw request-body cap (e.g. 16 KiB before financial
reads), staging-only principal/feature gates and a reviewed kill switch. No cloud
request cap is falsely inferred from the response-size limit. Validate actual
cloud retries, memory, routing and sustained multi-admin cost; budgets/alerts do
not stop API usage.

## Controlled acceptance checklist

Use existing evidenced records only. A missing case is **HOLD**, not permission to
generate transactions. Cases needing writes, revocation mutations, corrupting
evidence or volume generation stay on isolated synthetic emulators under current
authorization.

| Case | Required assertion | Staging preparation status |
| --- | --- | --- |
| Cash invoice | One evidenced collection; actual holder, source number and actors preserved | Candidate exists, but configuration/opening proof blocks certification |
| Partial invoice | Exact initial collection and remainder; no receipt double count | No partial-payment candidate observed |
| Single/multiple-invoice receipt | Count actual movement once; allocation refs explain receivable use, never settlement funding | No receipts |
| Actual cash refund | Only verified paying holder decreases; preserve original seller separately | No cash-refund candidate |
| Customer-credit return | No cash decrease | Candidate exists; local contract proof reusable; live details unavailable |
| Approved/pending expense | Only approved cash-funded movement changes holder cash | No expenses |
| Prior/partial/repeated settlement | Verify paired legs; exactly one representative outflow; carry and remainder reconcile | No settlements or opening/carry proof |
| Missing evidence | Withhold totals/certification; no zero opening; denied/blocked/expired states remain distinct | Existing prerequisites fail closed; no valid settlement target yet |
| Permissions/session integrity | Deny anonymous/non-admin/cross-company, recheck revocation per batch/PDF; reject mixed/modified/expired tokens | Local cases passed; real-cloud acceptance pending; do not alter staging users here |
| Arabic/English UI and PDF | RTL/LTR; 320/768/1366 px, 2× text, long references; loading/error/retry; complete sequence and fresh post-render PDF authorization | Local 680-test evidence and 42-page PDF audit reused; live stage/native large-PDF acceptance pending |

## Conditional deployment scope and rollback requirements

**Not an executable deployment approval.** After the blockers are resolved and
separately approved, seal a new, hash-reviewed candidate for **only**
`getSettlementBreakdown` in `fatoora-original-staging`, `us-central1`, and the
existing staging Flutter interface/Hosting build. Use a dedicated read-only entry
and principal. Retain the single-company structure and exact response contracts.
The current 35 functions, posting code, Rules, indexes and financial records need
no redeployment or modification for this read addition. Native acceptance uses
the existing staging registration/package, not a production package.

Do not run the old whole-release/provisioning commands: their artifact/source
guards and 35-export assumptions describe an earlier release. Do not loosen those
guards to make this candidate pass. Prepare a narrowly scoped reviewed release
path with an explicit function allowlist, no destructive cleanup, no predeploy
rebuild of old archives, and zero unrelated export/configuration drift. Server
and client switches start **off**; activation is a separate approval after checks.

Rollback must first close the new server gate and hide the new client feature,
invalidate process sessions/keys, and deny further pages/exports. Restore only the
freshly verified staging Hosting baseline if necessary. Keep all 35 current secure
functions, corrected posting, secure Rules, additive indexes and immutable history.
Never restore financial data or vulnerable original backend archives. Verify the
retained patched fallback's hash before any use; no rollback drill or release is
authorized in this phase. Cached/downloaded PDFs cannot be erased retroactively.

**Smallest safe next work:** implement and test the separate staging read-only
target/client/kill-switch boundary without extending any persistence guard; obtain
an owner decision on valid opening/currency evidence and missing acceptance cases;
then re-review IAM, cost and native acceptance. Until then, deployment stays HOLD.
