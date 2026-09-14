@echo off
setlocal
title Trading Control Center Downloader v11 - Permission Fix 1
echo Downloading Trading Control Center v11 Preview from GitHub...
echo.
powershell.exe -NoLogo -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $uri = 'https://raw.githubusercontent.com/thecalmstoic24/trading-control-center/dbd73ac93e4ac80b9dd95785f1cb7de688a75fa5/release/Setup_Trading_Control_Center_v11.ps1'; $dir = Join-Path $env:TEMP ('TradingAgentSetup-' + [guid]::NewGuid().ToString('N')); [IO.Directory]::CreateDirectory($dir) | Out-Null; $file = Join-Path $dir 'Setup_Trading_Control_Center_v11.ps1'; Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $file -TimeoutSec 60; $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash; if ($actual -ine '8d5780adffbb7d083f0d0d3ff316322df3c3d33a3d402bca0dc1c6a9da61dabc') { throw 'Checksum mismatch. Nothing was launched. Download the correct numbered installer.' }; Unblock-File -LiteralPath $file; Write-Host 'Download verified. Opening installer...'; $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; & $exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File $file; if ($LASTEXITCODE -ne 0) { throw 'Installer exited with an error.' }; Write-Host 'Installer window closed. If installation succeeded, use the Trading Control Center or VM agent desktop shortcut.'; exit 0 } catch { Write-Host ('SETUP COULD NOT FINISH: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host 'For a 404, make the repository public and confirm the numbered installer is available. No GitHub login or token is used by this downloader.'; exit 1 } }"
if errorlevel 1 goto failed
echo.
echo Done.
pause
exit /b 0
:failed
echo.
echo Download or setup failed. Read the message above.
pause
exit /b 1

