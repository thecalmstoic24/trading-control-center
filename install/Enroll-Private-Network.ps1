param([Parameter(Mandatory=$true)][string]$EncryptedKeyPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Private-Network.ps1')
$plainPath=Join-Path (Split-Path $EncryptedKeyPath -Parent) 'auth-key.txt'
try {
 $secure=Import-Clixml -LiteralPath $EncryptedKeyPath
 $key=[Net.NetworkCredential]::new('', $secure).Password
 if($key -notmatch '^tskey-auth-[A-Za-z0-9_-]+$') {throw 'Invalid key type.'}
 [IO.File]::WriteAllText($plainPath,$key,[Text.UTF8Encoding]::new($false));$key=$null
 $exe=Get-TailscaleExecutable
 & $exe up ('--auth-key=file:'+$plainPath) --unattended --timeout=60s '--exit-node=' '--advertise-exit-node=false' *> $null
 if($LASTEXITCODE -ne 0) {throw 'Enrollment failed.'}
 $null=Get-PrivateAddress15
 exit 0
} catch {Write-Host 'Enrollment failed. Check the key, expiry, device approval and Windows user permissions.';exit 1}
finally {Remove-Item $plainPath -Force -ErrorAction SilentlyContinue;Remove-Item $EncryptedKeyPath -Force -ErrorAction SilentlyContinue;$key=$null}
