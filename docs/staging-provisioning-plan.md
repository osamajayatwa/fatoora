# Original Fatoora: persistent staging approval plan

Prepared **2026-11-04, Asia/Amman**. Status: **awaiting explicit approval**.
This document and the [review manifest](../config/firebase/staging-plan.review.json)
are a proposal, not an executed deployment. Only bounded metadata reads were
performed. No project, app, database, account, API, deployment or data was changed.

## 1. Inspection and recommended target

The authorized Firebase project list contains:

| Project | Project number | Observed state |
| --- | --- | --- |
| `fatoora-6b192` | `961957914773` | Production. Default Firestore is Native mode in `nam5`. Never a staging write target. |
| `fatoora-platform-staging` | `813911311333` | Existing active staging project; reuse proposed instead of creating another project. |

Read-only staging inspection found:

- Android apps: `Fatoora Platform Staging Android` (`com.fujika.fatoora`) and
  **`Fatoora V1 Dev Android` (`com.fujika.fatoora.dev`)**. Reuse the latter,
  app ID `1:813911311333:android:efe57ed66e6c79dc21250c`.
- Existing Web app ID `1:813911311333:web:69d8ccb0bb8a771821250c`; reuse its
  project-specific SDK configuration. Its display name need not be changed.
- Email/Password Auth is enabled. Lookup of exactly `admin@fatoora.com`
  returned no staging user. No other Auth users were enumerated.
- The `(default)` Firestore database returned `NOT_FOUND`; no business document
  bodies were read. There is no database here to restore or reset.
- Cloud Functions listing was blocked by **`SERVICE_DISABLED`**. Do not report
  a verified zero function count: after approved API enablement, list again and
  stop if any existing function would collide with this app's exports.
- Billing is already enabled; no billing-account change is proposed.
- Existing Hosting site `fatoora-platform-staging` has deployments, most recently
  observed on October 30. Preserve it and all its releases.
- Proposed new Hosting site **`fatoora-v1-staging`** returned 404 on inspection;
  that is not a reservation or a guarantee of future name availability.
- SDK configuration advertises `fatoora-platform-staging.firebasestorage.app`,
  but bucket metadata returned 404. No Storage objects were read. The current
  app has no Firebase Storage integration; no bucket creation is proposed. Keep
  the SDK-provided nonproduction config value, without claiming Storage is ready.

**Recommended approval target:** reuse project `fatoora-platform-staging`, keep
`default_company`, reuse the existing `.dev` Android and Web registrations,
and create only the new Hosting site `fatoora-v1-staging` for this application.
Expected URL after approval/deployment: `https://fatoora-v1-staging.web.app`.

**Owner decision included in approval:** reserve this project's new default
Firestore database and original callable-function namespace for original Fatoora.
Apps within one Firebase project share backend/Auth resources; another Hosting
site is not another backend isolation boundary. Existing registrations are
preserved, but their future backend ownership must be agreed. If the Platform
application requires an independent backend in this project, stop and approve a
different project first; do not share the database or silently repurpose it.
[Firebase environment guidance](https://firebase.google.com/docs/projects/dev-workflows/general-best-practices).

Inspection evidence is ignored under `build/staging-plan/`. Read access failure
is never permission to enable an API or assume a resource is empty.

## 2. Exact proposed scope

### Cloud resources and data

1. Recheck the project ID **and number** against the manifest, caller identity,
   existing app IDs, hosting releases, Auth settings and database absence.
   Stop on a changed baseline. Never run using a default Firebase CLI project.
2. Enable only the APIs required by the existing second-generation Functions
   deployment (Functions, Cloud Run, Cloud Build, Artifact Registry, Eventarc
   and Pub/Sub as required). Use project-local service agents/runtime identity;
   no production roles, keys, secrets or CI credentials are copied. A dedicated
   staging-only deploy principal is preferable for repeat deployments.
   Existing authorized human access may perform the approved one-time setup.
3. Create `(default)` Firestore in Native mode, **`nam5`**, matching production's
   database location. Keep existing Functions/client region **`us-central1`**.
   Confirm these location choices before creation. No test-mode/open Rules.
4. Deploy the repository's existing Firestore Rules/indexes and existing
   Functions exports. Use codebase **`fatoora-v1-staging`** and a separate
   `firebase.staging.json`; reject name collisions and implicit deletion of any
   pre-existing function. Wait for indexes and required services to be ready.
5. Create a new staging-only Auth identity for `admin@fatoora.com`, with a newly
   generated UID and a strong separately chosen password. Initially disable it.
   Do not reuse production UID/password/tokens/claims, mark email verified
   without evidence, reset an existing account, or send an email automatically.
6. Seed only the paths below. Keep the profile inactive until validation finishes.
   Enable the new Auth identity and approved admin profile only after the data
   checks pass. An unexpectedly existing account or conflicting document stops
   setup for review, rather than taking it over.
7. Create Hosting site **`fatoora-v1-staging`** if still available. Add only
   `fatoora-v1-staging.web.app` to staging Auth authorized domains if needed;
   preserve the existing two domains. Publish only the staged Web build to this new site.
   Never deploy to `fatoora-platform-staging`'s existing Hosting site.

Functions require the Blaze plan; billing is already enabled, but enabling APIs,
builds, artifact storage and function usage can incur staging charges. Approve
usage/budget notifications with this scope; do not alter production billing.
[Functions deployment prerequisites](https://firebase.google.com/docs/functions/get-started).

### Seed data: 95 explicit documents, no business transactions

| Path | Proposed content |
| --- | --- |
| `companies/default_company` | Test company display name `Fatoora Staging`, setup provenance; no accounting book or balance. |
| `companies/default_company/settings/app` | Existing settings schema with staging name/email, blank sensitive company details, JoFotara disabled/not configured. No production settings or credentials copied. |
| `users/<new staging UID>` | `uid`, name `Test Administrator`, email `admin@fatoora.com`, empty phone/photo, role `admin`, approvalStatus `approved`, companyId `default_company`, active only after verification, fresh server timestamps. |
| `items/<original item ID>` × **91** | Existing root item schema; original IDs, codes/SKUs, definitions, categories, tax and selling prices, active/deleted/tracking flags. New staging admin creation provenance and server timestamps. |
| `companies/default_company/financial_ledger_account_activity_metadata/current` | Existing read-model readiness only, derived from an explicitly verified empty ledger. No cash position, opening entry or journal. |

The catalog is the already verified sanitized file
`build/local-test/catalog.json`, SHA-256
`1763b2233f03dc76f06c4ff9a1c757006dc4fc41a891e139109aa51c10555f35`.
It has **90 active/nondeleted definitions and one deleted definition**. Do not
refresh or substitute the file silently after approval.

Reuse `sanitizeCatalog`, `validateBundle`, `targetItem` and existing search-field
helpers. Adapt the target transformation to use the **actual staging admin UID**
and staging setup provenance, rather than `local-test-admin`. The current
`seedLocalEnvironment` remains emulator-only: do not remove its guard. Prepare
a separately gated staging bootstrap using those shared transformations after
approval, with pinned project/number, manifest/catalog hashes, create-only
preconditions and exact-match replay checks. There is no remote bootstrap yet.

All `currentStock`, `openingStock`, `minStock`, `costPrice` and `inventoryValue`
values start at zero; retain tracking flags and derive out/untracked status.
Never carry source authors, timestamps, creation requests, stock references or
source purchase costs. Seed creates no inventory movements. Existing triggers
may create new setup audit events and derived catalog fields; these are staging
provenance, not imported financial history. Do not disable audit to suppress them.

Verify **zero documents** in customers, invoices, quotations, receipts,
sales_returns, expenses, cash_movements, cash_balances, settlements,
customer_transactions, inventory_transfers, rep_inventory_balances,
rep_inventory_movements, stock_movements and financial_ledger_entries. Source
customer/financial/Auth exports are never inputs. Do not create the new GL's
books, policies, source keys, journals or preflight bindings in this task.

### Local changes to prepare activation, after approval

- Add a staging-only deploy config with Functions codebase
  `fatoora-v1-staging`, existing Rules/index paths, and Hosting
  **`site: fatoora-v1-staging`, public: build/staging/web**. A guard must pin the
  project ID/number and inspect built Web config before deploying. No unqualified
  `firebase deploy`, `firebase use` change, wildcard deletion or production alias.
- Download SDK configs from the existing approved staging app registrations into
  ignored `config/firebase/staging.android.json`, `staging.web.json` and
  `android/app/src/staging/google-services.json`. Set `FATOORA_ENV=staging` and
  exact `FIREBASE_PROJECT_ID_CONFIRM`. Add the native staging path to `.gitignore`
  before downloading it. Validate app ID/sender/project pairing. Never put
  service-account keys, passwords or Auth tokens in Dart defines or APK/Web assets.
- Android currently uses the production root `google-services.json` and has no
  staging variant. Add an **opt-in** `staging` flavor, package suffix `.dev`, and
  staging-only label `Fatoora Staging`. Select it only when the staging launcher
  passes `ORG_GRADLE_PROJECT_fatooraStaging=true`; normal production tasks retain
  their current no-flavor behavior. Couple the flavor to `FATOORA_ENV=staging`.
  The build must reject a missing/mismatched native staging file instead of
  falling back to the root production file. A staging manifest overlay supplies
  the label; production manifest, Firebase options and native config stay intact.
  [Native per-variant Firebase configuration](https://firebase.google.com/docs/projects/multiprojects).
- Use the existing Android registration `com.fujika.fatoora.dev`, not a new
  duplicate `.staging` registration. Debug APK signing is sufficient for device
  testing; do not use/copy the production release keystore. Register a staging
  debug SHA only if a requested provider needs it. Email/Password is in scope;
  adding Google sign-in, FCM or external integrations is not required.
- Preserve `lib/firebase_options.dart`, `.firebaserc` defaults,
  `firebase.json`, existing production Google services config and production
  signing configuration. No UI or domain/RBAC redesign, company switcher or
  accounting implementation. Android package and Web origin separation keep
  staging app caches/preferences separate from the production installation.

No Android flavor, staging SDK file, remote bootstrap or deploy wrapper has been
implemented/activated by this planning task. These are the concrete local changes
included in the proposed approval scope. The existing runtime staging guard and
emulator-only bootstrap remain as verified; do not claim Android staging builds
have been verified before these native changes exist.

## 3. Ordered deployment and acceptance procedure

These commands describe the **post-approval** procedure. Do not run them now.
Provisioning must use the resolved real ID, not an alias that could be remapped.

```powershell
$stageProject = 'fatoora-platform-staging'
# The guarded launcher rechecks project number 813911311333 and rejects prod.
firebase.cmd apps:list --project=$stageProject
# After approved API enablement: list functions and abort on a collision.
firebase.cmd functions:list --project=$stageProject
```

1. Store a private, hash-pinned pre-change manifest: project metadata and IAM
   principals, Auth provider/domains baseline, resource absences, existing app
   IDs, existing Hosting release/version IDs, source/catalog hashes and reviewed
   source artifact. Back up local files that the opt-in Android patch will touch.
   No production data backup/export is needed because production is not written.
2. Provision only the scoped resources in section 2. Recheck any apparent absence
   immediately before creating. If resources or intended ownership changed,
   stop and amend the plan; do not reset the project.
3. Build/lint the existing Functions; deploy Rules and indexes to the approved
   project, wait for index readiness, then deploy only this app's codebase:

   ```powershell
   npm.cmd --prefix functions run lint
   npm.cmd --prefix functions run build
   firebase.cmd deploy --config=firebase.staging.json --project=$stageProject --only firestore:rules,firestore:indexes
   firebase.cmd deploy --config=firebase.staging.json --project=$stageProject --only functions:fatoora-v1-staging
   ```

   Run through the guarded launcher, not freehand: API enablement and function
   deployment can create managed build/artifact/runtime/trigger resources. Do
   not use `--force` to resolve a deletion or collision prompt.
4. Create the initially disabled independent admin identity and seed the 95
   scoped documents with a resumable create-only manifest. Use the existing
   empty-ledger activity initializer with a one-write budget for the readiness
   marker. No clients receive access to a partially seeded catalog.
5. Validate exact document contents, role/approval, zero stock/history, expected
   project/resource IDs and manifest hashes. Enable the staged admin for smoke
   tests. Do not issue a production token, use source UID, or send test messages.
6. Build Android with the opt-in staging variant and own config:

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

   Inspect APK application ID/native Firebase project before installation.
   Expected package `com.fujika.fatoora.dev`, label `Fatoora Staging`; production
   remains `com.fujika.fatoora`. APK debug output is in the review manifest.
7. Build Web to its own directory, inspect its embedded Firebase target, then
   deploy **only the new named site** through its guarded config:

   ```powershell
   flutter.bat build web --output=build/staging/web --dart-define-from-file=config/firebase/staging.web.json
   firebase.cmd deploy --config=firebase.staging.json --project=$stageProject --only hosting
   ```

   `firebase.staging.json` must name `site: fatoora-v1-staging` literally. Keep
   `fatoora-platform-staging.web.app`'s current release unchanged. On a future
   staging-only update, preview/test the built artifact before live-site release.

Acceptance, using existing emulator fixtures/tests first, then read-only remote
checks: correct project/app IDs on both platforms; staging Auth issuer/audience
and fresh UID; approved admin access; anonymous/cross-project/unauthorized denial;
91 price/definition matches, 90 active catalog entries; zero inventory and all
listed business/history collections empty; existing authenticated dashboard and
cash-opening callables work against an empty ledger; app works without emulator
processes; production installed app/config and existing Hosting release unchanged.
Do destructive business-workflow/rollback tests only on isolated emulators.

## 4. Rollback and stop conditions

1. On any mismatch, stop the next step. Disable only the newly created staging
   admin and its new profile; suspend the new original-app Hosting site if it
   was released. Preserve all evidence and test data for review.
2. Never roll back through production or the pre-existing Platform Hosting site.
   For a later original-app staging update, restore that site's previously
   captured Hosting version and the last approved Functions source artifact.
3. This project's initial Functions API is disabled, not a verified empty
   namespace. After activation, record exact newly created function resource
   names, region and codebase. Any first-deploy cleanup must name only those
   manifest-owned resources. Never use broad function/project deletion, disable
   shared APIs/billing, or delete service agents needed by another app.
4. For a newly created database with no prior baseline, rollback means denying
   client access and retaining it for inspection, **not dropping/resetting it**.
   Optional removal of seeded docs/Auth identity requires a separate reviewed
   cleanup: matching setup ownership, hashes/update-time preconditions, no
   subsequent test business activity and an explicit path/UID allowlist. Do not
   delete audit evidence or another staging identity.
5. Restore/remove only configuration additions made by this run (for example,
   the new Auth authorized domain); preserve unrelated later additions. Revert
   the local staging patch only after matching its recorded before/after file
   hashes, preserving all unrelated workspace changes. Uninstall only
   `com.fujika.fatoora.dev` if device cleanup is requested.
6. Keep the original emulator bootstrap's cloud-write refusal. Do not add a
   bypass flag or a general-purpose production-capable import path.

## 5. Approval checklist and current limits

Approval must explicitly cover the exact project/number and backend ownership,
new database/location, required APIs/managed resources and staging costs, codebase
deployment, new Hosting site/domain, 91-definition bootstrap and independent
`admin@fatoora.com`, plus the listed local Android/configuration safeguards.

There is no cloud change to approve retroactively. The current admin, database
and new Hosting site are absent; the Functions API remains disabled. No new app
registration/project/bucket is necessary under this proposal. Name availability,
IAM propagation, index readiness and actual device/Web acceptance are gates for
the eventual activation, not results already obtained. Prior emulator verification
is reusable evidence, not proof of a remote deployment.

Accounting stays at Phase 2B-5. No accounting implementation is part of this plan.

## 6. Planning verification

Read-only project/app/Auth/Hosting/database metadata checks completed. The review
manifest parses and matches the inspected project number and app IDs. The pinned
catalog hash, 91 unique item IDs, 90 active/nondeleted definitions, one deleted
definition, unchanged selling prices and zero-stock transformations all checked.
The 13 existing offline catalog/guard tests passed again; `git diff --check` passed.
Only documentation and a non-executable approval manifest changed in this task.
No new emulator, remote-device, Android build or deployed-app test is claimed.
