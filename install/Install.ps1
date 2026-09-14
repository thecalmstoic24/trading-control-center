$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$version = '11.0-preview.1'
$base = Join-Path $env:LOCALAPPDATA 'TradingControlCenter'
$destination = Join-Path $base ("releases\" + $version)
$source = Split-Path $PSScriptRoot -Parent

function Protect-Directory([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $rights = [Security.AccessControl.FileSystemRights]::FullControl
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,
                       [Security.Principal.SecurityIdentifier]::new('S-1-5-18'),
                       [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid,$rights,$inherit,
            [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
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
$form.Text = 'Trading Control Center - Windows Setup'
$form.ClientSize = New-Object Drawing.Size(650,610)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
function LabelAt([string]$Text,[int]$Y) {
    $item = New-Object Windows.Forms.Label
    $item.Text=$Text; $item.Location=New-Object Drawing.Point(24,$Y); $item.Size=New-Object Drawing.Size(600,44)
    $form.Controls.Add($item); return $item
}
LabelAt 'Choose what to install on THIS computer. Simulation test release only.' 20 | Out-Null
$role = New-Object Windows.Forms.ComboBox
$role.DropDownStyle='DropDownList'; $role.Location=New-Object Drawing.Point(24,70); $role.Size=New-Object Drawing.Size(600,30)
@('Control center - my third computer','VM left - NinjaTrader agent','VM right - NinjaTrader agent') | ForEach-Object { [void]$role.Items.Add($_) }
$role.SelectedIndex=0; $form.Controls.Add($role)
$hostLabel = LabelAt 'VM public IPv4 address (only needed when installing an agent)' 120
$hostBox = New-Object Windows.Forms.TextBox
$hostBox.Location=New-Object Drawing.Point(24,155); $hostBox.Size=New-Object Drawing.Size(600,30); $form.Controls.Add($hostBox)
$sourceLabel = LabelAt 'Third computer public IPv4 address (limits access to its encrypted connection)' 205
$sourceBox = New-Object Windows.Forms.TextBox
$sourceBox.Location=New-Object Drawing.Point(24,240); $sourceBox.Size=New-Object Drawing.Size(600,30); $form.Controls.Add($sourceBox)
$notice=LabelAt 'Control center installs its own Python runtime. No GitHub login or manual Python installation is needed.' 295
$check=New-Object Windows.Forms.CheckBox
$check.Text='For agent installation: Sim101 is flat, no working orders, and the old agent is closed.'
$check.Location=New-Object Drawing.Point(24,365); $check.Size=New-Object Drawing.Size(600,52); $form.Controls.Add($check)
$install=New-Object Windows.Forms.Button
$install.Text='INSTALL'; $install.Location=New-Object Drawing.Point(24,450); $install.Size=New-Object Drawing.Size(600,45); $form.Controls.Add($install)
$status=LabelAt 'Ready. This installer will not submit any trade.' 520
$role.Add_SelectedIndexChanged({
    $agent = $role.SelectedIndex -gt 0
    $hostBox.Enabled=$agent; $sourceBox.Enabled=$agent; $check.Enabled=$agent
    $notice.Text = $(if($agent){'The new agent retains V10.4 paired trade logic and adds an encrypted browser connection. Your existing V10.4 backup is kept.'}else{'Install here on your Windows 11 third computer. The dashboard opens in your normal browser.'})
})
$hostBox.Enabled=$false; $sourceBox.Enabled=$false; $check.Enabled=$false
$install.Add_Click({
    $install.Enabled=$false
    try {
        $agent=$role.SelectedIndex -gt 0
        if($agent -and -not $check.Checked){throw 'Confirm the agent-installation checkbox first.'}
        $hostAddress=''; $sourceAddress=''
        if($agent){
            $hostAddress=([Net.IPAddress]::Parse($hostBox.Text.Trim())).ToString()
            $sourceAddress=([Net.IPAddress]::Parse($sourceBox.Text.Trim())).ToString()
            foreach($address in @($hostAddress,$sourceAddress)) {
                if(([Net.IPAddress]::Parse($address)).AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'This preview installer requires IPv4 addresses.'}
            }
        }
        $running = Get-CimInstance Win32_Process | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($destination,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
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
                Invoke-WebRequest -UseBasicParsing -Uri ('https://www.python.org/ftp/python/3.13.15/'+$filename) -OutFile $zip -TimeoutSec 120
                if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){Remove-Item -LiteralPath $zip;throw 'Runtime checksum mismatch. Installation stopped.'}
                Expand-Archive -LiteralPath $zip -DestinationPath $runtime -Force
                Remove-Item -LiteralPath $zip
            }
            $data=Join-Path $base 'coordinator-data'; Protect-Directory $data
            $scriptFile=Join-Path $destination 'install\Start-Control-Center.ps1'
            Add-DesktopShortcut 'Trading Control Center' $scriptFile
            $networkFile=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Control-Computer-Network.txt'
            $publicIp='Unable to detect automatically. Look up this computer public IPv4 address.'
            try {
                $detected=(Invoke-WebRequest -UseBasicParsing -Uri 'https://api.ipify.org' -TimeoutSec 8).Content.Trim()
                if(([Net.IPAddress]::Parse($detected)).AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){$publicIp=$detected}
            }catch{}
            @("Third computer public IPv4 address: $publicIp",'', 'Enter this address in the agent installer on each VM.',
              'If your home public IP changes, rerun the agent installer to update its scoped firewall rule.',
              'Cloud-provider firewalls may also need TCP 8789 from this address only.') | Set-Content -LiteralPath $networkFile -Encoding UTF8
            Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$scriptFile+'"')
            $status.Text='Installed. Dashboard is opening. Network details are on your desktop.'
        }else{
            $id=if($role.SelectedIndex -eq 1){'vm-left'}else{'vm-right'}
            $name=if($role.SelectedIndex -eq 1){'VM left'}else{'VM right'}
            $data=Join-Path $base 'agent-data'; Protect-Directory $data
            $identityPath=Join-Path $data 'identity.clixml'
            if(Test-Path -LiteralPath $identityPath){
                $identity=Import-Clixml -LiteralPath $identityPath
                if($identity.Id -cne $id){throw 'This computer is already enrolled as the other VM. Use the existing role.'}
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
            $status.Text='Allowing encrypted access from your third computer. Windows will request administrator access.';$form.Refresh()
            $firewall=Join-Path $destination 'install\Allow-Control-Connection.ps1'
            $process=Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$firewall+'" -SourceAddress '+$sourceAddress)
            if($process.ExitCode -ne 0){throw 'Firewall configuration failed. Installation files are present; rerun setup to finish.'}
            $scriptFile=Join-Path $destination 'agent\Control_VM_Agent_v11.ps1'
            Add-DesktopShortcut ('Trading Agent - '+$name) $scriptFile
            Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$scriptFile+'"')
            $status.Text='Installed. Enter your existing peer settings, Start Agent, Test Peer, then Copy Connection Code.'
        }
        $install.Text='INSTALLED'
    }catch{
        $status.Text='Installation stopped: '+$_.Exception.Message
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation stopped') | Out-Null
        $install.Enabled=$true
    }
})
[void]$form.ShowDialog()
