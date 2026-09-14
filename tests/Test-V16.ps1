$ErrorActionPreference='Stop'
function Check($v,$m){if(-not $v){throw $m}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlV16.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in @('Tick-Startup16','Maintain-StateRefresh16','Start-ClipboardCopy16')){
 $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $fn.Extent.Text
}
$script:busyTest=$false;$script:starts=0
function Test-SyncDesktopBusy15{return $script:busyTest}
function Start-Worker14{param($Mode);Check ($Mode -eq 'startup') 'Unexpected startup mode';$script:starts++}
$script:StartupAttempted16=$false;$script:busyTest=$true
Tick-Startup16
Check ($script:starts -eq 0 -and -not $script:StartupAttempted16) 'Startup ran during trading'
$script:busyTest=$false;Tick-Startup16;Tick-Startup16
Check ($script:starts -eq 1) 'Startup should run once per launch'
$script:refreshes=0
function Refresh-Display{param($Quiet);$script:refreshes++}
$script:refreshTimer=New-Object PSObject -Property @{Enabled=$false}
$script:refreshTimer | Add-Member ScriptMethod Start {$this.Enabled=$true}
$script:StateCacheUtc=[DateTime]::UtcNow.AddSeconds(-10)
$script:Busy=$false;$script:ScheduledAction=$null;$script:Worker14=$null
Maintain-StateRefresh16
Check ($script:refreshes -eq 1 -and $refreshTimer.Enabled) 'Stopped stale refresh did not recover'
$script:Worker14=@{Id=1};Maintain-StateRefresh16
Check ($script:refreshes -eq 1) 'Refresh interfered with export worker'
$script:Worker14=$null;$script:Busy=$true;Maintain-StateRefresh16
Check ($script:refreshes -eq 1) 'Refresh interfered with scheduled automation'
$script:connectionStatus=@{}
Start-ClipboardCopy16 'test-only'
Check ($script:ClipboardText16 -eq 'test-only' -and $script:ClipboardAttempts16 -eq 0) 'Clipboard retry not initialized'
'V16: startup once, trading deferral, stale timer recovery and clipboard request initialization passed.'

# Actual retry function with a clipboard stub that is busy twice, then succeeds.
Add-Type 'namespace Windows.Forms { public static class Clipboard { public static int Calls=0; public static void SetText(string text) { Calls++; if(Calls<3) throw new System.Exception("busy"); } } }'
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Tick-Clipboard16'},$true)
Invoke-Expression $fn.Extent.Text
Tick-Clipboard16;Tick-Clipboard16
Check ($script:ClipboardAttempts16 -eq 2 -and $script:ClipboardText16 -eq 'test-only') 'Busy clipboard lost the pending code'
Tick-Clipboard16
Check ($null -eq $script:ClipboardText16 -and [Windows.Forms.Clipboard]::Calls -eq 3) 'Clipboard retry failed to complete'
# Startup worker success must dispatch a fresh manual sync once.
$workerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlV14.ps1'),[ref]$tokens,[ref]$errors)
$fn=$workerAst.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Poll-Worker14'},$true)
Invoke-Expression $fn.Extent.Text
function Set-ControlsForBusyState {param($Busy)}
$script:syncRequests=0
function Request-ManualSync15 {$script:syncRequests++}
$script:Worker14=New-Object PSObject -Property @{HasExited=$true}
$script:Worker14 | Add-Member ScriptMethod Dispose {}
$script:WorkerMode14='startup';$script:WorkerStarted14=[DateTime]::UtcNow
$script:WorkerResult14=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')+'.json')
try {
 @{ok=$true;message='Airtable login verified.'} | ConvertTo-Json | Set-Content $script:WorkerResult14
 Poll-Worker14
 Check ($script:StartupFinished16 -and $script:syncRequests -eq 1) 'Startup login success did not request sync'
} finally {Remove-Item $script:WorkerResult14 -Force -ErrorAction SilentlyContinue}
'V16 clipboard retries and startup login-to-sync handoff passed.'
