param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('BuildWeb', 'BuildAndroid', 'RunWeb', 'RunAndroid', 'DeployRules', 'DeployFunctions', 'DeployHosting', 'ShowAdminPassword')]
  [string]$Action
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $workspace
$priorStagingOptIn = $env:ORG_GRADLE_PROJECT_fatooraStaging
$priorDebug = $env:DEBUG
try {
  $env:DEBUG = $null
  & node scripts/staging-cloud.cjs verify-local
  if ($LASTEXITCODE -ne 0) { throw 'Staging target/configuration verification failed.' }
  switch ($Action) {
    'BuildWeb' { & flutter.bat build web --output=build/staging/web --dart-define-from-file=config/firebase/staging.web.json }
    'BuildAndroid' {
      $env:ORG_GRADLE_PROJECT_fatooraStaging = 'true'
      & flutter.bat build apk --debug --flavor staging --dart-define-from-file=config/firebase/staging.android.json
    }
    'RunWeb' { & flutter.bat run -d chrome --dart-define-from-file=config/firebase/staging.web.json }
    'RunAndroid' {
      $env:ORG_GRADLE_PROJECT_fatooraStaging = 'true'
      & flutter.bat run --flavor staging --dart-define-from-file=config/firebase/staging.android.json
    }
    'DeployRules' { & node scripts/staging-deploy.cjs rules }
    'DeployFunctions' { & node scripts/staging-deploy.cjs functions }
    'DeployHosting' { & node scripts/staging-deploy.cjs hosting }
    'ShowAdminPassword' {
      # Windows DPAPI: only this Windows user can decrypt the new staging password.
      $protected = Get-Content -LiteralPath .staging/fatoora-original-staging/admin-password.dpapi -Raw
      $secure = ConvertTo-SecureString $protected
      $credential = [Net.NetworkCredential]::new('admin@fatoora.com', $secure)
      Write-Host 'Staging only: admin@fatoora.com'
      Write-Host $credential.Password
      $credential = $null
      return
    }
  }
  if ($LASTEXITCODE -ne 0) { throw "Staging action failed: $Action" }
} finally {
  $env:ORG_GRADLE_PROJECT_fatooraStaging = $priorStagingOptIn
  $env:DEBUG = $priorDebug
  Pop-Location
}
