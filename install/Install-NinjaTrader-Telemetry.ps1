$ErrorActionPreference='Stop'
if(Get-Process -Name NinjaTrader -ErrorAction SilentlyContinue){throw 'Close NinjaTrader before installing telemetry, then run this shortcut again.'}
$custom=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'NinjaTrader 8\bin\Custom'
if(-not (Test-Path -LiteralPath $custom)){throw 'NinjaTrader 8 custom directory was not found for this Windows user.'}
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'agent'
foreach($item in @(@('Indicators','TccTelemetry.cs'),@('AddOns','TccOrderSafety.cs'))){
 $targetDir=Join-Path $custom $item[0]
 New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
 $target=Join-Path $targetDir $item[1]
 if(Test-Path -LiteralPath $target){Copy-Item -LiteralPath $target -Destination ($target+'.'+(Get-Date -Format yyyyMMddHHmmss)+'.backup')}
 Copy-Item -LiteralPath (Join-Path $source $item[1]) -Destination $target -Force
}
Write-Host 'Telemetry installed. Start NinjaTrader and compile in NinjaScript Editor (F5).'
Write-Host 'On the ONE candle-source VM only: add TccTelemetry to a 1-minute NQ/MNQ chart for your active contract.'
Write-Host 'TccOrderSafety runs automatically on every VM after NinjaTrader loads the compiled add-on.'
Read-Host 'Press Enter to close'
