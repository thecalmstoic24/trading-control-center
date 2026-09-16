$ErrorActionPreference = 'Stop'

# NinjaTrader Chart - 1 layout recorded on the test VM.
$WindowTitlePrefix = 'Chart - 1'
$WindowX = 64
$WindowY = 30
$WindowWidth = 780
$WindowHeight = 460
$EditRelativeX = 735
$EditRelativeY = 353

# v10.4 is deliberately limited to the NinjaTrader simulation account and one contract.
$LockedAccount = 'Sim101'
$LockedQuantity = 1
$RequiredParameterType = 'Currency'
$ExpectedPosition = 'Flat'
$VerificationTimeoutSeconds = 6

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PairedVmAgentNativeV10
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    public static IntPtr[] FindWindows(string prefix)
    {
        var matches = new List<IntPtr>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored)
        {
            if (!IsWindowVisible(hWnd)) return true;
            var title = GetTitle(hWnd);
            if (title.Equals(prefix, StringComparison.OrdinalIgnoreCase) ||
                title.StartsWith(prefix + " -", StringComparison.OrdinalIgnoreCase))
            {
                matches.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return matches.ToArray();
    }

    public static string GetTitle(IntPtr hWnd)
    {
        var text = new StringBuilder(1024);
        GetWindowText(hWnd, text, text.Capacity);
        return text.ToString();
    }

    public static int[] ReadWindowRect(IntPtr hWnd)
    {
        RECT rect;
        if (!GetWindowRect(hWnd, out rect)) throw new InvalidOperationException("Cannot read the window coordinates.");
        return new int[] { rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top };
    }

    public static void LeftClick()
    {
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
}
'@

function Find-UiaById {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$AutomationId
    )
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $AutomationId
    )
    return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Get-UiaText {
    param([System.Windows.Automation.AutomationElement]$Element)
    if ($null -eq $Element) { return $null }

    try {
        $pattern = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
            return ([System.Windows.Automation.ValuePattern]$pattern).Current.Value.Trim()
        }
    } catch { }

    try {
        $pattern = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern, [ref]$pattern)) {
            $selection = ([System.Windows.Automation.SelectionPattern]$pattern).Current.GetSelection()
            if ($selection.Count -gt 0) { return $selection[0].Current.Name.Trim() }
        }
    } catch { }

    try { return $Element.Current.Name.Trim() } catch { return $null }
}

function Set-UiaValue {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [string]$Value,
        [string]$Label
    )
    if ($null -eq $Element) { throw "$Label field was not found." }

    $pattern = $null
    if (-not $Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        throw "$Label field does not support direct input."
    }
    if (([System.Windows.Automation.ValuePattern]$pattern).Current.IsReadOnly) {
        throw "$Label field is read-only."
    }

    ([System.Windows.Automation.ValuePattern]$pattern).SetValue($Value)
    Start-Sleep -Milliseconds 80
}

function Select-Currency {
    param([System.Windows.Automation.AutomationElement]$Combo)
    if ($null -eq $Combo) { throw 'Parameter Type control was not found.' }

    $current = Get-UiaText -Element $Combo
    if ($current -ceq $RequiredParameterType) { return }

    try {
        $expand = $null
        if ($Combo.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$expand)) {
            ([System.Windows.Automation.ExpandCollapsePattern]$expand).Expand()
            Start-Sleep -Milliseconds 150
        }
    } catch { }

    $Combo.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 180

    $selected = Get-UiaText -Element $Combo
    if ($selected -cne $RequiredParameterType) {
        throw "Parameter Type could not be changed to Currency. Found '$selected'."
    }
}

function Select-NinjaAccount {
    param(
        [System.Windows.Automation.AutomationElement]$Combo,
        [string]$DesiredAccount
    )
    if ($null -eq $Combo) { throw 'Account selector was not found.' }

    $current = Get-UiaText -Element $Combo
    if ($current -ceq $DesiredAccount) { return $current }

    $Combo.SetFocus()
    $expandPattern = $null
    if ($Combo.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$expandPattern)) {
        ([System.Windows.Automation.ExpandCollapsePattern]$expandPattern).Expand()
    } else {
        [System.Windows.Forms.SendKeys]::SendWait('%{DOWN}')
    }
    Start-Sleep -Milliseconds 250

    $selected = $false
    try {
        $itemContainer = $null
        if ($Combo.TryGetCurrentPattern([System.Windows.Automation.ItemContainerPattern]::Pattern, [ref]$itemContainer)) {
            $accountItem = ([System.Windows.Automation.ItemContainerPattern]$itemContainer).FindItemByProperty(
                $null,
                [System.Windows.Automation.AutomationElement]::NameProperty,
                $DesiredAccount
            )
            if ($null -ne $accountItem) {
                try {
                    $virtualized = $null
                    if ($accountItem.TryGetCurrentPattern([System.Windows.Automation.VirtualizedItemPattern]::Pattern, [ref]$virtualized)) {
                        ([System.Windows.Automation.VirtualizedItemPattern]$virtualized).Realize()
                    }
                } catch { }
                $selectionItem = $null
                if ($accountItem.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionItem)) {
                    ([System.Windows.Automation.SelectionItemPattern]$selectionItem).Select()
                    $selected = $true
                }
            }
        }
    } catch { }

    $nameCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        $DesiredAccount
    )
    if (-not $selected) {
        $candidates = $Combo.FindAll([System.Windows.Automation.TreeScope]::Descendants, $nameCondition)
        if ($candidates.Count -eq 0) {
            $candidates = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                $nameCondition
            )
        }
        foreach ($candidate in $candidates) {
            try {
                if ($candidate.Current.IsOffscreen) { continue }
                $selectionItem = $null
                if ($candidate.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionItem)) {
                    ([System.Windows.Automation.SelectionItemPattern]$selectionItem).Select()
                    $selected = $true
                    break
                }
            } catch { }
        }
    }

    try {
        if ($null -ne $expandPattern) { ([System.Windows.Automation.ExpandCollapsePattern]$expandPattern).Collapse() }
    } catch { }

    if (-not $selected) {
        [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        throw "Locked account '$DesiredAccount' was not found in the NinjaTrader Account dropdown."
    }

    Start-Sleep -Milliseconds 350
    $confirmed = Get-UiaText -Element $Combo
    if ($confirmed -cne $DesiredAccount) {
        throw "Account verification failed: expected '$DesiredAccount', found '$confirmed'."
    }
    return $confirmed
}

function Set-NinjaTicker {
    param(
        [System.Windows.Automation.AutomationElement]$TickerElement,
        [string]$RequestedTicker,
        [IntPtr]$ChartHandle
    )
    if ([string]::IsNullOrWhiteSpace($RequestedTicker)) { throw 'Ticker symbol is required.' }
    $RequestedTicker = $RequestedTicker.Trim()

    Set-UiaValue -Element $TickerElement -Value $RequestedTicker -Label 'Ticker'
    $TickerElement.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 1000

    $refreshedRoot = [System.Windows.Automation.AutomationElement]::FromHandle($ChartHandle)
    $refreshedTicker = Find-UiaById -Root $refreshedRoot -AutomationId 'ChartWindowInstrumentSelectorEdit'
    $resolvedTicker = Get-UiaText -Element $refreshedTicker
    if ([string]::IsNullOrWhiteSpace($resolvedTicker)) { throw "NinjaTrader did not resolve ticker '$RequestedTicker'." }
    if (-not $resolvedTicker.StartsWith($RequestedTicker, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Ticker verification failed: requested '$RequestedTicker', NinjaTrader shows '$resolvedTicker'."
    }
    return $resolvedTicker
}

function Test-NumberEquals {
    param([string]$Actual, [decimal]$Expected)
    $parsed = 0D
    $clean = if ($null -eq $Actual) { '' } else { $Actual -replace '[,$\s]', '' }
    $valid = [decimal]::TryParse(
        $clean,
        [System.Globalization.NumberStyles]::Any,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )
    return ($valid -and $parsed -eq $Expected)
}

function Invoke-UiaButton {
    param(
        [System.Windows.Automation.AutomationElement]$Button,
        [string]$Label
    )
    if ($null -eq $Button) { throw "$Label button was not found." }
    $pattern = $null
    if (-not $Button.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        throw "$Label button cannot be activated."
    }
    ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
}

function Close-ParametersWithoutSaving {
    param([System.Windows.Automation.AutomationElement]$Modal)
    if ($null -eq $Modal) { return }
    try {
        $cancel = Find-UiaById -Root $Modal -AutomationId 'ATMStrategyPropertiesCancelButton'
        Invoke-UiaButton -Button $cancel -Label 'Cancel'
    } catch {
        try {
            $Modal.SetFocus()
            [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        } catch { }
    }
}

function Wait-ForParametersWindow {
    param([int]$TimeoutMilliseconds = 2000)
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        'ATMStrategyProperties'
    )
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $found = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            $condition
        )
        if ($null -ne $found) { return $found }
        Start-Sleep -Milliseconds 80
    }
    return $null
}

function Get-ChartSnapshot {
    $handle = Get-CalibratedChart20
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
    $atmElement = Find-UiaById -Root $root -AutomationId 'ChartTraderControlATMStrategySelector'
    $atmEnabled = $false
    if ($null -ne $atmElement) {
        try { $atmEnabled = $atmElement.Current.IsEnabled } catch { $atmEnabled = $false }
    }

    return [pscustomobject]@{
        Handle = $handle
        Root = $root
        WindowTitle = [PairedVmAgentNativeV10]::GetTitle($handle)
        Account = Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlAccountSelector')
        Ticker = Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartWindowInstrumentSelectorEdit')
        Quantity = Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlQuantityEdit')
        AtmControlFound = ($null -ne $atmElement)
        AtmControlEnabled = $atmEnabled
        Position = Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlPositionQuantityText')
    }
}

function Get-PositionOnly {
    try {$handle=Get-CalibratedChart20;$root=[System.Windows.Automation.AutomationElement]::FromHandle($handle)} catch {return $null}
    return Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlPositionQuantityText')
}

function Assert-V10Safety {
    param(
        [pscustomobject]$Snapshot,
        [bool]$RequireFlat,
        [string]$ExpectedTicker
    )
    if ($Snapshot.Account -cne $LockedAccount) {
        throw "BLOCKED: prepared account is '$LockedAccount'. NinjaTrader shows '$($Snapshot.Account)'."
    }
    if ($RequireFlat -and -not (Test-NumberEquals -Actual $Snapshot.Quantity -Expected $LockedQuantity)) {
        throw "BLOCKED: prepared order quantity is $LockedQuantity. NinjaTrader shows '$($Snapshot.Quantity)'."
    }
    if ([string]::IsNullOrWhiteSpace($Snapshot.Ticker)) { throw 'BLOCKED: The ticker could not be read.' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedTicker) -and
        -not $Snapshot.Ticker.StartsWith($ExpectedTicker, [StringComparison]::OrdinalIgnoreCase)) {
        throw "BLOCKED: Ticker changed after preparation. Expected '$ExpectedTicker', found '$($Snapshot.Ticker)'."
    }
    if ($RequireFlat -and $Snapshot.Position -cne $ExpectedPosition) {
        throw "BLOCKED: Entry is allowed only while Flat. Current position shows '$($Snapshot.Position)'."
    }
    if ($RequireFlat -and (-not $Snapshot.AtmControlFound -or -not $Snapshot.AtmControlEnabled)) {
        throw 'BLOCKED: The ATM Strategy control was not found or is disabled.'
    }
}

function Prepare-Trade {
    param(
        [string]$Ticker,
        [decimal]$StopLoss,
        [decimal]$Profit
    )

    $chartHandle = Get-CalibratedChart20
    [PairedVmAgentNativeV10]::SetForegroundWindow($chartHandle) | Out-Null
    Start-Sleep -Milliseconds 300
    $chartRoot = [System.Windows.Automation.AutomationElement]::FromHandle($chartHandle)

    $currentPosition = Get-UiaText -Element (Find-UiaById -Root $chartRoot -AutomationId 'ChartTraderControlPositionQuantityText')
    if ($currentPosition -cne $ExpectedPosition) {
        throw "The currently displayed account must be Flat before changing settings. Found '$currentPosition'."
    }

    $accountSelector = Find-UiaById -Root $chartRoot -AutomationId 'ChartTraderControlAccountSelector'
    $selectedAccount = Select-NinjaAccount -Combo $accountSelector -DesiredAccount $LockedAccount

    $tickerElement = Find-UiaById -Root $chartRoot -AutomationId 'ChartWindowInstrumentSelectorEdit'
    $resolvedTicker = Set-NinjaTicker -TickerElement $tickerElement -RequestedTicker $Ticker -ChartHandle $chartHandle

    $chartRoot = [System.Windows.Automation.AutomationElement]::FromHandle($chartHandle)
    $confirmedAccount = Get-UiaText -Element (Find-UiaById -Root $chartRoot -AutomationId 'ChartTraderControlAccountSelector')
    if ($confirmedAccount -cne $LockedAccount) {
        throw "Account changed unexpectedly: expected '$LockedAccount', found '$confirmedAccount'."
    }

    $position = Get-UiaText -Element (Find-UiaById -Root $chartRoot -AutomationId 'ChartTraderControlPositionQuantityText')
    if ($position -cne $ExpectedPosition) { throw "'$LockedAccount' must be Flat for '$resolvedTicker'. Found '$position'." }

    $mainQuantity = Find-UiaById -Root $chartRoot -AutomationId 'ChartTraderControlQuantityEdit'
    Set-UiaValue -Element $mainQuantity -Value ([string]$LockedQuantity) -Label 'Chart Trader order quantity'
    $readMainQuantity = Get-UiaText -Element $mainQuantity
    if (-not (Test-NumberEquals -Actual $readMainQuantity -Expected $LockedQuantity)) {
        throw "Chart Trader order quantity verification failed. Expected $LockedQuantity, found '$readMainQuantity'."
    }

    $modal = Open-CalibratedAtm26 -Handle $chartHandle -Root $chartRoot

    $saved = $false
    try {
        $topQuantityContainer = Find-UiaById -Root $modal -AutomationId 'ATMStrategyPropertiesQuantityUpDown'
        $topQuantity = Find-UiaById -Root $topQuantityContainer -AutomationId 'ATMStrategyPropertiesQuantityEdit'
        $parameterType = Find-UiaById -Root $modal -AutomationId 'ATMStrategyPropertiesParameterTypeSelector'
        $stopLossField = Find-UiaById -Root $modal -AutomationId 'ATMStrategyPropertiesStopLossPriceEdit'
        $profitField = Find-UiaById -Root $modal -AutomationId 'ATMStrategyPropertiesProfitTargetPriceEdit'

        Set-UiaValue -Element $topQuantity -Value ([string]$LockedQuantity) -Label 'Order quantity'
        Select-Currency -Combo $parameterType
        Set-UiaValue -Element $stopLossField -Value $StopLoss.ToString([System.Globalization.CultureInfo]::InvariantCulture) -Label 'Stop loss'
        Set-UiaValue -Element $profitField -Value $Profit.ToString([System.Globalization.CultureInfo]::InvariantCulture) -Label 'Profit'

        $readOrderQuantity = Get-UiaText -Element $topQuantity
        $readParameterType = Get-UiaText -Element $parameterType
        $readStopLoss = Get-UiaText -Element $stopLossField
        $readProfit = Get-UiaText -Element $profitField

        if (-not (Test-NumberEquals -Actual $readOrderQuantity -Expected $LockedQuantity)) {
            throw "Order quantity verification failed. Expected $LockedQuantity, found '$readOrderQuantity'."
        }
        if ($readParameterType -cne $RequiredParameterType) { throw "Parameter Type verification failed. Found '$readParameterType'." }
        if (-not (Test-NumberEquals -Actual $readStopLoss -Expected $StopLoss)) { throw "Stop loss verification failed. Found '$readStopLoss'." }
        if (-not (Test-NumberEquals -Actual $readProfit -Expected $Profit)) { throw "Profit verification failed. Found '$readProfit'." }

        $okButton = Find-UiaById -Root $modal -AutomationId 'ATMStrategyPropertiesOKButton'
        Invoke-UiaButton -Button $okButton -Label 'OK'
        $saved = $true
    } finally {
        if (-not $saved) { Close-ParametersWithoutSaving -Modal $modal }
    }

    Start-Sleep -Milliseconds 300
    $finalSnapshot = Get-ChartSnapshot
    Assert-V10Safety -Snapshot $finalSnapshot -RequireFlat $true -ExpectedTicker $Ticker
    return [pscustomobject]@{
        Snapshot = $finalSnapshot
        Account = $LockedAccount
        Ticker = $resolvedTicker
        Quantity = $LockedQuantity
        ParameterType = $RequiredParameterType
        StopLoss = $StopLoss
        Profit = $Profit
    }
}

function Arm-ChartTraderButton {
    param(
        [pscustomobject]$Snapshot,
        [string]$AutomationId,
        [string]$ExpectedName
    )
    # Prepare focus, live bounds, and cursor position before the shared execution time.
    $null=Get-CalibratedChart20
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [PairedVmAgentNativeV10]::SetForegroundWindow($Snapshot.Handle) | Out-Null
        Start-Sleep -Milliseconds 100
        if ([PairedVmAgentNativeV10]::GetForegroundWindow() -eq $Snapshot.Handle) { break }
    }
    if ([PairedVmAgentNativeV10]::GetForegroundWindow() -ne $Snapshot.Handle) {
        throw "$ExpectedName was not clicked because NinjaTrader could not become the foreground window."
    }

    # Reacquire the live element after activation so stale screen bounds are never used.
    $freshRoot = [System.Windows.Automation.AutomationElement]::FromHandle($Snapshot.Handle)
    $button = Find-UiaById -Root $freshRoot -AutomationId $AutomationId
    if ($null -eq $button) { throw "$ExpectedName button was not found." }
    if (-not $button.Current.IsEnabled) { throw "$ExpectedName button is disabled." }
    if ($button.Current.IsOffscreen) { throw "$ExpectedName button is off-screen." }

    $bounds = $button.Current.BoundingRectangle
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw "$ExpectedName button has no clickable screen region." }
    $x = [int]($bounds.Left + ($bounds.Width / 2))
    $y = [int]($bounds.Top + ($bounds.Height / 2))

    [PairedVmAgentNativeV10]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 100
    if ([PairedVmAgentNativeV10]::GetForegroundWindow() -ne $Snapshot.Handle) {
        throw "$ExpectedName was not clicked because focus changed during the safety hover."
    }
    return [pscustomobject]@{
        Handle = $Snapshot.Handle
        X = $x
        Y = $y
        AutomationId = $AutomationId
        ExpectedName = $ExpectedName
    }
}

function Fire-ArmedChartTraderClick {
    param([pscustomobject]$ArmedClick)
    if ($null -eq $ArmedClick) { throw 'No NinjaTrader button is armed.' }
    if ([PairedVmAgentNativeV10]::GetForegroundWindow() -ne $ArmedClick.Handle) {
        throw "$($ArmedClick.ExpectedName) was not clicked because NinjaTrader lost foreground focus after arming."
    }
    [PairedVmAgentNativeV10]::SetCursorPos([int]$ArmedClick.X, [int]$ArmedClick.Y) | Out-Null
    [PairedVmAgentNativeV10]::LeftClick()
}

function Click-ChartTraderButton {
    param(
        [pscustomobject]$Snapshot,
        [string]$AutomationId,
        [string]$ExpectedName
    )
    $armed = Arm-ChartTraderButton -Snapshot $Snapshot -AutomationId $AutomationId -ExpectedName $ExpectedName
    Fire-ArmedChartTraderClick -ArmedClick $armed
}

function Wait-ForPosition {
    param([string]$ExpectedMode)
    $deadline = [DateTime]::UtcNow.AddSeconds($VerificationTimeoutSeconds)
    $lastPosition = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $lastPosition = Get-PositionOnly
        if ($ExpectedMode -eq 'OPEN' -and -not [string]::IsNullOrWhiteSpace($lastPosition) -and $lastPosition -cne 'Flat') {
            return Get-ChartSnapshot
        }
        if ($ExpectedMode -eq 'FLAT' -and $lastPosition -ceq 'Flat') { return Get-ChartSnapshot }
    }
    throw "NinjaTrader did not reach '$ExpectedMode' within $VerificationTimeoutSeconds seconds. Last position: '$lastPosition'. Check for an order-confirmation or rejection window."
}

function Show-ErrorMessage {
    param([string]$Message, [string]$Title = 'Paired VM Agent v10.4')
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Busy = $false
$script:Prepared = $false
$script:PreparedTicker = $null
$script:LastError = $null
$script:RemoteCommandActive = $false
$script:TcpListener = $null
$script:AgentStarted = $false
$script:LastCommand = 'None'
$script:LastCommandTime = $null
$script:ScheduledAction = $null
$script:PairCoordinatorActive = $false
$script:PairEverOpened = $false
$script:PairGraceDeadlineUtc = $null
$script:LastPeerPollUtc = [DateTime]::MinValue
$script:PendingVerification = $null

$form = New-Object System.Windows.Forms.Form
$form.Text = 'NinjaTrader Paired VM Agent v10.4 - Sim101 / Qty 1'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(650, 840)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.AutoScroll = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$heading = New-Object System.Windows.Forms.Label
$heading.Text = 'NinjaTrader Paired VM Agent v10.4'
$heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$heading.Location = New-Object System.Drawing.Point(24, 16)
$heading.AutoSize = $true
$form.Controls.Add($heading)

$lockNotice = New-Object System.Windows.Forms.Label
$lockNotice.Text = 'Select account and quantity in the browser. Parameters use Currency.'
$lockNotice.ForeColor = [System.Drawing.Color]::Firebrick
$lockNotice.Location = New-Object System.Drawing.Point(27, 52)
$lockNotice.AutoSize = $true
$form.Controls.Add($lockNotice)

$agentGroup = New-Object System.Windows.Forms.GroupBox
$agentGroup.Text = 'Remote Agent and Pair'
$agentGroup.Location = New-Object System.Drawing.Point(24, 80)
$agentGroup.Size = New-Object System.Drawing.Size(602, 235)
$form.Controls.Add($agentGroup)

$agentNameLabel = New-Object System.Windows.Forms.Label
$agentNameLabel.Text = 'Agent name'
$agentNameLabel.Location = New-Object System.Drawing.Point(18, 30)
$agentNameLabel.Size = New-Object System.Drawing.Size(90, 24)
$agentGroup.Controls.Add($agentNameLabel)

$agentNameInput = New-Object System.Windows.Forms.TextBox
$agentNameInput.Location = New-Object System.Drawing.Point(112, 27)
$agentNameInput.Size = New-Object System.Drawing.Size(180, 28)
$agentNameInput.Text = $env:COMPUTERNAME
$agentGroup.Controls.Add($agentNameInput)

$portLabel = New-Object System.Windows.Forms.Label
$portLabel.Text = 'Port'
$portLabel.Location = New-Object System.Drawing.Point(310, 30)
$portLabel.Size = New-Object System.Drawing.Size(45, 24)
$agentGroup.Controls.Add($portLabel)

$portInput = New-Object System.Windows.Forms.NumericUpDown
$portInput.Location = New-Object System.Drawing.Point(357, 27)
$portInput.Size = New-Object System.Drawing.Size(90, 28)
$portInput.Minimum = 1024
$portInput.Maximum = 65535
$portInput.Value = 8787
$agentGroup.Controls.Add($portInput)

$agentToggleButton = New-Object System.Windows.Forms.Button
$agentToggleButton.Text = 'START AGENT'
$agentToggleButton.Location = New-Object System.Drawing.Point(462, 25)
$agentToggleButton.Size = New-Object System.Drawing.Size(120, 34)
$agentToggleButton.BackColor = [System.Drawing.Color]::SeaGreen
$agentToggleButton.ForeColor = [System.Drawing.Color]::White
$agentToggleButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$agentGroup.Controls.Add($agentToggleButton)

$secretLabel = New-Object System.Windows.Forms.Label
$secretLabel.Text = 'Shared secret'
$secretLabel.Location = New-Object System.Drawing.Point(18, 70)
$secretLabel.Size = New-Object System.Drawing.Size(95, 24)
$agentGroup.Controls.Add($secretLabel)

$secretInput = New-Object System.Windows.Forms.TextBox
$secretInput.Location = New-Object System.Drawing.Point(112, 67)
$secretInput.Size = New-Object System.Drawing.Size(335, 28)
$secretInput.UseSystemPasswordChar = $true
$agentGroup.Controls.Add($secretInput)

$showSecret = New-Object System.Windows.Forms.CheckBox
$showSecret.Text = 'Show'
$showSecret.Location = New-Object System.Drawing.Point(462, 68)
$showSecret.Size = New-Object System.Drawing.Size(75, 26)
$agentGroup.Controls.Add($showSecret)

$agentStatus = New-Object System.Windows.Forms.Label
$agentStatus.Text = 'Stopped — enter the same secret on both VM agents.'
$agentStatus.Location = New-Object System.Drawing.Point(18, 198)
$agentStatus.Size = New-Object System.Drawing.Size(564, 25)
$agentStatus.ForeColor = [System.Drawing.Color]::DimGray
$agentGroup.Controls.Add($agentStatus)

$pairEnabled = New-Object System.Windows.Forms.CheckBox
$pairEnabled.Text = 'PAIR MODE'
$pairEnabled.Location = New-Object System.Drawing.Point(18, 112)
$pairEnabled.Size = New-Object System.Drawing.Size(110, 26)
$pairEnabled.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$agentGroup.Controls.Add($pairEnabled)

$peerIpLabel = New-Object System.Windows.Forms.Label
$peerIpLabel.Text = 'Peer IP'
$peerIpLabel.Location = New-Object System.Drawing.Point(135, 114)
$peerIpLabel.Size = New-Object System.Drawing.Size(60, 24)
$agentGroup.Controls.Add($peerIpLabel)

$peerIpInput = New-Object System.Windows.Forms.TextBox
$peerIpInput.Location = New-Object System.Drawing.Point(198, 110)
$peerIpInput.Size = New-Object System.Drawing.Size(155, 28)
$peerIpInput.Text = ''
$agentGroup.Controls.Add($peerIpInput)

$peerPortLabel = New-Object System.Windows.Forms.Label
$peerPortLabel.Text = 'Port'
$peerPortLabel.Location = New-Object System.Drawing.Point(368, 114)
$peerPortLabel.Size = New-Object System.Drawing.Size(42, 24)
$agentGroup.Controls.Add($peerPortLabel)

$peerPortInput = New-Object System.Windows.Forms.NumericUpDown
$peerPortInput.Location = New-Object System.Drawing.Point(412, 110)
$peerPortInput.Size = New-Object System.Drawing.Size(80, 28)
$peerPortInput.Minimum = 1024
$peerPortInput.Maximum = 65535
$peerPortInput.Value = 8787
$agentGroup.Controls.Add($peerPortInput)

$testPeerButton = New-Object System.Windows.Forms.Button
$testPeerButton.Text = 'TEST PEER'
$testPeerButton.Location = New-Object System.Drawing.Point(502, 108)
$testPeerButton.Size = New-Object System.Drawing.Size(80, 32)
$agentGroup.Controls.Add($testPeerButton)

$pairHelp = New-Object System.Windows.Forms.Label
$pairHelp.Text = 'Pair mode: Prepare configures both VMs. Buy here = Sell there; Sell here = Buy there; Close closes both.'
$pairHelp.Location = New-Object System.Drawing.Point(18, 154)
$pairHelp.Size = New-Object System.Drawing.Size(564, 35)
$pairHelp.ForeColor = [System.Drawing.Color]::DimGray
$agentGroup.Controls.Add($pairHelp)

$setupGroup = New-Object System.Windows.Forms.GroupBox
$setupGroup.Text = '1. Prepare Trade'
$setupGroup.Location = New-Object System.Drawing.Point(24, 330)
$setupGroup.Size = New-Object System.Drawing.Size(602, 205)
$form.Controls.Add($setupGroup)

function Add-SetupLabel {
    param([string]$Text, [int]$Y)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point(18, $Y)
    $label.Size = New-Object System.Drawing.Size(125, 25)
    $setupGroup.Controls.Add($label)
}

Add-SetupLabel -Text 'Ticker symbol' -Y 32
Add-SetupLabel -Text 'Stop loss' -Y 72
Add-SetupLabel -Text 'Profit' -Y 112

$tickerInput = New-Object System.Windows.Forms.TextBox
$tickerInput.Location = New-Object System.Drawing.Point(150, 28)
$tickerInput.Size = New-Object System.Drawing.Size(180, 28)
$tickerInput.Text = 'MNQ'
$setupGroup.Controls.Add($tickerInput)

$stopLossInput = New-Object System.Windows.Forms.TextBox
$stopLossInput.Location = New-Object System.Drawing.Point(150, 68)
$stopLossInput.Size = New-Object System.Drawing.Size(180, 28)
$stopLossInput.Text = '123'
$setupGroup.Controls.Add($stopLossInput)

$profitInput = New-Object System.Windows.Forms.TextBox
$profitInput.Location = New-Object System.Drawing.Point(150, 108)
$profitInput.Size = New-Object System.Drawing.Size(180, 28)
$profitInput.Text = '456'
$setupGroup.Controls.Add($profitInput)

$lockedValues = New-Object System.Windows.Forms.Label
$lockedValues.Text = "Account: $LockedAccount`nQuantity: $LockedQuantity`nParameter: Currency"
$lockedValues.Location = New-Object System.Drawing.Point(370, 30)
$lockedValues.Size = New-Object System.Drawing.Size(205, 70)
$lockedValues.ForeColor = [System.Drawing.Color]::DimGray
$setupGroup.Controls.Add($lockedValues)

$prepareButton = New-Object System.Windows.Forms.Button
$prepareButton.Text = 'PREPARE && VERIFY'
$prepareButton.Location = New-Object System.Drawing.Point(370, 110)
$prepareButton.Size = New-Object System.Drawing.Size(205, 45)
$prepareButton.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
$prepareButton.ForeColor = [System.Drawing.Color]::White
$prepareButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$setupGroup.Controls.Add($prepareButton)

$prepareStatus = New-Object System.Windows.Forms.Label
$prepareStatus.Text = 'Not prepared. Execution is disabled.'
$prepareStatus.Location = New-Object System.Drawing.Point(18, 166)
$prepareStatus.Size = New-Object System.Drawing.Size(557, 26)
$prepareStatus.ForeColor = [System.Drawing.Color]::DimGray
$setupGroup.Controls.Add($prepareStatus)

$executeGroup = New-Object System.Windows.Forms.GroupBox
$executeGroup.Text = '2. Local Execution'
$executeGroup.Location = New-Object System.Drawing.Point(24, 550)
$executeGroup.Size = New-Object System.Drawing.Size(602, 250)
$form.Controls.Add($executeGroup)

function Add-StateRow {
    param([string]$Name, [int]$X)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Name
    $label.Location = New-Object System.Drawing.Point($X, 30)
    $label.Size = New-Object System.Drawing.Size(85, 22)
    $executeGroup.Controls.Add($label)

    $value = New-Object System.Windows.Forms.Label
    $value.Text = '—'
    $value.Location = New-Object System.Drawing.Point($X, 52)
    $value.Size = New-Object System.Drawing.Size(130, 25)
    $value.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $executeGroup.Controls.Add($value)
    return $value
}

$accountValue = Add-StateRow -Name 'Account' -X 18
$tickerValue = Add-StateRow -Name 'Ticker' -X 160
$quantityValue = Add-StateRow -Name 'Quantity' -X 302
$positionValue = Add-StateRow -Name 'Position' -X 444

$buyButton = New-Object System.Windows.Forms.Button
$buyButton.Text = 'BUY MARKET'
$buyButton.Location = New-Object System.Drawing.Point(18, 95)
$buyButton.Size = New-Object System.Drawing.Size(172, 50)
$buyButton.BackColor = [System.Drawing.Color]::SeaGreen
$buyButton.ForeColor = [System.Drawing.Color]::White
$buyButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$buyButton.Enabled = $false
$executeGroup.Controls.Add($buyButton)

$sellButton = New-Object System.Windows.Forms.Button
$sellButton.Text = 'SELL MARKET'
$sellButton.Location = New-Object System.Drawing.Point(215, 95)
$sellButton.Size = New-Object System.Drawing.Size(172, 50)
$sellButton.BackColor = [System.Drawing.Color]::Firebrick
$sellButton.ForeColor = [System.Drawing.Color]::White
$sellButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$sellButton.Enabled = $false
$executeGroup.Controls.Add($sellButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'CLOSE POSITION'
$closeButton.Location = New-Object System.Drawing.Point(412, 95)
$closeButton.Size = New-Object System.Drawing.Size(172, 50)
$closeButton.BackColor = [System.Drawing.Color]::DarkOrange
$closeButton.ForeColor = [System.Drawing.Color]::White
$closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeButton.Enabled = $true
$executeGroup.Controls.Add($closeButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh State'
$refreshButton.Location = New-Object System.Drawing.Point(18, 166)
$refreshButton.Size = New-Object System.Drawing.Size(172, 34)
$executeGroup.Controls.Add($refreshButton)

$executionStatus = New-Object System.Windows.Forms.Label
$executionStatus.Text = 'Waiting for preparation.'
$executionStatus.Location = New-Object System.Drawing.Point(215, 170)
$executionStatus.Size = New-Object System.Drawing.Size(369, 50)
$executionStatus.ForeColor = [System.Drawing.Color]::DimGray
$executeGroup.Controls.Add($executionStatus)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'SIM TEST: commands execute without confirmation. Live accounts and quantities above 1 are blocked.'
$footer.Location = New-Object System.Drawing.Point(27, 813)
$footer.Size = New-Object System.Drawing.Size(599, 22)
$footer.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($footer)


# Background networking keeps WinForms timers free to click and verify positions.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
public static class PairNetworkV104 {
    public static Task<string> Send(string host, int port, string json, int timeout) {
        return Task.Run(() => {
            using (var client = new TcpClient()) {
                var connect = client.ConnectAsync(host, port);
                if (!connect.Wait(timeout)) throw new TimeoutException("Peer connection timed out.");
                connect.GetAwaiter().GetResult();
                client.ReceiveTimeout = timeout;
                client.SendTimeout = timeout;
                using (var stream = client.GetStream())
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                using (var writer = new StreamWriter(stream, new UTF8Encoding(false))) {
                    writer.AutoFlush = true;
                    writer.WriteLine(json);
                    string line = reader.ReadLine();
                    if (String.IsNullOrWhiteSpace(line)) throw new IOException("Empty peer response.");
                    return line;
                }
            }
        });
    }
}
'@

$script:StateCache = $null
$script:StateCacheUtc = [DateTime]::MinValue
$script:CacheError = 'No sample yet'
$script:PeerUnknownSinceUtc = $null
$script:PeerRequestUtc = [DateTime]::MinValue
$script:LocalOpened = $false
$script:CurrentPairId = ''
$script:DisconnectGraceSeconds = 8
$script:MaxStateAgeMs = 3000
$script:CloseAttemptedForPair = ''
$script:LastRemoteCloseId = ''
$script:CloseCheck = $null
$script:PeerMonitorTask = $null
$script:EntryFault = $false
$script:EntryLeadMs = 1500
$script:PeerOffsetMs = 0
$script:TimingLog = Join-Path ([System.IO.Path]::GetTempPath()) 'Paired_VM_Agent_v10_4.log'

function Write-PairLog {
    param([string]$Message)
    try { Add-Content -LiteralPath $script:TimingLog -Value ("{0} {1}" -f [DateTime]::UtcNow.ToString('o'), $Message) } catch { }
}

function Update-StateCache {
    if ($script:Busy -or $script:ScheduledAction) { return }
    try {
        $sample = Get-ChartSnapshot
        if ([string]::IsNullOrWhiteSpace($sample.Position)) { throw 'Position unreadable.' }
        $script:StateCache = $sample
        $script:StateCacheUtc = [DateTime]::UtcNow
        $script:CacheError = ''
        if ($script:PairCoordinatorActive -and $sample.Account -ceq $LockedAccount -and $sample.Position -cne 'Flat') {
            $script:LocalOpened = $true
        }
    } catch { $script:CacheError = $_.Exception.Message }
}

function Get-CachedStatus {
    $sample = $script:StateCache
    $age = ([DateTime]::UtcNow - $script:StateCacheUtc).TotalMilliseconds
    $fresh = $null -ne $sample -and $age -le $script:MaxStateAgeMs -and [string]::IsNullOrWhiteSpace($script:CacheError)
    return [ordered]@{
        ok=$fresh; version='10.4'; command='monitor_status'
        message=$(if ($fresh) {'Cached state'} else {'State unavailable or stale'})
        sampleAgeMs=$age; pairId=$script:CurrentPairId; everOpened=$script:LocalOpened
        pendingVerification=($null -ne $script:PendingVerification)
        scheduled=($null -ne $script:ScheduledAction); lastError=$script:LastError
        account=$(if ($fresh) {$sample.Account} else {$null})
        position=$(if ($fresh) {$sample.Position} else {$null})
    }
}

function Register-PeerDelay {
    param([string]$Reason)
    if ($null -eq $script:PeerUnknownSinceUtc) {
        $script:PeerUnknownSinceUtc = $script:PeerRequestUtc
        if ($script:PeerUnknownSinceUtc -eq [DateTime]::MinValue) { $script:PeerUnknownSinceUtc = [DateTime]::UtcNow }
        Write-PairLog "PEER STATUS UNKNOWN; retrying: $Reason"
    }
    $elapsed = ([DateTime]::UtcNow - $script:PeerUnknownSinceUtc).TotalSeconds
    if ($elapsed -ge $script:DisconnectGraceSeconds) {
        Invoke-PairEmergencyClose -Reason "No fresh pair status for $script:DisconnectGraceSeconds seconds: $Reason"
    } else {
        $executionStatus.Text = "PEER STATUS DELAYED - retrying ($([int]$elapsed)/$script:DisconnectGraceSeconds s)."
        $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

function Start-PeerTask {
    param([System.Collections.IDictionary]$Payload, [int]$TimeoutMilliseconds = 3000)
    if (-not $script:AgentStarted) { throw 'Start the agent first.' }
    if ([string]::IsNullOrWhiteSpace($peerIpInput.Text)) { throw 'Peer IP is required.' }
    $body = [ordered]@{}
    foreach ($key in $Payload.Keys) { $body[$key] = $Payload[$key] }
    $body.token = $secretInput.Text
    return [PairNetworkV104]::Send($peerIpInput.Text.Trim(), [int]$peerPortInput.Value,
        ($body | ConvertTo-Json -Compress -Depth 5), $TimeoutMilliseconds)
}

function Measure-PairTiming {
    $maxRtt = 0.0
    $bestRtt = [double]::MaxValue
    for ($i = 0; $i -lt 3; $i++) {
        $start = [DateTime]::UtcNow
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $reply = Send-PeerRequest -Payload ([ordered]@{command='ping'}) -TimeoutMilliseconds 1500
        $watch.Stop()
        if (-not $reply.ok -or $reply.version -ne '10.4') { throw 'Install V10.4 on BOTH VMs before pairing.' }
        $rtt = $watch.Elapsed.TotalMilliseconds
        $peerTime = [DateTime]::Parse([string]$reply.timestampUtc).ToUniversalTime()
        $offset = ($peerTime - $start.AddMilliseconds($rtt / 2)).TotalMilliseconds
        if ($rtt -lt $bestRtt) { $bestRtt = $rtt; $script:PeerOffsetMs = $offset }
        $maxRtt = [Math]::Max($maxRtt, $rtt)
    }
    if ($maxRtt -gt 1000) { throw 'Peer response exceeds 1 second. Entry blocked; inspect VM load/network.' }
    if ([Math]::Abs($script:PeerOffsetMs) -gt 500) { throw 'Estimated VM clock difference exceeds 500 ms. Synchronize Windows time.' }
    $script:EntryLeadMs = [int][Math]::Max(1200, (4 * $maxRtt + 500))
    Write-PairLog "TIMING maxRTT=$([int]$maxRtt)ms offset=$([int]$script:PeerOffsetMs)ms lead=$script:EntryLeadMs ms"
}

function Verify-PairedClose {
    if ($null -eq $script:CloseCheck -or $script:Busy) { return }
    $check = $script:CloseCheck
    $now = [DateTime]::UtcNow
    $local = Get-CachedStatus
    $localFlat = $local.ok -and $local.account -ceq $LockedAccount -and $local.position -ceq 'Flat'
    if ($check.Task -and $check.Task.IsCompleted) {
        $done = $check.Task
        $check.Task = $null
        try {
            $reply = $done.GetAwaiter().GetResult() | ConvertFrom-Json
            if ($reply.command -eq 'monitor_status') {
                $age = [double]$reply.sampleAgeMs + ($now - $check.RequestUtc).TotalMilliseconds
                $check.PeerFlat = $reply.ok -and $age -le $script:MaxStateAgeMs -and
                    $reply.pairId -ceq $script:CurrentPairId -and
                    $reply.account -ceq $script:PeerAccount14 -and $reply.position -ceq 'Flat'
                $check.PeerState = $(if ($reply.ok) { [string]$reply.position } else { 'Unknown' })
                $check.PeerSeenUtc = $now
            }
            if (-not $reply.ok) { Write-PairLog "CLOSE awaiting confirmation: $($reply.message)" }
        } catch {
            $check.PeerFlat = $false
            $check.PeerState = 'Unknown'
            Write-PairLog "CLOSE verification retry: $($_.Exception.Message)"
        }
    }
    if ($localFlat -and $check.PeerFlat -and ($now - $check.PeerSeenUtc).TotalMilliseconds -le 1500) {
        $script:CloseCheck = $null
        $executionStatus.Text = 'BOTH FLAT VERIFIED. Check working orders before preparing again.'
        $executionStatus.ForeColor = [System.Drawing.Color]::Green
        Write-PairLog 'CLOSE both fresh chart positions verified Flat'
        return
    }
    if ($now -ge $check.Deadline) {
        $script:CloseCheck = $null
        $script:LastError = "Close not verified. Local='$($local.position)' Peer='$($check.PeerState)'. Check both VMs manually."
        $executionStatus.Text = $script:LastError
        $executionStatus.ForeColor = [System.Drawing.Color]::Red
        Write-PairLog $script:LastError
        return
    }
    if (-not $check.Task -and ($now - $check.RequestUtc).TotalMilliseconds -ge 350) {
        try {
            $check.RequestUtc = $now
            $check.Task = Start-PeerTask -Payload ([ordered]@{command='monitor_status'})
        } catch { Write-PairLog "CLOSE status retry: $($_.Exception.Message)" }
    }
    $executionStatus.Text = "CLOSE VERIFY: Local='$($local.position)' Peer='$($check.PeerState)' - waiting for confirmation."
    $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
}

function Set-ControlsForBusyState {
    param([bool]$Busy)
    $prepareButton.Enabled = -not $Busy
    $tickerInput.Enabled = -not $Busy
    $stopLossInput.Enabled = -not $Busy
    $profitInput.Enabled = -not $Busy
    $refreshButton.Enabled = -not $Busy
    $entryAvailable = ((-not $Busy) -and $script:Prepared -and -not $script:EntryFault -and $null -eq $script:CloseCheck -and -not $script:PairCoordinatorActive -and $null -eq $script:PendingVerification -and $null -eq $script:ScheduledAction)
    $buyButton.Enabled = $entryAvailable
    $sellButton.Enabled = $entryAvailable
    # Close remains available as an emergency Sim101 flatten command even before preparation.
    $closeButton.Enabled = -not $Busy
}

function Invalidate-Preparation {
    if ($script:Prepared) {
        $script:Prepared = $false
        $script:PreparedTicker = $null
        $prepareStatus.Text = 'Inputs changed. Prepare again before execution.'
        $prepareStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        $buyButton.Enabled = $false
        $sellButton.Enabled = $false
        $closeButton.Enabled = $true
    }
}

function Refresh-Display {
    param([bool]$Quiet = $false)
    try {
        Update-StateCache
        if (-not [string]::IsNullOrWhiteSpace($script:CacheError) -or $null -eq $script:StateCache) { throw 'Position state unreadable.' }
        $snapshot = $script:StateCache
        $accountValue.Text = if ([string]::IsNullOrWhiteSpace($snapshot.Account)) { '(unreadable)' } else { $snapshot.Account }
        $tickerValue.Text = if ([string]::IsNullOrWhiteSpace($snapshot.Ticker)) { '(unreadable)' } else { $snapshot.Ticker }
        $quantityValue.Text = if ([string]::IsNullOrWhiteSpace($snapshot.Quantity)) { '(unreadable)' } else { $snapshot.Quantity }
        $positionValue.Text = if ([string]::IsNullOrWhiteSpace($snapshot.Position)) { '(unreadable)' } else { $snapshot.Position }
        $positionValue.ForeColor = if ($snapshot.Position -ceq 'Flat') { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::DarkOrange }
        if (-not $Quiet) {
            $executionStatus.Text = 'State refreshed. No command sent.'
            $executionStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
        return $snapshot
    } catch {
        $accountValue.Text = '—'
        $tickerValue.Text = '—'
        $quantityValue.Text = '—'
        $positionValue.Text = '—'
        if (-not $Quiet) {
            $executionStatus.Text = $_.Exception.Message
            $executionStatus.ForeColor = [System.Drawing.Color]::Red
        }
        return $null
    }
}

$prepareButton.Add_Click({
    if(-not $script:RemoteCommandActive) { $executionStatus.Text='Use the browser to select and prepare accounts.'; return }
    if ($script:Busy) { return }
    if ($script:CloseCheck -or $script:ScheduledAction -or $script:PairCoordinatorActive) { return }
    $script:LastError = $null
    $requestedTicker = $tickerInput.Text.Trim()
    $parsedStopLoss = 0D
    $parsedProfit = 0D
    $numberStyle = [System.Globalization.NumberStyles]::Number
    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    if ([string]::IsNullOrWhiteSpace($requestedTicker)) {
        $script:LastError = 'Enter a ticker symbol, such as MNQ or MQ.'
        if (-not $script:RemoteCommandActive) { Show-ErrorMessage -Message $script:LastError -Title 'Ticker Required' }
        return
    }
    if (-not ([decimal]::TryParse(($stopLossInput.Text -replace '[,$\s]', ''), $numberStyle, $culture, [ref]$parsedStopLoss)) -or $parsedStopLoss -lt 0) {
        $script:LastError = 'Enter a valid stop loss of zero or greater.'
        if (-not $script:RemoteCommandActive) { Show-ErrorMessage -Message $script:LastError -Title 'Invalid Stop Loss' }
        return
    }
    if (-not ([decimal]::TryParse(($profitInput.Text -replace '[,$\s]', ''), $numberStyle, $culture, [ref]$parsedProfit)) -or $parsedProfit -lt 0) {
        $script:LastError = 'Enter a valid profit of zero or greater.'
        if (-not $script:RemoteCommandActive) { Show-ErrorMessage -Message $script:LastError -Title 'Invalid Profit' }
        return
    }

    $script:Busy = $true
    $script:Prepared = $false
    Set-ControlsForBusyState -Busy $true
    $prepareStatus.Text = 'Preparing and verifying...'
    $prepareStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    $form.Refresh()

    try {
        if ($pairEnabled.Checked -and -not $script:RemoteCommandActive) {
            Test-PeerReady | Out-Null
        }
        $result = Prepare-Trade -Ticker $requestedTicker -StopLoss $parsedStopLoss -Profit $parsedProfit
        $peerPreparedMessage = ''
        if ($pairEnabled.Checked -and -not $script:RemoteCommandActive) {
            $peerResult = Send-PeerRequest -Payload ([ordered]@{
                command = 'prepare'
                ticker = $requestedTicker
                stopLoss = $parsedProfit
                profit = $parsedStopLoss
            }) -TimeoutMilliseconds 20000
            if (-not $peerResult.ok -or -not $peerResult.prepared) {
                throw "Local preparation succeeded, but peer preparation failed: $($peerResult.message)"
            }
            if ($peerResult.account -cne $script:PeerAccount14 -or [string]$peerResult.quantity -ne [string]$script:PeerQuantity14 -or $peerResult.position -cne 'Flat') {
                throw "Peer safety verification failed. Account='$($peerResult.account)', quantity='$($peerResult.quantity)', position='$($peerResult.position)'."
            }
            $peerPreparedMessage = " Peer reversed: SL $parsedProfit / Profit $parsedStopLoss."
        }
        $script:PreparedTicker = $requestedTicker
        $script:Prepared = $true
        $script:EntryFault = $false
        $prepareStatus.Text = "READY - $($result.Ticker), Qty $LockedQuantity, Currency, SL $parsedStopLoss, Profit $parsedProfit.$peerPreparedMessage"
        $prepareStatus.ForeColor = [System.Drawing.Color]::Green
        $executionStatus.Text = 'Preparation verified. Choose Buy or Sell when ready.'
        $executionStatus.ForeColor = [System.Drawing.Color]::Green
        Refresh-Display -Quiet $true | Out-Null
        if (-not $script:RemoteCommandActive) {
            $peerSummary = if ($pairEnabled.Checked) { "`nPeer stop loss: $parsedProfit`nPeer profit: $parsedStopLoss" } else { '' }
            [System.Windows.Forms.MessageBox]::Show(
                "PREPARED successfully.`n`nAccount: $LockedAccount`nTicker: $($result.Ticker)`nQuantity: $LockedQuantity`nParameter type: Currency`nLocal stop loss: $parsedStopLoss`nLocal profit: $parsedProfit$peerSummary`n`nNo trade was placed. Execution is now enabled.",
                'Paired VM Agent v10.4',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    } catch {
        $script:LastError = $_.Exception.Message
        $prepareStatus.Text = 'NOT PREPARED - execution remains disabled.'
        $prepareStatus.ForeColor = [System.Drawing.Color]::Red
        if (-not $script:RemoteCommandActive) {
            Show-ErrorMessage -Message $_.Exception.Message -Title 'Prepare Trade Failed'
        }
        Refresh-Display -Quiet $true | Out-Null
    } finally {
        $script:Busy = $false
        Set-ControlsForBusyState -Busy $false
    }
})

function Invoke-Entry {
    param([string]$Side, [string]$ButtonId)
    if ($script:Busy) { return }
    $script:LastError = $null
    if (-not $script:Prepared) {
        $script:LastError = 'Prepare and verify the trade before executing.'
        if (-not $script:RemoteCommandActive) {
            Show-ErrorMessage -Message $script:LastError -Title 'Execution Disabled'
        }
        return
    }

    $script:Busy = $true
    Set-ControlsForBusyState -Busy $true
    try {
        $snapshot = Get-ChartSnapshot
        Assert-V10Safety -Snapshot $snapshot -RequireFlat $true -ExpectedTicker $script:PreparedTicker

        $executionStatus.Text = "Sending $Side Market to $LockedAccount..."
        $form.Refresh()
        Click-ChartTraderButton -Snapshot $snapshot -AutomationId $ButtonId -ExpectedName "$Side Market"
        $script:PendingVerification = [pscustomobject]@{
            Mode = 'OPEN'
            DeadlineUtc = [DateTime]::UtcNow.AddSeconds(4)
            Label = "$Side entry"
        }
        $executionStatus.Text = "$Side CLICKED - monitoring position..."
        $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    } catch {
        $script:LastError = $_.Exception.Message
        $executionStatus.Text = 'ENTRY FAILED OR BLOCKED.'
        $executionStatus.ForeColor = [System.Drawing.Color]::Red
        if (-not $script:RemoteCommandActive) { Show-ErrorMessage -Message $_.Exception.Message }
        Refresh-Display -Quiet $true | Out-Null
    } finally {
        $script:Busy = $false
        Set-ControlsForBusyState -Busy $false
    }
}

function Invoke-Close {
    if ($script:Busy) { return }
    $script:LastError = $null
    $script:Busy = $true
    Set-ControlsForBusyState -Busy $true
    try {
        $snapshot = Get-ChartSnapshot
        $closeTicker = if ($script:Prepared) { $script:PreparedTicker } else { $null }
        Assert-V10Safety -Snapshot $snapshot -RequireFlat $false -ExpectedTicker $closeTicker
        if ($snapshot.Position -ceq 'Flat') {
            $script:PendingVerification = $null
            $executionStatus.Text = 'Already Flat. Close was not clicked.'
            return
        }

        $executionStatus.Text = "Closing $LockedAccount position..."
        $form.Refresh()
        Click-ChartTraderButton -Snapshot $snapshot -AutomationId 'ChartTraderControlQuickCloseButton' -ExpectedName 'Close'
        $script:CacheError = 'Waiting for a position sample after Close.'
        $script:PendingVerification = [pscustomobject]@{
            Mode = 'FLAT'
            DeadlineUtc = [DateTime]::UtcNow.AddSeconds(4)
            Label = 'Close'
        }
        $executionStatus.Text = 'CLOSE CLICKED - monitoring position...'
        $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    } catch {
        $script:LastError = $_.Exception.Message
        $executionStatus.Text = 'CLOSE FAILED OR BLOCKED.'
        $executionStatus.ForeColor = [System.Drawing.Color]::Red
        if (-not $script:RemoteCommandActive) { Show-ErrorMessage -Message $_.Exception.Message }
        Refresh-Display -Quiet $true | Out-Null
    } finally {
        $script:Busy = $false
        Set-ControlsForBusyState -Busy $false
    }
}

function Send-PeerRequest {
    param(
        [System.Collections.IDictionary]$Payload,
        [int]$TimeoutMilliseconds = 15000
    )
    $peerHost = $peerIpInput.Text.Trim()
    $peerPort = [int]$peerPortInput.Value
    if ([string]::IsNullOrWhiteSpace($peerHost)) { throw 'Enter the other VM agent IP address.' }
    if (-not $script:AgentStarted) { throw 'Start this VM Agent before using pair mode.' }
    if ([string]::IsNullOrWhiteSpace($secretInput.Text)) { throw 'Shared secret is required.' }

    $requestBody = [ordered]@{}
    foreach ($key in $Payload.Keys) { $requestBody[$key] = $Payload[$key] }
    $requestBody['token'] = $secretInput.Text

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect($peerHost, $peerPort, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne(2500)) { throw "Peer $peerHost`:$peerPort did not accept the connection." }
        $client.EndConnect($connect)
        $client.ReceiveTimeout = $TimeoutMilliseconds
        $client.SendTimeout = 3000

        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 1024, $true)
        $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)), 1024, $true)
        $writer.AutoFlush = $true
        $writer.WriteLine(($requestBody | ConvertTo-Json -Compress -Depth 5))
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { throw 'Peer returned an empty response.' }
        return ($line | ConvertFrom-Json)
    } finally {
        try { $client.Close() } catch { }
    }
}

function Test-PeerReady {
    $response = Send-PeerRequest -Payload ([ordered]@{ command = 'status' }) -TimeoutMilliseconds 4000
    if (-not $response.ok) { throw "Peer rejected status request: $($response.message)" }
    if ([string]$response.agent -ceq $agentNameInput.Text.Trim()) {
        throw 'Peer IP points back to this same agent. Enter the other VM IP address.'
    }
    return $response
}

function Schedule-LocalAction {
    param(
        [string]$Side,
        [DateTime]$ExecuteAtUtc,
        [string]$PairId,
        [bool]$Coordinator
    )
    if ($script:ScheduledAction) { throw 'This VM already has a scheduled action.' }
    $normalizedSide = $Side.ToUpperInvariant()
    $snapshot = Get-ChartSnapshot
    if ($normalizedSide -eq 'CLOSE') {
        $script:PendingVerification = $null
        Assert-V10Safety -Snapshot $snapshot -RequireFlat $false -ExpectedTicker $null
        $buttonId = 'ChartTraderControlQuickCloseButton'
        $buttonName = 'Close'
    } else {
        Assert-V10Safety -Snapshot $snapshot -RequireFlat $true -ExpectedTicker $script:PreparedTicker
        if (-not $script:Prepared) { throw 'This VM is not prepared.' }
        if ($normalizedSide -eq 'BUY') {
            $buttonId = 'ChartTraderControlQuickBuyMarketButton'
            $buttonName = 'Buy Market'
        } else {
            $buttonId = 'ChartTraderControlQuickSellMarketButton'
            $buttonName = 'Sell Market'
        }
    }

    $armedClick = Arm-ChartTraderButton -Snapshot $snapshot -AutomationId $buttonId -ExpectedName $buttonName
    $script:LastError = $null

    $script:CurrentPairId = $PairId
    $script:LocalOpened = $false
    $script:PeerUnknownSinceUtc = $null
    $script:CloseAttemptedForPair = ''
    $script:ScheduledAction = [pscustomobject]@{
        Side = $normalizedSide
        ExecuteAtUtc = $ExecuteAtUtc
        PairId = $PairId
        Coordinator = $Coordinator
        ArmedClick = $armedClick
        ArmedUtc = [DateTime]::UtcNow
    }
    if ($ExecuteAtUtc -eq [DateTime]::MaxValue) {
        $executionStatus.Text = "$normalizedSide ARMED - waiting for synchronized commit"
    } else {
        $executionStatus.Text = "$normalizedSide armed for $($ExecuteAtUtc.ToString('HH:mm:ss.fff')) UTC"
    }
    $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
}

function Commit-LocalAction {
    param(
        [string]$PairId,
        [DateTime]$ExecuteAtUtc
    )
    if ($null -eq $script:ScheduledAction) { throw 'No action is armed.' }
    if ($script:ScheduledAction.PairId -cne $PairId) { throw 'Pair ID does not match the armed action.' }
    $millisecondsAhead = ($ExecuteAtUtc - [DateTime]::UtcNow).TotalMilliseconds
    if ($millisecondsAhead -lt 100 -or $millisecondsAhead -gt 5000) {
        throw 'Committed execution time must be 100 milliseconds to 5 seconds in the future.'
    }
    if (($script:ScheduledAction.ExecuteAtUtc -ne [DateTime]::MaxValue)) { throw 'Action already committed. Duplicate commit blocked.' }
    $script:ScheduledAction.ExecuteAtUtc = $ExecuteAtUtc
    Write-PairLog "COMMIT pair=$PairId ahead=$([int]$millisecondsAhead)ms"
    $executionStatus.Text = "$($script:ScheduledAction.Side) COMMITTED for $($ExecuteAtUtc.ToString('HH:mm:ss.fff')) UTC"
    $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
}

function Invoke-PairedEntry {
    param([string]$LocalSide)
    if (-not $pairEnabled.Checked) { throw 'Pair mode is not enabled.' }
    if (-not $script:AgentStarted) { throw 'Start this VM Agent before paired execution.' }
    if (-not $script:Prepared) { throw 'Prepare and verify both VMs before paired execution.' }
    if ($script:EntryFault -or $script:CloseCheck) { throw 'Verify both VMs and Prepare again after the previous fault/close.' }
    if ($script:ScheduledAction -or $script:PairCoordinatorActive) { throw 'A paired action is already active.' }

    $localSideNormalized = $LocalSide.ToUpperInvariant()
    $peerSide = if ($localSideNormalized -eq 'BUY') { 'SELL' } else { 'BUY' }
    $script:EntryStage19='readiness check'
    $peerStatus = Test-PeerReady
    Measure-PairTiming
    if (-not $peerStatus.prepared -or $peerStatus.position -cne 'Flat') {
        throw "Peer is not ready. Prepared='$($peerStatus.prepared)', position='$($peerStatus.position)'."
    }
    if ($peerStatus.account -cne $script:PeerAccount14 -or [string]$peerStatus.quantity -ne [string]$script:PeerQuantity14) {
        throw "Peer safety lock mismatch. Account='$($peerStatus.account)', quantity='$($peerStatus.quantity)'."
    }
    if (-not ([string]$peerStatus.ticker).StartsWith($script:PreparedTicker, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Peer ticker '$($peerStatus.ticker)' does not match '$script:PreparedTicker'."
    }

    $pairId = [Guid]::NewGuid().ToString('N')
    $script:CurrentPairId = $pairId
    $script:LocalOpened = $false
    $script:CloseAttemptedForPair = ''
    $script:PeerUnknownSinceUtc = $null
    try {
    $script:EntryStage19='peer arm'
    $peerArm = Send-PeerRequest -Payload ([ordered]@{
        command = 'arm'
        side = $peerSide
        pairId = $pairId
    }) -TimeoutMilliseconds 5000
    if (-not $peerArm.ok -or -not $peerArm.scheduled) {
        throw "Peer did not arm ${peerSide}: $($peerArm.message)"
    }

        Schedule-LocalAction -Side $localSideNormalized -ExecuteAtUtc ([DateTime]::MaxValue) -PairId $pairId -Coordinator $true
        $executeAt = [DateTime]::UtcNow.AddMilliseconds($script:EntryLeadMs)
        $script:EntryStage19='peer commit'
        $peerCommit = Send-PeerRequest -Payload ([ordered]@{
            command = 'commit'
            executeAtUtc = $executeAt.AddMilliseconds($script:PeerOffsetMs).ToString('o')
            pairId = $pairId
        }) -TimeoutMilliseconds 3000
        if (-not $peerCommit.ok) { throw "Peer commit failed: $($peerCommit.message)" }
        $script:EntryStage19='local commit'
        Commit-LocalAction -PairId $pairId -ExecuteAtUtc $executeAt
    } catch {
        $failure = $_.Exception.Message
        $script:EntryFault = $true
        Invoke-PairEmergencyClose -Reason "Entry handshake failed at $script:EntryStage19 : $failure"
        throw "Entry failed: $failure. Recovery close requested; verify BOTH VMs."
    }

    Set-ControlsForBusyState -Busy $false
    $script:PairCoordinatorActive = $true
    $script:PairEverOpened = $false
    $script:PairGraceDeadlineUtc = $executeAt.AddSeconds(4)
    $executionStatus.Text = "PAIR ARMED: Here $localSideNormalized / Peer $peerSide"
    $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
}

function Invoke-PairedClose {
    if ($script:CloseCheck) { return }
    $script:CloseAttemptedForPair = $script:CurrentPairId
    $closeId = [Guid]::NewGuid().ToString('N')
    $script:ScheduledAction = $null
    $script:PendingVerification = $null
    $script:PairCoordinatorActive = $false
    $script:PairEverOpened = $false
    $script:PeerMonitorTask = $null
    $script:EntryFault = $true
    $task = $null
    $networkError = $null
    try { $task = Start-PeerTask -Payload ([ordered]@{command='emergency_close'; closeId=$closeId; pairId=$script:CurrentPairId}) } catch { $networkError = $_.Exception.Message }
    # The remote request runs in a .NET worker while we close locally.
    $wasRemote = $script:RemoteCommandActive
    $script:RemoteCommandActive = $true
    try { Invoke-Close } finally {
        $script:RemoteCommandActive = $wasRemote
        $script:Prepared = $false
    }
    Write-PairLog "CLOSE requested on both VMs; local error='$script:LastError'"
    $script:CloseCheck = [pscustomobject]@{
        Task=$task; PeerFlat=$false; PeerState='Unknown'; Deadline=[DateTime]::UtcNow.AddSeconds(15)
        RequestUtc=[DateTime]::UtcNow; PeerSeenUtc=[DateTime]::MinValue
    }
    if ($networkError) {
        $script:CloseCheck = $null
        $executionStatus.Text = "PEER CLOSE NOT SENT: $networkError. Check peer manually."
        $executionStatus.ForeColor = [System.Drawing.Color]::Red
    }
    Set-ControlsForBusyState -Busy $false
}

function Invoke-PairEmergencyClose {
    param([string]$Reason)
    if ($script:CloseCheck -or ($script:CurrentPairId -ne '' -and $script:CloseAttemptedForPair -ceq $script:CurrentPairId)) { return }
    Write-PairLog "FAIL-SAFE $Reason"
    Invoke-PairedClose
}

function Get-AgentSnapshotResponse {
    param(
        [bool]$Ok,
        [string]$Command,
        [string]$Message
    )
    $account = $null
    $ticker = $null
    $quantity = $null
    $position = $null
    try {
        $snapshot = Get-ChartSnapshot
        $account = $snapshot.Account
        $ticker = $snapshot.Ticker
        $quantity = $snapshot.Quantity
        $position = $snapshot.Position
    } catch {
        if ($Ok) {
            $Ok = $false
            $Message = $_.Exception.Message
        }
    }

    return [ordered]@{
        ok = $Ok
        version = '10.4'
        agent = $agentNameInput.Text.Trim()
        command = $Command
        message = $Message
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        listening = $script:AgentStarted
        busy = $script:Busy
        prepared = $script:Prepared
        scheduled = ($null -ne $script:ScheduledAction)
        pendingVerification = ($null -ne $script:PendingVerification)
        pairCoordinatorActive = $script:PairCoordinatorActive
        lastError = $script:LastError
        account = $account
        ticker = $ticker
        quantity = $quantity
        parameterType = $RequiredParameterType
        position = $position
    }
}

function Process-AgentRequest {
    param([string]$JsonLine)

    try {
        if ([string]::IsNullOrWhiteSpace($JsonLine)) { throw 'Empty request.' }
        if ($JsonLine.Length -gt 32768) { throw 'Request is too large.' }
        $request = $JsonLine | ConvertFrom-Json

        $suppliedToken = [string]$request.token
        $requiredToken = $secretInput.Text
        if ([string]::IsNullOrWhiteSpace($suppliedToken) -or $suppliedToken -cne $requiredToken) {
            return [ordered]@{
                ok = $false
                command = 'unauthorized'
                message = 'Authentication failed.'
                timestampUtc = [DateTime]::UtcNow.ToString('o')
            }
        }

        $command = ([string]$request.command).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($command)) { throw 'Command is required.' }
        $script:LastCommand = $command
        $script:LastCommandTime = [DateTime]::Now

        switch ($command) {
            'monitor_status' { return Get-CachedStatus }
            'ping' {
                return @{ok=$true; version='10.4'; timestampUtc=[DateTime]::UtcNow.ToString('o')}
            }
            'emergency_close' {
                if ([string]$request.pairId -cne $script:CurrentPairId) {
                    return @{ok=$false; command=$command; message='Close belongs to a different pair.'}
                }
                if (([string]$request.closeId -ne '' -and [string]$request.closeId -ceq $script:LastRemoteCloseId) -or
                    ($script:PendingVerification -and $script:PendingVerification.Mode -eq 'FLAT') -or $script:CloseCheck) {
                    return @{ok=$true; command=$command; message='Close already in progress; verify status.'}
                }
                $script:LastRemoteCloseId = [string]$request.closeId
                $script:CloseAttemptedForPair = $script:CurrentPairId
                $script:ScheduledAction = $null
                $script:PendingVerification = $null
                $script:PairCoordinatorActive = $false
                $script:PeerMonitorTask = $null
                $script:EntryFault = $true
                $script:RemoteCommandActive = $true
                try { Invoke-Close } finally {
                    $script:RemoteCommandActive = $false
                    $script:Prepared = $false
                }
                Write-PairLog "REMOTE emergency close; error='$script:LastError'"
                return @{ok=([string]::IsNullOrWhiteSpace($script:LastError)); command=$command; message='Close attempted; verify cached status.'}
            }
            'status' {
                return Get-AgentSnapshotResponse -Ok $true -Command $command -Message 'Agent is online.'
            }
            'prepare' {
                if ($script:Busy) { return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Agent is busy.' }
                $remoteTicker = ([string]$request.ticker).Trim()
                if ([string]::IsNullOrWhiteSpace($remoteTicker)) {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Ticker is required.'
                }
                if ($null -eq $request.stopLoss -or $null -eq $request.profit) {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'stopLoss and profit are required.'
                }

                $tickerInput.Text = $remoteTicker
                $stopLossInput.Text = ([string]$request.stopLoss)
                $profitInput.Text = ([string]$request.profit)
                $script:RemoteCommandActive = $true
                try { $prepareButton.PerformClick() } finally { $script:RemoteCommandActive = $false }

                if ($script:Prepared -and [string]::IsNullOrWhiteSpace($script:LastError)) {
                    return Get-AgentSnapshotResponse -Ok $true -Command $command -Message 'Trade prepared and verified.'
                }
                $message = if ([string]::IsNullOrWhiteSpace($script:LastError)) { 'Preparation failed.' } else { $script:LastError }
                return Get-AgentSnapshotResponse -Ok $false -Command $command -Message $message
            }
            'arm' {
                if ($script:Busy) { return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Agent is busy.' }
                if ($script:EntryFault -or $script:CloseCheck -or $script:PairCoordinatorActive) {
                    throw 'Pair is active, closing, or faulted. Verify both VMs and prepare again.'
                }
                $side = ([string]$request.side).Trim().ToUpperInvariant()
                if ($side -ne 'BUY' -and $side -ne 'SELL' -and $side -ne 'CLOSE') {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Armed side must be BUY, SELL, or CLOSE.'
                }
                if ($side -ne 'CLOSE' -and -not $script:Prepared) {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Peer is not prepared.'
                }
                Schedule-LocalAction -Side $side -ExecuteAtUtc ([DateTime]::MaxValue) -PairId ([string]$request.pairId) -Coordinator $false
                return Get-AgentSnapshotResponse -Ok $true -Command $command -Message "$side armed and awaiting commit."
            }
            'commit' {
                $executeAt = [DateTime]::Parse(
                    ([string]$request.executeAtUtc),
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                ).ToUniversalTime()
                Commit-LocalAction -PairId ([string]$request.pairId) -ExecuteAtUtc $executeAt
                # Do not traverse UI Automation in the time-critical commit acknowledgement.
                $script:PairCoordinatorActive = $true
                $script:PairEverOpened = $false
                $script:PairGraceDeadlineUtc = $executeAt.AddSeconds(4)
                return @{ok=$true; version='10.4'; command='commit'; message='Committed'; timestampUtc=[DateTime]::UtcNow.ToString('o')}
            }
            'schedule' {
                if ($script:Busy) { return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Agent is busy.' }
                $side = ([string]$request.side).Trim().ToUpperInvariant()
                if ($side -ne 'BUY' -and $side -ne 'SELL' -and $side -ne 'CLOSE') {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Scheduled side must be BUY, SELL, or CLOSE.'
                }
                if ($side -ne 'CLOSE' -and -not $script:Prepared) {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Peer is not prepared.'
                }
                $executeAt = [DateTime]::Parse(
                    ([string]$request.executeAtUtc),
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                ).ToUniversalTime()
                $millisecondsAhead = ($executeAt - [DateTime]::UtcNow).TotalMilliseconds
                if ($millisecondsAhead -lt 250 -or $millisecondsAhead -gt 10000) {
                    return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Execution time must be 250 milliseconds to 10 seconds in the future.'
                }
                Schedule-LocalAction -Side $side -ExecuteAtUtc $executeAt -PairId ([string]$request.pairId) -Coordinator $false
                return Get-AgentSnapshotResponse -Ok $true -Command $command -Message "$side armed."
            }
            'cancel_schedule' {
                $script:ScheduledAction = $null
                return Get-AgentSnapshotResponse -Ok $true -Command $command -Message 'Scheduled action cancelled.'
            }
            'buy' {
                if (-not $script:Prepared) { return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Prepare first.' }
                $script:RemoteCommandActive = $true
                try { Invoke-Entry -Side 'BUY' -ButtonId 'ChartTraderControlQuickBuyMarketButton' } finally { $script:RemoteCommandActive = $false }
                $ok = [string]::IsNullOrWhiteSpace($script:LastError)
                $message = if ($ok) { 'BUY clicked; position verification is running.' } else { $script:LastError }
                return Get-AgentSnapshotResponse -Ok $ok -Command $command -Message $message
            }
            'sell' {
                if (-not $script:Prepared) { return Get-AgentSnapshotResponse -Ok $false -Command $command -Message 'Prepare first.' }
                $script:RemoteCommandActive = $true
                try { Invoke-Entry -Side 'SELL' -ButtonId 'ChartTraderControlQuickSellMarketButton' } finally { $script:RemoteCommandActive = $false }
                $ok = [string]::IsNullOrWhiteSpace($script:LastError)
                $message = if ($ok) { 'SELL clicked; position verification is running.' } else { $script:LastError }
                return Get-AgentSnapshotResponse -Ok $ok -Command $command -Message $message
            }
            'close' {
                $script:RemoteCommandActive = $true
                try { Invoke-Close } finally { $script:RemoteCommandActive = $false }
                $ok = [string]::IsNullOrWhiteSpace($script:LastError)
                $message = if ($ok) { 'CLOSE clicked; Flat verification is running.' } else { $script:LastError }
                return Get-AgentSnapshotResponse -Ok $ok -Command $command -Message $message
            }
            default {
                return Get-AgentSnapshotResponse -Ok $false -Command $command -Message "Unknown command '$command'."
            }
        }
    } catch {
        return Get-AgentSnapshotResponse -Ok $false -Command 'invalid' -Message $_.Exception.Message
    }
}

function Start-AgentListener {
    if ($script:AgentStarted) { return }
    $agentName = $agentNameInput.Text.Trim()
    $secret = $secretInput.Text
    $port = [int]$portInput.Value

    if ([string]::IsNullOrWhiteSpace($agentName)) { throw 'Agent name is required.' }
    if ([string]::IsNullOrWhiteSpace($secret) -or $secret.Length -lt 12) {
        throw 'Use a shared secret containing at least 12 characters.'
    }

    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
    $listener.Start()
    $script:TcpListener = $listener
    $script:AgentStarted = $true

    $agentNameInput.Enabled = $false
    $portInput.Enabled = $false
    $secretInput.Enabled = $false
    $showSecret.Enabled = $false
    $agentToggleButton.Text = 'STOP AGENT'
    $agentToggleButton.BackColor = [System.Drawing.Color]::Firebrick

    $addresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and -not [System.Net.IPAddress]::IsLoopback($_) } |
        ForEach-Object { $_.ToString() }
    $ipText = if ($addresses.Count -gt 0) { $addresses -join ', ' } else { 'IP unavailable' }
    $agentStatus.Text = "ONLINE: $agentName at ${ipText}:$port"
    $agentStatus.ForeColor = [System.Drawing.Color]::Green
}

function Stop-AgentListener {
    if ($null -ne $script:TcpListener) {
        try { $script:TcpListener.Stop() } catch { }
    }
    $script:TcpListener = $null
    $script:AgentStarted = $false
    $agentNameInput.Enabled = $true
    $portInput.Enabled = $true
    $secretInput.Enabled = $true
    $showSecret.Enabled = $true
    $agentToggleButton.Text = 'START AGENT'
    $agentToggleButton.BackColor = [System.Drawing.Color]::SeaGreen
    $agentStatus.Text = 'Stopped.'
    $agentStatus.ForeColor = [System.Drawing.Color]::DimGray
}

function Receive-OneAgentRequest {
    if (-not $script:AgentStarted -or $null -eq $script:TcpListener) { return }
    if (-not $script:TcpListener.Pending()) { return }

    $client = $null
    try {
        $client = $script:TcpListener.AcceptTcpClient()
        $client.ReceiveTimeout = 3000
        $client.SendTimeout = 3000
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 1024, $true)
        $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)), 1024, $true)
        $writer.AutoFlush = $true

        $line = $reader.ReadLine()
        $response = Process-AgentRequest -JsonLine $line
        $writer.WriteLine(($response | ConvertTo-Json -Compress -Depth 5))

        $timeText = if ($null -eq $script:LastCommandTime) { '' } else { $script:LastCommandTime.ToString('HH:mm:ss') }
        $agentStatus.Text = "ONLINE: $($agentNameInput.Text) | Last: $($script:LastCommand) $timeText"
        $agentStatus.ForeColor = if ($response.ok) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::DarkOrange }
        $writer.Dispose()
        $reader.Dispose()
    } catch {
        $agentStatus.Text = "Agent request error: $($_.Exception.Message)"
        $agentStatus.ForeColor = [System.Drawing.Color]::Red
    } finally {
        if ($null -ne $client) { try { $client.Close() } catch { } }
    }
}

function Run-ScheduledActionIfDue {
    if ($null -eq $script:ScheduledAction -or $script:Busy) { return }
    if ($script:ScheduledAction.ExecuteAtUtc -eq [DateTime]::MaxValue -and
        ([DateTime]::UtcNow - $script:ScheduledAction.ArmedUtc).TotalSeconds -gt 10) {
        $script:ScheduledAction = $null
        $script:Prepared = $false
        $script:EntryFault = $true
        $executionStatus.Text = 'ARM EXPIRED: prepare again.'
        return
    }
    if ([DateTime]::UtcNow -lt $script:ScheduledAction.ExecuteAtUtc) { return }

    $action = $script:ScheduledAction
    $script:ScheduledAction = $null
    $script:Busy = $true
    $script:RemoteCommandActive = $true
    try {
        $lateMs = ([DateTime]::UtcNow - $action.ExecuteAtUtc).TotalMilliseconds
        Write-PairLog "FIRE pair=$($action.PairId) side=$($action.Side) lateness=$([int]$lateMs)ms"
        if ($action.Side -ne 'CLOSE' -and $lateMs -gt 250) { throw 'Entry missed its execution deadline; late click blocked.' }
        Fire-ArmedChartTraderClick -ArmedClick $action.ArmedClick
        $script:CacheError = 'Waiting for a position sample after the click.'
        $mode = if ($action.Side -eq 'CLOSE') { 'FLAT' } else { 'OPEN' }
        $script:PendingVerification = [pscustomobject]@{
            Mode = $mode
            DeadlineUtc = [DateTime]::UtcNow.AddSeconds(4)
            Label = $action.Side
        }
        $script:LastError = $null
        $executionStatus.Text = "$($action.Side) CLICKED - monitoring asynchronously"
        $executionStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    } catch {
        $script:LastError = $_.Exception.Message
        $executionStatus.Text = "SCHEDULED CLICK FAILED: $script:LastError"
        $executionStatus.ForeColor = [System.Drawing.Color]::Red
    } finally {
        $script:RemoteCommandActive = $false
        $script:Busy = $false
        Set-ControlsForBusyState -Busy $false
    }

    if (-not [string]::IsNullOrWhiteSpace($script:LastError)) {
        Invoke-PairEmergencyClose -Reason "Local scheduled action failed: $script:LastError"
    }
}

function Verify-PendingPositionState {
    if ($null -eq $script:PendingVerification -or $script:Busy) { return }
    $pending = $script:PendingVerification
    try {
        $sample = Get-CachedStatus
        if (-not $sample.ok) {
            if ([DateTime]::UtcNow -lt $pending.DeadlineUtc) { return }
            throw 'No fresh local position available for verification.'
        }
        $position = $sample.position
        $verified = ($pending.Mode -eq 'OPEN' -and -not [string]::IsNullOrWhiteSpace($position) -and $position -cne 'Flat') -or
                    ($pending.Mode -eq 'FLAT' -and $position -ceq 'Flat')
        if ($verified) {
            if ($pending.Mode -eq 'OPEN') { $script:LocalOpened = $true }
            $script:PendingVerification = $null
            $script:LastError = $null
            $executionStatus.Text = "$($pending.Label) VERIFIED - position '$position'"
            $executionStatus.ForeColor = [System.Drawing.Color]::Green
            Set-ControlsForBusyState -Busy $false
            return
        }

        if ([DateTime]::UtcNow -ge $pending.DeadlineUtc) {
            $script:PendingVerification = $null
            $script:LastError = "$($pending.Label) click was sent, but position did not reach $($pending.Mode). Last position '$position'."
            $executionStatus.Text = "VERIFICATION FAILED: $script:LastError"
            $executionStatus.ForeColor = [System.Drawing.Color]::Red
            Set-ControlsForBusyState -Busy $false
            if ($script:PairCoordinatorActive) {
                Invoke-PairEmergencyClose -Reason $script:LastError
            }
        }
    } catch {
        $script:PendingVerification = $null
        $script:LastError = $_.Exception.Message
        $executionStatus.Text = "POSITION MONITOR ERROR: $script:LastError"
        $executionStatus.ForeColor = [System.Drawing.Color]::Red
        Set-ControlsForBusyState -Busy $false
        if ($script:PairCoordinatorActive) {
            Invoke-PairEmergencyClose -Reason $script:LastError
        }
    }
}

function Monitor-ActivePair {
    if (-not $script:PairCoordinatorActive -or $script:Busy -or $script:ScheduledAction) { return }
    $now = [DateTime]::UtcNow
    if (($now - $script:LastPeerPollUtc).TotalMilliseconds -lt 250) { return }
    $script:LastPeerPollUtc = $now
    $local = Get-CachedStatus
    if ($local.ok -and $local.account -cne $LockedAccount) {
        Invoke-PairEmergencyClose -Reason 'Local account safety lock changed.'
        return
    }
    if ($local.ok -and $script:LocalOpened -and $local.position -ceq 'Flat') {
        Invoke-PairEmergencyClose -Reason 'Local position exited after being observed open.'
        return
    }
    if ($script:PeerUnknownSinceUtc -and ($now - $script:PeerUnknownSinceUtc).TotalSeconds -ge $script:DisconnectGraceSeconds) {
        Register-PeerDelay -Reason 'Fresh status has not recovered.'
        return
    }
    try {
        if (-not $script:PeerMonitorTask) {
            $script:PeerRequestUtc = $now
            $script:PeerMonitorTask = Start-PeerTask -Payload ([ordered]@{command='monitor_status'})
            return
        }
        if (-not $script:PeerMonitorTask.IsCompleted) { return }
        $done = $script:PeerMonitorTask
        $script:PeerMonitorTask = $null
        $peer = $done.GetAwaiter().GetResult() | ConvertFrom-Json
        $age = [double]$peer.sampleAgeMs + ($now - $script:PeerRequestUtc).TotalMilliseconds
        if (-not $local.ok -or -not $peer.ok -or $age -gt $script:MaxStateAgeMs -or
            $peer.pairId -cne $script:CurrentPairId -or [string]::IsNullOrWhiteSpace([string]$peer.position)) {
            throw 'A fresh matching pair position is not yet available.'
        }
        if ($peer.account -cne $script:PeerAccount14) {
            Invoke-PairEmergencyClose -Reason 'Peer account safety lock changed.'
            return
        }
        if ($script:PeerUnknownSinceUtc) { Write-PairLog 'PEER STATUS RECOVERED; pair remains active.' }
        $script:PeerUnknownSinceUtc = $null
        $localOpen = $local.position -cne 'Flat'
        $peerOpen = $peer.position -cne 'Flat'
        if ($peer.everOpened -and -not $peerOpen) {
            Invoke-PairEmergencyClose -Reason 'Peer position exited after being observed open.'
            return
        }
        if ($localOpen -and $peerOpen) {
            $script:PairEverOpened = $true
            $executionStatus.Text = "PAIR ACTIVE: Here $($local.position) / Peer $($peer.position)"
            $executionStatus.ForeColor = [System.Drawing.Color]::Green
            return
        }
        if ($script:PairEverOpened) {
            Invoke-PairEmergencyClose -Reason "Confirmed position exit. Local='$($local.position)', peer='$($peer.position)'."
            return
        }
        if ($now -ge $script:PairGraceDeadlineUtc) {
            Invoke-PairEmergencyClose -Reason "Fresh readings confirm both sides did not open. Local='$($local.position)', peer='$($peer.position)'."
        }
    } catch {
        $script:PeerMonitorTask = $null
        Register-PeerDelay -Reason $_.Exception.Message
    }
}

$showSecret.Add_CheckedChanged({ $secretInput.UseSystemPasswordChar = -not $showSecret.Checked })
$pairEnabled.Add_CheckedChanged({
    if ($pairEnabled.Checked) {
        $setupGroup.Text = '1. Prepare Both VMs'
        $buyButton.Text = 'BUY HERE / SELL PEER'
        $sellButton.Text = 'SELL HERE / BUY PEER'
        $closeButton.Text = 'CLOSE BOTH'
    } else {
        $setupGroup.Text = '1. Prepare Trade'
        $buyButton.Text = 'BUY MARKET'
        $sellButton.Text = 'SELL MARKET'
        $closeButton.Text = 'CLOSE POSITION'
        $script:PairCoordinatorActive = $false
    }
})
$agentToggleButton.Add_Click({
    try {
        if ($script:AgentStarted) { Stop-AgentListener } else { Start-AgentListener }
    } catch {
        Show-ErrorMessage -Message $_.Exception.Message -Title 'VM Agent'
    }
})

$testPeerButton.Add_Click({
    try {
        $peer = Test-PeerReady
        $agentStatus.Text = "PEER ONLINE: $($peer.agent) | $($peer.account) | $($peer.position)"
        $agentStatus.ForeColor = [System.Drawing.Color]::Green
    } catch {
        $agentStatus.Text = "PEER FAILED: $($_.Exception.Message)"
        $agentStatus.ForeColor = [System.Drawing.Color]::Red
    }
})

$tickerInput.Add_TextChanged({ Invalidate-Preparation })
$stopLossInput.Add_TextChanged({ Invalidate-Preparation })
$profitInput.Add_TextChanged({ Invalidate-Preparation })
$buyButton.Add_Click({
    if(-not $script:RemoteCommandActive) { $executionStatus.Text='Use the browser to select and prepare accounts.'; return }
    try {
        if ($pairEnabled.Checked) { Invoke-PairedEntry -LocalSide 'BUY' }
        else { Invoke-Entry -Side 'BUY' -ButtonId 'ChartTraderControlQuickBuyMarketButton' }
    } catch { Show-ErrorMessage -Message $_.Exception.Message -Title 'Paired Buy Failed' }
})
$sellButton.Add_Click({
    if(-not $script:RemoteCommandActive) { $executionStatus.Text='Use the browser to select and prepare accounts.'; return }
    try {
        if ($pairEnabled.Checked) { Invoke-PairedEntry -LocalSide 'SELL' }
        else { Invoke-Entry -Side 'SELL' -ButtonId 'ChartTraderControlQuickSellMarketButton' }
    } catch { Show-ErrorMessage -Message $_.Exception.Message -Title 'Paired Sell Failed' }
})
$closeButton.Add_Click({
    try {
        if ($pairEnabled.Checked) { Invoke-PairedClose } else { Invoke-Close }
    } catch { Show-ErrorMessage -Message $_.Exception.Message -Title 'Paired Close Failed' }
})
$refreshButton.Add_Click({ Refresh-Display | Out-Null })

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 500
$refreshTimer.Add_Tick({
    if (-not $script:Busy -and -not $script:ScheduledAction) { Refresh-Display -Quiet $true | Out-Null }
})

$agentTimer = New-Object System.Windows.Forms.Timer
$agentTimer.Interval = 50
$agentTimer.Add_Tick({ Receive-OneAgentRequest })

$scheduledTimer = New-Object System.Windows.Forms.Timer
$scheduledTimer.Interval = 15
$scheduledTimer.Add_Tick({ Run-ScheduledActionIfDue })

$positionTimer = New-Object System.Windows.Forms.Timer
$positionTimer.Interval = 25
$positionTimer.Add_Tick({ Verify-PendingPositionState; Verify-PairedClose })

$pairMonitorTimer = New-Object System.Windows.Forms.Timer
$pairMonitorTimer.Interval = 100
$pairMonitorTimer.Add_Tick({ Monitor-ActivePair })

$form.Add_Shown({
    Refresh-Display | Out-Null
    $refreshTimer.Start()
    $agentTimer.Start()
    $scheduledTimer.Start()
    $positionTimer.Start()
    $pairMonitorTimer.Start()
})
$form.Add_FormClosed({
    $pairMonitorTimer.Stop()
    $positionTimer.Stop()
    $scheduledTimer.Stop()
    $agentTimer.Stop()
    $refreshTimer.Stop()
    Stop-AgentListener
})

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

# Appended before ShowDialog by scripts/build_package.py. Core V10.4 functions remain intact.
# Load in script scope so later timer callbacks retain these functions.
. (Join-Path $PSScriptRoot '..\install\Private-Network.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'ControlGateway.cs')
$script:ControlGateway = $null
$script:ControlPreparedId = ''
$script:BoundPeer = $null
$script:ControlRevision = 0
$script:ControlVersion = '16.0-preview.26'
$controlDirectory = Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data'
$identityPath = Join-Path $controlDirectory 'identity.clixml'
$script:ControlIdentity = Import-Clixml -LiteralPath $identityPath
$agentNameInput.Text = $script:ControlIdentity.Name
$form.Text = "Trading Agent $script:ControlVersion - $($script:ControlIdentity.Name) - V16"
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
    $state['singlePair'] = $true
    $state['skipResults'] = $true
    $state['backgroundExports'] = $true
    $state['syncReceipt'] = $script:SyncReceipt17
    $state['calibrationRequired'] = [bool]$script:CalibrationRequired20
    $state['queueReceipts'] = $true
    $state['queueAccountRefresh'] = $true
    $state['accountRefreshId'] = $script:AccountRefreshId18
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
    if ($Pending.Command -eq 'accounts') { Start-Worker14 -Mode 'accounts' -RefreshId ([string]$request.refreshId); return @{ok=$true;message='Reading account list.'} }
    if ($Pending.Command -eq 'skip_results') {
        $id23=[string]$request.tradeId
        if($id23 -notmatch '^[a-f0-9]{32}$') { throw 'Invalid trade ID.' }
        if($script:ScheduledAction -or $script:PendingVerification -or $script:CloseCheck) { throw 'Wait for trade closure verification.' }
        if((Get-ChartSnapshot).Position -cne 'Flat') { throw 'Results can only be skipped after the account is Flat.' }
        if($script:Worker14 -and ($script:WorkerMode14 -cne 'export' -or $script:WorkerTradeId23 -cne $id23)){throw 'Another desktop operation is running.'}
        $script:SkippedResults23[$id23]=$true
        $skipPath23=Join-Path $controlDirectory 'skipped-results.json'
        ConvertTo-Json -InputObject @($script:SkippedResults23.Keys) | Set-Content ($skipPath23+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($skipPath23+'.tmp') -Destination $skipPath23 -Force
        if($script:Worker14) {
            if($script:WorkerMode14 -cne 'export' -or $script:WorkerTradeId23 -cne $id23) { throw 'Another desktop operation is running.' }
            if(-not $script:Worker14.HasExited) { $script:Worker14.Kill(); if(-not $script:Worker14.WaitForExit(5000)) { throw 'Export has not stopped.' } }
            $script:Worker14.Dispose();$script:Worker14=$null
            $script:Busy=$false;Set-ControlsForBusyState -Busy $false;$refreshTimer.Start()
        }
        $path23=Join-Path $controlDirectory 'sync-pending.json'
        if(Test-Path $path23) {
            $item23=Get-Content $path23 -Raw | ConvertFrom-Json
            if([string]$item23.tradeId -cne $id23) { throw 'A different trade has pending export work.' }
            Remove-Item -LiteralPath $path23 -Force
        }
        $script:RetryTrade14='';$script:Sync14='Results skipped by user.'
        return @{ok=$true;message='Export and desktop retries stopped.'}
    }
    if ($Pending.Command -eq 'bind_single') {
        $null=Assert-Idle14
        if((Get-ChartSnapshot).Position -cne 'Flat') { throw 'Single Pair requires Flat.' }
        if([string]$request.bindingId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid binding.' }
        $script:BoundPeer=$null;$script:SingleBinding23=[string]$request.bindingId
        $script:PairCoordinatorActive=$false;$script:LocalOpened=$false;$script:CurrentPairId=''
        $pairEnabled.Checked=$false;$peerIpInput.Text='';Invalidate-Preparation;$script:ControlPreparedId=''
        return @{ok=$true;message='Single Pair bound; preparation required.'}
    }
    if ($Pending.Command -eq 'post_trade') {
        if([string]$request.tradeId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid trade ID.' }
        $script:RetryTrade14=[string]$request.tradeId
        Start-Worker14 -Mode 'export' -TradeId $script:RetryTrade14 -CaptureOnly:([bool]$request.captureOnly)
        return @{ok=$true;message='Export started.'}
    }
    if ($Pending.Command -eq 'bind_peer') {
        $null=Assert-Idle14
        if ($script:Busy -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:CloseCheck -or $script:PendingVerification) { throw 'VM is active or closing.' }
        $snapshot = Get-ChartSnapshot
        if($snapshot.Position -cne 'Flat') { throw 'Current chart account must be Flat.' }
        $script:SingleBinding23=''
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
        if ($script:Busy -or $script:Worker14 -or $script:ScheduledAction -or $script:CloseCheck -or $script:PendingVerification) { throw 'VM is active or closing.' }
        $snapshot = Get-ChartSnapshot
        if($snapshot.Position -cne 'Flat') { throw 'Current chart account must be Flat.' }
        $script:PairCoordinatorActive=$false
        $script:LocalOpened=$false
        $script:CurrentPairId=''
        Invalidate-Preparation
        $script:ControlPreparedId = ''
        $script:BoundPeer = $null
        $script:SingleBinding23=''
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
        if(Test-Path (Join-Path $controlDirectory 'sync-pending.json')) { throw 'Post-trade sync is pending. Sync Airtable Now before preparing another trade.' }
        $null=Assert-Idle14
        $account14=[string]$request.account
        $qty14=0
        if(-not [int]::TryParse([string]$request.quantity,[ref]$qty14) -or $qty14 -lt 1 -or $qty14 -gt 1000) { throw 'Quantity must be a whole number from 1 to 1000.' }
        if($account14 -cne 'Sim101') {
            if($script:AccountStamp14.ToLocalTime().Date -ne [DateTime]::Today -or $script:Accounts14 -cnotcontains $account14) { throw 'Refresh accounts first. Choose a current Airtable / NinjaTrader match.' }
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
        $pairEnabled.Checked = -not [bool]$request.single
        if([bool]$request.single -and -not $script:SingleBinding23) { throw 'Bind Single Pair first.' }
        # Remote preparation deliberately prepares ONLY this VM. Coordinator mirrors both requests.
        $payload = @{command='prepare'; token=$secretInput.Text; ticker=[string]$request.ticker; stopLoss=$request.stopLoss; profit=$request.profit}
        $answer = Process-AgentRequest -JsonLine ($payload | ConvertTo-Json -Compress)
        if (-not $answer.ok -or -not $script:Prepared) { throw ([string]$answer.message) }
        $script:ControlPreparedId = $prepareId
        return @{ok=$true; message='Prepared and verified locally.'}
    }
    if ($Pending.Command -eq 'peer_check') {
        if (-not $script:BoundPeer -or [string]::IsNullOrWhiteSpace($script:ControlPreparedId) -or [string]$request.prepareId -cne $script:ControlPreparedId) { throw 'Prepare this pair before checking its peer connection.' }
        $last19=''
        for($attempt19=1;$attempt19 -le 3;$attempt19++) {
            try {
                $reply19=Send-PeerRequest -Payload ([ordered]@{command='ping'}) -TimeoutMilliseconds 3000
                if(-not $reply19.ok) { throw 'Peer rejected the authenticated connection check.' }
                return @{ok=$true;message='Direct peer connection verified. No trade command sent.'}
            } catch { $last19=$_.Exception.Message }
            if($attempt19 -lt 3) { Start-Sleep -Milliseconds 250 }
        }
        throw ('Direct peer connection failed after 3 checks: '+$last19+'. No trade command sent.')
    }
    if ($Pending.Command -eq 'single_entry') {
        if(-not $script:SingleBinding23 -or $script:BoundPeer -or $pairEnabled.Checked) { throw 'Prepare Single Pair first.' }
        if(-not $script:ControlPreparedId -or [string]$request.prepareId -cne $script:ControlPreparedId) { throw 'Preparation changed.' }
        $side23=[string]$request.side
        if($side23 -cnotin @('BUY','SELL')) { throw 'Invalid side.' }
        $button23=if($side23 -ceq 'BUY'){'ChartTraderControlQuickBuyMarketButton'}else{'ChartTraderControlQuickSellMarketButton'}
        $script:ControlPreparedId=''
        $script:RemoteCommandActive=$true
        try { Invoke-Entry -Side $side23 -ButtonId $button23 } finally { $script:RemoteCommandActive=$false }
        if($script:LastError) { throw $script:LastError }
        return @{ok=$true;message='Single entry requested; verify actual position.'}
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
        try { Invoke-PairedEntry -LocalSide $side } catch { throw ('Entry stage '+$script:EntryStage19+': '+$_.Exception.Message) } finally { $script:RemoteCommandActive = $false }
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
        Start-ClipboardCopy16 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($code)))
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
    if($syncStatus15) { $syncStatus15.Text=$script:Sync14 }
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
    $area17=[System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $form.Location=[Drawing.Point]::new([Math]::Max($area17.Left,$area17.Right-$form.Width-12),[Math]::Max($area17.Top,$area17.Bottom-$form.Height-12))
    try {
        $certificate = Get-Item -LiteralPath ("Cert:\CurrentUser\My\" + $script:ControlIdentity.Thumbprint)
        $credential = [System.Net.NetworkCredential]::new('', $script:ControlIdentity.Token).Password
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

$controlGroup.Height=220
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
$retry14.Text='Sync Airtable Now'
$retry14.Location=New-Object Drawing.Point(15,132)
$retry14.Size=New-Object Drawing.Size(180,30)
$retry14.Add_Click({
 try {
  Request-ManualSync15
  $syncStatus15.Text=$script:Sync14
 } catch { Show-ErrorMessage $_.Exception.Message }
})
$controlGroup.Controls.Add($retry14)

$setup14=New-Object System.Windows.Forms.Button
$setup14.Text='Airtable Setup'
$setup14.Location=New-Object Drawing.Point(240,132)
$setup14.Size=New-Object Drawing.Size(175,30)
$setup14.Add_Click({ try { Start-Worker14 -Mode 'setup' } catch { Show-ErrorMessage $_.Exception.Message } })
$controlGroup.Controls.Add($setup14)

$syncStatus15=New-Object System.Windows.Forms.Label
$syncStatus15.Text=$script:Sync14
$syncStatus15.Location=New-Object Drawing.Point(15,170)
$syncStatus15.Size=New-Object Drawing.Size(570,42)
$controlGroup.Controls.Add($syncStatus15)

# Hide only this process console; closing the form returns from ShowDialog and exits its dedicated host.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AgentConsole16 {
 [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
}
'@
[void][AgentConsole16]::ShowWindow([AgentConsole16]::GetConsoleWindow(),0)
# Compact presentation; legacy controls remain private implementation state for tested trade functions.
$form.SuspendLayout()
$form.Controls.Clear()
$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
$form.AutoScaleMode='Dpi'
$form.Font=New-Object Drawing.Font('Segoe UI',9)
$form.ClientSize=New-Object Drawing.Size(460,285)
$form.AutoScroll=$true
$heading.Text=$script:ControlIdentity.Name
$heading.AutoSize=$false;$heading.Location=New-Object Drawing.Point(12,8);$heading.Size=New-Object Drawing.Size(436,30)
$heading.Font=New-Object Drawing.Font('Segoe UI Semibold',13)
$form.Controls.Add($heading)
$controlGroup.Controls.Clear()
$controlGroup.Text='Connection and Airtable'
$controlGroup.Location=New-Object Drawing.Point(12,43);$controlGroup.Size=New-Object Drawing.Size(436,230)
$form.Controls.Add($controlGroup)
$connectionButton.Text='Copy Connection Code';$connectionButton.Location=New-Object Drawing.Point(10,20);$connectionButton.Size=New-Object Drawing.Size(205,28)
$controlGroup.Controls.Add($connectionButton)
$connectionStatus.AutoSize=$false;$connectionStatus.Location=New-Object Drawing.Point(10,53);$connectionStatus.Size=New-Object Drawing.Size(416,34)
$controlGroup.Controls.Add($connectionStatus)
$masterLabel16=New-Object Windows.Forms.Label
$masterLabel16.Text='Airtable Master Account';$masterLabel16.Location=New-Object Drawing.Point(10,90);$masterLabel16.Size=New-Object Drawing.Size(220,18)
$controlGroup.Controls.Add($masterLabel16)
$master14.Location=New-Object Drawing.Point(10,111);$master14.Size=New-Object Drawing.Size(250,24);$controlGroup.Controls.Add($master14)
$saveMaster14.Location=New-Object Drawing.Point(270,109);$saveMaster14.Size=New-Object Drawing.Size(156,28);$saveMaster14.Text='Save mapping';$controlGroup.Controls.Add($saveMaster14)
$retry14.Location=New-Object Drawing.Point(10,145);$retry14.Size=New-Object Drawing.Size(205,28);$controlGroup.Controls.Add($retry14)
$setup14.Location=New-Object Drawing.Point(223,145);$setup14.Size=New-Object Drawing.Size(203,28);$controlGroup.Controls.Add($setup14)
$syncStatus15.Location=New-Object Drawing.Point(10,179);$syncStatus15.Size=New-Object Drawing.Size(416,44);$controlGroup.Controls.Add($syncStatus15)
$form.ResumeLayout($true)

$script:ClipboardText16=$null;$script:ClipboardAttempts16=0
function Start-ClipboardCopy16([string]$Text) {
 $script:ClipboardText16=$Text;$script:ClipboardAttempts16=0
 $connectionStatus.Text='Copying connection code...'
}
function Tick-Clipboard16 {
 if(-not $script:ClipboardText16){return}
 try {
  [Windows.Forms.Clipboard]::SetText($script:ClipboardText16)
  $script:ClipboardText16=$null
  $connectionStatus.Text='Code copied. Paste into Register VM in your dashboard.'
 } catch {
  $script:ClipboardAttempts16++
  if($script:ClipboardAttempts16 -lt 8){return}
  $copyForm=New-Object Windows.Forms.Form
  $copyForm.Text='Copy your private connection code';$copyForm.Size=New-Object Drawing.Size(440,180);$copyForm.StartPosition='CenterParent'
  $copyBox=New-Object Windows.Forms.TextBox
  $copyBox.Multiline=$true;$copyBox.ReadOnly=$true;$copyBox.Dock='Fill';$copyBox.ScrollBars='Vertical';$copyBox.Text=$script:ClipboardText16
  $copyForm.Controls.Add($copyBox);$script:ClipboardText16=$null
  $connectionStatus.Text='Clipboard busy. Select and copy the code from the separate window.'
  $copyForm.Show($form);$copyBox.SelectAll();$copyBox.Focus() | Out-Null
 }
}
$clipboardTimer16=New-Object Windows.Forms.Timer
$clipboardTimer16.Interval=100;$clipboardTimer16.Add_Tick({Tick-Clipboard16});$clipboardTimer16.Start()

$script:StartupAttempted16=$false
$script:StartupFinished16=$false
function Tick-Startup16 {
 if($script:StartupAttempted16 -or (Test-SyncDesktopBusy15)){return}
 $script:StartupAttempted16=$true
 try {Start-Worker14 -Mode 'startup'} catch {$script:Sync14='Startup Airtable check failed: '+$_.Exception.Message}
}
function Maintain-StateRefresh16 {
 if($script:Busy -or $script:ScheduledAction -or $script:Worker14){return}
 # Restore a stopped refresh timer after startup/recovery, without falsifying stale status.
 if(-not $refreshTimer.Enabled){$refreshTimer.Start()}
 if(([DateTime]::UtcNow-$script:StateCacheUtc).TotalMilliseconds -ge 750){Refresh-Display -Quiet $true | Out-Null}
}
$maintenanceTimer16=New-Object Windows.Forms.Timer
$maintenanceTimer16.Interval=500
$maintenanceTimer16.Add_Tick({
 try {Maintain-StateRefresh16;Tick-Startup16} catch {$script:Sync14='Agent maintenance: '+$_.Exception.Message}
 $syncStatus15.Text=$script:Sync14
})
$form.Add_Shown({$maintenanceTimer16.Start()})
$form.Add_FormClosed({$maintenanceTimer16.Stop();$clipboardTimer16.Stop();$script:ClipboardText16=$null})

# Calibrate only at startup or by explicit operator request.
$script:CalibratedChart20=[IntPtr]::Zero
$script:CalibratedBounds20=$null
$script:CalibrationRequired20=$true
function Get-CalibratedChart20 {
 if($script:CalibratedChart20 -eq [IntPtr]::Zero){throw 'Calibration required. Click Calibrate Chart 1 in the Trading Agent, then Retry preparation.'}
 try {
  $h=$script:CalibratedChart20
  if(-not [PairedVmAgentNativeV10]::GetTitle($h).StartsWith($WindowTitlePrefix)){throw 'Chart changed.'}
  $rect=[PairedVmAgentNativeV10]::ReadWindowRect($h)
  if(($rect -join ',') -cne ($script:CalibratedBounds20 -join ',')){throw 'Chart moved or resized.'}
  return $h
 } catch {$script:CalibrationRequired20=$true;throw 'Calibration required. Chart changed or is unavailable. Click Calibrate Chart 1, then Retry preparation.'}
}
# Resolve the actual UI Automation Edit button once; preparation reuses the element.
$script:AtmEdit26=$null
$script:AtmEditBounds26=$null
$script:AtmSelectorBounds26=$null
function Find-AtmEdit26($Root,$Bounds) {
 $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
 $candidates26=@()
 foreach($element in $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)) {
  $c=$element.Current;$b=$c.BoundingRectangle
  if($c.IsOffscreen -or -not $c.IsEnabled -or $b.Width -le 0 -or $b.Height -le 0){continue}
  if($c.Name -notmatch '(?i)^edit(?:\s|$)' -and $c.AutomationId -notmatch '(?i)(atm.*edit|edit.*atm)'){continue}
  # Constrain the match to the ATM selector area, excluding unrelated chart buttons.
  if($b.Right -lt $Bounds.Left -or $b.Left -gt ($Bounds.Right+80) -or $b.Bottom -lt ($Bounds.Top-30) -or $b.Top -gt ($Bounds.Bottom+60)){continue}
  $candidates26+=,$element
 }
 if($candidates26.Count -ne 1){throw 'Cannot identify a unique ATM Edit button. Select an ATM template, then click Calibrate Chart 1.'}
 return $candidates26[0]
}
function Initialize-AtmEdit26($Handle,$Root) {
 $script:AtmEdit26=$null
 $selector=Find-UiaById -Root $Root -AutomationId 'ChartTraderControlATMStrategySelector'
 if($null -eq $selector){throw 'ATM Strategy box was not found. Enable Chart Trader and calibrate again.'}
 [void][PairedVmAgentNativeV10]::SetForegroundWindow($Handle)
 $b=$selector.Current.BoundingRectangle
 [void][PairedVmAgentNativeV10]::SetCursorPos([int]($b.Left+$b.Width/2),[int]($b.Top+$b.Height/2))
 Start-Sleep -Milliseconds 450
 $button=Find-AtmEdit26 -Root $Root -Bounds $b
 $null=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
 $script:AtmEditBounds26=$button.Current.BoundingRectangle
 $script:AtmSelectorBounds26=$b
 $script:AtmEdit26=$button
}
function Open-CalibratedAtm26($Handle,$Root) {
 $null=Get-CalibratedChart20
 if($null -eq $script:AtmEdit26){throw 'ATM Edit calibration required. Click Calibrate Chart 1, then Retry preparation.'}
 $selector=Find-UiaById -Root $Root -AutomationId 'ChartTraderControlATMStrategySelector'
 if($null -eq $selector){throw 'ATM Strategy box is unavailable. Calibrate Chart 1 again.'}
 $b=$selector.Current.BoundingRectangle
 if(-not $b.Equals($script:AtmSelectorBounds26)){throw 'Chart Trader layout changed. Click Calibrate Chart 1, then Retry preparation.'}
 for($attempt=1;$attempt -le 2;$attempt++) {
  [void][PairedVmAgentNativeV10]::SetForegroundWindow($Handle)
  [void][PairedVmAgentNativeV10]::SetCursorPos([int]($b.Left+$b.Width/2),[int]($b.Top+$b.Height/2))
  Start-Sleep -Milliseconds 400
  try {
   $c=$script:AtmEdit26.Current
   if($c.IsOffscreen -or -not $c.IsEnabled -or -not $c.BoundingRectangle.Equals($script:AtmEditBounds26)){throw 'Edit changed.'}
   if([PairedVmAgentNativeV10]::GetForegroundWindow() -ne $Handle){throw 'Chart is not foreground.'}
   # Invoke the verified control instead of clicking a saved screen coordinate.
   $invoke=$script:AtmEdit26.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
   $invoke.Invoke()
  } catch {throw 'ATM Edit control changed or is unavailable. Click Calibrate Chart 1, then Retry preparation.'}
  $modal=Wait-ForParametersWindow -TimeoutMilliseconds 2000
  if($null -ne $modal){return $modal}
 }
 throw 'Strategy Parameters did not open. Click Calibrate Chart 1, then Retry preparation.'
}
function Calibrate-Chart20 {
 if($script:Busy -or $script:Worker14 -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:PendingVerification -or $script:CloseCheck){throw 'Wait until this agent is idle before calibration.'}
 $windows=[PairedVmAgentNativeV10]::FindWindows($WindowTitlePrefix)
 if($windows.Count -ne 1){throw 'Open exactly one Chart 1 window, then click Calibrate Chart 1.'}
 $h=$windows[0]
 $root=[System.Windows.Automation.AutomationElement]::FromHandle($h)
 $position=Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlPositionQuantityText')
 if($position -cne 'Flat'){throw 'The displayed chart must be Flat before calibration.'}
 [void][PairedVmAgentNativeV10]::ShowWindow($h,9)
 if(-not [PairedVmAgentNativeV10]::SetWindowPos($h,[IntPtr]::Zero,$WindowX,$WindowY,$WindowWidth,$WindowHeight,0x0040)){throw 'Chart calibration could not resize the window.'}
 $script:CalibratedChart20=$h
 $script:CalibratedBounds20=[PairedVmAgentNativeV10]::ReadWindowRect($h)
 Invalidate-Preparation
 $script:ControlPreparedId=''
 # Chart tracking remains usable if Edit calibration needs an ATM template selected.
 Initialize-AtmEdit26 -Handle $h -Root ([System.Windows.Automation.AutomationElement]::FromHandle($h))
 $script:CalibrationRequired20=$false
 $calibrationStatus20.Text='Chart 1 and ATM Edit calibrated.'
}
$form.ClientSize=New-Object Drawing.Size(460,348)
$calibrate20=New-Object Windows.Forms.Button
$calibrate20.Text='Calibrate Chart 1';$calibrate20.Location=New-Object Drawing.Point(22,282);$calibrate20.Size=New-Object Drawing.Size(205,28)
$calibrationStatus20=New-Object Windows.Forms.Label
$calibrationStatus20.Location=New-Object Drawing.Point(22,314);$calibrationStatus20.Size=New-Object Drawing.Size(416,30)
$form.Controls.Add($calibrate20);$form.Controls.Add($calibrationStatus20)
$calibrate20.Add_Click({try{Calibrate-Chart20}catch{$calibrationStatus20.Text=$_.Exception.Message}})
$form.Add_Shown({try{Calibrate-Chart20}catch{$calibrationStatus20.Text=$_.Exception.Message}})

[void]$form.ShowDialog()
exit 0
