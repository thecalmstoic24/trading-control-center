$ErrorActionPreference='Stop'
function Check($value,$message){if(-not $value){throw $message}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlV14.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in @('Test-SyncDesktopBusy15','Request-ManualSync15','Start-ManualSync15')) {
 $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $fn.Extent.Text
}
$originalLocal=$env:LOCALAPPDATA
$env:LOCALAPPDATA=Join-Path ([IO.Path]::GetTempPath()) ('sync-test-'+[guid]::NewGuid().ToString('N'))
$directory=Join-Path $env:LOCALAPPDATA 'TradingControlCenter/agent-data'
New-Item $directory -ItemType Directory -Force | Out-Null
function Start-Worker14 {param($Mode,$TradeId,[switch]$FreshExport);$script:requests+=,@{Mode=$Mode;Id=$TradeId;Fresh=[bool]$FreshExport}}
function Assert-Idle14 {throw 'Export must not inspect the trading chart'}
try {
 $script:requests=@()
 Request-ManualSync15
 Request-ManualSync15
 Check ($requests.Count -eq 2 -and $requests[0].Id -cne $requests[1].Id) 'Each idle click must get a new export ID'
 Check ($requests[0].Fresh -and $requests[1].Fresh) 'Manual clicks must request current Accounts data'
 $pending=Join-Path $directory 'sync-pending.json'
 @{tradeId=('a'*32);csvPath='old.csv'} | ConvertTo-Json | Set-Content $pending
 Request-ManualSync15
 Check ($requests[-1].Id -ceq ('a'*32) -and $requests[-1].Fresh) 'Pending job must request fresh export without losing pending identity'
 $script:PairCoordinatorActive=$true;$count=$requests.Count
 Request-ManualSync15
 Check ($requests.Count -eq $count -and (Test-Path (Join-Path $directory 'sync-manual.json'))) 'Active trade must retain a queued request'
 $script:PairCoordinatorActive=$false
 Start-ManualSync15
 Check ($requests.Count -eq ($count+1)) 'Queued request must run when automation releases desktop'
 # Execute real worker-launch function with process/UI stubs: no chart-flat assertion for exports.
 $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-Worker14'},$true)
 $workerFunction=$fn.Extent.Text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
 Invoke-Expression $workerFunction
 function Invalidate-Preparation {}
 function Set-ControlsForBusyState {param($Busy)}
 function Start-Process {param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru);return @{Id=123}}
 $script:refreshTimer=New-Object PSObject
 $script:refreshTimer | Add-Member ScriptMethod Stop {}
 $script:refreshTimer | Add-Member ScriptMethod Start {}
 $script:ControlIdentity=@{Name='Test VM'}
 $script:SkippedResults23=@{}
 Start-Worker14 -Mode export -TradeId ('b'*32) -FreshExport
 $request=Get-Content (Join-Path $directory 'worker-request.json') -Raw | ConvertFrom-Json
 Check ($request.FreshExport -and $request.Mode -eq 'export') 'Fresh export flag lost at worker boundary'
 $script:Busy=$false;$script:Worker14=$null
 $blocked=$false;try {Start-Worker14 -Mode accounts} catch {$blocked=$true}
 Check $blocked 'Account discovery must retain chart safety gate'
 'Manual sync: fresh IDs, pending refresh, durable busy queue, independent Accounts export and unchanged account-discovery safety passed.'
} finally {$script:Worker14=$null;$script:Busy=$false;Remove-Item $env:LOCALAPPDATA -Recurse -Force;$env:LOCALAPPDATA=$originalLocal}
