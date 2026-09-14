# V15 discovers this machine's private endpoint; never accepts a public fallback.
function Get-TailscaleExecutable {
    $paths=@((Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'))
    if(${env:ProgramFiles(x86)}) { $paths+=(Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe') }
    foreach($path in $paths) { if(Test-Path -LiteralPath $path) { return $path } }
    throw 'Click SET UP PRIVATE NETWORK, install Tailscale, and sign in on this computer.'
}
function Test-PrivateAddress15([string]$Address) {
    $parsed=$null
    if(-not [Net.IPAddress]::TryParse($Address,[ref]$parsed)) { return $false }
    $bytes=$parsed.GetAddressBytes()
    return ($bytes.Length -eq 4 -and $bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
}
function Read-TailscaleStatus15 {
    $exe=Get-TailscaleExecutable
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$exe;$start.Arguments='status --json';$start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;$start.CreateNoWindow=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    try {
        [void]$process.Start()
        $output=$process.StandardOutput.ReadToEndAsync();$errorOutput=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(5000)) { $process.Kill();throw 'Private network status timed out. Open Tailscale and check its connection.' }
        if($process.ExitCode -ne 0) { throw 'Tailscale is unavailable. Open it and sign in to your private network.' }
        return ($output.GetAwaiter().GetResult() | ConvertFrom-Json)
    } finally { $process.Dispose() }
}
function Get-PrivateAddress15 {
    $state=Read-TailscaleStatus15
    if($state.BackendState -cne 'Running') { throw 'Sign in to Tailscale using the same private network on all computers, then click CHECK CONNECTION.' }
    $addresses=@($state.Self.TailscaleIPs | Where-Object { Test-PrivateAddress15 ([string]$_) })
    if($addresses.Count -ne 1) { throw 'A unique Tailscale IPv4 address was not found.' }
    return [string]$addresses[0]
}
function Open-PrivateNetworkSetup15 {
    try { $exe=Get-TailscaleExecutable } catch { $exe=$null }
    if(-not $exe) {
        $temporary=Join-Path ([IO.Path]::GetTempPath()) ('TccNetwork-'+[guid]::NewGuid().ToString('N')+'.exe')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-1.102.4.exe' -OutFile $temporary -TimeoutSec 120
            $signature=Get-AuthenticodeSignature -LiteralPath $temporary
            if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O="?Tailscale Inc\.?"?(,|$)') { throw 'Tailscale publisher signature could not be verified. No installer was launched.' }
            $install=Start-Process -FilePath $temporary -Verb RunAs -Wait -PassThru
            if($install.ExitCode -notin @(0,3010)) { throw 'Tailscale installation was cancelled or failed.' }
        } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        $exe=Get-TailscaleExecutable
    }
    $gui=Join-Path (Split-Path $exe -Parent) 'tailscale-ipn.exe'
    if(Test-Path $gui) { Start-Process -FilePath $gui }
    # Official client owns authentication. No credentials or auth keys enter this installer.
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList @('up','--unattended','--timeout=60s')
}
