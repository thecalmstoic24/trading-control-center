# Optional, VM-local fallback. Automatic UI Automation calibration remains the default.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EditLocation261 {
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
 public struct POINT { public int X,Y; public POINT(int x,int y){X=x;Y=y;} }
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr window,uint flags);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
}
'@
$script:ManualEdit261=$null
$script:LocatingEdit261=$false
$script:EditLocationPath261=Join-Path $controlDirectory 'atm-edit-location.json'
function Get-EditLayout261($Handle,$Root) {
 $rect=[PairedVmAgentNativeV10]::ReadWindowRect($Handle)
 $selector=Find-UiaById -Root $Root -AutomationId 'ChartTraderControlATMStrategySelector'
 if($null -eq $selector -or $selector.Current.IsOffscreen -or -not $selector.Current.IsEnabled){throw 'ATM Strategy box is unavailable. Select an ATM template first.'}
 $b=$selector.Current.BoundingRectangle
 if($b.Width -le 0 -or $b.Height -le 0){throw 'ATM Strategy box is not visible.'}
 return [pscustomobject]@{Schema=1;Machine=$env:COMPUTERNAME;Vm=$script:ControlIdentity.Name;Width=$rect[2];Height=$rect[3];Dpi=[EditLocation261]::GetDpiForWindow($Handle);Left=$rect[0];Top=$rect[1];SelectorX=($b.Left-$rect[0]);SelectorY=($b.Top-$rect[1]);SelectorWidth=$b.Width;SelectorHeight=$b.Height}
}
function Test-EditLayout261($Saved,$Current) {
 if($null -eq $Saved -or $null -eq $Current){return $false}
 foreach($key in @('Schema','Machine','Vm','Width','Height','Dpi','SelectorX','SelectorY','SelectorWidth','SelectorHeight')) {
  if($null -eq $Saved.$key -or [string]$Saved.$key -cne [string]$Current.$key){return $false}
 }
 return $true
}
function Test-EditPoint261($Layout,[double]$X,[double]$Y) {
 # Limit a mouse click to the ATM selector's right-hand area, away from trade buttons.
 return (-not [double]::IsNaN($X) -and -not [double]::IsNaN($Y) -and $X -ge ($Layout.SelectorX+$Layout.SelectorWidth/2) -and $X -le ($Layout.SelectorX+$Layout.SelectorWidth+24) -and $Y -ge $Layout.SelectorY -and $Y -lt ($Layout.SelectorY+$Layout.SelectorHeight) -and $X -ge 0 -and $X -lt $Layout.Width -and $Y -ge 0 -and $Y -lt $Layout.Height)
}
function Restore-ManualEdit261($Handle,$Root) {
 $script:ManualEdit261=$null
 if(-not (Test-Path -LiteralPath $script:EditLocationPath261)){return $false}
 try {
  $saved=Get-Content -LiteralPath $script:EditLocationPath261 -Raw | ConvertFrom-Json
  $current=Get-EditLayout261 $Handle $Root
  if(-not (Test-EditLayout261 $saved $current) -or $null -eq $saved.X -or $null -eq $saved.Y -or -not (Test-EditPoint261 $current $saved.X $saved.Y)){return $false}
  $script:ManualEdit261=$saved
  return $true
 } catch {return $false}
}
function Assert-EditTarget261($Handle,$Layout,$Saved) {
 $null=Get-CalibratedChart20
 if(-not (Test-EditLayout261 $Saved $Layout) -or -not (Test-EditPoint261 $Layout $Saved.X $Saved.Y)){throw 'Saved Edit layout changed. Click Locate Edit button again.'}
 if([PairedVmAgentNativeV10]::GetForegroundWindow() -ne $Handle){throw 'Chart 1 must stay in front while locating Edit.'}
 $x=[int]($Layout.Left+$Saved.X);$y=[int]($Layout.Top+$Saved.Y)
 $point=New-Object EditLocation261+POINT($x,$y)
 $hit=[EditLocation261]::WindowFromPoint($point)
 if($hit -eq [IntPtr]::Zero -or ([EditLocation261]::GetAncestor($hit,2) -ne $Handle -and [EditLocation261]::GetAncestor($hit,3) -ne $Handle)){throw 'Another window covers the saved Edit location. Bring Chart 1 to the front.'}
}
function Open-ManualAtm261($Handle,$Root,$Saved) {
 $layout=Get-EditLayout261 $Handle $Root
 if(-not (Test-EditLayout261 $Saved $layout) -or -not (Test-EditPoint261 $layout $Saved.X $Saved.Y)){throw 'Saved Edit layout changed. Click Locate Edit button again.'}
 if($null -ne (Wait-ForParametersWindow -TimeoutMilliseconds 100)){throw 'Close the existing strategy parameters window before continuing.'}
 [void][PairedVmAgentNativeV10]::SetForegroundWindow($Handle)
 [void][PairedVmAgentNativeV10]::SetCursorPos([int]($layout.Left+$layout.SelectorX+$layout.SelectorWidth/2),[int]($layout.Top+$layout.SelectorY+$layout.SelectorHeight/2))
 Start-Sleep -Milliseconds 400
 [void][PairedVmAgentNativeV10]::SetCursorPos([int]($layout.Left+$Saved.X),[int]($layout.Top+$Saved.Y))
 Start-Sleep -Milliseconds 150
 Assert-EditTarget261 $Handle (Get-EditLayout261 $Handle $Root) $Saved
 [PairedVmAgentNativeV10]::LeftClick()
 $modal=Wait-ForParametersWindow -TimeoutMilliseconds 2000
 if($null -eq $modal){throw 'That location did not open ATM parameters. Click Locate Edit button and try again.'}
 if($modal.Current.ProcessId -ne $Root.Current.ProcessId){throw 'The parameters window belongs to a different NinjaTrader process.'}
 return $modal
}
function Stop-LocateEdit261 {
 $locateTimer261.Stop()
 if($script:LocatingEdit261){$script:LocatingEdit261=$false;$script:Busy=$false}
 $calibrate20.Enabled=$true;$locateEdit261.Text='Locate Edit button'
}
function Start-LocateEdit261 {
 if($script:LocatingEdit261){Stop-LocateEdit261;$calibrationStatus20.Text='Locate Edit canceled. Previous calibration kept.';return}
 if($script:Busy -or $script:Worker14 -or $script:ScheduledAction -or $script:PairCoordinatorActive -or $script:PendingVerification -or $script:CloseCheck){throw 'Wait until this VM is idle before locating Edit.'}
 # Calibrate the chart frame if it has not yet been established. Missing automatic Edit is expected here.
 if($script:CalibratedChart20 -eq [IntPtr]::Zero){try{Calibrate-Chart20}catch{}}
 $h=Get-CalibratedChart20
 $root=[System.Windows.Automation.AutomationElement]::FromHandle($h)
 $position=Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlPositionQuantityText')
 if($position -cne 'Flat'){throw 'The displayed chart must be Flat before locating Edit.'}
 if($null -ne (Wait-ForParametersWindow -TimeoutMilliseconds 100)){throw 'Close the strategy parameters dialog first, then click Locate Edit button.'}
 $script:LocateLayout261=Get-EditLayout261 $h $root
 Invalidate-Preparation;$script:ControlPreparedId=''
 $script:Busy=$true;$script:LocatingEdit261=$true
 $script:LocateDeadline261=[DateTime]::UtcNow.AddSeconds(5)
 $calibrate20.Enabled=$false;$locateEdit261.Text='Cancel locating'
 [void][PairedVmAgentNativeV10]::SetForegroundWindow($h)
 $calibrationStatus20.Text='5 seconds: point at the center of Edit. Do not click.'
 $locateTimer261.Start()
}
function Complete-LocateEdit261 {
 $modal=$null
 try {
  # Read the pointer before moving it anywhere.
  $point=[Windows.Forms.Cursor]::Position
  $h=Get-CalibratedChart20;$root=[System.Windows.Automation.AutomationElement]::FromHandle($h)
  $layout=Get-EditLayout261 $h $root
  if(-not (Test-EditLayout261 $script:LocateLayout261 $layout)){throw 'Chart layout changed during the countdown. Locate Edit again.'}
  $position=Get-UiaText -Element (Find-UiaById -Root $root -AutomationId 'ChartTraderControlPositionQuantityText')
  if($position -cne 'Flat'){throw 'Chart must remain Flat during calibration.'}
  $saved=$layout | Select-Object *
  $saved | Add-Member -NotePropertyName X -NotePropertyValue ($point.X-$layout.Left)
  $saved | Add-Member -NotePropertyName Y -NotePropertyValue ($point.Y-$layout.Top)
  Assert-EditTarget261 $h $layout $saved
  $calibrationStatus20.Text='Checking Edit location...'
  $modal=Open-ManualAtm261 $h $root $saved
  $dialogHandle=[IntPtr]$modal.Current.NativeWindowHandle
  if($dialogHandle -eq [IntPtr]::Zero){throw 'Cannot verify the parameters window handle. Location was not saved.'}
  Close-ParametersWithoutSaving -Modal $modal
  $deadline=[DateTime]::UtcNow.AddSeconds(2)
  while([EditLocation261]::IsWindow($dialogHandle) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 80}
  if([EditLocation261]::IsWindow($dialogHandle)){throw 'Parameters opened but could not be closed. Close with Cancel, then locate again.'}
  $modal=$null
  # Save only after a new, same-process parameters dialog opened and closed without saving.
  $temp=$script:EditLocationPath261+'.tmp'
  $saved | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding UTF8
  Move-Item -LiteralPath $temp -Destination $script:EditLocationPath261 -Force
  $script:ManualEdit261=$saved;$script:AtmEdit26=$null;$script:CalibrationRequired20=$false
  $calibrationStatus20.Text='Edit verified and saved for this VM. Chart 1 calibrated.'
 } finally {
  if($null -ne $modal){Close-ParametersWithoutSaving -Modal $modal}
  Stop-LocateEdit261
 }
}
function Tick-LocateEdit261 {
 if(-not $script:LocatingEdit261){return}
 $remaining=[int][Math]::Ceiling(($script:LocateDeadline261-[DateTime]::UtcNow).TotalSeconds)
 if($remaining -gt 0){$calibrationStatus20.Text="$remaining seconds: point at the center of Edit. Do not click.";return}
 $locateTimer261.Stop()
 try{Complete-LocateEdit261}catch{$calibrationStatus20.Text=$_.Exception.Message;Stop-LocateEdit261}
}
$form.ClientSize=New-Object Drawing.Size(460,370)
$calibrationStatus20.Size=New-Object Drawing.Size(416,50)
$locateEdit261=New-Object Windows.Forms.Button
$locateEdit261.Text='Locate Edit button';$locateEdit261.Location=New-Object Drawing.Point(235,282);$locateEdit261.Size=New-Object Drawing.Size(203,28)
$form.Controls.Add($locateEdit261)
$locateTimer261=New-Object Windows.Forms.Timer
$locateTimer261.Interval=100;$locateTimer261.Add_Tick({Tick-LocateEdit261})
$locateEdit261.Add_Click({try{Start-LocateEdit261}catch{$calibrationStatus20.Text=$_.Exception.Message;Stop-LocateEdit261}})
$form.Add_FormClosed({Stop-LocateEdit261;$locateTimer261.Dispose()})
