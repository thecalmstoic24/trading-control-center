$ErrorActionPreference='Stop'
# Extract actual bridge dispatch; stub Windows/UI functions, never click NinjaTrader.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlBridge.ps1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ControlCommand'},$true)
Invoke-Expression $function.Extent.Text
function Check($Condition,$Message){if(-not $Condition){throw $Message}}
function Get-ChartSnapshot {return @{Position=$script:position}}
function Assert-V10Safety {param($Snapshot,$RequireFlat,$ExpectedTicker);if($RequireFlat -and $Snapshot.Position -ne 'Flat'){throw 'Not flat'}}
function Invalidate-Preparation {$script:Prepared=$false}
function Invoke-Close {$script:localCloses++}
function Invoke-PairedClose {throw 'Coordinator close must not follow a stored peer'}
function Process-AgentRequest {param($JsonLine);$script:coreCalls++;return @{ok=$true}}
function Reset-Test {
    $script:AgentStarted=$true;$script:Busy=$false;$script:ScheduledAction=$null;$script:PairCoordinatorActive=$false
    $script:CloseCheck=$null;$script:PendingVerification=$null;$script:LastError='';$script:ControlRevision=0
    $script:BoundPeer=@{id='old-peer';bindingId='a'*32};$script:position='Flat'
    $script:localCloses=0;$script:coreCalls=0;$script:cancellations=0
    $script:ControlGateway=New-Object PSObject
    $script:ControlGateway | Add-Member ScriptMethod CancelQueued {$script:cancellations++}
    $script:peerIpInput=@{Text='192.0.2.1'};$script:secretInput=@{Text='test-only'}
}
function Pending($Command,$Body){return @{AgeSeconds=0;Command=$Command;Body=($Body|ConvertTo-Json -Compress)}}
Reset-Test
Invoke-ControlCommand (Pending 'close' @{}) | Out-Null
Check ($script:localCloses -eq 1) 'Coordinator close did not close locally'
Check ($script:coreCalls -eq 0) 'Coordinator close followed another peer'
Reset-Test
$rejected=$false
try{Invoke-ControlCommand (Pending 'peer_close' @{controlBindingId=('b'*32);controlSenderId='old-peer';command='emergency_close'})|Out-Null}catch{$rejected=$true}
Check ($rejected -and $script:cancellations -eq 0 -and $script:coreCalls -eq 0) 'Old binding affected queued work'
Invoke-ControlCommand (Pending 'peer_close' @{controlBindingId=('a'*32);controlSenderId='old-peer';command='emergency_close'})|Out-Null
Check ($script:cancellations -eq 1 -and $script:coreCalls -eq 1) 'Valid partner close did not retain priority'
Reset-Test
Invoke-ControlCommand (Pending 'unbind_peer' @{})|Out-Null
Check ($null -eq $script:BoundPeer -and $script:peerIpInput.Text -eq '') 'Release retained old peer'
Reset-Test
$script:position='1 L';$rejected=$false
try{Invoke-ControlCommand (Pending 'unbind_peer' @{})|Out-Null}catch{$rejected=$true}
Check ($rejected -and $null -ne $script:BoundPeer) 'Release accepted an open position'
'Bridge isolation: local-only coordinator close, stale-binding rejection, valid partner priority and flat-only unbind passed.'
