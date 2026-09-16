# Entry timers use measured peer monotonic counters; wall clocks are diagnostics only.
$script:TimingPlan27=$null
function Measure-PairTiming {
 $script:TimingPlan27=$null
 for($pass27=1;$pass27 -le 2;$pass27++) {
  try {
   $samples27=New-Object 'System.Collections.Generic.List[TimingSample27]'
   for($i27=0;$i27 -lt 3;$i27++) {
    $reply27=Send-PeerRequest -Payload ([ordered]@{command='ping'}) -TimeoutMilliseconds 1500
    if(-not $reply27.ok -or $reply27.timingProtocol -ne 27){throw 'Update both selected VM agents to Preview 27 for coordinated entry timing.'}
    $sample27=New-Object TimingSample27
    $sample27.StartTicks=[long]$reply27.clientStartTicks;$sample27.EndTicks=[long]$reply27.clientEndTicks;$sample27.CallStartTicks=[long]$reply27.callStartTicks
    $sample27.LocalFrequency=[long]$reply27.clientFrequency;$sample27.PeerTicks=[long]$reply27.peerTicks;$sample27.PeerFrequency=[long]$reply27.peerFrequency
    $sample27.StartUtc=[DateTime]::Parse([string]$reply27.clientStartUtc).ToUniversalTime();$sample27.EndUtc=[DateTime]::Parse([string]$reply27.clientEndUtc).ToUniversalTime();$sample27.PeerUtc=[DateTime]::Parse([string]$reply27.timestampUtc).ToUniversalTime()
    $samples27.Add($sample27)
   }
   $script:TimingPlan27=[PairTiming27]::Evaluate($samples27.ToArray())
   $script:PeerOffsetMs=$script:TimingPlan27.Sample.OffsetMs
   $script:EntryLeadMs=$script:TimingPlan27.LeadMs
   Write-PairLog "TIMING27 offset=$([int]$script:PeerOffsetMs)ms measuredRTT=$([int]$script:TimingPlan27.Sample.RoundTripMs)ms lead=$script:EntryLeadMs ms; monotonic entry timers"
   return
  } catch {
   $reason27=$_.Exception.Message
   Write-PairLog "TIMING27 check $pass27 failed before arm: $reason27"
   if($pass27 -eq 2 -or $reason27 -like 'Update both*'){throw $reason27}
   Start-Sleep -Milliseconds 150
  }
 }
}
function Commit-LocalAction {
 param([string]$PairId,[DateTime]$ExecuteAtUtc,[long]$ExecuteAtTicks=0)
 if($null -eq $script:ScheduledAction){throw 'No action is armed.'}
 if($script:ScheduledAction.PairId -cne $PairId){throw 'Pair ID does not match the armed action.'}
 if($script:ScheduledAction.ExecuteAtUtc -ne [DateTime]::MaxValue){throw 'Action already committed. Duplicate commit blocked.'}
 if($ExecuteAtTicks -le 0){throw 'Monotonic entry deadline missing. Update both VM agents to Preview 27.'}
 [PairTiming27]::ValidateCommit($ExecuteAtTicks)
 $script:ScheduledAction | Add-Member -NotePropertyName ExecuteAtTicks -NotePropertyValue $ExecuteAtTicks -Force
 $script:ScheduledAction.ExecuteAtUtc=$ExecuteAtUtc
 Write-PairLog "COMMIT27 pair=$PairId ahead=$([int][PairTiming27]::RemainingMs($ExecuteAtTicks))ms"
 $executionStatus.Text="$($script:ScheduledAction.Side) COMMITTED with verified entry timer"
 $executionStatus.ForeColor=[System.Drawing.Color]::DarkOrange
}
