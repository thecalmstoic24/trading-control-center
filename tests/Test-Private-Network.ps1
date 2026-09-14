$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../install/Private-Network.ps1')
function Check($Condition,$Message) { if(-not $Condition) { throw $Message } }
foreach($address in @('100.64.0.1','100.127.255.254')) { Check (Test-PrivateAddress15 $address) 'Private address rejected' }
foreach($address in @('45.32.199.44','192.168.1.219','127.0.0.1','0.0.0.0','100.63.255.255','100.128.0.1','::1','bad')) { Check (-not (Test-PrivateAddress15 $address)) 'Non-private endpoint accepted' }
function Read-TailscaleStatus15 { return $script:fakeNetwork }
$script:fakeNetwork=@{BackendState='Running';Self=@{TailscaleIPs=@('100.66.1.2','fd7a:115c:a1e0::1')}}
Check ((Get-PrivateAddress15) -ceq '100.66.1.2') 'Wrong endpoint detected'
$script:fakeNetwork.BackendState='NeedsLogin';$rejected=$false
try { Get-PrivateAddress15 | Out-Null } catch { $rejected=$true }
Check $rejected 'Signed-out network accepted'
$tokens=$null;$errors=$null
Get-ChildItem (Join-Path $PSScriptRoot '../install'),(Join-Path $PSScriptRoot '../agent') -Filter '*.ps1' | ForEach-Object {
 [void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) ('Syntax errors in '+$_.Name+': '+($errors.Message -join '; '))
}
'Private network: address detection, public-address rejection, sign-in requirement and PowerShell syntax passed.'
