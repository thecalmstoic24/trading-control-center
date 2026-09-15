"""Explicit versioned adaptations; the tested V10.4 source remains unchanged."""
def upgrade(source):
    source=source.replace("Set-UiaValue -Element $mainQuantity -Value '1'", "Set-UiaValue -Element $mainQuantity -Value ([string]$LockedQuantity)")
    source=source.replace("Set-UiaValue -Element $topQuantity -Value '1'", "Set-UiaValue -Element $topQuantity -Value ([string]$LockedQuantity)")
    for var in ['$reply', '$peerResult', '$peerStatus', '$peer']:
        source=source.replace(var+'.account -ceq $LockedAccount',var+'.account -ceq $script:PeerAccount14')
        source=source.replace(var+'.account -cne $LockedAccount',var+'.account -cne $script:PeerAccount14')
        source=source.replace('[string]'+var+".quantity -ne '1'", '[string]'+var+'.quantity -ne [string]$script:PeerQuantity14')
    source=source.replace('Expected 1, found', 'Expected $LockedQuantity, found')
    source=source.replace('Qty 1, Currency', 'Qty $LockedQuantity, Currency').replace('Quantity: 1`n','Quantity: $LockedQuantity`n')
    source=source.replace('Sending $Side Market to Sim101...', 'Sending $Side Market to $LockedAccount...')
    source=source.replace("'Closing Sim101 position...'", '"Closing $LockedAccount position..."')
    source=source.replace("'TEST LOCK: Account Sim101  |  Order quantity 1  |  Parameter type Currency'", "'Select account and quantity in the browser. Parameters use Currency.'")
    source=source.replace('v10.4 only permits', 'prepared account is').replace('v10.4 order quantity is locked to','prepared order quantity is')
    for button in ['$prepareButton', '$buyButton', '$sellButton']:
        source=source.replace(button+'.Add_Click({', button+".Add_Click({\n    if(-not $script:RemoteCommandActive) { $executionStatus.Text='Use the browser to select and prepare accounts.'; return }")
    source=source.replace('$peerStatus = Test-PeerReady', "$script:EntryStage19='readiness check'\n    $peerStatus = Test-PeerReady")
    source=source.replace('    $peerArm = Send-PeerRequest', "    $script:EntryStage19='peer arm'\n    $peerArm = Send-PeerRequest")
    source=source.replace('        $peerCommit = Send-PeerRequest', "        $script:EntryStage19='peer commit'\n        $peerCommit = Send-PeerRequest")
    source=source.replace('        Commit-LocalAction -PairId $pairId', "        $script:EntryStage19='local commit'\n        Commit-LocalAction -PairId $pairId")
    source=source.replace('Entry handshake failed: $failure', 'Entry handshake failed at $script:EntryStage19 : $failure')
    return source
