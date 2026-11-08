# Firebase environments

Fatoora supports three explicit runtime environments. Production remains the
default, so existing `flutter run` and release commands continue to use the
current `fatoora-6b192` project.

| Environment | Firebase project | Data policy |
| --- | --- | --- |
| `production` | `fatoora-6b192` | Existing live project. Never use test data. |
| `staging` | A separate remote project supplied at build time | Non-production data only. Production project IDs are rejected. |
| `test` | `demo-fatoora-test` | Local Firebase Emulator Suite only. No cloud data. |

## Local test environment

Recommended smallest setup: keep the app single-company and use the local
`demo-fatoora-test` project with the existing `default_company`, Auth, Rules and
Functions. No company switcher, membership migration or production write is
needed. A separate remote staging project is optional for a persistent/shared
test deployment and requires separate creation/deployment/account approval.

### Ready-to-run local setup (2026-11-04)

From `C:\src\fatoora`, use three terminals:

```powershell
# 1. Build and start the existing Auth, Firestore and Functions emulators.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/local-test.ps1 -Action Start

# 2. Seed the sanitized catalog and a local-only administrator.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/local-test.ps1 -Action Seed -Catalog build/local-test/catalog.json

# 3. Run the existing app/screens in Chrome against the emulators.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/local-test.ps1 -Action Run
```

The Seed action prompts for a **new test-only password of at least 12
characters**. Log in through the existing administrator login with
`admin@fatoora.com` and that password. This is an independent emulator identity,
not the production Auth user or password. No credentials are printed or stored
by the launcher. The execution-policy override applies only to that process.

The launcher selects the existing Android Studio Java 21 runtime when available;
otherwise pass `-JavaHome '<path to JDK 21+>'` to Start. It uses an ignored
workspace-local emulator binary cache, leaving other sessions' caches alone.
Stop the Start terminal with Ctrl+C when done. By default emulator data is
ephemeral; the catalog JSON remains local. Bootstrap does not reset history or
overwrite edited inventory/catalog values; use a fresh emulator session to
start over. Never reuse a production password for local tests.

The supplied `config/firebase/test.local.json` selects `FATOORA_ENV=test` and
loopback routing. Keep the production defaults and `lib/firebase_options.dart`
unchanged. For Android emulators use the existing `10.0.2.2` host support instead
of the Chrome-specific loopback launch file.

### Sanitized catalog transfer

Executed on 2026-11-04: a **read-only projected export** of 91 production item
definitions from `fatoora-6b192` / `default_company`, including selling prices,
saved at ignored `build/local-test/catalog.json`. It preserves source IDs and
flags: 90 active/nondeleted definitions, one deleted definition. Import preserves
these flags, so the normal catalog shows 90 active definitions. Source data was
not changed.

To refresh after production catalog changes, use a new output filename:

```powershell
node functions/scripts/local_test_environment.js --export-catalog=build/local-test/catalog-next.json
```

This command uses existing authorized user ADC through the Google SDK. It can
only issue a projected, paginated `items` read against the fixed production
project. It does not read Auth users, customer/financial collections, stock,
purchase costs or creator fields. Existing output files are never overwritten.
No CLI tokens or service-account keys are extracted. If the user's ADC needs
renewal, the user must renew it through their normal Google Cloud login workflow;
do not copy credentials into the test project.

Import permits only a `demo-` project with **both loopback emulator hosts**; it
has no remote-write, deployment, account-promotion or reset mode. IDs, names,
codes/SKUs, descriptions, units, selling prices/tax, categories, barcodes and
recognized technical specification fields are retained. Inventory/opening/minimum
quantities, inventory value and purchase cost start at zero. Production authors,
timestamps, creation requests, source movements and history are not imported.
The local administrator supplies the new creation provenance. No customers,
invoices, receipts, custody, cash balances, settlements or financial ledger rows
are copied or created by bootstrap.

The existing cash/ledger report screens require their existing reporting
projection readiness marker. If testing those screens in a completely empty
emulator, initialize the existing read model **locally only**, after Start/Seed:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
node functions/lib/maintenance/rebuild_financial_ledger_account_activity.js --project=demo-fatoora-test --company=default_company --apply --confirm-project=demo-fatoora-test --confirm-company=default_company --max-writes=1
```

For an empty ledger this writes only the projection-readiness metadata, never a
cash balance or opening transaction. The one-write budget blocks a nonempty
unprojected ledger. Do not use this command against production. This is existing
reporting setup, not the new accounting engine or a production migration.

Start the Auth, Firestore, Functions, Hosting, and Emulator UI services:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
firebase emulators:start --project=demo-fatoora-test
```

Current Firebase Emulator Suite releases require Java 21 or newer. The bundled
Android Studio JBR can be used as above when the system `java` still points to
Java 17.

Run Android against the emulators (the Android emulator automatically uses
`10.0.2.2`):

```powershell
flutter run --dart-define=FATOORA_ENV=test
```

Run Web or desktop against the emulators:

```powershell
flutter run -d chrome --dart-define=FATOORA_ENV=test
```

For a physical Android device, forward the ports with `adb reverse`, or supply
a reachable host explicitly:

```powershell
flutter run --dart-define=FATOORA_ENV=test --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.20
```

The test environment always enables the emulators. Its `demo-` project ID also
causes Firebase SDKs to fail any non-emulated service access instead of reaching
a cloud project, so it cannot silently connect to production.

## Remote staging setup

The dedicated original-app project is `fatoora-original-staging`, number
`5438538531`, under approved parent `organizations/81973318356` and billing
`0104EE-737092-D9DBF0`. Web access:
[Fatoora Original Staging](https://fatoora-original-staging.web.app).
`fatoora-platform-staging` remains reserved for V1; both it and production
`fatoora-6b192` are forbidden write targets in all staging tooling.

See [actual provisioning and verification results](staging-provisioning-results.md),
the [reviewed plan](staging-provisioning-plan.md), and
[approval manifest](../config/firebase/staging-plan.review.json).
The single company is `default_company`; the independent administrator is
`admin@fatoora.com`. Retrieve its new password locally with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/staging.ps1 -Action ShowAdminPassword
```

The password is Windows DPAPI encrypted for the provisioning Windows user in
ignored `.staging/fatoora-original-staging/`. That directory also preserves
provisioning ownership and evidence across `flutter clean`; protect and retain it.
No password or user token is checked into source or included in reports.

Use `scripts/staging.ps1 -Action BuildWeb`, `BuildAndroid`, `RunWeb` or `RunAndroid`.
Android uses debug signing and the opt-in package
`com.fujika.fatoora.original.staging`; its generated native configuration and
Dart configuration are checked together. Deployment actions verify the exact
project, number, identities and artifacts. Production remains the default;
its options, native configuration, CLI defaults, screens and workflows are unchanged.

### Local verification and accounting boundary

The new tests verify sanitized definitions/zero quantities, real emulator
Email/Password sign-in, existing admin catalog permissions, wrong-password and
anonymous denial, cross-company/project isolation, idempotency and refusal to
overwrite test history or inventory. The unchanged dashboard callable was also
invoked through the actual local Functions HTTP emulator with an emulator ID
token. All production access was read-only catalog projection; no production
account, membership, record, Rules or code was changed.

Completed checks: 18 bootstrap/Auth/Rules/isolation tests; 565 Flutter regression
tests with the local launch file; TypeScript build/lint and Flutter analysis.
The existing backend regression covered 662 tests: 624 passed in the main run,
and the 38 audit tests were rerun successfully after their initial emulator
readiness failure. No test failure remains unresolved. Logs are ignored under
`build/local-test/`. A preliminary emulator run was interrupted and is not
counted as a completed regression. Functions startup plus an authenticated HTTP
dashboard call passed; the existing empty-ledger reporting initializer scanned
zero rows and wrote only its readiness metadata. The emulators were stopped
after verification; run Start/Seed/Run above to create your own local session.

`functions/test/local_test_environment.test.js` has 13 offline tests; setting
both `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` enables the five
real Auth/Firestore integration tests. Existing Firestore-only test commands
continue to run the offline portion without requiring Auth.

Fatoora remains single-company. Multi-company implementation was stopped before
any patch applied. Accounting modernization remains at **Phase 2B-5 completed**.
The next proposal is the pending-settlement evidence/timestamp contract and
emulator proof described in `phase2b5-settlement-preflight.md`; it is not
implemented by this environment setup.

## Configuration ownership

- `lib/firebase_options.dart` remains the checked-in production configuration.
- `lib/core/firebase/firebase_environment.dart` selects and validates the
  runtime environment.
- `config/firebase/*.example.json` documents non-secret staging inputs.
- `config/firebase/staging.*.json` is ignored and must remain local/CI-secret.
- `.firebaserc` keeps production as the default and defines only the safe local
  test alias. Remote staging commands must pin the approved project ID/number;
  no staging alias was added by the planning task.
- `firebase.json` defines deterministic Emulator Suite ports.
