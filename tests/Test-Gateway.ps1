$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '../agent/ControlGateway.cs')
# Test certificate exists only in memory. This test never contacts a VM or NinjaTrader.
$rsa=[Security.Cryptography.RSA]::Create(2048)
$request=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=localhost',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
$certificate=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-1),[DateTimeOffset]::UtcNow.AddDays(1))
$hash=[Security.Cryptography.SHA256]::Create()
$pin=([BitConverter]::ToString($hash.ComputeHash($certificate.RawData))).Replace('-','').ToLowerInvariant()
$credential='b'*64
$gateway=[ControlGateway11]::new(18789,$certificate,$credential)
function Check($Condition,$Message){if(-not $Condition){throw $Message}}
function Call($Command,$PinValue=$pin,$TokenValue=$credential){
    $task=[ControlGateway11]::Send('127.0.0.1',18789,$PinValue,$TokenValue,$Command,'{}',1500)
    return ($task.GetAwaiter().GetResult() | ConvertFrom-Json)
}
try {
    $gateway.Start()
    $gateway.Publish('{"id":"test-agent","ok":true}')
    Check ((Call 'status').state.id -eq 'test-agent') 'TLS status failed'
    Check ((Call 'peer_ping').version -eq '10.4') 'Timing compatibility failed'
    $gateway.PublishPeer('{"ok":true,"position":"Flat"}',150)
    Check ((Call 'peer_monitor').ok) 'Fresh peer status unavailable'
    Start-Sleep -Milliseconds 200
    Check (-not (Call 'peer_monitor').ok) 'Expired peer sample was incorrectly fresh'
    Check (-not (Call 'status' $pin ('c'*64)).ok) 'Bad credential accepted'
    $rejected=$false
    try { Call 'status' ('0'*64) | Out-Null } catch {$rejected=$true}
    Check $rejected 'Bad certificate pin accepted'
    foreach($command in @('bind_peer','accounts','post_trade')) {
        $task=[ControlGateway11]::Send('127.0.0.1',18789,$pin,$credential,$command,'{}',2000)
        $pending=$null
        for($i=0;$i -lt 50 -and -not $pending;$i++){ $pending=$gateway.Take();Start-Sleep -Milliseconds 10 }
        Check ($pending.Command -eq $command) "Command $command did not reach queue"
        $pending.Complete('{"ok":true}')
        Check (($task.GetAwaiter().GetResult() | ConvertFrom-Json).ok) "Queue reply failed: $command"
    }
    $invalid=Call 'not_a_command'
    Check (-not $invalid.ok -and $invalid.message -match 'Unsupported command') 'Unsupported command lacked structured error'
    'TLS gateway: pinning, authentication, status expiry, timing and queued peer command passed.'
} finally {$gateway.Dispose();$certificate.Dispose();$rsa.Dispose();$hash.Dispose()}
