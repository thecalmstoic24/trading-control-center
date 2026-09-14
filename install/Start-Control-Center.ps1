$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Private-Network.ps1')
try { $null=Get-PrivateAddress15 } catch { Write-Host $_.Exception.Message;Read-Host 'Press Enter to close';exit 1 }
$data = Join-Path $env:LOCALAPPDATA 'TradingControlCenter\coordinator-data'
$launch = Join-Path $data 'launch.json'
if (Test-Path -LiteralPath $launch) {
    try {
        $saved = Get-Content -LiteralPath $launch -Raw | ConvertFrom-Json
        $process = Get-Process -Id ([int]$saved.pid) -ErrorAction Stop
        $expected = Join-Path $root 'runtime\python.exe'
        if ($process.Path -eq $expected -and ([string]$saved.url) -match '^http://127\.0\.0\.1:8788/#[a-f0-9]{64}$') {
            Start-Process ([string]$saved.url)
            exit
        }
    } catch { }
}
$python = Join-Path $root 'runtime\python.exe'
$server = Join-Path $root 'coordinator\server.py'
& $python $server --data-dir $data
if ($LASTEXITCODE -ne 0) {
    Write-Host 'The coordinator did not start. If another version is running, use its dashboard or stop it when both VMs are flat.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
}
