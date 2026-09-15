$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/ControlBridge.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$function=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ControlCommand'},$true)
. ([scriptblock]::Create($function.Extent.Text))
function Check($value,$message){if(-not $value){throw $message}}
function Get-ChartSnapshot { @{Position=$script:TestPosition23} }
function Set-ControlsForBusyState { param($Busy) }
function Invoke-Entry {param($Side,$ButtonId) $script:EntryCalls23+=,@{Side=$Side;Button=$ButtonId}}
function Run($command,$body){Invoke-ControlCommand ([pscustomobject]@{Command=$command;AgeSeconds=0;Body=($body | ConvertTo-Json)})}
$controlDirectory=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $controlDirectory | Out-Null
$script:AgentStarted=$true;$script:SkippedResults23=@{};$script:TestPosition23='Flat'
$script:EntryCalls23=@();$pairEnabled=[pscustomobject]@{Checked=$false}
try {
 $id='a'*32;$other='b'*32
 @{tradeId=$id} | ConvertTo-Json | Set-Content (Join-Path $controlDirectory 'sync-pending.json')
 $script:WorkerMode14='export';$script:WorkerTradeId23=$id
 $script:Worker14=[pscustomobject]@{HasExited=$false;Killed=$false;Waited=$false}
 $worker=$script:Worker14
 $worker | Add-Member ScriptMethod Kill {$this.Killed=$true}
 $worker | Add-Member ScriptMethod WaitForExit {param($ms) $this.Waited=$true;return $true}
 $worker | Add-Member ScriptMethod Dispose {}
 $refreshTimer=New-Object PSObject;$refreshTimer | Add-Member ScriptMethod Start {}
 Check (Run 'skip_results' @{tradeId=$id}).ok 'Skip failed'
 Check ($worker.Killed -and $worker.Waited -and -not $script:Worker14) 'Worker must exit before success'
 Check (-not (Test-Path (Join-Path $controlDirectory 'sync-pending.json'))) 'Retry not removed'
 Check (@(Get-Content (Join-Path $controlDirectory 'skipped-results.json') -Raw | ConvertFrom-Json) -contains $id) 'Skip tombstone not persisted'
 Check (Run 'skip_results' @{tradeId=$id}).ok 'Skip must be idempotent'
 $script:TestPosition23='1 L';$rejected=$false
 try {Run 'skip_results' @{tradeId=$other}} catch {$rejected=$true}
 Check $rejected 'Open position allowed skip';Check (-not $script:SkippedResults23.ContainsKey($other)) 'Open position wrote skip'
 $script:TestPosition23='Flat';$script:SingleBinding23=$id;$script:ControlPreparedId=$other
 Check (Run 'single_entry' @{prepareId=$other;side='SELL'}).ok 'Single entry failed'
 Check ($script:EntryCalls23.Count -eq 1 -and $script:EntryCalls23[0].Side -ceq 'SELL') 'Wrong Single Pair direction'
 $rejected=$false;try {Run 'single_entry' @{prepareId=$other;side='SELL'}} catch {$rejected=$true}
 Check $rejected 'Same preparation allowed repeated entry'
 Check ($script:EntryCalls23.Count -eq 1) 'Duplicate single entry'
 'Preview 23 agent: export termination, durable skip, open-position rejection, Single Pair direction and duplicate-entry rejection passed.'
} finally {Remove-Item $controlDirectory -Recurse -Force}
