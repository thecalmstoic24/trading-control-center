@echo off
setlocal
title Trading Control Center - Install or Update
set "TCC_LAUNCHER=%~f0"
echo Checking the latest Trading Control Center installer...
powershell.exe -NoLogo -NoProfile -Command "$text=[IO.File]::ReadAllText($env:TCC_LAUNCHER); & ([scriptblock]::Create(($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1]))"
set "TCC_RESULT=%ERRORLEVEL%"
if not "%TCC_RESULT%"=="0" pause
exit /b %TCC_RESULT%
# POWERSHELL_PAYLOAD
$ErrorActionPreference='Stop'
function Get-ReleaseFile([string]$Ref,[string]$Path,[string]$Destination) {
    $repo='thecalmstoic24/trading-control-center'
    $raw='https://raw.githubusercontent.com/'+$repo+'/'+$Ref+'/'+$Path
    $api='https://api.github.com/repos/'+$repo+'/contents/'+$Path+'?ref='+[Uri]::EscapeDataString($Ref)
    $failures=@()
    # A second hostname avoids depending exclusively on raw.githubusercontent.com.
    for($attempt=0;$attempt -lt 4;$attempt++) {
        $useApi=($attempt % 2) -eq 1
        $route=if($useApi){'api.github.com'}else{'raw.githubusercontent.com'}
        Write-Host ('Download attempt '+($attempt+1)+'/4 via '+$route+' ...')
        try {
            if($useApi) {
                $response=Invoke-RestMethod -Uri ($api+'&check='+[Guid]::NewGuid().ToString('N')) -Headers @{'User-Agent'='TradingControlCenter-Updater';'Accept'='application/vnd.github+json'} -TimeoutSec 45
                if($response.type -ne 'file' -or $response.encoding -ne 'base64' -or -not $response.content){throw 'GitHub returned an unsupported file response.'}
                [IO.File]::WriteAllBytes($Destination,[Convert]::FromBase64String($response.content))
            } else {
                Invoke-WebRequest -UseBasicParsing -Uri ($raw+'?check='+[Guid]::NewGuid().ToString('N')) -OutFile $Destination -TimeoutSec 45
            }
            if(-not (Test-Path -LiteralPath $Destination) -or (Get-Item -LiteralPath $Destination).Length -eq 0){throw 'Downloaded file is empty.'}
            return
        } catch {
            $failures+=($route+': '+$_.Exception.Message)
            Write-Host ('Attempt failed: '+$_.Exception.Message) -ForegroundColor Yellow
            if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Force}
        }
    }
    throw ('Unable to download '+$Path+'. '+($failures -join ' | '))
}
$temp=$null
try {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('TradingUpdate-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    $manifestFile=Join-Path $temp 'latest.json'
    Get-ReleaseFile 'control-center-third-computer' 'release/latest.json' $manifestFile
    $manifest=Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
    if($manifest.schema -ne 1 -or [string]$manifest.version -notmatch '^[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[a-z0-9.]+)?$'){throw 'Invalid release manifest.'}
    if([string]$manifest.url -cnotmatch '^https://raw\.githubusercontent\.com/thecalmstoic24/trading-control-center/[a-f0-9]{40}/release/Setup_Trading_Control_Center_v[0-9]+\.ps1$'){throw 'Installer URL is not an approved immutable repository file.'}
    if([string]$manifest.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid installer checksum.'}
    Write-Host ('Downloading version '+$manifest.version+'...')
    $file=Join-Path $temp 'Setup_Trading_Control_Center.ps1'
    $releaseRef=([Uri]$manifest.url).AbsolutePath.Split('/')[3]
    $releasePath='release/'+([Uri]$manifest.url).Segments[-1]
    Get-ReleaseFile $releaseRef $releasePath $file
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.sha256){throw 'Installer checksum mismatch. Nothing was launched.'}
    Unblock-File -LiteralPath $file
    Write-Host 'Verified. Setup will let you review this computer role and settings.'
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File $file
    if($LASTEXITCODE -ne 0){throw 'Setup exited with an error.'}
    Write-Host 'Setup window closed. If installed, use the desktop shortcut to reopen the application.'
} catch {
    Write-Host ('SETUP STOPPED: '+$_.Exception.Message) -ForegroundColor Red
    Write-Host 'The VM could not complete a verified download. Check its connection to raw.githubusercontent.com and api.github.com, then run this updater again.'
    exit 1
} finally {
    if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Recurse -Force}
}
