param([Parameter(Mandatory = $true)][ValidateSet('Protect', 'Unprotect')][string]$Mode)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Protect') {
  $secretValue = [Console]::In.ReadToEnd()
  if ($secretValue.Length -lt 32) { throw 'A new strong staging password is required.' }
  $secureValue = ConvertTo-SecureString $secretValue -AsPlainText -Force
  $secretValue = $null
  [Console]::Out.Write((ConvertFrom-SecureString $secureValue))
} else {
  $encryptedValue = [Console]::In.ReadToEnd()
  $secureValue = ConvertTo-SecureString $encryptedValue
  $credential = [Net.NetworkCredential]::new('admin@fatoora.com', $secureValue)
  [Console]::Out.Write($credential.Password)
  $credential = $null
}
