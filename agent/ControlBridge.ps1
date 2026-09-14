# Appended before ShowDialog by scripts/build_package.py. Core V10.4 functions remain intact.
Add-Type -Path (Join-Path $PSScriptRoot 'ControlGateway.cs')
$script:ControlGateway = $null
$script:ControlPreparedId = ''
$script:BoundPeer = $null
$script:ControlRevision = 0
$script:ControlVersion = '15.0-preview.2'
$controlDirectory = Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
$identityPath = Join-Path $controlDirectory 'identity.clixml'
$script:ControlIdentity = Import-Clixml -LiteralPath $identityPath
$agentNameInput.Text = $script:ControlIdentity.Name
$form.Text = "Trading Agent $script:ControlVersion - $($script:ControlIdentity.Name) - V15 account selection"
$heading.Text = "Trading Agent - $($script:ControlIdentity.Name)"
$portInput.Value = 8789
$peerPortInput.Value = 8789
$secretLabel.Text = 'Managed key'
$pairHelp.Text = 'Choose this VM and its partner in the browser. Prepare & Verify assigns the encrypted peer connection automatically.'



# V12 uses pinned TLS for peer traffic, while retaining V10.4 arm/commit/click/monitor logic.
function Start-AgentListener {
    if ($script:AgentStarted) { return }
    $secretInput.Text = [Guid]::NewGuid().ToString('N')
    $script:AgentStarted = $true
    $agentToggleButton.Text = 'STOP AGENT'
    $agentNameInput.Enabled = $false
    $portInput.Enabled = $false
    $secretInput.Enabled = $false
    $showSecret.Enabled = $false
    $peerIpInput.ReadOnly = $true
    $peerPortInput.Enabled = $false
    $pairEnabled.Checked = $true
    $pairEnabled.Enabled = $false
    $agentStatus.Text = 'ONLINE - select and prepare the pair in the browser.'
    $agentStatus.ForeColor = [Drawing.Color]::Green
}
function Start-PeerTask {
    param([System.Collections.IDictionary]$Payload, [int]$TimeoutMilliseconds = 3000)
    if (-not $script:AgentStarted -or -not $script:BoundPeer) { throw 'Select and prepare this pair in the browser first.' }
    $body = [ordered]@{}
    foreach($key in $Payload.Keys) { $body[$key] = $Payload[$key] }
    $body['controlBindingId'] = $script:BoundPeer.bindingId
    $body['controlSenderId'] = $script:ControlIdentity.Id
    $kind = switch([string]$Payload.command) {
        'ping' {'peer_ping'}
        'monitor_status' {'peer_monitor'}
        'emergency_close' {'peer_close'}
        default {'peer'}
    }
    return [ControlGateway11]::Send($script:BoundPeer.host,8789,$script:BoundPeer.pin,$script:BoundPeer.token,
        $kind,($body | ConvertTo-Json -Compress -Depth 6),$TimeoutMilliseconds)
}
function Send-PeerRequest {
    param([System.Collections.IDictionary]$Payload, [int]$TimeoutMilliseconds = 15000)
    $task = Start-PeerTask -Payload $Payload -TimeoutMilliseconds $TimeoutMilliseconds
    $line = $task.GetAwaiter().GetResult()
    return ($line | ConvertFrom-Json)
}

function Get-ControlStatus {
    $state = Get-CachedStatus
    $state['closing'] = ($null -ne $script:CloseCheck)
    $state['bindingId'] = $(if($script:BoundPeer){$script:BoundPeer.bindingId}else{''})
    $state['id'] = $script:ControlIdentity.Id
    $state['controlVersion'] = $script:ControlVersion
    $state['prepared'] = $script:Prepared -and -not $script:EntryFault -and -not $script:CloseCheck
    $state['prepareId'] = $script:ControlPreparedId
    $state['pairActive'] = $script:PairCoordinatorActive
    $state['busy'] = $script:Busy -or ($null -ne $script:Worker14)
    $state['accounts'] = @($script:Accounts14)
    $state['accountMessage'] = $script:AccountMessage14
    $state['sync'] = $script:Sync14
    $state['selectedAccount'] = $script:LockedAccount
    $state['selectedQuantity'] = $script:LockedQuantity
    $state['ticker'] = $(if ($state.ok) { $script:StateCache.Ticker } else { $null })
    $state['quantity'] = $(if ($state.ok) { $script:StateCache.Quantity } else { $null })
    $state['stopLoss'] = $stopLossInput.Text
    $state['profit'] = $profitInput.Text
    $state['sampleUtc'] = $script:StateCacheUtc.ToString('o')
    $state['execution'] = $executionStatus.Text
    if (-not $script:AgentStarted) { $state.ok = $false; $state.message = 'Start the VM agent and Test Peer first.' }
    return $state
}

function Invoke-ControlCommand {
    param($Pending)
    if ($Pending.AgeSeconds -gt 10 -and $Pending.Command -notin @('close','peer_close')) { throw 'Command expired in queue; prepare again.' }
    $request = $Pending.Body | ConvertFrom-Json
    if (-not $script:AgentStarted) { throw 'Start the agent and verify its peer connection first.' }
    if ($Pending.Command -eq 'peer' -or $Pending.Command -eq 'peer_close') {
        if (-not $script:BoundPeer -or [string]$request.controlBindingId -cne $script:BoundPeer.bindingId -or
            [string]$request.controlSenderId -cne $script:BoundPeer.id) { throw 'Peer binding mismatch.' }
        $coreCommand = [string]$request.command
        if ($coreCommand -notin @('status','arm','commit','cancel_schedule','emergency_close')) { throw 'Unsupported TLS peer command.' }
        if ($Pending.Command -eq 'peer_close' -and $coreCommand -cne 'emergency_close') { throw 'Invalid priority command.' }
        if ($Pending.Command -eq 'peer_close') { $script:ControlGateway.CancelQueued() }
        $request | Add-Member -NotePropertyName token -NotePropertyValue $secretInput.Text -Force
        return Process-AgentRequest -JsonLine ($request | ConvertTo-Json -Compress -Depth 6)
    }
    if ($Pending.Command -eq 'accounts') { Start-Worker14 -Mode 'accounts'; return @{ok=$true;message='Reading account list.'} }
    if ($Pending.Command -eq 'post_trade') {
        if([string]$request.tradeId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid trade ID.' }
        $script:RetryTrade14=[string]$request.tradeId
        Start-Worker14 -Mode 'export' -TradeId $script:RetryTrade14
        return @{ok=$true;message='Export started.'}
    }
    if ($Pending.Command -eq 'bind_peer') {
        $null=Assert-Idle14
        if ($script:Busy -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:CloseCheck -or $script:PendingVerification) { throw 'VM is active or closing.' }
        $snapshot = Get-ChartSnapshot
        if($snapshot.Position -cne 'Flat') { throw 'Current chart account must be Flat.' }
        $peer = $request.peer
        if ([string]$request.bindingId -notmatch '^[a-f0-9]{32}$' -or [string]$peer.id -ceq $script:ControlIdentity.Id -or
            [string]$peer.token -notmatch '^[a-f0-9]{64}$' -or [string]$peer.pin -notmatch '^[a-f0-9]{64}$') { throw 'Invalid peer registration.' }
        $address = [Net.IPAddress]::Parse([string]$peer.host)
        if(-not (Test-PrivateAddress15 $address.ToString())) { throw 'Peer is not on the V15 private network. Update and register this VM again.' }
        if ([int]$peer.port -ne 8789) { throw 'Peer TLS port must be 8789.' }
        if([string]::IsNullOrWhiteSpace([string]$request.peerAccount) -or [int]$request.peerQuantity -lt 1 -or [int]$request.peerQuantity -gt 1000) { throw 'Invalid peer account or quantity.' }
        $script:PeerAccount14=[string]$request.peerAccount
        $script:PeerQuantity14=[int]$request.peerQuantity
        Save-Target14
        $script:BoundPeer = @{id=[string]$peer.id;name=[string]$peer.name;host=$address.ToString();port=8789;pin=[string]$peer.pin;token=[string]$peer.token;bindingId=[string]$request.bindingId}
        $script:ControlPreparedId = ''
        $script:LocalOpened = $false
        $script:CurrentPairId = ''
        Invalidate-Preparation
        $peerIpInput.Text = $address.ToString()
        $peerPortInput.Value = 8789
        $pairEnabled.Checked = $true
        return @{ok=$true;message='TLS peer bound; prepare required.'}
    }
    if ($Pending.Command -eq 'unbind_peer') {
        $null=Assert-Idle14
        if ($script:Busy -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:CloseCheck -or $script:PendingVerification) { throw 'VM is active or closing.' }
        $snapshot = Get-ChartSnapshot
        if($snapshot.Position -cne 'Flat') { throw 'Current chart account must be Flat.' }
        Invalidate-Preparation
        $script:ControlPreparedId = ''
        $script:BoundPeer = $null
        $script:CurrentPairId = ''
        $script:LocalOpened = $false
        $peerIpInput.Text = ''
        return @{ok=$true;message='Previous peer removed; VM is available for another pair.'}
    }
    if ($Pending.Command -eq 'close') {
        $script:ControlPreparedId = ''
        $script:ControlRevision++
        # Coordinator dispatches to each selected VM independently. Never follow
        # a retained peer address here: a newly created pair may not be bound yet.
        if ($script:Busy -or $script:Worker14) { throw 'Agent is busy; close outcome must be verified.' }
        $script:ScheduledAction = $null
        $script:PendingVerification = $null
        $script:PairCoordinatorActive = $false
        $script:PeerMonitorTask = $null
        $script:CloseCheck = $null
        $script:EntryFault = $true
        $script:RemoteCommandActive = $true
        try { Invoke-Close } finally { $script:RemoteCommandActive = $false; $script:Prepared = $false }
        if (-not [string]::IsNullOrWhiteSpace($script:LastError)) { throw $script:LastError }
        return @{ok=$true; message='Close requested. Observe both positions to verify.'}
    }
    if ($Pending.Command -eq 'invalidate') {
        $script:ControlPreparedId = ''
        Invalidate-Preparation
        return @{ok=$true; message='Preparation invalidated.'}
    }
    if ($script:Busy -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:CloseCheck) {
        throw 'Agent is busy, scheduled, active, or closing.'
    }
    if ($Pending.Command -eq 'prepare') {
        if(Test-Path (Join-Path $controlDirectory 'sync-pending.json')) { throw 'Post-trade sync is pending. Retry Airtable Sync before preparing another trade.' }
        $null=Assert-Idle14
        $account14=[string]$request.account
        $qty14=0
        if(-not [int]::TryParse([string]$request.quantity,[ref]$qty14) -or $qty14 -lt 1 -or $qty14 -gt 1000) { throw 'Quantity must be a whole number from 1 to 1000.' }
        if($account14 -cne 'Sim101') {
            if(([DateTime]::UtcNow-$script:AccountStamp14).TotalMinutes -gt 5 -or $script:Accounts14 -cnotcontains $account14) { throw 'Refresh accounts first. Choose a current Airtable / NinjaTrader match.' }
        }
        $available14=@(Get-Accounts14)
        if($available14 -cnotcontains $account14) { throw 'Selected account is no longer in NinjaTrader.' }
        $script:LockedAccount=$account14
        $script:LockedQuantity=$qty14
        Save-Target14
        $lockedValues.Text="Account: $account14`nQuantity: $qty14`nParameter: Currency"
        $script:ControlPreparedId = ''
        $prepareId = [string]$request.prepareId
        if ($prepareId -notmatch '^[0-9a-f]{32}$') { throw 'Invalid preparation ID.' }
        if ([decimal]$request.stopLoss -le 0 -or [decimal]$request.profit -le 0) { throw 'Currency amounts must be positive.' }
        $pairEnabled.Checked = $true
        # Remote preparation deliberately prepares ONLY this VM. Coordinator mirrors both requests.
        $payload = @{command='prepare'; token=$secretInput.Text; ticker=[string]$request.ticker; stopLoss=$request.stopLoss; profit=$request.profit}
        $answer = Process-AgentRequest -JsonLine ($payload | ConvertTo-Json -Compress)
        if (-not $answer.ok -or -not $script:Prepared) { throw ([string]$answer.message) }
        $script:ControlPreparedId = $prepareId
        return @{ok=$true; message='Prepared and verified locally.'}
    }
    if ($Pending.Command -eq 'entry') {
        if (-not $script:BoundPeer) { throw 'Prepare this selected pair first.' }
        if ([string]::IsNullOrWhiteSpace($script:ControlPreparedId) -or
            [string]$request.prepareId -cne $script:ControlPreparedId) { throw 'Preparation changed. Prepare both VMs again.' }
        $side = [string]$request.side
        if ($side -cne 'BUY' -and $side -cne 'SELL') { throw 'Invalid entry side.' }
        if (-not $pairEnabled.Checked) { throw 'PAIR MODE is required.' }
        # No replacement trading protocol: invoke the tested V10.4 paired entry function.
        $script:RemoteCommandActive = $true
        try { Invoke-PairedEntry -LocalSide $side } finally { $script:RemoteCommandActive = $false }
        $script:ControlPreparedId = ''
        return @{ok=$true; message='Pair entry accepted; monitor actual positions.'}
    }
    throw 'Unsupported control command.'
}

$controlGroup = New-Object System.Windows.Forms.GroupBox
$controlGroup.Text = 'Browser control - encrypted connection'
$controlGroup.Location = New-Object System.Drawing.Point(24, 845)
$controlGroup.Size = New-Object System.Drawing.Size(602, 100)
$form.Controls.Add($controlGroup)
$visibleHeight = [Math]::Min(970, [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 90)
$form.ClientSize = New-Object System.Drawing.Size(650, $visibleHeight)
$connectionButton = New-Object System.Windows.Forms.Button
$connectionButton.Text = 'COPY CONNECTION CODE'
$connectionButton.Location = New-Object System.Drawing.Point(15, 25)
$connectionButton.Size = New-Object System.Drawing.Size(220, 35)
$controlGroup.Controls.Add($connectionButton)
$connectionStatus = New-Object System.Windows.Forms.Label
$connectionStatus.Text = 'Starting encrypted browser connection...'
$connectionStatus.Location = New-Object System.Drawing.Point(15, 65)
$connectionStatus.AutoSize = $true
$controlGroup.Controls.Add($connectionStatus)

$connectionButton.Add_Click({
    try {
        if ($null -eq $script:ControlGateway) { throw 'Encrypted connection is not running. See the status below.' }
        $credential = [System.Net.NetworkCredential]::new('', $script:ControlIdentity.Token).Password
        $code = @{id=$script:ControlIdentity.Id; name=$script:ControlIdentity.Name; host=$script:ControlIdentity.HostAddress; port=8789;
                  pin=$script:ControlIdentity.Pin; token=$credential} | ConvertTo-Json -Compress
        [System.Windows.Forms.Clipboard]::SetDataObject([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($code)), $true, 5, 100)
        $connectionStatus.Text = 'Private code copied. Paste into Register VM in the browser.'
    } catch { Show-ErrorMessage -Message $_.Exception.Message }
})

# Editing the original UI invalidates browser preparation as well.
foreach ($box in @($tickerInput, $stopLossInput, $profitInput)) {
    $box.Add_TextChanged({ $script:ControlPreparedId = '' })
}
$pairEnabled.Add_CheckedChanged({ $script:ControlPreparedId = '' })
$controlTimer = New-Object System.Windows.Forms.Timer
$controlTimer.Interval = 50
$controlTimer.Add_Tick({
    if ($null -eq $script:ControlGateway) { return }
    Poll-Worker14
    # Cached status is served on a TLS worker even while the UI is busy with NinjaTrader.
    $script:ControlGateway.Publish(((Get-ControlStatus) | ConvertTo-Json -Compress -Depth 5))
    $cachedPeer = Get-CachedStatus
    $remaining = if ($cachedPeer.ok -and $script:AgentStarted) { [Math]::Max(0, 2800 - [int]$cachedPeer.sampleAgeMs) } else { 0 }
    $script:ControlGateway.PublishPeer(($cachedPeer | ConvertTo-Json -Compress -Depth 5), $remaining)
    $pending = $script:ControlGateway.Take()
    if ($null -eq $pending) { return }
    try { $answer = Invoke-ControlCommand -Pending $pending }
    catch { $answer = @{ok=$false; message=$_.Exception.Message} }
    $pending.Complete(($answer | ConvertTo-Json -Compress -Depth 5))
})
$form.Add_Shown({
    try {
        $certificate = Get-Item -LiteralPath ("Cert:\CurrentUser\My\" + $script:ControlIdentity.Thumbprint)
        $credential = [System.Net.NetworkCredential]::new('', $script:ControlIdentity.Token).Password
        . (Join-Path $PSScriptRoot '..\install\Private-Network.ps1')
        $privateAddress15=Get-PrivateAddress15
        if($privateAddress15 -cne $script:ControlIdentity.HostAddress) { throw 'Private network address changed. Rerun the installer and re-import this VM connection code.' }
        $script:ControlGateway = [ControlGateway11]::new(8789, $certificate, $credential, $privateAddress15)
        $script:ControlGateway.Start()
        Start-AgentListener
        $controlTimer.Start()
        $connectionStatus.Text = 'Encrypted browser connection listening on port 8789.'
    } catch {
        $connectionStatus.Text = 'Browser connection failed: ' + $_.Exception.Message
        $connectionStatus.ForeColor = [Drawing.Color]::Red
    }
})
$form.Add_FormClosed({
    $controlTimer.Stop()
    if ($null -ne $script:ControlGateway) { $script:ControlGateway.Dispose() }
})

$controlGroup.Height=190
$master14=New-Object System.Windows.Forms.TextBox
$master14.Location=New-Object Drawing.Point(15,95)
$master14.Size=New-Object Drawing.Size(210,25)
$masterPath14=Join-Path $controlDirectory 'airtable-master.txt'
$master14.Text=$script:ControlIdentity.Name
if(Test-Path $masterPath14) { $master14.Text=(Get-Content $masterPath14 -Raw).Trim() }
$controlGroup.Controls.Add($master14)
$saveMaster14=New-Object System.Windows.Forms.Button
$saveMaster14.Text='Save Master Account'
$saveMaster14.Location=New-Object Drawing.Point(240,92)
$saveMaster14.Size=New-Object Drawing.Size(175,30)
$saveMaster14.Add_Click({
 try {
  $null=Assert-Idle14
  if([string]::IsNullOrWhiteSpace($master14.Text)) { throw 'Enter Airtable Master Account.' }
  $master14.Text.Trim() | Set-Content $masterPath14 -Encoding UTF8
  $script:Accounts14=@('Sim101');$script:AccountStamp14=[DateTime]::MinValue
  Invalidate-Preparation;$script:ControlPreparedId=''
  $connectionStatus.Text='Master Account saved. Refresh accounts in the browser.'
 } catch { Show-ErrorMessage $_.Exception.Message }
})
$controlGroup.Controls.Add($saveMaster14)
$retry14=New-Object System.Windows.Forms.Button
$retry14.Text='Retry Airtable Sync'
$retry14.Location=New-Object Drawing.Point(15,132)
$retry14.Size=New-Object Drawing.Size(180,30)
$retry14.Add_Click({
 try {
  $pendingPath14=Join-Path $controlDirectory 'sync-pending.json'
  if(Test-Path $pendingPath14) { $script:RetryTrade14=(Get-Content $pendingPath14 -Raw | ConvertFrom-Json).tradeId }
  if(-not $script:RetryTrade14) { throw 'No pending post-trade export.' }
  Start-Worker14 -Mode 'export' -TradeId $script:RetryTrade14
 } catch { Show-ErrorMessage $_.Exception.Message }
})
$controlGroup.Controls.Add($retry14)

$setup14=New-Object System.Windows.Forms.Button
$setup14.Text='Airtable Setup'
$setup14.Location=New-Object Drawing.Point(240,132)
$setup14.Size=New-Object Drawing.Size(175,30)
$setup14.Add_Click({ try { Start-Worker14 -Mode 'setup' } catch { Show-ErrorMessage $_.Exception.Message } })
$controlGroup.Controls.Add($setup14)
