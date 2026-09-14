# Appended before ShowDialog by scripts/build_package.py. Core V10.4 functions remain intact.
Add-Type -Path (Join-Path $PSScriptRoot 'ControlGateway.cs')
$script:ControlGateway = $null
$script:ControlPreparedId = ''
$script:ControlRevision = 0
$script:ControlVersion = '11.0-preview.1'
$controlDirectory = Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
$identityPath = Join-Path $controlDirectory 'identity.clixml'
$script:ControlIdentity = Import-Clixml -LiteralPath $identityPath
$agentNameInput.Text = $script:ControlIdentity.Name
$form.Text = "Trading Agent $script:ControlVersion - $($script:ControlIdentity.Name) - Sim101 / Qty 1"
$heading.Text = "Trading Agent - $($script:ControlIdentity.Name)"

function Get-ControlStatus {
    $state = Get-CachedStatus
    $state['id'] = $script:ControlIdentity.Id
    $state['controlVersion'] = $script:ControlVersion
    $state['prepared'] = $script:Prepared -and -not $script:EntryFault -and -not $script:CloseCheck
    $state['prepareId'] = $script:ControlPreparedId
    $state['pairActive'] = $script:PairCoordinatorActive
    $state['busy'] = $script:Busy
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
    if ($Pending.AgeSeconds -gt 10 -and $Pending.Command -ne 'close') { throw 'Command expired in queue; prepare again.' }
    $request = $Pending.Body | ConvertFrom-Json
    if (-not $script:AgentStarted) { throw 'Start the agent and verify its peer connection first.' }
    if ($Pending.Command -eq 'close') {
        $script:ControlPreparedId = ''
        $script:ControlRevision++
        # Each VM receives its own close; the baseline continues partner close verification.
        Invoke-PairedClose
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
        if ($script:ControlIdentity.Id -cne 'vm-left') { throw 'Paired dashboard entry must be coordinated by VM left.' }
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
        $code = @{id=$script:ControlIdentity.Id; host=$script:ControlIdentity.HostAddress; port=8789;
                  pin=$script:ControlIdentity.Pin; token=$credential} | ConvertTo-Json -Compress
        [System.Windows.Forms.Clipboard]::SetText([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($code)))
        $connectionStatus.Text = 'Private code copied. Paste into the matching dashboard VM panel.'
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
    # Cached status is served on a TLS worker even while the UI is busy with NinjaTrader.
    $script:ControlGateway.Publish(((Get-ControlStatus) | ConvertTo-Json -Compress -Depth 5))
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
        $script:ControlGateway = [ControlGateway11]::new(8789, $certificate, $credential)
        $script:ControlGateway.Start()
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
