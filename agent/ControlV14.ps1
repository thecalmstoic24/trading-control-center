$script:SkippedResults23=@{}
$skipPath23=Join-Path $env:LOCALAPPDATA 'TradingControlCenter/agent-data/skipped-results.json'
if(Test-Path $skipPath23){foreach($id23 in @(Get-Content $skipPath23 -Raw | ConvertFrom-Json)){$script:SkippedResults23[[string]$id23]=$true}}
$script:SyncReceipt17 = $null
# V14 account targets are retained across restarts; never silently fall back to Sim101 for an active account.
$script:PeerAccount14 = 'Sim101'
$script:PeerQuantity14 = 1
$script:Accounts14 = @('Sim101')
$script:AccountMessage14 = 'Refresh accounts to discover NinjaTrader / Airtable matches.'
$script:Sync14 = 'Post-trade sync ready'
$script:Worker14 = $null
$script:WorkerMode14 = ''
$script:WorkerResult14 = ''
$script:WorkerStarted14 = [DateTime]::MinValue
$script:AccountStamp14 = [DateTime]::MinValue
$script:AccountRefreshId18 = ''
$script:DesktopLease14 = $null
$script:RetryAfter14=[DateTime]::UtcNow.AddSeconds(30)
$data14 = Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
New-Item -ItemType Directory -Path $data14 -Force | Out-Null
$receiptPath17=Join-Path $data14 'sync-done.json'
if(Test-Path $receiptPath17) { try { $script:SyncReceipt17=(Get-Content $receiptPath17 -Raw | ConvertFrom-Json).receipt } catch { $script:SyncReceipt17=$null } }
$script:TargetPath14 = Join-Path $data14 'trade-target.clixml'
if(Test-Path -LiteralPath $script:TargetPath14) {
    $saved14 = Import-Clixml -LiteralPath $script:TargetPath14
    $script:LockedAccount = [string]$saved14.Account
    $script:LockedQuantity = [int]$saved14.Quantity
    $script:PeerAccount14 = [string]$saved14.PeerAccount
    $script:PeerQuantity14 = [int]$saved14.PeerQuantity
}
function Save-Target14 {
    $temporary = $script:TargetPath14 + '.tmp'
    @{Account=$script:LockedAccount;Quantity=$script:LockedQuantity;PeerAccount=$script:PeerAccount14;PeerQuantity=$script:PeerQuantity14} | Export-Clixml -LiteralPath $temporary
    Move-Item -LiteralPath $temporary -Destination $script:TargetPath14 -Force
}
function Assert-Idle14 {
    if($script:Busy -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:PendingVerification -or $script:CloseCheck -or $script:Worker14) { throw 'VM is active, closing, or refreshing. Wait for completion.' }
    $snapshot=Get-ChartSnapshot
    if($snapshot.Position -cne 'Flat') { throw 'The current chart account must be Flat before changing settings.' }
    return $snapshot
}
function Get-Accounts14 {
    $snapshot=Assert-Idle14
    $combo=Find-UiaById -Root $snapshot.Root -AutomationId 'ChartTraderControlAccountSelector'
    if($null -eq $combo) { throw 'NinjaTrader Account dropdown not found.' }
    $names=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $expand=$null
    try {
        if(-not $combo.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expand)) { throw 'Account dropdown does not expose its list.' }
        $expand.Expand()
        Start-Sleep -Milliseconds 200
        $container=$null
        if($combo.TryGetCurrentPattern([System.Windows.Automation.ItemContainerPattern]::Pattern,[ref]$container)) {
            $item=$null
            for($i=0;$i -lt 2000;$i++) {
                $item=$container.FindItemByProperty($item,$null,$null)
                if($null -eq $item) { break }
                $name=$item.Current.Name
                if($name) { [void]$names.Add($name) }
                if($i -eq 1999) { throw 'Account list exceeds discovery limit.' }
            }
        }
        if($names.Count -eq 0) {
            $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
            foreach($item in $combo.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)) {
                if($item.Current.Name) { [void]$names.Add($item.Current.Name) }
            }
        }
        if($names.Count -eq 0) { throw 'No account items could be read. Keep the NinjaTrader chart visible.' }
        return @($names)
    } finally { if($expand) { $expand.Collapse() } }
}
function Test-SyncDesktopBusy15 {
    return [bool]($script:Busy -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:PendingVerification -or $script:CloseCheck -or $script:Worker14)
}
function Request-ManualSync15 {
    $directory=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
    $path=Join-Path $directory 'sync-manual.json'
    @{requestedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content ($path+'.tmp') -Encoding UTF8
    Move-Item ($path+'.tmp') $path -Force
    $script:Sync14='Sync requested; waiting for trading automation to release the desktop.'
    Start-ManualSync15
}
function Start-ManualSync15 {
    $directory=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
    $path=Join-Path $directory 'sync-manual.json'
    if(-not (Test-Path $path) -or (Test-SyncDesktopBusy15)) { return }
    $pending=Join-Path $directory 'sync-pending.json'
    $id=[guid]::NewGuid().ToString('N')
    if(Test-Path $pending) { $id=[string](Get-Content $pending -Raw | ConvertFrom-Json).tradeId }
    if($id -notmatch '^[a-f0-9]{32}$') { throw 'Pending sync ID is invalid. Check the sync log.' }
    Start-Worker14 -Mode 'export' -TradeId $id -FreshExport
    Remove-Item $path -ErrorAction SilentlyContinue
}
function Start-Worker14 {
    param([string]$Mode,[string]$TradeId='',[switch]$FreshExport,[string]$RefreshId='',[switch]$CaptureOnly)
    if($Mode -eq 'export' -and $script:SkippedResults23.ContainsKey($TradeId)){throw 'Results were skipped; export will not restart.'}
    if($Mode -in @('export','startup')) {
        if(Test-SyncDesktopBusy15) { throw 'Trading automation is using the desktop. Sync will wait.' }
    } else { $null=Assert-Idle14 }
    Invalidate-Preparation
    $script:ControlPreparedId=''
    $directory=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
    $request=@{CaptureOnly=[bool]$CaptureOnly;RefreshId=$RefreshId;Mode=$Mode;TradeId=$TradeId;FreshExport=[bool]$FreshExport;MasterAccount=$script:ControlIdentity.Name}
    $mappingPath=Join-Path $directory 'airtable-master.txt'
    if(Test-Path $mappingPath) { $request.MasterAccount=(Get-Content $mappingPath -Raw).Trim() }
    if($Mode -eq 'accounts') {
        $script:AccountRefreshId18='';$script:Accounts14=@('Sim101');$script:AccountStamp14=[DateTime]::MinValue
        $request.Accounts=@(Get-Accounts14)
        $script:AccountMessage14='Reading current Airtable account matches...'
    }
    $requestPath=Join-Path $directory 'worker-request.json'
    $script:WorkerResult14=Join-Path $directory 'worker-result.json'
    Remove-Item $script:WorkerResult14 -ErrorAction SilentlyContinue
    $request | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $worker=Join-Path $PSScriptRoot 'AirtableWorker.ps1'
    # Stop only desktop scanning while the export owns the desktop. TLS worker stays responsive.
    if($Mode -eq 'export') { $refreshTimer.Stop();$script:Sync14='Exporting NinjaTrader Accounts...' }
    $script:Busy=$true
    Set-ControlsForBusyState -Busy $true
    if($Mode -eq 'startup') { $script:Sync14='Checking Airtable login; complete setup if prompted.' }
    $script:WorkerTradeId23=$TradeId
    $script:WorkerMode14=$Mode
    $script:WorkerStarted14=[DateTime]::UtcNow
    try {
        $script:Worker14=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$worker+'"'),'-RequestPath',('"'+$requestPath+'"'),'-ResultPath',('"'+$script:WorkerResult14+'"')) -WindowStyle $(if($Mode -in @('setup','startup')){'Normal'}else{'Hidden'}) -PassThru
    } catch { $script:Busy=$false;Set-ControlsForBusyState -Busy $false;$refreshTimer.Start();throw }
}
function Poll-Worker14 {
    Poll-Upload22
    if(-not $script:Worker14) {
        $manualPath=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data\sync-manual.json'
        if(Test-Path $manualPath) {
            try { Start-ManualSync15 } catch { $script:Sync14='Sync failed: '+$_.Exception.Message }
            return
        }
        $retryPath=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data\sync-pending.json'
        if([DateTime]::UtcNow -gt $script:RetryAfter14 -and (Test-Path $retryPath)) {
            $script:RetryAfter14=[DateTime]::UtcNow.AddSeconds(30)
            try { $item=Get-Content $retryPath -Raw | ConvertFrom-Json; Start-Worker14 -Mode 'export' -TradeId $item.tradeId -CaptureOnly:([bool]$item.captureOnly) } catch { }
        }
        return
    }
    $deadline14=if($script:WorkerMode14 -in @('setup','startup')){600}else{120}
    if(-not $script:Worker14.HasExited -and ([DateTime]::UtcNow-$script:WorkerStarted14).TotalSeconds -lt $deadline14) { return }
    if(-not $script:Worker14.HasExited) { $script:Worker14.Kill() }
    $mode=$script:WorkerMode14
    $script:Worker14.Dispose();$script:Worker14=$null
    $script:Busy=$false
    Set-ControlsForBusyState -Busy $false
    $script:RetryAfter14=[DateTime]::UtcNow.AddSeconds(30)
    $refreshTimer.Start()
    try {
        if(-not (Test-Path $script:WorkerResult14)) { throw 'Worker timed out or stopped. Check the local sync log.' }
        $result=Get-Content $script:WorkerResult14 -Raw | ConvertFrom-Json
        if(-not $result.ok) { throw [string]$result.error }
        if($mode -eq 'export' -and $result.receipt) { $script:SyncReceipt17=$result.receipt }
        if($mode -eq 'accounts') {
            $script:Accounts14=@('Sim101')+@($result.accounts | Where-Object { $_ -cne 'Sim101' })
            $script:AccountRefreshId18=[string]$result.refreshId
            $script:AccountStamp14=[DateTime]::UtcNow
            $script:AccountMessage14=[string]$result.message
        } else { $script:Sync14=[string]$result.message }
        if($mode -eq 'startup') { $script:StartupFinished16=$true;Request-ManualSync15 }
    } catch {
        if($mode -eq 'accounts') { $script:AccountMessage14=$_.Exception.Message } else { $script:Sync14='Sync failed: '+$_.Exception.Message }
    }
}

# Upload immutable CSVs in capture order without owning the NinjaTrader desktop.
$script:Upload22=$null
$script:UploadRetry22=[DateTime]::MinValue
function Poll-Upload22 {
    $directory=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data\outbox22'
    if($script:Upload22) {
        if(-not $script:Upload22.HasExited){return}
        $script:Upload22.Dispose();$script:Upload22=$null
        try {
            $result=Get-Content ($script:UploadJob22+'.result') -Raw | ConvertFrom-Json
            if(-not $result.ok){throw $result.error}
            Remove-Item -LiteralPath $script:UploadJob22 -Force
        } catch { $script:Sync14='Background upload pending: '+$_.Exception.Message }
        $script:UploadRetry22=[DateTime]::UtcNow.AddSeconds(30)
    }
    if([DateTime]::UtcNow -lt $script:UploadRetry22){return}
    $job=Get-ChildItem -LiteralPath $directory -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if(-not $job){return}
    $script:UploadJob22=$job.FullName
    Remove-Item ($job.FullName+'.result') -ErrorAction SilentlyContinue
    $worker=Join-Path $PSScriptRoot 'AirtableWorker.ps1'
    $script:Upload22=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$worker+'"'),'-RequestPath',('"'+$job.FullName+'"'),'-ResultPath',('"'+$job.FullName+'.result"'))
}
