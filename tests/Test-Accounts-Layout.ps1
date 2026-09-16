$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot '../agent/AirtableWorker.ps1') -Raw
$errors=$null;$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$errors)
if($errors){throw $errors}
foreach($name in @('GetAccountsRect','SameAccountsRect','NewAccountsLayout','GetAccountsLayoutKey','PrepareAccountsLayout','SaveAccountsLayout')) {
 $fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 if(-not $fn){throw "Missing $name"};. ([scriptblock]::Create($fn.Extent.Text))
}
# Simulated Windows adapter: exercise production preparation/cache code without moving a desktop.
Add-Type @'
using System;
public class NTDesktop {
 public struct RECT { public int L,T,R,B; }
 public static RECT Rect;
 public static int Moves,Restores;
 public static bool Minimized,Maximized,RefuseMove,RefuseFocus;
 public static IntPtr Foreground=(IntPtr)7;
 public static bool GetWindowRect(IntPtr h,out RECT r){r=Rect;return true;}
 public static bool IsIconic(IntPtr h){return Minimized;}
 public static bool IsZoomed(IntPtr h){return Maximized;}
 public static uint ProcessId(IntPtr h){return (uint)System.Diagnostics.Process.GetCurrentProcess().Id;}
 public static bool ShowWindow(IntPtr h,int cmd){Restores++;Minimized=false;Maximized=false;return true;}
 public static bool MoveWindow(IntPtr h,int x,int y,int w,int height,bool repaint){Moves++;if(!RefuseMove)Rect=new RECT{L=x,T=y,R=x+w,B=y+height};return true;}
 public static IntPtr GetForegroundWindow(){return Foreground;}
 public static bool SetForegroundWindow(IntPtr h){if(!RefuseFocus)Foreground=h;return !RefuseFocus;}
}
'@
function Log([string]$Message) {}
$script:sleeps=0;$script:plans=0
function Start-Sleep {param([int]$Milliseconds) $script:sleeps++}
$planner=${function:NewAccountsLayout}
function NewAccountsLayout($Cfg,$Display) {$script:plans++; & $planner $Cfg $Display}
$script:display=[pscustomobject]@{Name='DISPLAY1';Left=0;Top=0;Width=1920;Height=1040;Dpi=96}
function GetAccountsDisplay([IntPtr]$Handle) {return $script:display}
function Assert($Condition,[string]$Message) {if(-not $Condition){throw $Message}}
function MustFail([scriptblock]$Action,[string]$Message) {$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Assert $failed $Message}
$state=Join-Path ([IO.Path]::GetTempPath()) ('accounts-layout-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($state)
$cfg=[pscustomobject]@{Left=954;Top=6;Width=964;Height=1148;X=466;Y=820}
try {
 $first=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ($first.Layout.Height -eq 1040 -and $first.Layout.Top -eq 0 -and $first.Layout.Y -eq 820) '1080p taskbar fit failed'
 Assert ([NTDesktop]::Moves -eq 1 -and [NTDesktop]::Restores -eq 0) 'First export should move once without restoring a normal window'
 Assert (-not (Test-Path $first.CacheFile)) 'Unverified export click must not be cached'
 SaveAccountsLayout $first
 for($i=0;$i -lt 100;$i++) {$warm=PrepareAccountsLayout ([IntPtr]7) $cfg}
 Assert (-not $warm.NeedsSave -and [NTDesktop]::Moves -eq 1 -and $script:plans -eq 1 -and $script:sleeps -eq 0) 'Repeated exports resized, recalculated, or slept'
 # An unchanged layout can require focus but never requires a resize.
 [NTDesktop]::Foreground=[IntPtr]8;$warm=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ([NTDesktop]::Foreground -eq [IntPtr]7 -and [NTDesktop]::Moves -eq 1) 'Focus-only export moved the window'
 [NTDesktop]::MoveWindow([IntPtr]7,50,50,900,900,$true) | Out-Null
 $changed=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ($changed.NeedsSave -and [NTDesktop]::Moves -eq 3) 'User-moved window not repaired'
 SaveAccountsLayout $changed
 [NTDesktop]::Minimized=$true;$restored=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ([NTDesktop]::Restores -eq 1 -and $restored.NeedsSave) 'Minimized window not restored'
 SaveAccountsLayout $restored
 [NTDesktop]::Maximized=$true;$restored=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ([NTDesktop]::Restores -eq 2 -and $restored.NeedsSave) 'Maximized window not restored';SaveAccountsLayout $restored
 $script:display.Dpi=120;$dpi=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert $dpi.NeedsSave 'DPI change did not invalidate cache';SaveAccountsLayout $dpi
 $script:display.Height=728;$small=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ($small.Layout.Height -eq 728 -and $small.Layout.Y -eq 628) 'Smaller VM click did not fit';SaveAccountsLayout $small
 $script:display.Left=-1920;$script:display.Name='DISPLAY2';$monitor=PrepareAccountsLayout ([IntPtr]7) $cfg
 Assert ($monitor.Layout.Left -ge -1920 -and $monitor.Layout.Left+$monitor.Layout.Width -le 0) 'Negative-coordinate monitor fit failed';SaveAccountsLayout $monitor
 $newWindow=PrepareAccountsLayout ([IntPtr]9) $cfg
 Assert $newWindow.NeedsSave 'Recreated window reused stale handle cache';SaveAccountsLayout $newWindow
 Set-Content $newWindow.CacheFile '{broken'
 $corrupt=PrepareAccountsLayout ([IntPtr]9) $cfg
 Assert $corrupt.NeedsSave 'Corrupt cache was not rebuilt';SaveAccountsLayout $corrupt
 $bad=Get-Content $corrupt.CacheFile -Raw | ConvertFrom-Json;$bad.Layout.Y=99999
 $bad | ConvertTo-Json | Set-Content $corrupt.CacheFile
 $repaired=PrepareAccountsLayout ([IntPtr]9) $cfg
 Assert ($repaired.NeedsSave -and $repaired.Layout.Y -eq 628) 'Invalid cached click accepted';SaveAccountsLayout $repaired
 $tall=[pscustomobject]@{Name='TALL';Left=0;Top=0;Width=1920;Height=1200;Dpi=96}
 $original=NewAccountsLayout $cfg $tall
 Assert ((SameAccountsRect $original $cfg) -and $original.X -eq $cfg.X -and $original.Y -eq $cfg.Y) 'Existing large-screen layout changed'
 [NTDesktop]::RefuseMove=$true;$script:display.Height=1040
 MustFail {PrepareAccountsLayout ([IntPtr]9) $cfg} 'OS-rejected resize accepted'
 [NTDesktop]::RefuseMove=$false;[NTDesktop]::RefuseFocus=$true;[NTDesktop]::Foreground=[IntPtr]8
 MustFail {PrepareAccountsLayout ([IntPtr]9) $cfg} 'Background window accepted'
 $script:display.Width=500
 MustFail {PrepareAccountsLayout ([IntPtr]9) $cfg} 'Unusable desktop accepted'
 'PASS: 100 cached exports without recalculation, resize or sleep; 1080p/small/negative-monitor layouts; focus; moved/minimized windows; DPI and handle invalidation; corrupt cache; rejected resize/focus.'
} finally {Remove-Item -LiteralPath $state -Recurse -Force}
