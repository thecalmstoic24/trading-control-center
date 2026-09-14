$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$source=Get-Content (Join-Path $root 'agent/AirtableWorker.ps1') -Raw
# Exercise the exact success/retry serializer from the worker without loading Windows UI or making requests.
$receipt=@{id='a'*32;completedUtc='2026-09-14T12:00:00Z';accounts=@(@{Account='Account-A';Status='Matched';CurrentBalance=50900;'Realized PnL'=900},@{Account='Sim101';Status='Simulation';CurrentBalance=100000;'Realized PnL'=0})}
$doneValue14=@{receipt=$receipt}
$line=($source -split "`n" | Where-Object {$_ -match "message='Already synced this trade'"} | Select-Object -First 1)
if(-not $line){$line=($source -split "`n" | Where-Object {$_ -match 'receipt=\$doneValue14.receipt' } | Select-Object -First 1)}
if(-not $line){throw 'Retry serializer not found'}
$expression=($line -split '\| Set-Content')[0]
$value=Invoke-Expression $expression | ConvertFrom-Json
if($value.receipt.accounts[0].'Realized PnL' -ne 900 -or $value.receipt.accounts.Count -ne 2){throw 'Receipt values lost during serialization'}
'Export receipt retry serialization passed.'
