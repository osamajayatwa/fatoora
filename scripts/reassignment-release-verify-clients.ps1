$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$candidate = Join-Path $workspace 'build/reassignment-release/rc1'
$apkPath = Join-Path $candidate 'android/app-staging-debug.apk'
$sdkPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Join-Path $sdkPath 'build-tools\36.0.0'
$badging = & (Join-Path $buildTools 'aapt.exe') dump badging $apkPath
if ($LASTEXITCODE -ne 0 -or -not ($badging -match "^package: name='com.fujika.fatoora.original.staging'") -or
    -not ($badging -match "^application-label:'Fatoora Original Staging'")) { throw 'Candidate APK package/label mismatch.' }
$signature = & (Join-Path $buildTools 'apksigner.bat') verify --print-certs $apkPath 2>&1
if ($LASTEXITCODE -ne 0 -or -not ($signature -match 'CN=Android Debug')) { throw 'Candidate APK debug signing is invalid.' }
[xml]$resources = Get-Content -LiteralPath (Join-Path $workspace 'build/app/generated/res/processStagingDebugGoogleServices/values/values.xml')
$values = @{}
foreach ($entry in $resources.resources.string) { $values[$entry.name] = $entry.InnerText }
$config = Get-Content -LiteralPath (Join-Path $candidate 'inputs/staging.android.json') -Raw | ConvertFrom-Json
if ($values['project_id'] -ne 'fatoora-original-staging' -or $values['google_app_id'] -ne $config.FIREBASE_APP_ID -or
    $values['gcm_defaultSenderId'] -ne '5438538531' -or $values['google_api_key'] -ne $config.FIREBASE_API_KEY) { throw 'Effective candidate native resources mismatch.' }
$webConfig = Get-Content -LiteralPath (Join-Path $candidate 'inputs/staging.web.json') -Raw | ConvertFrom-Json
$webJs = Get-Content -LiteralPath (Join-Path $candidate 'web/main.dart.js') -Raw
foreach ($value in @($webConfig.FIREBASE_APP_ID, $webConfig.FIREBASE_API_KEY, $webConfig.FIREBASE_PROJECT_ID)) {
  if (-not $webJs.Contains($value)) { throw 'Candidate Web staging SDK inputs missing.' }
}
$result = [PSCustomObject]@{
  status = 'PASS'
  project = 'fatoora-original-staging'
  projectNumber = '5438538531'
  apkPackage = 'com.fujika.fatoora.original.staging'
  apkLabel = 'Fatoora Original Staging'
  debugSignatureVerified = $true
  nativeSdkPairingVerified = $true
  webSdkInputsVerified = $true
  apkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
  webJavaScriptSha256 = (Get-FileHash -LiteralPath (Join-Path $candidate 'web/main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $workspace 'build/reassignment-release-evidence/client-artifacts.json') -Encoding UTF8
$result | ConvertTo-Json
