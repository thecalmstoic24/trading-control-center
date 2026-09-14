param([Parameter(Mandatory=$true)][string]$SourceAddress)
$ErrorActionPreference = 'Stop'
try {
    $addresses=@($SourceAddress -split ',' | ForEach-Object {
        $ip=[Net.IPAddress]::Parse($_.Trim())
        if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'Only IPv4 sources are allowed.'}
        $ip.ToString()
    } | Select-Object -Unique)
    if($addresses.Count -lt 2){throw 'Supply the controller and at least one peer address.'}
    $name = 'Trading Control Center TLS 8789'
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8789 -Profile Any -RemoteAddress $addresses | Out-Null
    Write-Host 'Encrypted control port 8789 is allowed only from the specified controller and peer computers.'
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
