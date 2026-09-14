param([Parameter(Mandatory=$true)][string]$LocalAddress)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Private-Network.ps1')
try {
    if(-not (Test-PrivateAddress15 $LocalAddress)) { throw 'A Tailscale address is required.' }
    $actual=Get-PrivateAddress15
    if($actual -cne $LocalAddress) { throw 'Private address changed. Check connection and run installation again.' }
    $network=@(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $LocalAddress -ErrorAction Stop)
    if($network.Count -ne 1) { throw 'Private network interface could not be identified uniquely.' }
    $name='Trading Control Center V15 Private TLS'
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8789 -Profile Any -LocalAddress $LocalAddress -InterfaceAlias $network[0].InterfaceAlias -RemoteAddress '100.64.0.0/10' | Out-Null
    # Retire only our former public control rule; unrelated firewall configuration is untouched.
    Get-NetFirewallRule -DisplayName 'Trading Control Center TLS 8789' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host 'Trading connections enabled on the private interface. No peer IP list is required.'
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
