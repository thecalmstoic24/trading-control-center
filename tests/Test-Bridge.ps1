$ErrorActionPreference='Stop'
# Extract actual bridge dispatch; stub Windows/UI functions, never click NinjaTrader.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlBridge.ps1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ControlCommand'},$true)
Invoke-Expression $function.Extent.Text
function Check($Condition,$Message){if(-not $Condition){throw $Message}}
function Get-ChartSnapshot {return @{Position=$script:position}}
function Assert-Idle14 { if($script:position -ne 'Flat'){throw 'Not flat'}; return @{Position=$script:position} }
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
# V14: a selected account/quantity must be in the discovered set; reject stale membership.
function Get-Accounts14 { return @('Sim101','MFF-123') }
function Save-Target14 { $script:savedTarget=@($script:LockedAccount,$script:LockedQuantity) }
function Process-AgentRequest { param($JsonLine); $script:Prepared=$true;return @{ok=$true} }
$script:controlDirectory=Join-Path ([IO.Path]::GetTempPath()) ('v14-test-'+[guid]::NewGuid().ToString('N'))
New-Item $script:controlDirectory -ItemType Directory | Out-Null
try {
 Reset-Test
 $script:Accounts14=@('Sim101','MFF-123');$script:AccountStamp14=[DateTime]::UtcNow
 $script:lockedValues=@{};$script:pairEnabled=@{}
 $body=@{account='MFF-123';quantity=3;prepareId=('c'*32);stopLoss=100;profit=200;ticker='MNQ'}
 Invoke-ControlCommand (Pending 'prepare' $body) | Out-Null
 Check ($script:LockedAccount -ceq 'MFF-123' -and $script:LockedQuantity -eq 3) 'Selected target was not locked'
 Check ($script:ControlPreparedId -ceq ('c'*32)) 'Verified target not prepared'
 foreach($quantity in @(0,-1,'2.5',1001)) {
  $body.quantity=$quantity;$rejected=$false
  try { Invoke-ControlCommand (Pending 'prepare' $body) | Out-Null } catch { $rejected=$true }
  Check $rejected 'Invalid quantity accepted'
 }
 $body.quantity=2;$body.account='OTHER';$rejected=$false
 try { Invoke-ControlCommand (Pending 'prepare' $body) | Out-Null } catch { $rejected=$true }
 Check $rejected 'Unmatched account accepted'
 $body.account='MFF-123';$script:AccountStamp14=[DateTime]::UtcNow.AddMinutes(-6);$rejected=$false
 try { Invoke-ControlCommand (Pending 'prepare' $body) | Out-Null } catch { $rejected=$true }
 Check $rejected 'Expired account list accepted'
 'V14 bridge: exact account membership, selected quantity, invalid quantity and stale list rejection passed.'
} finally { Remove-Item $script:controlDirectory -Recurse -Force }
# Discovery without any Airtable credentials must retain unmatched NinjaTrader accounts.
$extensionAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlV15.ps1'),[ref]$tokens,[ref]$errors)
$start=$extensionAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-Worker14'},$true)
Invoke-Expression $start.Extent.Text
$previousLocalAppData=$env:LOCALAPPDATA
$testData=Join-Path ([IO.Path]::GetTempPath()) ('v15-discovery-'+[guid]::NewGuid().ToString('N'))
try {
 $env:LOCALAPPDATA=$testData
 New-Item (Join-Path $testData 'TradingControlCenter/agent-data') -ItemType Directory -Force | Out-Null
 Reset-Test
 $script:ControlIdentity=@{Name='MFF-LOCDAO'}
 $script:Worker14=$null
 Start-Worker14 -Mode 'accounts'
 Check ($script:Accounts14 -ccontains 'MFF-123') 'Missing Airtable login hid a NinjaTrader account'
 Check ($script:MatchStatus15 -ceq 'unknown') 'Unavailable Airtable matching was reported as definitive'
 Check ($null -eq $script:Worker14) 'Missing token unnecessarily launched a worker'
 Invoke-ControlCommand (Pending 'post_trade' @{tradeId=('d'*32)}) | Out-Null
 Check ($script:Sync14 -match 'no verified Airtable match') 'Unmatched account incorrectly started an upload'
 'V15: credential-free discovery retains all accounts; unmatched post-trade sync is explicit.'
} finally { $env:LOCALAPPDATA=$previousLocalAppData; Remove-Item $testData -Recurse -Force }
