param(
  [Parameter(Mandatory = $true)][ValidateSet('Start', 'Seed', 'Run')][string]$Action,
  [string]$Catalog = 'build/local-test/catalog.json',
  [string]$JavaHome = ''
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $workspace
try {
  switch ($Action) {
    'Start' {
      & npm.cmd --prefix functions run build
      if ($LASTEXITCODE -ne 0) { throw 'Functions build failed.' }
      $previousJavaHome = $env:JAVA_HOME
      $previousPath = $env:Path
      $previousEmulatorCache = $env:FIREBASE_EMULATORS_PATH
      try {
        if (-not $JavaHome -and (Test-Path -LiteralPath 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe')) {
          $JavaHome = 'C:\Program Files\Android\Android Studio\jbr'
        }
        if ($JavaHome) {
          if (-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))) { throw 'Java runtime not found.' }
          $env:JAVA_HOME = $JavaHome
          $env:Path = "$(Join-Path $JavaHome 'bin');$previousPath"
        }
        # Keep downloads and updates separate from other local emulator sessions.
        $env:FIREBASE_EMULATORS_PATH = Join-Path $workspace 'build/local-test/emulator-cache'
        & firebase.cmd emulators:start --project=demo-fatoora-test --only auth,firestore,functions
      } finally {
        $env:JAVA_HOME = $previousJavaHome
        $env:Path = $previousPath
        $env:FIREBASE_EMULATORS_PATH = $previousEmulatorCache
      }
    }
    'Seed' {
      $previousFirestoreHost = $env:FIRESTORE_EMULATOR_HOST
      $previousAuthHost = $env:FIREBASE_AUTH_EMULATOR_HOST
      $previousPassword = $env:FATOORA_TEST_ADMIN_PASSWORD
      try {
        $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
        $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
        if (-not $env:FATOORA_TEST_ADMIN_PASSWORD) {
          $testPassword = Read-Host 'Choose a test-only admin password (12+ characters)' -AsSecureString
          $env:FATOORA_TEST_ADMIN_PASSWORD = [Net.NetworkCredential]::new('', $testPassword).Password
        }
        & node functions/scripts/local_test_environment.js --seed "--catalog=$Catalog"
        if ($LASTEXITCODE -ne 0) { throw 'Local bootstrap blocked; inspect the safe status above.' }
      } finally {
        $env:FIRESTORE_EMULATOR_HOST = $previousFirestoreHost
        $env:FIREBASE_AUTH_EMULATOR_HOST = $previousAuthHost
        $env:FATOORA_TEST_ADMIN_PASSWORD = $previousPassword
      }
    }
    'Run' {
      & flutter.bat run -d chrome --dart-define-from-file=config/firebase/test.local.json
    }
  }
  if ($LASTEXITCODE -ne 0) { throw "Local test command failed (exit $LASTEXITCODE)." }
} finally { Pop-Location }
