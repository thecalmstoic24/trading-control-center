$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot '../agent/AirtableWorker.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-AccountId16','Get-AccountMatches16')) {
 $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
}
$raw='BX-M7526703186112!Bulenox!Bulenox';$id='BX-M7526703186112'
$records=@([pscustomobject]@{id='rec1';fields=@{id=$id;'Master Account'='BUL-THAO'}})
$result=@(Get-AccountMatches16 @($raw,'Sim101') $records 'BUL-THAO')
if($result.Count -ne 1 -or $result[0] -cne $raw){throw 'Full label was not retained.'}
if(@(Get-AccountMatches16 @($raw) $records 'BUL-SEAN').Count){throw 'Wrong master accepted.'}
if((Get-AccountId16 'MFF123!Bulenox') -cne 'MFF123!Bulenox'){throw 'Unrelated account modified.'}
$blocked=$false
try {Get-AccountMatches16 @($raw,$id) $records 'BUL-THAO'}catch{$blocked=$true}
if(-not $blocked){throw 'Duplicate account accepted.'}
if(($raw -split '!',2)[0] -cne $id){throw 'Export ID mismatch.'}
'PowerShell discovery: exact record/master, raw label preservation, ambiguity rejection and export ID passed.'

foreach($raw in @('BX-M7526703186112|Bulenox','BX-M7526703186112|Bulenox!Bulenox')) {
 $result=@(Get-AccountMatches16 @($raw,'Sim101') $records 'BUL-THAO')
 if($result.Count -ne 1 -or $result[0] -cne $raw){throw 'Pipe label matching failed.'}
 if(($raw -split '[!|]',2)[0] -cne $id){throw 'Pipe CSV export ID mismatch.'}
}

$mt='BX-MT123456';$m='BX-M123456'
$records=@([pscustomobject]@{id='recMT';fields=@{id=$mt;'Master Account'='BUL-HONG'}},[pscustomobject]@{id='recM';fields=@{id=$m;'Master Account'='BUL-HONG'}})
foreach($suffix in @('','!Bulenox','!Bulenox!Bulenox','|Bulenox','|Bulenox|Bulenox','|Bulenox!Bulenox')) {
 $raw=$mt+$suffix
 if((Get-AccountId16 $raw) -cne $mt){throw 'MT normalization failed'}
 $result=@(Get-AccountMatches16 @($raw,$m+'|Bulenox','Sim101') $records 'BUL-HONG')
 if($result.Count -ne 2 -or $result[0] -cne $raw){throw 'MT and M were confused, or trading label changed'}
 if(@(Get-AccountMatches16 @($raw) $records 'BUL-SEAN').Count){throw 'Wrong master accepted for MT'}
 if(($raw -split '[!|]',2)[0] -cne $mt){throw 'MT export ID mismatch'}
}
$blocked=$false
try {Get-AccountMatches16 @($mt,$mt+'|Bulenox') $records 'BUL-HONG'} catch {$blocked=$true}
if(-not $blocked){throw 'Duplicate MT account accepted'}
$missing=@(Get-AccountMatches16 @($mt+'|Bulenox') @($records[1]) 'BUL-HONG')
if($missing.Count){throw 'MT account matched a different M account'}
'PowerShell BX-MT: suffix variants, exact Airtable ID/master, raw trading label, distinct M account, duplicate rejection and CSV ID passed.'
