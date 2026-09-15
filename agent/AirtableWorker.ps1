# One-click NinjaTrader Accounts export and direct Airtable sync.
# First run prompts for a token, validates access, and saves it encrypted for this Windows user/PC.
param([string]$RequestPath,[string]$ResultPath)
function Get-AccountId16([string]$Name) {
 if($Name -cmatch '^(BX-?M?\d+)(?:!Bulenox)+$') { return $Matches[1] }
 return $Name
}
function Get-AccountMatches16($Names, $Records, [string]$Master) {
 $key=($Master -replace '[^a-zA-Z0-9]','').ToUpperInvariant()
 $group=@($Records | Where-Object { (([string]$_.fields.'Master Account' -replace '[^a-zA-Z0-9]','').ToUpperInvariant()) -ceq $key })
 $distinct=@($group | ForEach-Object { [string]$_.fields.'Master Account' } | Sort-Object -Unique)
 if($distinct.Count -gt 1) { throw 'Ambiguous Master Account names. Use an exact Master Account mapping.' }
 foreach($name in @($Names)) {
  $id=Get-AccountId16 ([string]$name)
  $same=@($Names | Where-Object { (Get-AccountId16 ([string]$_)) -ceq $id })
  if($same.Count -gt 1) { throw ('Ambiguous NinjaTrader account ID: '+$id+'. Resolve duplicate connection labels before refreshing.') }
  $found=@($Records | Where-Object { [string]$_.fields.id -ceq $id })
  if($same.Count -eq 1 -and $found.Count -eq 1 -and @($group | Where-Object { $_.id -ceq $found[0].id }).Count -eq 1) { $name }
 }
}
$Setup=$false; $Preview=$false; $ExportOnly=$false; $Diagnose=$false; $CsvPath=$null
$request14=Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$queue14=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data\sync-pending.json'
$done14=Join-Path $env:LOCALAPPDATA 'TradingControlCenter\agent-data\sync-done.json'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class NTDesktop {
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT rect);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder text,int count);
 public static string Title(IntPtr h) { var text=new StringBuilder(2048); GetWindowText(h,text,text.Capacity); return text.ToString(); }
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int cmd);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int width,int height,bool repaint);
 public delegate bool EnumProc(IntPtr h,IntPtr extra);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback,IntPtr extra);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc callback,IntPtr extra);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint process);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder name,int max);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsChild(IntPtr parent,IntPtr child);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h,uint msg,IntPtr w,string text);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO { public int cbSize; public uint flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public RECT rect; }
 [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread,ref GUITHREADINFO info);
 public static string ClassName(IntPtr h) { var b=new StringBuilder(256); GetClassName(h,b,256); return b.ToString(); }
 public static uint ProcessId(IntPtr h) { uint p; GetWindowThreadProcessId(h,out p); return p; }
 public static IntPtr Focused(IntPtr h) { uint p; uint t=GetWindowThreadProcessId(h,out p); var g=new GUITHREADINFO(); g.cbSize=Marshal.SizeOf(g); return GetGUIThreadInfo(t,ref g)?g.focus:IntPtr.Zero; }
 public static IntPtr SaveDialog(uint process) {
  IntPtr found=IntPtr.Zero; int count=0;
  EnumWindows(delegate(IntPtr h,IntPtr x) {
   string title=Title(h);
   if(ProcessId(h)==process && IsWindowVisible(h) && ClassName(h)=="#32770" && (title=="Export As" || title=="Save As")) { found=h;count++; }
   return true;
  },IntPtr.Zero);
  if(count>1) throw new Exception("Multiple save dialogs are open. Close leftover save dialogs and retry.");
  return found;
 }
 [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="SendMessageTimeoutW")] static extern IntPtr ReadMessage(IntPtr h,uint msg,UIntPtr w,StringBuilder text,uint flags,uint timeout,out UIntPtr result);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h,uint command);
 public static string ReadEdit(IntPtr h) {
  var b=new StringBuilder(32768); UIntPtr result;
  if(ReadMessage(h,13,(UIntPtr)b.Capacity,b,2,2000,out result)==IntPtr.Zero) throw new Exception("Text input did not respond.");
  return b.ToString();
 }
 public static bool OwnedBy(IntPtr h,IntPtr owner) {
  for(int i=0;i<12 && h!=IntPtr.Zero;i++,h=GetWindow(h,4)) if(h==owner) return true;
  return false;
 }
 public static IntPtr FilenameEdit(IntPtr dialog) {
  IntPtr found=IntPtr.Zero; int count=0;
  EnumChildWindows(dialog,delegate(IntPtr h,IntPtr x) {
   if(IsWindowVisible(h) && ClassName(h)=="Edit" && GetDlgCtrlID(h)==1001) {found=h;count++;}
   return true;
  },IntPtr.Zero);
  return count==1?found:IntPtr.Zero;
 }
 public static IntPtr SaveButton(IntPtr dialog) {
  IntPtr found=IntPtr.Zero; int count=0;
  EnumChildWindows(dialog,delegate(IntPtr h,IntPtr x) {
   string title=Title(h).Replace("&","").Trim();
   if(IsWindowVisible(h) && ClassName(h)=="Button" && (title=="Save" || title=="Export")) {found=h;count++;}
   return true;
  },IntPtr.Zero);
  return count==1?found:IntPtr.Zero;
 }

}
'@
try { $dpiOK=[NTDesktop]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { $dpiOK=$false }
if(-not $dpiOK) { [void][NTDesktop]::SetProcessDPIAware() }
$state = Join-Path $env:LOCALAPPDATA 'NT-Airtable'
[void](New-Item $state -ItemType Directory -Force)
$configFile = Join-Path $state 'config.json'
$tokenFile = Join-Path $state 'token.dat'
$script:sent = 0
$script:stage = 'Starting'
$exportFolder = Join-Path $env:USERPROFILE 'NT-Airtable\Exports'
$mutex = New-Object System.Threading.Mutex($false, 'Local\NT-Airtable-ManualSync')
$locked = $false
$script:headers = $null
$endpoint = 'https://api.airtable.com/v0/appzvICrv7LLlZdxm/tbl1u1mKMpVLmTqQP'
$mapping = [ordered]@{'Net liquidation'='CurrentBalance'; 'Realized PnL'='Realized PnL'; 'Trailing max drawdown'='Trailing max drawdown'}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff')
$logFile = Join-Path $state ('run_' + $stamp + '.log')
function Log([string]$message) {
 $message = $message -replace 'pat[A-Za-z0-9]+\.[A-Za-z0-9]+', '[TOKEN REDACTED]'
 Write-Host $message
 Add-Content -LiteralPath $logFile -Value ((Get-Date -Format o) + ' ' + $message)
}
function Elements($parent) {
 return $parent.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
}
function NormalizeTitle([string]$title) {
 return (($title -replace '[\u2010-\u2015\u2212]', '-' -replace '[\u200B-\u200F\uFEFF]', '' -replace '\s+', ' ').Trim())
}
function IsAccountsTitle([string]$title) {
 return (NormalizeTitle $title) -eq 'Control Center - Accounts'
}
function AccountsIdentity($window) {
 $native=[NTDesktop]::Title([IntPtr]$window.Current.NativeWindowHandle)
 $uia=$window.Current.Name
 $nativeMatch=IsAccountsTitle $native
 $uiaMatch=IsAccountsTitle $uia
 $headers=@{}
 $required=@('Connection','Display name','Cash value','Net liquidation','Realized PnL')
 # WPF's accessibility name may differ from the native taskbar title.
 # If neither matches, require the complete Accounts-specific column signature.
 if(-not $nativeMatch -and -not $uiaMatch) {
  foreach($el in (Elements $window)) {
   try {
    $label=NormalizeTitle $el.Current.Name
    if($required -contains $label) { $headers[$label]=$true }
   } catch { }
  }
 }
 $gridMatch=$headers.Count -eq $required.Count
 $reason='No Accounts identity found'
 if($nativeMatch) { $reason='Native Windows title' }
 elseif($uiaMatch) { $reason='UI Automation title' }
 elseif($gridMatch) { $reason='All five Accounts column headers' }
 return [pscustomobject]@{Native=$native; UIA=$uia; Eligible=($nativeMatch -or $uiaMatch -or $gridMatch); Reason=$reason; Headers=($headers.Keys -join ', ')}
}
function GetAccountsWindows {
 $root=[System.Windows.Automation.AutomationElement]::RootElement
 $windows=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
 foreach($w in $windows) {
  try { $proc=Get-Process -Id $w.Current.ProcessId } catch { continue }
  if($proc.ProcessName -ne 'NinjaTrader') { continue }
  try {
   $identity=AccountsIdentity $w
   Log ("NinjaTrader window: native='{0}'; UIA='{1}'; detection={2}; headers={3}" -f $identity.Native,$identity.UIA,$identity.Reason,$identity.Headers)
   if($identity.Eligible) { $w }
  } catch { Log ("Could not inspect one NinjaTrader window: " + $_.Exception.Message) }
 }
}
function FindNamed($parent,[string]$name,[int]$processId) {
 $processCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$processId)
 $candidates = $parent.FindAll([System.Windows.Automation.TreeScope]::Descendants,$processCondition)
 $found = @()
 foreach($el in $candidates) {
  try {
   if($el.Current.Name.Replace([string][char]0x2026,'...') -eq $name -and -not $el.Current.IsOffscreen) { $found += $el }
  } catch { }
 }
 if($found.Count -gt 1) { throw "More than one '$name' control is open. Close leftover export dialogs and retry." }
 if($found.Count -eq 1) { return $found[0] }
 return $null
}
function InvokeControl($element) {
 if($null -eq $element) { throw 'Required window control was not found. Nothing was clicked.' }
 $pattern = $null
 if(-not $element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)) { throw 'This control does not expose InvokePattern. Send the error text for adjustment.' }
 $pattern.Invoke()
}
function ExportAccounts($cfg) {
 $script:stage='Locate Accounts window'
 Log 'Looking only for NinjaTrader: Control Center - Accounts'
 $root = [System.Windows.Automation.AutomationElement]::RootElement
 $matches = @(GetAccountsWindows)
 if($matches.Count -eq 0) { throw 'No Accounts window could be verified from its Windows title, accessibility name or Accounts columns. Run 5-Diagnose-Windows.cmd and send the resulting log.' }
 if($matches.Count -gt 1) { throw 'Multiple Control Center - Accounts windows were found. This version needs one Accounts window; charts and other NinjaTrader windows can stay open.' }
 $window = $matches[0]
 $handle = [IntPtr]$window.Current.NativeWindowHandle
 $script:stage='Restore Accounts window'
 if(-not $cfg -or -not $cfg.Width -or -not $cfg.Height) { throw 'The built-in window layout is invalid.' }
 [void][NTDesktop]::ShowWindow($handle,9)
 Start-Sleep -Milliseconds 300
 $left=20; $top=20
 if($null -ne $cfg.Left) { $left=[int]$cfg.Left }
 if($null -ne $cfg.Top) { $top=[int]$cfg.Top }
 if(-not [NTDesktop]::MoveWindow($handle,$left,$top,[int]$cfg.Width,[int]$cfg.Height,$true)) { throw 'Could not move/resize the Accounts window.' }
 [void][NTDesktop]::SetForegroundWindow($handle)
 Start-Sleep -Milliseconds 600
 if([NTDesktop]::GetForegroundWindow() -ne $handle) { throw 'Could not activate Accounts. Bring it forward and retry.' }
 $nativeRect=New-Object NTDesktop+RECT
 if(-not [NTDesktop]::GetWindowRect($handle,[ref]$nativeRect)) { throw 'Cannot verify restored window coordinates.' }
 $rect=[pscustomobject]@{Left=$nativeRect.L; Top=$nativeRect.T; Width=($nativeRect.R-$nativeRect.L); Height=($nativeRect.B-$nativeRect.T)}
 if($rect.Left -ne $cfg.Left -or $rect.Top -ne $cfg.Top -or $rect.Width -ne $cfg.Width -or $rect.Height -ne $cfg.Height) { throw "Window coordinates were not restored exactly. Actual X=$($rect.Left), Y=$($rect.Top), Width=$($rect.Width), Height=$($rect.Height). Check display scaling and monitor layout." }
 if(-not (AccountsIdentity $window).Eligible) { throw 'Accounts tab identity was lost after resizing.' }
 Log 'Verified window X=954 Y=6 Width=964 Height=1148.' 
 if($cfg.X -le 0 -or $cfg.Y -le 0 -or $cfg.X -ge $rect.Width -or $cfg.Y -ge $rect.Height) { throw 'Saved grid point is outside Accounts. Run Setup again.' }
 $script:stage='Open Export menu'
 $x = [int]($rect.Left+$cfg.X)
 $y = [int]($rect.Top+$cfg.Y)
 if(-not [NTDesktop]::SetCursorPos($x,$y)) { throw 'Cannot move cursor to saved grid point.' }
 $clickPoint=New-Object NTDesktop+POINT
 if(-not [NTDesktop]::GetCursorPos([ref]$clickPoint) -or $clickPoint.X -ne $x -or $clickPoint.Y -ne $y) { throw 'Cursor did not reach the saved location.' }
 if([NTDesktop]::GetAncestor([NTDesktop]::WindowFromPoint($clickPoint),2) -ne $handle -or [NTDesktop]::GetForegroundWindow() -ne $handle) { throw 'The saved mouse point is covered by another window. No right-click sent.' }
 Log "Right-clicking saved screen point X=$x Y=$y."
 [NTDesktop]::mouse_event(8,0,0,0,[UIntPtr]::Zero)
 [NTDesktop]::mouse_event(16,0,0,0,[UIntPtr]::Zero)
 $export = $null
 for($i=0;$i -lt 12 -and $null -eq $export;$i++) {
  Start-Sleep -Milliseconds 250
  # Search only the new visible menu, and only MenuItem controls.
  $menuCondition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Menu)
  $menus=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$menuCondition)
  $menuCandidates=@()
  foreach($menu in $menus) {
   if($menu.Current.ProcessId -ne $window.Current.ProcessId -or $menu.Current.IsOffscreen) { continue }
   $bounds=$menu.Current.BoundingRectangle
   if($x -lt $bounds.Left-40 -or $x -gt $bounds.Right+40 -or $y -lt $bounds.Top-40 -or $y -gt $bounds.Bottom+40) { continue }
   $itemCondition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem)
   $items=$menu.FindAll([System.Windows.Automation.TreeScope]::Descendants,$itemCondition)
   foreach($item in $items) {
    if(-not $item.Current.IsOffscreen -and $item.Current.Name.Replace([string][char]0x2026,'...') -eq 'Export...') { $menuCandidates += $item }
   }
  }
  # The same MenuItem can be returned through nested Menu parents; deduplicate.
  $unique=@{}
  foreach($item in $menuCandidates) { $unique[($item.GetRuntimeId() -join ':')]=$item }
  if($unique.Count -eq 1) { $export=@($unique.Values)[0] }
  elseif($unique.Count -gt 1) { throw 'More than one Export menu item is near the click. Close the popup and retry.' }
 }
 if($null -eq $export) { throw 'Export menu item was not found in the popup near the Accounts click.' }
 InvokeControl $export
 $script:stage='Locate native Export As dialog'
 $dialogHandle=[IntPtr]::Zero
 for($i=0;$i -lt 30 -and $dialogHandle -eq [IntPtr]::Zero;$i++) {
  Start-Sleep -Milliseconds 200
  $dialogHandle=[NTDesktop]::SaveDialog([uint32]$window.Current.ProcessId)
 }
 if($dialogHandle -eq [IntPtr]::Zero) { throw 'The native Export As / Save As dialog was not found for NinjaTrader.' }
 [void][NTDesktop]::SetForegroundWindow($dialogHandle)
 Start-Sleep -Milliseconds 300
 if([NTDesktop]::GetForegroundWindow() -ne $dialogHandle) { throw 'Cannot focus the Export As dialog. No keys or save clicks were sent.' }
 $folder=$exportFolder
 [void](New-Item $folder -ItemType Directory -Force)
 # Read the existing name without changing it. WM_GETTEXT works across processes;
 # GetWindowText cannot read another application's edit control.
 $script:stage='Read default CSV filename'
 $editHandle=[NTDesktop]::FilenameEdit($dialogHandle)
 if($editHandle -eq [IntPtr]::Zero) {
  [System.Windows.Forms.SendKeys]::SendWait('%n')
  Start-Sleep -Milliseconds 200
  $editHandle=[NTDesktop]::Focused($dialogHandle)
  if(-not [NTDesktop]::IsChild($dialogHandle,$editHandle) -or [NTDesktop]::ClassName($editHandle) -ne 'Edit') { throw 'Could not locate the File name input in Export As.' }
 }
 $defaultName=[NTDesktop]::ReadEdit($editHandle).Trim().Trim('"')
 if([string]::IsNullOrWhiteSpace($defaultName) -or $defaultName -ne [IO.Path]::GetFileName($defaultName) -or $defaultName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw 'The default export filename is empty or invalid.' }
 if(-not $defaultName.EndsWith('.csv',[StringComparison]::OrdinalIgnoreCase)) { $defaultName += '.csv' }
 $outFile=Join-Path $folder $defaultName
 $script:stage='Set export folder using address bar'
 [System.Windows.Forms.SendKeys]::SendWait('%d')
 Start-Sleep -Milliseconds 250
 $addressHandle=[NTDesktop]::Focused($dialogHandle)
 if([NTDesktop]::GetForegroundWindow() -ne $dialogHandle -or -not [NTDesktop]::IsChild($dialogHandle,$addressHandle) -or [NTDesktop]::ClassName($addressHandle) -ne 'Edit' -or $addressHandle -eq $editHandle) { throw 'Could not focus the export folder address bar. Nothing was saved.' }
 [void][NTDesktop]::SendMessage($addressHandle,12,[IntPtr]::Zero,$folder)
 if([NTDesktop]::ReadEdit($addressHandle) -cne $folder) { throw 'The address bar did not accept the export folder.' }
 [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
 Start-Sleep -Milliseconds 800
 # Reopen the address bar to verify navigation actually completed.
 [System.Windows.Forms.SendKeys]::SendWait('%d')
 Start-Sleep -Milliseconds 250
 $addressHandle=[NTDesktop]::Focused($dialogHandle)
 if(-not [NTDesktop]::IsChild($dialogHandle,$addressHandle) -or [NTDesktop]::ClassName($addressHandle) -ne 'Edit') { throw 'Could not verify the destination folder.' }
 $actualFolder=[NTDesktop]::ReadEdit($addressHandle)
 if($actualFolder.TrimEnd('\') -ine $folder.TrimEnd('\')) { throw "Export folder navigation failed. Expected: $folder" }
 [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
 Log "Export folder verified. Keeping default filename: $defaultName"
 $beforeTicks=$null
 if(Test-Path -LiteralPath $outFile) { $beforeTicks=(Get-Item -LiteralPath $outFile).LastWriteTimeUtc.Ticks }
 $saveStarted=[DateTime]::UtcNow
 $script:stage='Click Save in Export As'
 $saveHandle=[NTDesktop]::SaveButton($dialogHandle)
 if($saveHandle -eq [IntPtr]::Zero) { throw 'Could not identify a unique Save button in the export dialog.' }
 if([NTDesktop]::GetForegroundWindow() -ne $dialogHandle) { throw 'Export dialog lost focus before Save. Nothing was clicked.' }
 if(-not [NTDesktop]::PostMessage($saveHandle,245,[IntPtr]::Zero,[IntPtr]::Zero)) { throw 'Windows could not send the Save click.' }
 Log 'Save clicked. Waiting for CSV; an overwrite confirmation will be handled automatically.'
 $script:stage='Confirm overwrite and wait for fresh CSV'
 $previous=''; $stable=0; $confirmed=$false
 for($i=0;$i -lt 60;$i++) {
  Start-Sleep -Milliseconds 500
  $front=[NTDesktop]::GetForegroundWindow()
  if(-not $confirmed -and $front -ne $dialogHandle -and [NTDesktop]::ProcessId($front) -eq $window.Current.ProcessId -and [NTDesktop]::OwnedBy($front,$dialogHandle)) {
   $confirmation=[System.Windows.Automation.AutomationElement]::FromHandle($front)
   $parts=@(Elements $confirmation)
   $message=($parts | ForEach-Object { $_.Current.Name }) -join ' '
   if($message -match '(?i)replace|already exists|overwrite' -and $message.IndexOf($defaultName,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
    $yes=@($parts | Where-Object { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and -not $_.Current.IsOffscreen -and $_.Current.Name.Replace('&','').Trim() -match '^(Yes|Replace)$' })
    if($yes.Count -eq 1) { InvokeControl $yes[0]; $confirmed=$true; Log 'Confirmed replacement of this export CSV.' }
   }
  }
  if(Test-Path -LiteralPath $outFile) {
   $file=Get-Item -LiteralPath $outFile
   $fresh=$file.LastWriteTimeUtc -ge $saveStarted -and ($null -eq $beforeTicks -or $file.LastWriteTimeUtc.Ticks -ne $beforeTicks)
   $signature="$($file.Length):$($file.LastWriteTimeUtc.Ticks)"
   if($fresh -and $file.Length -gt 0 -and $signature -eq $previous) { $stable++ } else { $stable=0 }
   $previous=$signature
   if($stable -ge 3 -and -not [NTDesktop]::IsWindowVisible($dialogHandle)) {
    try {
     $stream=[IO.File]::Open($outFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
     $stream.Dispose()
    } catch [System.IO.IOException] { continue }
    Log "Fresh export verified: $outFile"
    return $outFile
   }
  }
 }
 throw "Save did not finish with a fresh CSV within 30 seconds: $outFile. No stale CSV was sent to Airtable. Check for a remaining export or overwrite dialog."

}
function Money([string]$text) {
 $s=$text.Trim()
 if($s -notmatch '^\(?-?\$?\d+(?:,\d{3})*(?:\.\d+)?\)?$') { throw "Invalid or blank numeric value: '$text'" }
 if($s.StartsWith('(') -ne $s.EndsWith(')')) { throw "Unbalanced parentheses in value: '$text'" }
 $negative=$s.StartsWith('(')
 $s=$s.Replace('$','').Replace(',','').Replace('(','').Replace(')','')
 $n=[decimal]::Parse($s,[Globalization.CultureInfo]::InvariantCulture)
 if($negative) { if($n -lt 0) { throw 'Ambiguous negative amount.' }; $n=-$n }
 return $n
}
function Api([string]$method,[string]$url,$body=$null) {
 for($attempt=0;$attempt -lt 4;$attempt++) {
  Start-Sleep -Milliseconds 300
  try {
   $requestParams=@{Uri=$url; Method=$method; Headers=$script:headers; TimeoutSec=30; ErrorAction='Stop'}
   if($null -ne $body) { $requestParams.Body=($body|ConvertTo-Json -Depth 8 -Compress); $requestParams.ContentType='application/json; charset=utf-8' }
   return Invoke-RestMethod @requestParams
  } catch {
   $code=0
   if($null -ne $_.Exception.Response) { $code=[int]$_.Exception.Response.StatusCode }
   # Stop immediately on an API failure; do not proceed to another batch.
   $detail=[string]$_.ErrorDetails.Message
   throw "Airtable request failed (HTTP $code). $detail Check token scopes, base access, field names and writable field types."
  }
 }
}

function Initialize-Airtable {
 $script:stage='Automatic Airtable setup'
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $secure=$null
 if(Test-Path -LiteralPath $tokenFile) {
  try {
   $encoded=(Get-Content -LiteralPath $tokenFile -Raw).Trim()
   if($encoded) { $secure=ConvertTo-SecureString -String $encoded -ErrorAction Stop }
  } catch {
   Log 'Saved login cannot be read on this Windows user/PC. Enter a token to set up this machine.'
  } finally { $encoded=$null }
 }
 if($null -ne $secure) {
  $savedCredential=New-Object System.Net.NetworkCredential('', $secure)
  $script:headers=@{Authorization='Bearer '+$savedCredential.Password.Trim()}
  $savedCredential=$null
  try {
   $probe=Invoke-RestMethod -Uri ($endpoint+'?maxRecords=1&fields%5B%5D=id') -Method GET -Headers $script:headers -TimeoutSec 30 -ErrorAction Stop
   if($null -eq $probe.records) { throw 'Airtable returned an unexpected response.' }
   Log 'Saved Airtable login verified. Continuing automatically.'
   return
  } catch {
   $status=0
   if($null -ne $_.Exception.Response) { $status=[int]$_.Exception.Response.StatusCode }
   if($status -ne 401 -and $status -ne 403) { throw "Airtable connection check failed (HTTP $status). Check network access and the configured base/table. No export started." }
   $script:headers=$null
   Log 'Saved Airtable login was rejected. Enter a valid token to update setup.'
  }
 }
 Write-Host ''
 if($request14.Mode -notin @('setup','startup')) { throw 'Airtable login is missing or invalid. Run Airtable Setup on this VM, then refresh accounts.' }
 Write-Host 'FIRST-RUN SETUP - this machine needs your Airtable personal access token.' -ForegroundColor Cyan
 Write-Host 'Use a token with data.records:read and data.records:write and access to your base.'
 Write-Host 'Paste your token below and press Enter. Input is hidden. This is needed only once per Windows user/PC.'
 $entered=Read-Host 'Airtable token' -AsSecureString
 if($entered.Length -eq 0) { throw 'Setup cancelled: no token entered.' }
 $newCredential=New-Object System.Net.NetworkCredential('', $entered)
 $plain=$newCredential.Password.Trim()
 $newCredential=$null
 try {
  if(-not $plain.StartsWith('pat')) { throw 'Expected an Airtable personal access token beginning with pat.' }
  $script:headers=@{Authorization='Bearer '+$plain}
  $secure=ConvertTo-SecureString -String $plain -AsPlainText -Force
 } finally { $plain=$null; $entered=$null }
 $script:stage='Validate Airtable setup'
 try {
  $probe=Invoke-RestMethod -Uri ($endpoint+'?maxRecords=1&fields%5B%5D=id') -Method GET -Headers $script:headers -TimeoutSec 30 -ErrorAction Stop
  if($null -eq $probe.records) { throw 'Airtable returned an unexpected response.' }
 } catch {
  $status=0
  if($null -ne $_.Exception.Response) { $status=[int]$_.Exception.Response.StatusCode }
  $script:headers=$null
  throw "Airtable setup check failed (HTTP $status). Check token, base access, network, and table. Token was not saved; no export started. Run Execute again after correcting it."
 }
 $script:stage='Save encrypted Airtable setup'
 $temporaryToken=Join-Path $state ('token_'+[Guid]::NewGuid().ToString('N')+'.tmp')
 try {
  $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $temporaryToken -Encoding UTF8
  Move-Item -LiteralPath $temporaryToken -Destination $tokenFile -Force
 } finally {
  if(Test-Path -LiteralPath $temporaryToken) { Remove-Item -LiteralPath $temporaryToken -Force }
  $secure=$null
 }
 Log 'Airtable setup saved securely for this Windows user/PC. Continuing this sync now.'
}

try {
 $locked=$mutex.WaitOne(0)
 if(-not $locked) { throw 'Another sync is already running.' }
 if($Diagnose) {
  $script:stage='Window diagnostics'
  $detected=@(GetAccountsWindows)
  Log "Verified Accounts windows: $($detected.Count). No clicks or Airtable requests were made."
  Log "Diagnostic log: $logFile"

 } else {
  if($request14.Mode -eq 'export' -and -not (Test-Path $queue14)) {
   @{tradeId=$request14.TradeId;csvPath=$null} | ConvertTo-Json | Set-Content ($queue14+'.tmp') -Encoding UTF8
   Move-Item ($queue14+'.tmp') $queue14 -Force
  }
  Initialize-Airtable
  if($request14.Mode -in @('setup','startup')) { @{ok=$true;message='Airtable login verified.'} | ConvertTo-Json | Set-Content $ResultPath -Encoding UTF8; exit 0 }
  if($request14.Mode -eq 'accounts') {
   $records14=@();$offset14=''
   do {
    $url14=$endpoint+'?pageSize=100&fields%5B%5D=id&fields%5B%5D=Master%20Account'
    if($offset14) { $url14+='&offset='+[Uri]::EscapeDataString($offset14) }
    $page14=Api 'GET' $url14
    $records14+=@($page14.records);$offset14=$page14.offset
   } while($offset14)
   $master14=[string]$request14.MasterAccount
   $matches14=@(Get-AccountMatches16 $request14.Accounts $records14 $master14)
   @{ok=$true;accounts=@($matches14);message=($matches14.Count.ToString()+' matched accounts for '+$master14+'. Sim101 remains available.')} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
   exit 0
  }
  if($request14.Mode -ne 'export') { throw 'Unsupported worker mode.' }
  if(Test-Path $done14) {
   $doneValue14=Get-Content $done14 -Raw | ConvertFrom-Json
   if($doneValue14.tradeId -ceq $request14.TradeId -and -not $request14.FreshExport) {
    Remove-Item $queue14 -ErrorAction SilentlyContinue
    @{ok=$true;message='Already synced this trade.';receipt=$doneValue14.receipt} | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding UTF8
    exit 0
   }
  }
  if(Test-Path $queue14) {
   $pending14=Get-Content $queue14 -Raw | ConvertFrom-Json
   if($pending14.tradeId -cne $request14.TradeId) { throw 'Previous sync is pending. Retry it before exporting another trade.' }
   if(-not $request14.FreshExport) { $CsvPath=$pending14.csvPath }
  }
  if(-not $CsvPath) {
   @{tradeId=$request14.TradeId;csvPath=$null} | ConvertTo-Json | Set-Content ($queue14+'.tmp') -Encoding UTF8
   Move-Item ($queue14+'.tmp') $queue14 -Force
   $cfg=[pscustomobject]@{Left=954; Top=6; Width=964; Height=1148; X=466; Y=820}
   $CsvPath=ExportAccounts $cfg
   @{tradeId=$request14.TradeId;csvPath=$CsvPath} | ConvertTo-Json | Set-Content ($queue14+'.tmp') -Encoding UTF8
   Move-Item ($queue14+'.tmp') $queue14 -Force
  }
  $script:stage='Read and validate CSV'
  Log "Reading CSV: $CsvPath"
  $rows=@(Import-Csv -LiteralPath $CsvPath -WarningAction SilentlyContinue)
  if($rows.Count -eq 0) { throw 'CSV has no account rows.' }
  foreach($name in @('Display name')+@($mapping.Keys)) {
   if($rows[0].PSObject.Properties.Name -cnotcontains $name) { throw "CSV missing exact column: $name" }
  }
  $data=@(); $seen=@{}
  foreach($row in $rows) {
   $id=(([string]$row.'Display name') -split '!',2)[0].Trim()
   if(-not $id) { throw 'CSV has a blank account ID.' }
   # Sim101 is read for queue test receipts; it is never uploaded to Accounts.
   if($row.PSObject.Properties.Name -contains 'ConnectionStatus' -and $row.ConnectionStatus -ne 'Connected') { Log "Skipped disconnected account: $id"; continue }
   if($seen.ContainsKey($id)) { throw "Duplicate CSV account ID: $id. Nothing updated." }
   $seen[$id]=$true
   $fields=[ordered]@{}
   if($id -ieq 'Sim101') {
    try {
     $fields['CurrentBalance']=Money ([string]$row.'Net liquidation')
     $fields['Realized PnL']=Money ([string]$row.'Realized PnL')
    } catch { Log 'Sim101 receipt unavailable: numeric balance/PnL not exported. Other accounts will still sync.'; continue }
   } else {
    foreach($key in $mapping.Keys) { $fields[$mapping[$key]]=Money ([string]$row.$key) }
   }
   $data+=@{Account=$id; Fields=$fields}
  }
  if($ExportOnly) {
   if($ResultPath) { @{ok=$true; csvPath=$CsvPath; count=$data.Count}|ConvertTo-Json|Set-Content -LiteralPath $ResultPath -Encoding UTF8 }
   Log "EXPORT TEST PASSED: $($data.Count) non-simulation connected accounts parsed. No Airtable requests made. File: $CsvPath"; exit 0 }
  if($data.Count -eq 0) { throw 'No eligible connected accounts to sync. Nothing uploaded.' }
  $script:stage='Read Airtable records'
  Log 'Connecting to Airtable for account matching.'
  $index=@{}; $offset=''
  do {
   $url=$endpoint+'?pageSize=100&fields%5B%5D=id'
   if($offset) { $url+='&offset='+[Uri]::EscapeDataString($offset) }
   $page=Api 'GET' $url
   if($null -eq $page.records) { throw 'Unexpected Airtable response: records missing.' }
   foreach($record in $page.records) {
    $key=([string]$record.fields.id).Trim()
    if($key) {
     if(-not $index.ContainsKey($key)) { $index[$key]=@() }
     $index[$key]+=$record
    }
   }
   $offset=$page.offset
  } while($offset)
  $updates=@(); $report=@()
  foreach($item in $data) {
   $id=$item.Account
   if($id -ieq 'Sim101') { $status='Simulation' }
   elseif(-not $index.ContainsKey($id)) { Log "UNMATCHED: $id"; $status='Unmatched' }
   elseif($index[$id].Count -ne 1) { Log "DUPLICATE in Airtable, skipped: $id"; $status='Duplicate Airtable ID' }
   elseif(([string]$index[$id][0].fields.id).Trim() -cne $id) { Log "Case mismatch, skipped: $id"; $status='Case mismatch' }
   else { $updates+=@{id=$index[$id][0].id; fields=$item.Fields}; $status='Matched' }
   $report+=[pscustomobject]@{Account=$id; Status=$status; CurrentBalance=$item.Fields['CurrentBalance']; 'Realized PnL'=$item.Fields['Realized PnL']; 'Trailing max drawdown'=$item.Fields['Trailing max drawdown']}
  }
  $report|Format-Table -AutoSize|Out-Host
  $reportPath=Join-Path $state ('preview_'+$stamp+'.csv')
  $report|Export-Csv -LiteralPath $reportPath -NoTypeInformation
  $skippedCount=@($report | Where-Object { $_.Status -ne 'Matched' }).Count
  if($skippedCount -gt 0) { Log "Skipping $skippedCount unmatched/ambiguous accounts. Continuing with $($updates.Count) matched accounts. Report: $reportPath" }
  if($updates.Count -eq 0) { Log 'No matching accounts to update. All exported accounts were skipped; no Airtable writes needed.' }
  if($Preview) { Log "PREVIEW ONLY: $($updates.Count) matches. No Airtable records changed. Report: $reportPath" }
  else {
   for($i=0;$i -lt $updates.Count;$i+=10) {
    $last=[Math]::Min($i+9,$updates.Count-1)
    $batch=@($updates[$i..$last])
    $script:stage='Update Airtable records'
    $result=Api 'PATCH' $endpoint @{records=$batch; typecast=$false}
    $returned=@($result.records)
    $script:sent+=$returned.Count
    if($returned.Count -ne $batch.Count) { throw 'Airtable did not confirm every record in this batch.' }
    foreach($expected in $batch) {
     $confirmed=@($returned | Where-Object { $_.id -ceq $expected.id })
     if($confirmed.Count -ne 1) { throw 'Airtable response does not match the requested record IDs.' }
     foreach($fieldName in $expected.fields.Keys) {
      $actualValue=$confirmed[0].fields.$fieldName
      if($null -eq $actualValue -or [decimal]$actualValue -ne [decimal]$expected.fields[$fieldName]) { throw "Airtable returned an unexpected value for $fieldName on record $($expected.id)." }
     }
    }
    Log "Confirmed updates so far: $script:sent"
   }
   if($script:sent -ne $updates.Count) { throw "Only $script:sent of $($updates.Count) matched records were confirmed." }
   Log "SUCCESS: CSV saved; $script:sent matched accounts confirmed in Airtable; $skippedCount unmatched/ambiguous accounts skipped."
  }
 }
 $receipt17=@{id=$request14.TradeId;completedUtc=[DateTime]::UtcNow.ToString('o');accounts=@($report | Where-Object {$_.Status -in @('Matched','Simulation')})}
 @{tradeId=$request14.TradeId;csvPath=$CsvPath;receipt=$receipt17} | ConvertTo-Json -Depth 8 | Set-Content ($done14+'.tmp') -Encoding UTF8
 Move-Item ($done14+'.tmp') $done14 -Force
 Remove-Item $queue14 -ErrorAction SilentlyContinue
 @{ok=$true;message=('Synced '+$script:sent+' account records to Airtable.');receipt=$receipt17} | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding UTF8
} catch {
 Log "STOPPED at [$script:stage]: $($_.Exception.Message)"
 Log "Diagnostic log: $logFile"
 if($script:stage -eq 'Update Airtable records') { Log "Confirmed writes before stop: $script:sent. The last request may have reached Airtable if it timed out." }
 if($ResultPath) { @{ok=$false; error=$_.Exception.Message; stage=$script:stage}|ConvertTo-Json|Set-Content -LiteralPath $ResultPath -Encoding UTF8 }

 exit 1
} finally {
 $script:headers=$null
 if($locked) { $mutex.ReleaseMutex() }
 $mutex.Dispose()
}
