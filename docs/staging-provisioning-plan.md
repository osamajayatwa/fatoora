# Original Fatoora: dedicated staging approval plan

Reviewed **2026-11-04, Asia/Amman**; explicitly approved in session, including
parent `organizations/81973318356` and billing `0104EE-737092-D9DBF0`.
Execution results and remaining acceptance limits are recorded in
[staging-provisioning-results.md](staging-provisioning-results.md).
The sections below preserve the reviewed pre-creation plan and its original gates;
their pending-state statements describe that review, not the current deployment.
This plan and the [review manifest](../config/firebase/staging-plan.review.json)
replace the proposal to reuse V1 infrastructure.

## 1. Verified candidate and protected projects

| Purpose | Project ID | Project number / policy |
| --- | --- | --- |
| Proposed new original-app staging | `fatoora-original-staging` | Unknown until approved creation; capture and pin. |
| Original production: forbidden write target | `fatoora-6b192` | `961957914773` |
| Fatoora V1: forbidden write target | `fatoora-platform-staging` | `813911311333` |

New display name: **Fatoora Original Staging**. Keep only `default_company` and
the current screens, Auth/RBAC, Functions and Firestore architecture. No company
switcher, parallel backend or accounting implementation. Do not reuse either
existing project's registrations, identities, credentials, IAM or Hosting.

Read-only checks: candidate syntax is valid; the complete accessible Firebase
list contains only the two protected projects. Candidate Google Cloud/Firebase
lookups returned **403**, which does not prove absence or availability. Hosting
lookup returned **404**; no name was reserved. **Global availability remains
unconfirmed.** Check at approved creation; if unavailable, stop for approval of
a different exact ID, with no automatic suffix or project reuse. Deleted project
IDs cannot be reused. [Project-ID requirements](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects).

Evidence is ignored under `build/staging-plan/original-inspection.json`.
Creation permission/quota, parent and billing eligibility remain unverified.
No API was enabled to perform inspection.

## 2. Exact scope requiring approval

- **New project:** exact ID/display name above; explicit organization/folder or
  confirmed no organization. Parent remains unresolved; do not inherit a CLI
  default. Record the generated project number after approved creation and pin
  it for every later operation. Never adopt an unowned pre-existing project.
- **Billing/services:** select and approve a permitted billing account, link only
  the new project and activate Blaze. Enable required Firebase/Auth/Firestore/
  Hosting services plus the existing second-generation Functions APIs as needed
  (Functions, Build, Artifact Registry, Run, Eventarc, Pub/Sub). Review staging
  costs/budget alerts. No existing-project billing/IAM changes or copied secrets.
  [Functions prerequisites](https://firebase.google.com/docs/functions/get-started).
- **Database/backend:** `(default)` Firestore, Standard/Native, **`nam5`**;
  existing Rules/indexes and Functions exports, region **`us-central1`**, Node 22,
  codebase **`fatoora-original-staging`**. No new endpoints or business changes.
- **Hosting:** one dedicated default site **`fatoora-original-staging`**, expected
  URL `https://fatoora-original-staging.web.app`. Explicitly create/verify it
  **before Auth enablement and Web registration**. Site creation is deferred in
  current Firebase behavior; do not assume project creation reserved the name.
  Stop on naming conflicts or an unexpected auto-generated site; no fallback.
  [Default-site behavior](https://firebase.google.com/docs/hosting/default-site).
- **New registrations:** Android `Fatoora Original Staging Android`, package
  **`com.fujika.fatoora.original.staging`**; Web `Fatoora Original Staging Web`.
  Both app IDs and all SDK settings must come from the new project. Enable only
  Email/Password Auth and the new site's required domains. No Google sign-in,
  Analytics, new FCM integration or Storage bucket is needed. Use returned SDK
  Storage metadata only; if absent, allow an absent unused option through a
  narrow tested local fix instead of inventing/provisioning a bucket.
- **Admin:** independent new Auth UID for `admin@fatoora.com`, strong new password,
  initially disabled, with the existing approved admin profile initially inactive.
  Full **application-level** permissions, no Google Cloud IAM role. Copy no UID,
  password, token or claims; send no automatic emails or unsupported email-
  verification flag. Enable only after data validation.

### Seed boundary: 95 explicit documents, no business history

Use the already verified `build/local-test/catalog.json`, SHA-256
`1763b2233f03dc76f06c4ff9a1c757006dc4fc41a891e139109aa51c10555f35`.
It contains **91 definitions: 90 active/nondeleted and one deleted**. No silent
refresh or new production export. Preserve original IDs, names, codes/SKUs,
specifications/metadata, categories, units, tax, selling prices and flags where
present. Reuse `validateBundle`, `sanitizeCatalog`, `targetItem` and search helpers;
replace emulator author/marker fields with the real new staging UID/provenance.

Set `currentStock`, `openingStock`, `minStock`, `costPrice`, `inventoryValue` to
**zero**; preserve tracking flags and derive stock status. Use fresh trusted
server timestamps; copy no source authors/timestamps, stock references, costs or
request identifiers. No inventory movements or opening-balance transactions.

| Path | Content |
| --- | --- |
| `companies/default_company` | `Fatoora Original Staging`, new setup provenance; no balances/book. |
| `companies/default_company/settings/app` | Existing schema, staging name/email, blank sensitive company details, JoFotara disabled/unconfigured. |
| `users/<new staging UID>` | Existing uid/name/email/empty phone/photo, role `admin`, approvalStatus `approved`, companyId `default_company`, new timestamps; inactive until verification. |
| `items/<original ID>` (91) | Sanitized definitions/prices, zero quantities/costs, new provenance. |
| `companies/default_company/financial_ledger_account_activity_metadata/current` | Existing readiness marker from a verified empty ledger, using the one-write-budget initializer. No journal/opening entry. |

Allow existing-trigger setup audit records/derived fields; these are new staging
provenance. Never disable audit. Verify root legacy and company history paths
empty: customers, invoices, quotations, receipts, sales_returns, expenses,
cash_movements, cash_balances, settlements, customer_transactions,
inventory_transfers, rep_inventory_balances, rep_inventory_movements,
stock_movements, financial_ledger_entries. No receivables, custody or GL books/
policies/journals. Only the approved company may exist.

## 3. Local safeguards to implement after approval

1. Separate `firebase.staging.json`: existing source/Rules/indexes/SPA rewrite,
   codebase `fatoora-original-staging`, literal Hosting site
   `fatoora-original-staging`, public directory `build/staging/web`.
2. Guarded provisioning/build/deploy launcher: allow only the exact new project,
   deny **both** protected IDs/numbers, then require captured new number and app/
   SDK pairings. Reject emulator variables during remote operations, mismatched
   credential targets, unknown ownership, `--force` and implicit deletions. No
   unqualified deployment, alias remapping or default-project fallback.
3. Use project-local runtime/service identities and a staging-only deploy
   principal after bootstrap. Inspect inherited IAM/cross-project access; stop
   on conflicts, without editing either existing project's IAM. No exported keys
   or cross-project resource grants.
4. Opt-in Android `staging` flavor, suffix `.original.staging`, label
   **Fatoora Original Staging**, manifest overlay and matching ignored native
   `android/app/src/staging/google-services.json` (add ignore entry first).
   Launcher scopes/restores `ORG_GRADLE_PROJECT_fatooraStaging=true`; normal
   production tasks stay no-flavor. Reject missing/mismatched native config or
   non-staging Dart options; never fall back to production native config. Debug
   signing only, no production keystore. [Per-variant config](https://firebase.google.com/docs/projects/multiprojects).
5. Populate ignored `config/firebase/staging.android.json`/`staging.web.json`
   from new SDK configs; set `FATOORA_ENV=staging` and project/confirmation to
   `fatoora-original-staging`. Validate app/sender/API-key/project pairing before
   build/startup. Extend the existing staging guard to reject V1 and pin the
   approved original target; its current checks only explicitly block production.
6. Separate gated create-only staging bootstrap, reusing pure emulator-fixture
   transformations. Preserve `seedLocalEnvironment`'s emulator-only refusal.
   Resume only manifest-owned exact matches; stop on changed stock/history,
   conflicting identities/docs or unknown setup ownership.

Preserve production `lib/firebase_options.dart`, native config/signing,
`.firebaserc`, `firebase.json`, Rules, Functions behavior and UI. No activation
code, SDK files or Android flavor was added during this planning task. Generated
number/app IDs remain explicit `null`; no invented project metadata.

## 4. Smallest activation sequence: after approval only

1. Confirm parent/billing selection; capture approved source/catalog/manifest
   hashes and backup local files to patch. Recheck ID/quota/permissions. Create
   the new project once, add Firebase, pin its number and operation ownership.
2. Link approved billing/enable scoped services. Create and verify the exact
   default site **before** Auth/Web setup; register both apps and Email/Password.
   Create closed-rule Native database and verify location. Capture SDK configs.
3. Complete local safeguards; run existing environment/Auth/Rules/catalog fixtures
   and relevant regressions in isolated emulators, Functions build/lint, Flutter
   analysis and Android/Web builds. Destructive/retry tests stay on emulators.
4. Deploy existing Rules/indexes, wait for readiness, then the named Functions
   codebase. Stop on failures, unavailable listings, collisions or deletion prompts.
   Capture exact resources/source hashes; never assume an inaccessible service
   is empty. Keep admin disabled and Web unpublished while preparing data.
5. Create disabled admin/profile and seed exactly the approved documents with
   create-only preconditions. Wait for triggers, verify all 91 definitions/prices,
   zero stock/history and permissions, then activate that admin/profile.
6. Inspect effective native/Dart targets, install the APK and deploy only the new
   Web site. Verify device access over the internet with emulators stopped.

Installed CLI help/source verified these **post-approval command forms; none
were executed**. The future launcher checks every exit status/target and requires
the recorded parent/billing account/number; this is not an unattended script.

```powershell
$stageProject = 'fatoora-original-staging'
firebase.cmd projects:create $stageProject --display-name="Fatoora Original Staging"
# Supply --organization=<approved ID> or --folder=<approved ID> if applicable.
# Pin project number; link approved billing and enable services before proceeding.
firebase.cmd hosting:sites:create fatoora-original-staging --project=$stageProject
firebase.cmd apps:create ANDROID "Fatoora Original Staging Android" --package-name=com.fujika.fatoora.original.staging --project=$stageProject
firebase.cmd apps:create WEB "Fatoora Original Staging Web" --project=$stageProject
firebase.cmd firestore:databases:create '(default)' --location=nam5 --edition=standard --project=$stageProject
# Configure Auth, guards and native/Dart configs; complete offline verification.
firebase.cmd deploy --config=firebase.staging.json --project=$stageProject --only firestore:rules,firestore:indexes
firebase.cmd deploy --config=firebase.staging.json --project=$stageProject --only functions:fatoora-original-staging
# Seed/verify scoped documents and enable only the new admin.
flutter.bat build web --output=build/staging/web --dart-define-from-file=config/firebase/staging.web.json
firebase.cmd deploy --config=firebase.staging.json --project=$stageProject --only hosting
```

Use noninteractive guarded creation once parent selection is explicit. Never
automatically retry creation after an uncertain outcome; inspect operation
ownership first. If CLI setup tries to create an unexpected default site, stop.
The installed database command creates Native mode; no unsupported `--type` flag.

Android (after implementation, scoped launcher opt-in):

```powershell
$priorStagingOptIn = $env:ORG_GRADLE_PROJECT_fatooraStaging
try {
  $env:ORG_GRADLE_PROJECT_fatooraStaging = 'true'
  flutter.bat build apk --debug --flavor staging --dart-define-from-file=config/firebase/staging.android.json
  if ($LASTEXITCODE -ne 0) { throw 'Staging APK build failed.' }
  flutter.bat run --flavor staging --dart-define-from-file=config/firebase/staging.android.json
} finally {
  $env:ORG_GRADLE_PROJECT_fatooraStaging = $priorStagingOptIn
}
```

Acceptance: independent Auth UID/issuer/audience, full approved-admin access,
catalog match/zero stock/history, dashboard/cash-opening reads on empty ledger,
anonymous/unauthorized/cross-project-token denial. Exercise cross-project denial
only against the **new** backend with synthetic fixtures, with no writes or sign-in
attempts against either existing project. Verify APK coexists with production/V1
and Web sessions/cache are separate. No test emails or business integrations.
Remote/device acceptance remains pending actual approved activation.

## 5. Rollback and open gates

- Stop at first mismatch. Deactivate only the new profile, disable its Auth
  identity/revoke refresh tokens, suspend the new Hosting release and, if needed,
  deny client database access. Retain data/audits and the resource/hash manifest.
- Later updates restore the recorded staging Hosting version/Functions artifact.
  Cleanup/deletion of the new project, database, Functions, seeded data or Auth
  requires separate reviewed approval and exact ownership checks. No automatic
  deletion/reset, no rollback through prod/V1. Default Hosting site rollback is
  suspension; it cannot be deleted independently.
- Revert only owned local changes after matching file hashes, preserving unrelated
  dirty workspace work. Device cleanup targets only
  `com.fujika.fatoora.original.staging`. Existing projects/resources and their
  credential/configuration files stay untouched throughout.

Approval must cover the exact new project/display name; selected parent and
billing account/Blaze costs; database location; APIs/managed Functions resources;
new registrations/package/site; independent admin; 95-document seed boundary;
and listed local safeguards. **Parent/billing selection, global project/site
availability and creation quota/permissions remain gates.** No fallback target
is approved. Capture generated number/app IDs after creation, never copy them.

Planning verification: **13 existing offline catalog/guard tests passed**.
Manifest/candidate consistency, both protected projects, catalog hash, 91 unique
IDs, 90 active/one deleted definition, unchanged prices and zero-stock transforms
passed local checks; `git diff --check` passed. No emulator, remote deployment or
Android staging build was performed in this revision. Accounting stays at
**Phase 2B-5 completed**.
