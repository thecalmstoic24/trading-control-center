$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$version = '15.0-preview.3'
$base = Join-Path $env:LOCALAPPDATA 'TradingControlCenter'
$destination = Join-Path $base ("releases\" + $version)
$source = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Private-Network.ps1')

function Protect-Directory([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    # Load and persist ONLY the DACL. The PowerShell Set-Acl provider can attempt
    # an audit/SACL write requiring SeSecurityPrivilege, especially on reinstall.
    # Preserve the existing owner, group and audit policy.
    $acl = [IO.Directory]::GetAccessControl($Path, [Security.AccessControl.AccessControlSections]::Access)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existing in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
        $acl.RemoveAccessRuleSpecific($existing)
    }
    $rights = [Security.AccessControl.FileSystemRights]::FullControl
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,
                       [Security.Principal.SecurityIdentifier]::new('S-1-5-18'),
                       [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid,$rights,$inherit,
            [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    [IO.Directory]::SetAccessControl($Path, $acl)
}
function Add-DesktopShortcut([string]$Name,[string]$Script) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) ($Name + '.lnk')))
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $Script + '"'
    $shortcut.WorkingDirectory = Split-Path $Script -Parent
    $shortcut.Save()
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Trading Control Center - V15 Private Network Setup'
$form.ClientSize = New-Object Drawing.Size(650,740)
$form.StartPosition = 'CenterScreen'
$form.AutoScroll = $true
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
function LabelAt([string]$Text,[int]$Y) {
    $item = New-Object Windows.Forms.Label
    $item.Text=$Text; $item.Location=New-Object Drawing.Point(24,$Y); $item.Size=New-Object Drawing.Size(600,44)
    $form.Controls.Add($item); return $item
}
LabelAt 'Choose what to install. Use the same Tailscale network on every computer.' 20 | Out-Null
$role = New-Object Windows.Forms.ComboBox
$role.DropDownStyle='DropDownList'; $role.Location=New-Object Drawing.Point(24,70); $role.Size=New-Object Drawing.Size(600,30)
@('Control center - my third computer','Named VM - NinjaTrader agent') | ForEach-Object { [void]$role.Items.Add($_) }
$role.SelectedIndex=0; $form.Controls.Add($role)
$nameLabel=LabelAt 'VM name (examples: MFFLocDao, LCDLocDao, FNThu, FNSean)' 112
$nameBox=New-Object Windows.Forms.ComboBox
$nameBox.Location=New-Object Drawing.Point(24,145);$nameBox.Size=New-Object Drawing.Size(600,30)
@('MFFLocDao','LCDLocDao','FNThu','FNSean') | ForEach-Object {[void]$nameBox.Items.Add($_)}
$form.Controls.Add($nameBox)
$networkLabel=LabelAt 'Private network: not checked' 190
$networkLabel.Height=65
$connectNetwork=New-Object Windows.Forms.Button
$connectNetwork.Text='SET UP PRIVATE NETWORK (TAILSCALE)'
$connectNetwork.Location=New-Object Drawing.Point(24,275);$connectNetwork.Size=New-Object Drawing.Size(600,40)
$form.Controls.Add($connectNetwork)
$connectNetwork.Add_Click({
    try { Open-PrivateNetworkSetup15; $status.Text='Finish signing in to Tailscale, then click CHECK CONNECTION.' }
    catch { $status.Text=$_.Exception.Message }
})
$detect=New-Object Windows.Forms.Button
$detect.Text='CHECK CONNECTION'
$detect.Location=New-Object Drawing.Point(24,335);$detect.Size=New-Object Drawing.Size(600,40)
$form.Controls.Add($detect)
function Detect-PrivateNetwork {
    $script:PrivateAddress15=Get-PrivateAddress15
    $networkLabel.Text='Private network connected. Address detected automatically.'
    $status.Text='Ready to install. No public or peer IP addresses are needed.'
}
$detect.Add_Click({try { Detect-PrivateNetwork } catch { $networkLabel.Text=$_.Exception.Message }})
$form.Add_Shown({try { Detect-PrivateNetwork } catch { $networkLabel.Text=$_.Exception.Message }})
$notice=LabelAt 'Control center installs its own Python runtime. No GitHub login or manual Python installation is needed.' 440
$check=New-Object Windows.Forms.CheckBox
$check.Text='For agent installation: All accounts are flat, no working orders, and the old agent is closed.'
$check.Location=New-Object Drawing.Point(24,500); $check.Size=New-Object Drawing.Size(600,52); $form.Controls.Add($check)
$install=New-Object Windows.Forms.Button
$install.Text='INSTALL'; $install.Location=New-Object Drawing.Point(24,580); $install.Size=New-Object Drawing.Size(600,45); $form.Controls.Add($install)
$status=LabelAt 'Ready. This installer will not submit any trade.' 650
$role.Add_SelectedIndexChanged({
    $agent=$role.SelectedIndex -gt 0
    $check.Enabled=$agent;$nameBox.Enabled=$agent
    $notice.Text='V15 uses your private network. Paired agents retain direct encrypted connections. Your third computer remains the coordinator.'
})
$check.Enabled=$false;$nameBox.Enabled=$false
$identityFile=Join-Path $base 'agent-data\identity.clixml'
if(Test-Path -LiteralPath $identityFile) {
    $existingIdentity=Import-Clixml -LiteralPath $identityFile
    $role.SelectedIndex=1;$nameBox.Text=$existingIdentity.Name
}
$install.Add_Click({
    $install.Enabled=$false
    try {
        $agent=$role.SelectedIndex -gt 0
        if($agent -and -not $check.Checked){throw 'Confirm the agent-installation checkbox first.'}
        $hostAddress=Get-PrivateAddress15
        $name=$nameBox.Text.Trim()
        if($agent -and $name -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.\-]{0,39}$') { throw 'Enter a unique VM name, up to 40 characters.' }
        $running = Get-CimInstance Win32_Process | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf((Join-Path $base 'releases'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            ($_.Name -match '^(python|pythonw|powershell|pwsh)\.exe$')
        }
        if($running){throw 'This release is already running. Close it only after verifying both VMs are flat, then run setup again.'}
        $status.Text='Installing files...'; $form.Refresh()
        Protect-Directory $base
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        foreach($folder in @('coordinator','agent','install')){
            Copy-Item -LiteralPath (Join-Path $source $folder) -Destination $destination -Recurse -Force
        }
        if(-not $agent){
            $runtime=Join-Path $destination 'runtime'
            if(-not (Test-Path -LiteralPath (Join-Path $runtime 'python.exe'))){
                $architecture=if($env:PROCESSOR_ARCHITEW6432){$env:PROCESSOR_ARCHITEW6432}else{$env:PROCESSOR_ARCHITECTURE}
                if($architecture -eq 'ARM64'){
                    $filename='python-3.13.15-embed-arm64.zip'; $expected='cd992cbfb33be433ff20f150691595efb2862e56f4f1bec684c6077d4775af8e'
                }else{
                    $filename='python-3.13.15-embed-amd64.zip'; $expected='d1f04d990aee1253d8569e8e5104e30fa9f5fa830899f14843448872d936a2cf'
                }
                $status.Text='Downloading the private Python runtime (about 11 MB)...';$form.Refresh()
                $zip=Join-Path $base $filename
                Invoke-WebRequest -UseBasicParsing -Uri ('https://www.python.org/ftp/python/3.13.15/'+$filename) -OutFile $zip -TimeoutSec 190
                if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){Remove-Item -LiteralPath $zip;throw 'Runtime checksum mismatch. Installation stopped.'}
                Expand-Archive -LiteralPath $zip -DestinationPath $runtime -Force
                Remove-Item -LiteralPath $zip
            }
            $data=Join-Path $base 'coordinator-data'; Protect-Directory $data
            $scriptFile=Join-Path $destination 'install\Start-Control-Center.ps1'
            Add-DesktopShortcut 'Trading Control Center' $scriptFile
            Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$scriptFile+'"')
            $status.Text='Installed. Dashboard is opening on your third computer.'
        }else{
            $id=($name.ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-')
            $data=Join-Path $base 'agent-data'; Protect-Directory $data
            $identityPath=Join-Path $data 'identity.clixml'
            if(Test-Path -LiteralPath $identityPath){
                $identity=Import-Clixml -LiteralPath $identityPath
                $id=$identity.Id
                $identity.Name=$name
                $identity.HostAddress=$hostAddress
                Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$identity.Thumbprint) | Out-Null
            }else{
                $cert=New-SelfSignedCertificate -DnsName ('trading-'+$id) -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(2)
                $random=New-Object byte[] 32; $rng=[Security.Cryptography.RandomNumberGenerator]::Create();$rng.GetBytes($random);$rng.Dispose()
                $token=([BitConverter]::ToString($random)).Replace('-','').ToLowerInvariant()
                $hash=[Security.Cryptography.SHA256]::Create()
                $pin=([BitConverter]::ToString($hash.ComputeHash($cert.RawData))).Replace('-','').ToLowerInvariant();$hash.Dispose()
                $identity=[pscustomobject]@{Id=$id;Name=$name;HostAddress=$hostAddress;Thumbprint=$cert.Thumbprint;Pin=$pin;Token=(ConvertTo-SecureString $token -AsPlainText -Force)}
            }
            $identity | Export-Clixml -LiteralPath $identityPath
            $networkFile=Join-Path $data 'network.json'
            if((Test-Path $networkFile) -and -not (Test-Path ($networkFile+'.v14-backup'))) { Copy-Item $networkFile ($networkFile+'.v14-backup') }
            @{mode='tailscale';address=$hostAddress} | ConvertTo-Json | Set-Content $networkFile -Encoding UTF8
            $status.Text='Configuring the private network interface. Windows will request administrator access.';$form.Refresh()
            $firewall=Join-Path $destination 'install\Allow-Control-Connection.ps1'
            $process=Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$firewall+'" -LocalAddress '+$hostAddress)
            if($process.ExitCode -ne 0){throw 'Firewall configuration failed. Installation files are present; rerun setup to finish.'}
            $scriptFile=Join-Path $destination 'agent\Control_VM_Agent_v15.ps1'
            Add-DesktopShortcut ('Trading Agent - '+$name) $scriptFile
            Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$scriptFile+'"')
            $status.Text='Installed. Agent starts automatically. Copy its connection code into the VM registry on your third computer.'
        }
        $install.Text='INSTALLED'
    }catch{
        $status.Text='Installation stopped: '+$_.Exception.Message
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation stopped') | Out-Null
        $install.Enabled=$true
    }
})
[void]$form.ShowDialog()
