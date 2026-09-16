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
 if($null -eq $script:AtmEdit26){
  if($null -ne $script:ManualEdit261){return Open-ManualAtm261 -Handle $Handle -Root $Root -Saved $script:ManualEdit261}
  throw 'ATM Edit calibration required. Click Calibrate Chart 1 or Locate Edit button, then Retry preparation.'
 }
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
 $root=[System.Windows.Automation.AutomationElement]::FromHandle($h)
 $script:ManualEdit261=$null
 try {
  Initialize-AtmEdit26 -Handle $h -Root $root
  $calibrationStatus20.Text='Chart 1 and ATM Edit calibrated.'
 } catch {
  if(-not (Restore-ManualEdit261 -Handle $h -Root $root)){throw 'Cannot find ATM Edit automatically. Use Locate Edit button to save its location on this VM.'}
  $calibrationStatus20.Text='Chart 1 calibrated using your saved Edit location.'
 }
 $script:CalibrationRequired20=$false
}
$form.ClientSize=New-Object Drawing.Size(460,348)
$calibrate20=New-Object Windows.Forms.Button
$calibrate20.Text='Calibrate Chart 1';$calibrate20.Location=New-Object Drawing.Point(22,282);$calibrate20.Size=New-Object Drawing.Size(205,28)
$calibrationStatus20=New-Object Windows.Forms.Label
$calibrationStatus20.Location=New-Object Drawing.Point(22,314);$calibrationStatus20.Size=New-Object Drawing.Size(416,30)
$form.Controls.Add($calibrate20);$form.Controls.Add($calibrationStatus20)
$calibrate20.Add_Click({try{Calibrate-Chart20}catch{$calibrationStatus20.Text=$_.Exception.Message}})
$form.Add_Shown({try{Calibrate-Chart20}catch{$calibrationStatus20.Text=$_.Exception.Message}})
