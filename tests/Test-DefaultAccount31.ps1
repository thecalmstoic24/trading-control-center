$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
public static class PairedVmAgentNativeV10 {
 public static bool SetForegroundWindow(System.IntPtr h) { return true; }
}
'@
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlV14.ps1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-Idle14'},$true)
Invoke-Expression $fn.Extent.Text
. (Join-Path $PSScriptRoot '../agent/DefaultAccount31.ps1')
function Check($ok,$message){if(-not $ok){throw $message}}
function Reset {
 foreach($name in @('Busy','ScheduledAction','PairCoordinatorActive','PendingVerification','CloseCheck','Worker14','BoundPeer','SingleBinding23','LocalOpened','EntryFault','CalibrationRequired20','ControlGateway')){Set-Variable -Name $name -Value $null -Scope Script}
 $script:current=[pscustomobject]@{Account='';Position='Flat';Root=$null;Handle=[IntPtr]1;AtmControlFound=$true;AtmControlEnabled=$true}
 $script:selections=0;$script:invalidations=0;$script:reads=0;$script:changeAt=0;$script:wrong=$false
 $script:LockedAccount='REAL-TARGET';$script:LockedQuantity=3;$script:ControlPreparedId='old'
}
function Get-ChartSnapshot {
 $script:reads++
 if($script:changeAt -eq $script:reads){$script:current.Position='1 L'}
 return $script:current
}
function Find-UiaById {param($Root,$AutomationId);Check ($AutomationId -ceq 'ChartTraderControlAccountSelector') 'Wrong UI control';return 'account-box'}
function Get-FirstAvailableAccount40 {param($Combo);return 'FIRST-ACCOUNT'}
function Select-NinjaAccount {param($Combo,$DesiredAccount);Check ($DesiredAccount -ceq 'FIRST-ACCOUNT') 'Wrong fallback account';$script:selections++;$script:current.Account=if($script:wrong){'OTHER'}else{'FIRST-ACCOUNT'};return $script:current.Account}
function Invalidate-Preparation {$script:invalidations++}
function Update-StateCache {}
Reset
$result=Select-DefaultAccount31
Check ($result.ok -and $result.changed -and $selections -eq 1 -and -not $script:Busy) 'Blank selection was not recovered'
Check ($script:LockedAccount -ceq 'REAL-TARGET' -and $script:LockedQuantity -eq 3) 'Saved trade target changed'
Check ($script:ControlPreparedId -ceq '' -and $invalidations -eq 1) 'Old preparation survived selection'
$result=Select-DefaultAccount31
Check ($result.ok -and -not $result.changed -and $selections -eq 1) 'Existing selection was replaced'
foreach($flag in @('Busy','ScheduledAction','PairCoordinatorActive','PendingVerification','CloseCheck','Worker14','BoundPeer','SingleBinding23','LocalOpened','EntryFault','CalibrationRequired20')){
 Reset;Set-Variable -Name $flag -Value $true -Scope Script
 $blocked=$false;try{Select-DefaultAccount31 | Out-Null}catch{$blocked=$true}
 Check ($blocked -and $selections -eq 0) ('Unsafe selection allowed: '+$flag)
}
foreach($flag in @('AtmControlFound','AtmControlEnabled')){
 Reset;$current.$flag=$false;$blocked=$false;try{Select-DefaultAccount31 | Out-Null}catch{$blocked=$true}
 Check ($blocked -and $selections -eq 0) ('Unavailable ATM accepted: '+$flag)
}
Reset;$current.Position='Unknown';$blocked=$false;try{Select-DefaultAccount31 | Out-Null}catch{$blocked=$true};Check ($blocked -and $selections -eq 0) 'Unknown position accepted'
Reset;$script:changeAt=2;$blocked=$false;try{Select-DefaultAccount31 | Out-Null}catch{$blocked=$true};Check ($blocked -and $selections -eq 0 -and -not $script:Busy) 'Changed position accepted'
Reset;$script:wrong=$true;$blocked=$false;try{Select-DefaultAccount31 | Out-Null}catch{$blocked=$true};Check ($blocked -and -not $script:Busy) 'Wrong selection readback accepted'
Reset;$script:changeAt=3;$blocked=$false;try{Select-DefaultAccount31 | Out-Null}catch{$blocked=$true};Check ($blocked -and -not $script:Busy) 'Non-flat FIRST-ACCOUNT accepted'
# Dispatch the new command through the production authenticated command handler.
Reset;$script:AgentStarted=$true
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlBridge.ps1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ControlCommand'},$true)
Invoke-Expression $fn.Extent.Text
$result=Invoke-ControlCommand ([pscustomobject]@{Command='ensure_default_account';Body='{}';AgeSeconds=0})
Check ($result.ok -and $result.changed -and $selections -eq 1) 'Command dispatch failed'
'PASS: blank-only FIRST-ACCOUNT recovery, saved target preservation, idle/Flat/ATM and pending-command guards, verified readback, busy cleanup and authenticated command dispatch.'
