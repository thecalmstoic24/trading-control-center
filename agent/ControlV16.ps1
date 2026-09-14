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
