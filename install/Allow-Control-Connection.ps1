param([Parameter(Mandatory=$true)][string]$SourceAddress)
$ErrorActionPreference = 'Stop'
try {
    $ip = [System.Net.IPAddress]::Parse($SourceAddress)
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or [System.Net.IPAddress]::IsLoopback($ip)) {
        throw 'Enter the third computer public IPv4 address.'
    }
    $name = 'Trading Control Center TLS 8789'
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8789 -Profile Any -RemoteAddress $ip.ToString() | Out-Null
    Write-Host 'Encrypted control port 8789 is allowed only from the specified computer.'
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
