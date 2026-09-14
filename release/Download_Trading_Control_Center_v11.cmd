@echo off
setlocal
title Trading Control Center Downloader v11
echo Downloading Trading Control Center v11 Preview from GitHub...
echo.
powershell.exe -NoLogo -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $uri = 'https://raw.githubusercontent.com/thecalmstoic24/trading-control-center/91037e5332ea55b358c2d1afcec4fdec4b50c5fa/release/Setup_Trading_Control_Center_v11.ps1'; $dir = Join-Path $env:TEMP ('TradingAgentSetup-' + [guid]::NewGuid().ToString('N')); [IO.Directory]::CreateDirectory($dir) | Out-Null; $file = Join-Path $dir 'Setup_Trading_Control_Center_v11.ps1'; Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $file -TimeoutSec 60; $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash; if ($actual -ine '4736bad4d4417565aa2398081397174f0da398617247b06e8c217df09d6d8522') { throw 'Checksum mismatch. Nothing was launched. Download the correct numbered installer.' }; Unblock-File -LiteralPath $file; Write-Host 'Download verified. Opening installer...'; $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; & $exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File $file; if ($LASTEXITCODE -ne 0) { throw 'Installer exited with an error.' }; Write-Host 'Installer window closed. If installation succeeded, use the Trading Control Center or VM agent desktop shortcut.'; exit 0 } catch { Write-Host ('SETUP COULD NOT FINISH: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host 'For a 404, make the repository public and confirm the numbered installer is available. No GitHub login or token is used by this downloader.'; exit 1 } }"
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

