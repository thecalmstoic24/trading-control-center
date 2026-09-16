$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot '../agent/AirtableWorker.ps1') -Raw
$errors=$null;$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$errors)
if($errors){throw $errors}
# Prevent reintroducing the .NET Core-only setter that failed on Windows PowerShell.
if($source -match '\$info\.StandardInputEncoding\s*='){throw 'Unsupported Windows PowerShell property'}
foreach($name in @('Get-AirtableHttpStatus','ConvertTo-CurlConfigValue','Invoke-AirtableCurl','Invoke-AirtableRequest')) {
 $fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 if(-not $fn){throw "Missing $name"};. ([scriptblock]::Create($fn.Extent.Text))
}
$state=Join-Path ([IO.Path]::GetTempPath()) ('transport-test-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($state)
$script:UseAirtableCurl=$false;$script:curlCalls=0;$script:powerCalls=0;$script:httpStatus=0
function Log([string]$message) {if($message.Contains('patTEST')){throw 'Token leaked'}}
# Keep the real process adapter for a separate fake-executable integration test.
$adapter=${function:Invoke-AirtableCurl}
function Invoke-AirtableCurl($RequestParams) {$script:curlCalls++;return @{records=@(@{id='recTest'})}}
function Invoke-RestMethod {
 $script:powerCalls++
 if($script:httpStatus){$e=New-Object System.Exception('Rejected');$e.Data['HttpStatus']=$script:httpStatus;throw $e}
 throw 'Simulated transport timeout'
}
try {
 $request=@{Uri='https://api.airtable.com/v0/test/table';Method='GET';Headers=@{Authorization='Bearer patTEST'}}
 $r=Invoke-AirtableRequest $request
 if($r.records[0].id -ne 'recTest' -or $script:curlCalls -ne 1 -or $script:powerCalls -ne 1){throw 'Fallback failed'}
 $script:UseAirtableCurl=$false
 $null=Invoke-AirtableRequest $request
 if($script:powerCalls -ne 1 -or $script:curlCalls -ne 2){throw 'Persistent preference failed'}
 Remove-Item (Join-Path $state 'curl-transport.txt');$script:UseAirtableCurl=$false
 foreach($status in @(401,403,429,500)) {
  $script:httpStatus=$status;$caught=$false
  try{$null=Invoke-AirtableRequest $request}catch{if((Get-AirtableHttpStatus $_) -ne $status){throw};$caught=$true}
  if(-not $caught -or $script:curlCalls -ne 2){throw "HTTP $status incorrectly retried"}
 }
 ${function:Invoke-AirtableCurl}=$adapter
 if($env:TCC_FAKE_CURL_ROOT){
  $previousWindir=$env:WINDIR;$env:WINDIR=$env:TCC_FAKE_CURL_ROOT
  try{
   $r=Invoke-AirtableCurl $request
   if($r.records[0].id -ne 'recTest'){throw 'Process adapter GET failed'}
   $body='{"records":[{"id":"recTest","fields":{"name":"Nguyễn \"quote\" \\ path","number":5}}]}'
   $request.Method='PATCH';$request.Body=$body
   $r=Invoke-AirtableCurl $request
   if($r.echoBody -cne $body){throw 'PATCH body changed'}
   $env:TCC_FAKE_HTTP='403';$caught=$false
   try{$null=Invoke-AirtableCurl $request}catch{if((Get-AirtableHttpStatus $_) -ne 403){throw};$caught=$true}
   if(-not $caught){throw 'Curl HTTP error lost'}
   $env:TCC_FAKE_HTTP='200';$env:TCC_FAKE_EXIT='28';$caught=$false
   try{$null=Invoke-AirtableCurl $request}catch{$caught=$true}
   if(-not $caught){throw 'Curl timeout accepted'}
  }finally{$env:WINDIR=$previousWindir;Remove-Item Env:TCC_FAKE_HTTP,Env:TCC_FAKE_EXIT -ErrorAction SilentlyContinue}
 }
 'PASS: transport fallback, persisted preference, HTTP errors not retried, process adapter, UTF-8 PATCH, curl timeout.'
}finally{Remove-Item $state -Recurse -Force}
