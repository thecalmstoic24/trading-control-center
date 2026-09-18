$ErrorActionPreference='Stop'
$text=Get-Content (Join-Path $PSScriptRoot '../release/Update_Trading_Control_Center_API.cmd') -Raw
$payload=($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1]
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($payload,[ref]$null,[ref]$errors)
if($errors){throw $errors}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ReleaseFile'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$temp=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
$script:count=0;$script:fail=$false
function Invoke-WebRequest {throw 'Raw downloads are forbidden in the API updater'}
function Invoke-RestMethod {param($Uri,$Headers,$TimeoutSec,$MaximumRedirection)
 $script:count++
 if($Uri -notlike 'https://api.github.com/repos/thecalmstoic24/trading-control-center/contents/release/latest.json?ref=control-center-third-computer&check=*'){throw 'Unexpected API URL'}
 if($MaximumRedirection -ne 0){throw 'Redirects must be disabled'}
 if($script:fail){[IO.File]::WriteAllText($temp,'partial');throw 'Simulated timeout'}
 return @{type='file';encoding='base64';content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('verified bytes'))}
}
try {
 Get-ReleaseFile 'control-center-third-computer' 'release/latest.json' $temp
 if([IO.File]::ReadAllText($temp) -cne 'verified bytes' -or $script:count -ne 1){throw 'API decode failed'}
 $script:count=0;$script:fail=$true;$caught=$false
 try{Get-ReleaseFile 'control-center-third-computer' 'release/latest.json' $temp}catch{$caught=$true}
 if(-not $caught -or $script:count -ne 3 -or (Test-Path $temp)){throw 'Retry limit or cleanup failed'}
 if($payload -notmatch 'SHA256' -or $payload -notmatch 'Installer URL is not an approved immutable repository file'){throw 'Verification guards missing'}
 Write-Host 'PASS: API-only updater syntax, exact decoding, no redirects/raw requests, bounded retries, cleanup and validation guards.'
}finally{if(Test-Path $temp){Remove-Item $temp}}
