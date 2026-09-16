$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
public static class PairedVmAgentNativeV10 {
 public static int X,Y,Clicks; public static bool Covered;
 public static int[] ReadWindowRect(IntPtr h){return new int[]{64,30,780,460};}
 public static bool SetForegroundWindow(IntPtr h){return true;}
 public static bool SetCursorPos(int x,int y){X=x;Y=y;return true;}
 public static IntPtr GetForegroundWindow(){return (IntPtr)1;}
 public static void LeftClick(){Clicks++;}
}
public static class EditLocation261 {
 public struct POINT {public int X,Y;public POINT(int x,int y){X=x;Y=y;}}
 public static IntPtr WindowFromPoint(POINT p){return PairedVmAgentNativeV10.Covered?(IntPtr)2:(IntPtr)1;}
 public static IntPtr GetAncestor(IntPtr h,uint f){return h;}
}
'@
$source=Join-Path $PSScriptRoot '../agent/ControlV16.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Open-CalibratedAtm26'},$true)
Invoke-Expression $fn.Extent.Text
function Check($condition,$message){if(-not $condition){throw $message}}
function Get-CalibratedChart20 {return [IntPtr]1}
function Find-UiaById {param($Root,$AutomationId) return [pscustomobject]@{Current=[pscustomobject]@{BoundingRectangle=[pscustomobject]@{Left=664;Top=370;Width=150;Height=26}}}}
function Start-Sleep {param($Milliseconds)}
$script:modalFails=$false
function Wait-ForParametersWindow {param($TimeoutMilliseconds) if(-not $script:modalFails){return [pscustomobject]@{Current=[pscustomobject]@{ProcessId=10}}}}
$script:manualUsed=$false
function Open-ManualAtm261 {param($Handle,$Root,$Saved) $script:manualUsed=$true;return 'manual'}
$EditRelativeX=735;$EditRelativeY=353;$root=[pscustomobject]@{Current=[pscustomobject]@{ProcessId=10}}
$script:ManualEdit261=$null
$null=Open-CalibratedAtm26 -Handle ([IntPtr]1) -Root $root
Check ([PairedVmAgentNativeV10]::X -eq 799 -and [PairedVmAgentNativeV10]::Y -eq 383) 'Preview 24 preset coordinates changed'
Check ([PairedVmAgentNativeV10]::Clicks -eq 1 -and -not $script:manualUsed) 'Preset did not work without manual calibration'
$script:ManualEdit261=@{X=750;Y=353};$null=Open-CalibratedAtm26 -Handle ([IntPtr]1) -Root $root
Check ($script:manualUsed -and [PairedVmAgentNativeV10]::Clicks -eq 1) 'Saved override was not used'
$script:ManualEdit261=$null;[PairedVmAgentNativeV10]::Covered=$true;$blocked=$false
try{$null=Open-CalibratedAtm26 -Handle ([IntPtr]1) -Root $root}catch{$blocked=$_.Exception.Message -match 'covers ATM'}
Check ($blocked -and [PairedVmAgentNativeV10]::Clicks -eq 1) 'Covered chart was clicked'
[PairedVmAgentNativeV10]::Covered=$false;$script:modalFails=$true;$blocked=$false
try{$null=Open-CalibratedAtm26 -Handle ([IntPtr]1) -Root $root}catch{$blocked=$_.Exception.Message -match 'Locate Edit'}
Check ($blocked -and [PairedVmAgentNativeV10]::Clicks -eq 3) 'Failed preset did not stop after two attempts'
$calibrate=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Calibrate-Chart20'},$true).Extent.Text
Check ($calibrate -notmatch 'Initialize-AtmEdit|Wait-ForParameters|Start-LocateEdit') 'Calibration still requires Edit discovery'
'PASS: Preview 24 preset, explicit saved override, covered-chart rejection, bounded retry and no mandatory Edit discovery.'
