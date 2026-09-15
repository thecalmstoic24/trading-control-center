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
