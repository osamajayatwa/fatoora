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

At the time this support was added, the authenticated Firebase account
contained only the production project. A Firebase project owner must create a
separate remote project before staging can be run.

1. Create a dedicated Firebase project, such as `fatoora-staging`, in the
   Firebase console. Do not reuse `fatoora-6b192`.
2. Enable Authentication providers required by the app, Firestore, Functions,
   Storage, and Hosting in that project.
3. Register separate Android and Web apps. The Android registration must use
   `com.fujika.fatoora` and include the required signing certificate hashes if
   Google sign-in is tested.
4. Copy the appropriate tracked example file to its ignored local counterpart:

```powershell
Copy-Item config/firebase/staging.android.example.json config/firebase/staging.android.json
Copy-Item config/firebase/staging.web.example.json config/firebase/staging.web.json
```

5. Fill both local files with values downloaded from the staging project. Set
   `FIREBASE_PROJECT_ID_CONFIRM` to exactly the same staging project ID. The app
   refuses missing configuration, mismatched confirmation, or the production
   project ID.
6. Add a local Firebase CLI alias only after the project exists:

```powershell
firebase use --add
```

Choose the new project and name the alias `staging`. Do not change the default
or production aliases.

Run staging Android:

```powershell
flutter run --dart-define-from-file=config/firebase/staging.android.json
```

Build staging Web:

```powershell
flutter build web --dart-define-from-file=config/firebase/staging.web.json
```

For Windows, create `config/firebase/staging.windows.json` using the same keys
and the staging Windows/Web app registration.

## Staging deployment safeguards

There is intentionally no automatic staging deployment in the repository.
After the remote project has been created and verified, always name it or its
`staging` alias explicitly:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project=staging
firebase deploy --only functions --project=staging
firebase deploy --only hosting --project=staging
```

Before any deployment, verify the resolved target:

```powershell
firebase use
firebase projects:list
```

Never copy production Firestore data, Auth users, service-account credentials,
Functions secrets, or JoFotara credentials into staging. Use staging-specific
test identities and secrets. Maintenance scripts must receive the staging
project ID explicitly and retain their existing confirmation and dry-run
guards.

## Configuration ownership

- `lib/firebase_options.dart` remains the checked-in production configuration.
- `lib/core/firebase/firebase_environment.dart` selects and validates the
  runtime environment.
- `config/firebase/*.example.json` documents non-secret staging inputs.
- `config/firebase/staging.*.json` is ignored and must remain local/CI-secret.
- `.firebaserc` keeps production as the default and defines only the safe local
  test alias until a real staging project exists.
- `firebase.json` defines deterministic Emulator Suite ports.
