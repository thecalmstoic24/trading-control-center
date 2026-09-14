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

# Load the actual top-level import, then dispatch after a separate startup callback returns.
$imports=@($ast.EndBlock.Statements | Where-Object { $_.Extent.Text -match '^\. \(Join-Path \$PSScriptRoot .*Private-Network.ps1' })
Check ($imports.Count -eq 1) 'Private network helpers must load at script scope, not in the Shown callback'
$bridgeDirectory=(Resolve-Path (Join-Path $PSScriptRoot '../agent')).Path
$importText=$imports[0].Extent.Text.Replace('$PSScriptRoot',("'"+$bridgeDirectory.Replace("'","''")+"'"))
Invoke-Expression $importText
& { Test-PrivateAddress15 '100.91.78.85' | Out-Null }
Reset-Test
$script:ControlIdentity=@{Id='local'};$script:peerPortInput=@{};$script:pairEnabled=@{}
function Save-Target14 {}
$request=@{bindingId=('c'*32);peerAccount='ACTUAL-PEER';peerQuantity=3;peer=@{id='other';name='Other';host='100.91.78.85';port=8789;pin=('a'*64);token=('b'*64)}}
$result=Invoke-ControlCommand (Pending 'bind_peer' $request)
Check ($result.ok -and $script:PeerAccount14 -ceq 'ACTUAL-PEER' -and $script:PeerQuantity14 -eq 3) 'Private peer binding failed after startup scope ended'
$request.peer.host='45.32.199.44';$rejected=$false
try { Invoke-ControlCommand (Pending 'bind_peer' $request) | Out-Null } catch { $rejected=$_.Exception.Message -like 'Peer is not on*' }
Check $rejected 'Public peer address bypassed validation'
'V15 callback scope: later private peer binding succeeds with selected account/quantity; public addresses rejected.'

Reset-Test
$script:Worker14=$null;$script:PairCoordinatorActive=$true
Invoke-ControlCommand (Pending 'unbind_peer' @{}) | Out-Null
Check (-not $script:PairCoordinatorActive -and $null -eq $script:BoundPeer) 'Fresh local Flat did not clear stale pair flag on release'
Reset-Test
$script:ScheduledAction=@{Side='BUY'};$rejected=$false
try {Invoke-ControlCommand (Pending 'unbind_peer' @{}) | Out-Null} catch {$rejected=$true}
Check ($rejected -and $null -ne $script:BoundPeer) 'Release allowed a pending scheduled click'
'Flat release: stale active flag clears; scheduled click remains a blocker.'
