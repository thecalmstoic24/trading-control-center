function Get-FirstAvailableAccount40 {
    param($Combo)
    if($null -eq $Combo){throw 'Account selector was not found.'}
    $Combo.SetFocus()
    $expand=$null
    if($Combo.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expand)){
        $expand.Expand()
    }else{[System.Windows.Forms.SendKeys]::SendWait('%{DOWN}')}
    Start-Sleep -Milliseconds 250
    try {
        $container=$null
        if($Combo.TryGetCurrentPattern([System.Windows.Automation.ItemContainerPattern]::Pattern,[ref]$container)){
            $item=$null
            for($i=0;$i -lt 1000;$i++){
                $item=$container.FindItemByProperty($item,$null,$null)
                if($null -eq $item){break}
                if($item.Current.IsEnabled -and -not [string]::IsNullOrWhiteSpace($item.Current.Name)){return [string]$item.Current.Name}
            }
        }
        $items=$Combo.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
        foreach($item in $items){
            $selection=$null
            if($item.Current.IsEnabled -and -not $item.Current.IsOffscreen -and -not [string]::IsNullOrWhiteSpace($item.Current.Name) -and $item.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$selection)){return [string]$item.Current.Name}
        }
        throw 'No available account found in Chart 1. Queue remains waiting.'
    }finally{if($expand){$expand.Collapse()}else{[System.Windows.Forms.SendKeys]::SendWait('{ESC}')}}
}

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
        throw 'ATM controls are unavailable. Verify the chart is idle before selecting the first available account.'
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
        $first=Get-FirstAvailableAccount40 -Combo $combo
        $selected=Select-NinjaAccount -Combo $combo -DesiredAccount $first
        $verified=Get-ChartSnapshot
        if($selected -cne $first -or $verified.Account -cne $first -or $verified.Position -cne 'Flat') {
            throw 'the first available account selection did not verify Flat. Queue remains waiting.'
        }
        $script:StateCache=$verified
        $script:StateCacheUtc=[DateTime]::UtcNow
        $script:CacheError=''
        return @{ok=$true;changed=$true;message='Blank account box restored to the first available account; Flat verified.'}
    } finally {
        $script:Busy=$false
        Update-StateCache
        if($script:ControlGateway){$script:ControlGateway.Publish(((Get-ControlStatus) | ConvertTo-Json -Compress -Depth 5))}
    }
}
