# Queue recovery only: never replace an existing selection or saved trade target.
function Select-DefaultAccount31 {
    $snapshot=Assert-Idle14
    if(-not [string]::IsNullOrWhiteSpace([string]$snapshot.Account)) {
        return @{ok=$true;changed=$false;message='Existing account selection retained.'}
    }
    if($script:BoundPeer -or $script:SingleBinding23 -or $script:LocalOpened -or $script:EntryFault) {
        throw 'Account box is blank, but prior trade state is unresolved. Verify the prior pair first.'
    }
    if($script:CalibrationRequired20) { throw 'Calibrate Chart 1 before automatic account selection.' }
    if(-not $snapshot.AtmControlFound -or -not $snapshot.AtmControlEnabled) {
        throw 'ATM controls are unavailable. Verify the chart is idle before selecting Sim101.'
    }
    # Invalidate any old preparation before touching the account dropdown.
    Invalidate-Preparation
    $script:ControlPreparedId=''
    $script:Busy=$true
    try {
        [PairedVmAgentNativeV10]::SetForegroundWindow($snapshot.Handle) | Out-Null
        $current=Get-ChartSnapshot
        if($current.Handle -ne $snapshot.Handle -or $current.Position -cne 'Flat') { throw 'Chart changed during account recovery.' }
        if(-not [string]::IsNullOrWhiteSpace([string]$current.Account)) {
            return @{ok=$true;changed=$false;message='Existing account selection retained.'}
        }
        $combo=Find-UiaById -Root $current.Root -AutomationId 'ChartTraderControlAccountSelector'
        $selected=Select-NinjaAccount -Combo $combo -DesiredAccount 'Sim101'
        $verified=Get-ChartSnapshot
        if($selected -cne 'Sim101' -or $verified.Account -cne 'Sim101' -or $verified.Position -cne 'Flat') {
            throw 'Sim101 selection did not verify Flat. Queue remains waiting.'
        }
        $script:StateCache=$verified
        $script:StateCacheUtc=[DateTime]::UtcNow
        $script:CacheError=''
        return @{ok=$true;changed=$true;message='Blank account box restored to Sim101; Flat verified.'}
    } finally {
        $script:Busy=$false
        Update-StateCache
        if($script:ControlGateway){$script:ControlGateway.Publish(((Get-ControlStatus) | ConvertTo-Json -Compress -Depth 5))}
    }
}
