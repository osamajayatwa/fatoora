# Fatoora Original — current Staging Web and Android release

2026-11-10, Asia/Amman. **Deployment PASS. Android installed and running.**
Only `fatoora-original-staging / 5438538531` was accessed. No production or other
staging project was contacted. Settlement activation limitations did not block
the normal application release.

## Live components

| Component | Verified result |
| --- | --- |
| Web | https://fatoora-original-staging.web.app/ |
| Hosting version | `35f553308cd219a8` |
| Hosting release | `1794329063402000` |
| Backend update | `recordCashSettlement`, revision `recordcashsettlement-00004-yek` |
| Preserved Functions | All 36 ACTIVE: 34 other business Functions and `getSettlementBreakdown` unchanged; the existing settlement writer updated compatibly |
| Breakdown callable | Remains `getsettlementbreakdown-00001-wiz`, financial gate **false**, App Check enforcement retained |
| Firestore Rules | Unchanged: `a96acaef-4431-4f95-9af6-08fb9ea67625` |
| Indexes | All **300 READY**, no additions/removals |
| Android package | `com.fujika.fatoora.original.staging` |
| Android label | **Fatoora Original Staging** |
| Android Firebase app | `1:5438538531:android:560f7feecdb97bf5240296` |

Only the settlement writer needed a backend update: its completed shared-write
refactor keeps the callable's original default financial behavior. The dedicated
deployment entry exports only this Function, retaining the Native Firestore
compatibility setting, existing service/build accounts, runtime configuration and
permissions. The other 35 Functions were not redeployed. Backend dependencies and
lock match the already verified patched deployment; no journal posting was wired
into the existing callable. Rules/index sources match the existing release, so
neither was unnecessarily redeployed.

## Android APK and F5

Installable artifact, preserved separately from Flutter's mutable build output:

`C:\src\fatoora\build\original-staging-current\android\fatoora-original-staging-debug.apk`

SHA-256: `5b501f8677541295c045c16ea6a934cb2bc9237abf1e92f43fce75974e565f38`.
The normal output is also `build/app/outputs/flutter-apk/app-staging-debug.apk`.
This is a fresh universal **debug-signed staging APK**, not a production release.
The APK's package, label, embedded Firebase project/app ID and signer were checked
before installation. It was installed successfully on the authorized **TECNO
KM7k**, without uninstalling or clearing data. The existing staging administrator
signed in successfully, and the app was left open on its Arabic dashboard.

In VS Code, select **Fatoora Original Staging Android** in Run and Debug, keep the
phone connected/unlocked, then press **F5**. The profile is in `.vscode/launch.json`
and its local preflight task is in `.vscode/tasks.json`. It pins the connected
device `152143758E021512`, staging flavor, debug mode, staging configuration file
and `ORG_GRADLE_PROJECT_fatooraStaging=true`. Both settlement pilot and emulator
flags are explicitly false. For a different phone, change only the profile's
device ID to the ID shown by `adb devices -l`.

Dart and Flutter VS Code extensions are installed. Local native/Dart registration
checks and the exact staging configuration tests passed. A live Flutter debugger
attached successfully to this running APK, exposing the Dart VM Service and
DevTools. That temporary CLI attachment was closed without stopping the app, so
F5 can own the next debug session. The VS Code F5 keystroke itself was not driven
through editor automation.

Manual installation on another authorized Android device:

```powershell
adb devices -l
adb -s DEVICE_ID install -r C:\src\fatoora\build\original-staging-current\android\fatoora-original-staging-debug.apk
```

Open **Fatoora Original Staging** from the launcher. It is separate from the
production app and does not use production Firebase configuration.

## Signing and App Check

The existing local debug signer was reused. Its SHA-256 is
`8f19c3002be031b4204d51287f6ad71096b097dfb5e7f4be081400c8ffbf96ab`;
SHA-1 is `9bf28c717508843f295a4ac3d1020215eced3570`.
Both were missing from the existing staging Android registration and were added
to that registration only. No production registration, key, signing configuration
or App Check enforcement was changed. No debug-token bypass was introduced.

The Android App Check provider still exposes its pre-existing default
`NO_INTEGRITY` policy. This is not accepted settlement pilot enrollment. Genuine
attestation enrollment/policy acceptance remains a **feature-specific limitation**;
the normal app runs with the settlement pilot switch off. Existing authentication,
Firestore and reporting requests succeeded without relaxing server enforcement.
Google account selection/Google SSO was not exercised; existing email/password
authentication was verified. No password was saved to the phone's password
manager, output files or logs.

## Checks and practical coverage

- Fresh Flutter Web release and Android staging debug builds completed. APK
  identity/signature/resource verification passed. Backend TypeScript build and
  lint passed; no runtime dependency drift.
- **21** focused Flutter Firebase-target, staging-gate and trusted-callable tests
  passed; **8** existing staging runtime/provisioning/release guard tests passed.
  The unchanged application behavior reuses the verified **683 Flutter** and
  **347 affected backend** cases from 2B-15, including responsive layouts, large
  text/content and exact PDF checks. This release did not rerun those broad suites.
- Existing administrator authentication and **12 real read checks passed**:
  invoices, receipts, returns, expenses, root item catalog, inventory transfers,
  cash movements, settlements, financial entries, dashboard, financial summary and
  accessible customers. Queries were bounded; no financial posting call succeeded
  or was attempted. The updated settlement writer rejects unauthenticated calls.
- Live Web executable/shell/manifest assets match the sealed release. HTTPS,
  secondary Firebase domain, SPA route and browser callable CORS checks passed.
  Live browser visual automation was unavailable because the browser access host
  was unavailable. Desktop/mobile visual regressions remain local test evidence;
  no live desktop browser interaction is claimed.
- On the phone, real sign-in, dashboard, invoice/return lists, receipt/expense
  navigation, inventory, cash and financial reporting were exercised. Arabic RTL
  and English LTR, loading states and long document/actor labels were observed;
  Arabic was restored. Existing invoice, return, stock and report data loaded.
  App-scoped logs report only `fatoora-original-staging`, with zero observed fatal
  exceptions or RenderFlex overflows. Screenshots and accessibility evidence are
  in `output/staging-current-20261110/phone/`.
- No financial documents, accounting openings, stock values, users, roles or
  permissions were edited. Authentication changes normal login metadata only.
  The before/after financial digest remains
  `54cc6348af6b8159d9cf5117dc2369fe15f94ed64710bc663e589e5b55e0aa58`.
  No resets, fabricated openings, corrections, migrations or backfills occurred.

## Intentionally unavailable financial tests

Experimental double-entry journal posting and settlement breakdown stay off.
Existing operational financial reporting remains available. Staging has no
settlement/receipt/expense examples or approved opening/currency evidence for the
future breakdown. Empty lists and navigation are testable; a completed detailed
settlement/PDF cannot be certified from that data. Existing cash reporting's
legacy figures are not newly persisted or certified breakdown openings.
No invoices, receipts, refunds, expenses or settlements were created/confirmed to
test posting. That would violate this release's no-financial-write boundary.

## Rollback

The previous finalized Hosting version `9c820eb4da13e96b` is retained. The guarded
command below restores only that version on the same staging site, provided the
currently deployed version still matches this release:

```powershell
node scripts/staging-app-release.cjs rollback-hosting
```

It was prepared, not executed. Exact original Function build/source generations,
service configuration and Hosting configuration are retained in
`.staging/fatoora-original-staging/application-20261110/baseline.json`.
The safe patched backend fallback archive's SHA-256
`2faa245e1544384652a31be142353ca37b91d4d2dc621aee126c705348026f97`
was rechecked before deployment. A backend rollback must target only
`recordCashSettlement` and preserve its current service identity/configuration;
never redeploy all Functions, restore financial data, or use a vulnerable archive.
Settlement gates remain closed throughout rollback.

Machine-readable proofs: `output/staging-current-20261110/`.
