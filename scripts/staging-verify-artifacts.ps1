$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $workspace
$priorDebug = $env:DEBUG
try {
  $env:DEBUG = $null
  & node scripts/staging-cloud.cjs verify-local
  if ($LASTEXITCODE -ne 0) { throw 'Staging configuration verification failed.' }
  $sdkPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
  $buildTools = Join-Path $sdkPath 'build-tools\36.0.0'
  $apkPath = 'build/app/outputs/flutter-apk/app-staging-debug.apk'
  $badging = & (Join-Path $buildTools 'aapt.exe') dump badging $apkPath
  if ($LASTEXITCODE -ne 0 -or -not ($badging -match "^package: name='com.fujika.fatoora.original.staging'") -or
      -not ($badging -match "^application-label:'Fatoora Original Staging'")) { throw 'APK package/label mismatch.' }
  $signature = & (Join-Path $buildTools 'apksigner.bat') verify --print-certs $apkPath 2>&1
  if ($LASTEXITCODE -ne 0 -or -not ($signature -match 'CN=Android Debug')) { throw 'APK is not validly debug signed.' }
  [xml]$resources = Get-Content -LiteralPath 'build/app/generated/res/processStagingDebugGoogleServices/values/values.xml'
  $values = @{}
  foreach ($entry in $resources.resources.string) { $values[$entry.name] = $entry.InnerText }
  $config = Get-Content -LiteralPath config/firebase/staging.android.json -Raw | ConvertFrom-Json
  if ($values['project_id'] -ne 'fatoora-original-staging' -or
      $values['google_app_id'] -ne $config.FIREBASE_APP_ID -or
      $values['gcm_defaultSenderId'] -ne '5438538531' -or
      $values['google_api_key'] -ne $config.FIREBASE_API_KEY) { throw 'Effective native resources mismatch.' }
  $webConfig = Get-Content -LiteralPath config/firebase/staging.web.json -Raw | ConvertFrom-Json
  $webJs = Get-Content -LiteralPath build/staging/web/main.dart.js -Raw
  foreach ($value in @($webConfig.FIREBASE_APP_ID, $webConfig.FIREBASE_API_KEY, $webConfig.FIREBASE_PROJECT_ID)) {
    if (-not $webJs.Contains($value)) { throw 'Compiled Web SDK inputs are missing.' }
  }
  $report = [PSCustomObject]@{
    project = 'fatoora-original-staging'
    projectNumber = '5438538531'
    apkPackage = 'com.fujika.fatoora.original.staging'
    apkLabel = 'Fatoora Original Staging'
    apkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    debugSignatureVerified = $true
    nativeSdkPairingVerified = $true
    webSdkInputsPresent = $true
    webJavaScriptSha256 = (Get-FileHash -LiteralPath build/staging/web/main.dart.js -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $report | ConvertTo-Json | Set-Content -LiteralPath build/staging/artifact-verification.json
  $report | ConvertTo-Json
} finally {
  $env:DEBUG = $priorDebug
  Pop-Location
}
