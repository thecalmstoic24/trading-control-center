$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$version = '12.0-preview.1'
$base = Join-Path $env:LOCALAPPDATA 'TradingControlCenter'
$destination = Join-Path $base ("releases\" + $version)
$source = Split-Path $PSScriptRoot -Parent

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
$form.Text = 'Trading Control Center - V12 Named VM Setup'
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
LabelAt 'Choose what to install on THIS computer. Simulation test release only.' 20 | Out-Null
$role = New-Object Windows.Forms.ComboBox
$role.DropDownStyle='DropDownList'; $role.Location=New-Object Drawing.Point(24,70); $role.Size=New-Object Drawing.Size(600,30)
@('Control center - my third computer','Named VM - NinjaTrader agent') | ForEach-Object { [void]$role.Items.Add($_) }
$role.SelectedIndex=0; $form.Controls.Add($role)
$nameLabel=LabelAt 'VM name (examples: MFFLocDao, LCDLocDao, FNThu, FNSean)' 112
$nameBox=New-Object Windows.Forms.ComboBox
$nameBox.Location=New-Object Drawing.Point(24,145);$nameBox.Size=New-Object Drawing.Size(600,30)
@('MFFLocDao','LCDLocDao','FNThu','FNSean') | ForEach-Object {[void]$nameBox.Items.Add($_)}
$form.Controls.Add($nameBox)
$hostLabel = LabelAt 'VM public IPv4 address (only needed when installing an agent)' 190
$hostBox = New-Object Windows.Forms.TextBox
$hostBox.Location=New-Object Drawing.Point(24,225); $hostBox.Size=New-Object Drawing.Size(600,30); $form.Controls.Add($hostBox)
$sourceLabel = LabelAt 'Third computer public IPv4 address (limits access to its encrypted connection)' 270
$sourceBox = New-Object Windows.Forms.TextBox
$sourceBox.Location=New-Object Drawing.Point(24,305); $sourceBox.Size=New-Object Drawing.Size(600,30); $form.Controls.Add($sourceBox)
$peerLabel=LabelAt 'Other trading VMs public IPv4 addresses (comma separated; permits TLS pairing)' 350
$peerBox=New-Object Windows.Forms.TextBox
$peerBox.Location=New-Object Drawing.Point(24,385);$peerBox.Size=New-Object Drawing.Size(600,30);$form.Controls.Add($peerBox)
$notice=LabelAt 'Control center installs its own Python runtime. No GitHub login or manual Python installation is needed.' 440
$check=New-Object Windows.Forms.CheckBox
$check.Text='For agent installation: Sim101 is flat, no working orders, and the old agent is closed.'
$check.Location=New-Object Drawing.Point(24,500); $check.Size=New-Object Drawing.Size(600,52); $form.Controls.Add($check)
$install=New-Object Windows.Forms.Button
$install.Text='INSTALL'; $install.Location=New-Object Drawing.Point(24,580); $install.Size=New-Object Drawing.Size(600,45); $form.Controls.Add($install)
$status=LabelAt 'Ready. This installer will not submit any trade.' 650
$role.Add_SelectedIndexChanged({
    $agent = $role.SelectedIndex -gt 0
    $hostBox.Enabled=$agent; $sourceBox.Enabled=$agent; $check.Enabled=$agent; $nameBox.Enabled=$agent; $peerBox.Enabled=$agent
    $notice.Text = $(if($agent){'V12 retains the SIM click logic and uses TLS for selected peer connections. Previous releases are kept for rollback.'}else{'Install here on your Windows 11 third computer. The dashboard opens in your normal browser.'})
})
$hostBox.Enabled=$false; $sourceBox.Enabled=$false; $check.Enabled=$false; $nameBox.Enabled=$false; $peerBox.Enabled=$false
$identityFile=Join-Path $base 'agent-data\identity.clixml'
if(Test-Path -LiteralPath $identityFile){
    $existingIdentity=Import-Clixml -LiteralPath $identityFile
    $role.SelectedIndex=1
    $nameBox.Text=switch($existingIdentity.Id){'vm-left' {'MFFLocDao'} 'vm-right' {'LCDLocDao'} default {$existingIdentity.Name}}
    $hostBox.Text=$existingIdentity.HostAddress
    $networkConfig=Join-Path $base 'agent-data\network.json'
    if(Test-Path -LiteralPath $networkConfig){$savedNetwork=Get-Content -LiteralPath $networkConfig -Raw|ConvertFrom-Json;$sourceBox.Text=$savedNetwork.controller;$peerBox.Text=$savedNetwork.peers -join ','}
}
$install.Add_Click({
    $install.Enabled=$false
    try {
        $agent=$role.SelectedIndex -gt 0
        if($agent -and -not $check.Checked){throw 'Confirm the agent-installation checkbox first.'}
        $hostAddress=''; $sourceAddress=''; $peers=@(); $name=$nameBox.Text.Trim()
        if($agent){
            if($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.\-]{0,39}$'){throw 'Enter a unique VM name, up to 40 characters.'}
            $hostAddress=([Net.IPAddress]::Parse($hostBox.Text.Trim())).ToString()
            $sourceAddress=([Net.IPAddress]::Parse($sourceBox.Text.Trim())).ToString()
            $peers=@($peerBox.Text -split ',' | Where-Object { $_.Trim() } | ForEach-Object { ([Net.IPAddress]::Parse($_.Trim())).ToString() } | Select-Object -Unique)
            if($peers.Count -eq 0){throw 'Enter the public IPv4 addresses of the other VMs you want to pair with.'}
            foreach($address in @($hostAddress,$sourceAddress)+$peers) {
                if(([Net.IPAddress]::Parse($address)).AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'This preview installer requires IPv4 addresses.'}
                $octets=$address.Split('.')
                if($octets[0] -in @('0','10','127') -or ([int]$octets[0] -ge 224) -or ($octets[0] -eq '192' -and $octets[1] -eq '168') -or ($octets[0] -eq '172' -and [int]$octets[1] -ge 16 -and [int]$octets[1] -le 31) -or ($octets[0] -eq '169' -and $octets[1] -eq '254')){throw ('Use a PUBLIC IPv4 address, not '+$address+'. Your third computer public IP is in Control-Computer-Network.txt.')}
            }
        }
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
            $networkFile=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Control-Computer-Network.txt'
            $publicIp='Unable to detect automatically. Look up this computer public IPv4 address.'
            try {
                $detected=(Invoke-WebRequest -UseBasicParsing -Uri 'https://api.ipify.org' -TimeoutSec 8).Content.Trim()
                if(([Net.IPAddress]::Parse($detected)).AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){$publicIp=$detected}
            }catch{}
            @("Third computer public IPv4 address: $publicIp",'', 'Enter this address in the agent installer on each VM.',
              'If your home public IP changes, rerun the agent installer to update its scoped firewall rule.',
              'Each VM also needs TCP 8789 from the public IPs of the other VMs it will pair with.') | Set-Content -LiteralPath $networkFile -Encoding UTF8
            Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$scriptFile+'"')
            $status.Text='Installed. Dashboard is opening. Network details are on your desktop.'
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
            @{controller=$sourceAddress;peers=$peers} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'network.json') -Encoding UTF8
            $status.Text='Allowing encrypted access from your third computer and selected peer IPs. Windows will request administrator access.';$form.Refresh()
            $firewall=Join-Path $destination 'install\Allow-Control-Connection.ps1'
            $process=Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$firewall+'" -SourceAddress '+((@($sourceAddress)+$peers | Select-Object -Unique) -join ','))
            if($process.ExitCode -ne 0){throw 'Firewall configuration failed. Installation files are present; rerun setup to finish.'}
            $scriptFile=Join-Path $destination 'agent\Control_VM_Agent_v12.ps1'
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
