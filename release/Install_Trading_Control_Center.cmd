@echo off
setlocal
title Trading Control Center - Install or Update
set "TCC_LAUNCHER=%~f0"
echo Checking the latest Trading Control Center installer...
powershell.exe -NoLogo -NoProfile -Command "$text=[IO.File]::ReadAllText($env:TCC_LAUNCHER); & ([scriptblock]::Create(($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1]))"
set "TCC_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %TCC_RESULT%
# POWERSHELL_PAYLOAD
$ErrorActionPreference='Stop'
$temp=$null
try {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $manifestUri='https://raw.githubusercontent.com/thecalmstoic24/trading-control-center/control-center-third-computer/release/latest.json'
    $manifest=Invoke-RestMethod -Uri ($manifestUri+'?check='+[Guid]::NewGuid().ToString('N')) -TimeoutSec 30
    if($manifest.schema -ne 1 -or [string]$manifest.version -notmatch '^[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[a-z0-9.]+)?$'){throw 'Invalid release manifest.'}
    if([string]$manifest.url -cnotmatch '^https://raw\.githubusercontent\.com/thecalmstoic24/trading-control-center/[a-f0-9]{40}/release/Setup_Trading_Control_Center_v[0-9]+\.ps1$'){throw 'Installer URL is not an approved immutable repository file.'}
    if([string]$manifest.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid installer checksum.'}
    Write-Host ('Downloading version '+$manifest.version+'...')
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('TradingUpdate-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    $file=Join-Path $temp 'Setup_Trading_Control_Center.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri $manifest.url -OutFile $file -TimeoutSec 120
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.sha256){throw 'Installer checksum mismatch. Nothing was launched.'}
    Unblock-File -LiteralPath $file
    Write-Host 'Verified. Setup will let you review this computer role and settings.'
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File $file
    if($LASTEXITCODE -ne 0){throw 'Setup exited with an error.'}
    Write-Host 'Setup window closed. If installed, use the desktop shortcut to reopen the application.'
} catch {
    Write-Host ('SETUP STOPPED: '+$_.Exception.Message) -ForegroundColor Red
    Write-Host 'Downloads require this GitHub repository to remain public and accessible.'
    exit 1
} finally {
    if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Recurse -Force}
}
