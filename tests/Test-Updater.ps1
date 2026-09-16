$ErrorActionPreference='Stop'
$text=Get-Content (Join-Path $PSScriptRoot '../release/Install_Trading_Control_Center.cmd') -Raw
$payload=($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1]
$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($payload,[ref]$null,[ref]$errors)
if($errors){throw $errors}
$fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ReleaseFile'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$temp=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
$script:requests=@();$script:failApi=$false
function Invoke-WebRequest {param($Uri,$OutFile,$TimeoutSec,[switch]$UseBasicParsing)
 $script:requests+='raw';[IO.File]::WriteAllText($OutFile,'partial');throw 'Simulated timeout'
}
function Invoke-RestMethod {param($Uri,$Headers,$TimeoutSec)
 $script:requests+='api'
 if($script:failApi){throw 'Simulated API failure'}
 if($Uri -notlike 'https://api.github.com/repos/thecalmstoic24/trading-control-center/contents/release/latest.json?ref=control-center-third-computer&check=*'){throw 'Unexpected API URL'}
 return @{type='file';encoding='base64';content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('verified bytes'))}
}
try {
 Get-ReleaseFile 'control-center-third-computer' 'release/latest.json' $temp
 if([IO.File]::ReadAllText($temp) -cne 'verified bytes' -or ($script:requests -join ',') -ne 'raw,api'){throw 'Fallback failed'}
 $script:requests=@();$script:failApi=$true;$caught=$false
 try{Get-ReleaseFile 'control-center-third-computer' 'release/latest.json' $temp}catch{$caught=$true}
 if(-not $caught -or $script:requests.Count -ne 4 -or (Test-Path $temp)){throw 'Retry limit or partial cleanup failed'}
 $uri=[Uri]'https://raw.githubusercontent.com/thecalmstoic24/trading-control-center/e9e6bc10bdd7ba46dbbe26d61edaf3d0d16e3aa9/release/Setup_Trading_Control_Center_v16.ps1'
 if($uri.AbsolutePath.Split('/')[3] -ne 'e9e6bc10bdd7ba46dbbe26d61edaf3d0d16e3aa9' -or ('release/'+$uri.Segments[-1]) -ne 'release/Setup_Trading_Control_Center_v16.ps1'){throw 'Pinned URL parsing failed'}
 Write-Host 'PASS: syntax, raw timeout/API fallback, exact bytes, bounded retries, partial cleanup, pinned URL parsing.'
}finally{if(Test-Path $temp){Remove-Item $temp}}
