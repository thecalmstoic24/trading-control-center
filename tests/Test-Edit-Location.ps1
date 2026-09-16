$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$source=Join-Path $PSScriptRoot '../agent/ManualEdit26.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
foreach($name in @('Test-EditLayout261','Test-EditPoint261','Restore-ManualEdit261','Start-LocateEdit261','Stop-LocateEdit261','Tick-LocateEdit261')) {
 $fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 if(-not $fn){throw "Missing function $name"};Invoke-Expression $fn.Extent.Text
}
function Check($condition,$message){if(-not $condition){throw $message}}
$current=[pscustomobject]@{Schema=1;Machine='VM-A';Vm='BUL-HONG';Width=780;Height=460;Dpi=96;Left=64;Top=30;SelectorX=600;SelectorY=340;SelectorWidth=150;SelectorHeight=26}
$saved=$current | Select-Object *;$saved | Add-Member -NotePropertyName X -NotePropertyValue 735;$saved | Add-Member -NotePropertyName Y -NotePropertyValue 353
Check (Test-EditPoint261 $current 735 353) 'Valid Edit center rejected'
foreach($point in @(@(610,353),@(735,339),@(735,366),@(800,353),@([double]::NaN,353),@([double]::PositiveInfinity,353))){Check (-not (Test-EditPoint261 $current $point[0] $point[1])) 'Outside or invalid point accepted'}
Check (Test-EditLayout261 $saved $current) 'Matching layout rejected'
foreach($field in @('Machine','Vm','Dpi','Width','Height','SelectorX','SelectorY','SelectorWidth','SelectorHeight')) {
 $changed=$current | Select-Object *;$changed.$field='changed';Check (-not (Test-EditLayout261 $saved $changed)) "Changed $field accepted"
}
$shifted=$current | Select-Object *;$shifted.Left=-1920;$shifted.Top=60
Check (Test-EditLayout261 $saved $shifted) 'Relative layout cannot survive explicit recalibration at another origin'
function Get-EditLayout261 {param($Handle,$Root) return $current}
$script:EditLocationPath261=Join-Path ([IO.Path]::GetTempPath()) ('edit-test-'+[guid]::NewGuid().ToString('N')+'.json')
try {
 Check (-not (Restore-ManualEdit261 1 $null)) 'Missing setting accepted'
 $saved | ConvertTo-Json | Set-Content $script:EditLocationPath261
 Check (Restore-ManualEdit261 1 $null) 'Verified saved setting was not restored'
 Check ($script:ManualEdit261.X -eq 735) 'Saved point changed'
 $invalid=$saved | Select-Object *;$invalid.X=610;$invalid | ConvertTo-Json | Set-Content $script:EditLocationPath261
 Check (-not (Restore-ManualEdit261 1 $null)) 'Unsafe stored point restored'
 Set-Content $script:EditLocationPath261 '{broken'
 Check (-not (Restore-ManualEdit261 1 $null)) 'Corrupt saved JSON accepted'
} finally {Remove-Item $script:EditLocationPath261 -ErrorAction SilentlyContinue}
$locateTimer261=[pscustomobject]@{Stops=0};$locateTimer261 | Add-Member ScriptMethod Stop {$this.Stops++}
$calibrate20=[pscustomobject]@{Enabled=$false};$locateEdit261=[pscustomobject]@{Text='Cancel locating'};$calibrationStatus20=[pscustomobject]@{Text=''}
$script:LocatingEdit261=$true;$script:Busy=$true;$script:LocateDeadline261=[DateTime]::UtcNow.AddSeconds(5);$script:completed=0
function Complete-LocateEdit261 {$script:completed++;Stop-LocateEdit261}
Tick-LocateEdit261;Check ($script:completed -eq 0 -and $calibrationStatus20.Text -match 'seconds') 'Capture happened before countdown'
$script:LocateDeadline261=[DateTime]::UtcNow.AddSeconds(-1);Tick-LocateEdit261;Tick-LocateEdit261
Check ($script:completed -eq 1 -and -not $script:Busy -and $calibrate20.Enabled) 'Countdown did not release busy state exactly once'
$script:LocatingEdit261=$true;$script:Busy=$true;Start-LocateEdit261
Check (-not $script:LocatingEdit261 -and -not $script:Busy) 'Cancel did not release desktop'
$script:Busy=$true;$blocked=$false;try{Start-LocateEdit261}catch{$blocked=$true}
Check $blocked 'Capture started while trading was busy'
'PASS: saved-point bounds, per-VM layout validation, corrupt/missing settings, countdown, one-shot capture, cancellation, busy rejection.'
