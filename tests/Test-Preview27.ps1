$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot '../agent/ControlGateway.cs')
function Check($value,$message){if(-not $value){throw $message}}
function Reject([scriptblock]$action,$message){$failed=$false;try{& $action}catch{$failed=$true};Check $failed $message}
function Sample([double]$offset=2000,[int]$index=0,[double]$rtt=20) {
 $s=New-Object TimingSample27;$s.LocalFrequency=10000000;$s.PeerFrequency=20000000
 $s.StartTicks=[long](1000000000+$index*10000000);$s.EndTicks=[long]($s.StartTicks+$rtt*10000);$s.CallStartTicks=$s.StartTicks-4000000
 $s.PeerTicks=[long](2*$s.StartTicks+3000000000+$rtt*10000)
 $s.StartUtc=([DateTime]'2026-09-16T12:00:00Z').AddSeconds($index);$s.EndUtc=$s.StartUtc.AddMilliseconds($rtt);$s.PeerUtc=$s.StartUtc.AddMilliseconds($offset+$rtt/2)
 return $s
}
$samples=@((Sample 2000 0),(Sample 2000 1),(Sample 2000 2))
$plan=[PairTiming27]::Evaluate($samples)
Check ([Math]::Abs($plan.Sample.OffsetMs-2000) -lt .001) 'Stable two-second difference was not retained'
Check ($plan.Sample.RoundTripMs -eq 20) 'Connection setup leaked into measured RTT'
$mapped=$plan.PeerDeadline([long]($plan.Sample.MidTicks+15000000))
Check ([Math]::Abs($mapped-($plan.Sample.PeerTicks+30000000)) -le 1) 'Different-frequency peer timer mapping failed'
$negative=@((Sample -5000 0),(Sample -5000 1),(Sample -5000 2));Check ([PairTiming27]::Evaluate($negative).Sample.OffsetMs -eq -5000) 'Stable negative clock offset rejected'
$bad=@((Sample 2000 0),(Sample 2300 1),(Sample 2000 2));Reject {[PairTiming27]::Evaluate($bad)} 'Clock jump accepted'
$bad=@((Sample 2000 0),(Sample 2000 1),(Sample 2000 2));$bad[1].PeerTicks+=6000000;Reject {[PairTiming27]::Evaluate($bad)} 'Unstable peer counter accepted'
$bad=@((Sample 2000 0 300),(Sample 2000 1 300),(Sample 2000 2 300));Reject {[PairTiming27]::Evaluate($bad)} 'High uncertainty accepted'
$bad=@((Sample 2000 0),(Sample 2000 1),(Sample 2000 2));$bad[1].EndUtc=$bad[1].EndUtc.AddSeconds(1);Reject {[PairTiming27]::Evaluate($bad)} 'Local wall-clock step accepted'
$plan.CreatedTicks=[Diagnostics.Stopwatch]::GetTimestamp()-[Diagnostics.Stopwatch]::Frequency*11;Reject {$plan.PeerDeadline(1000000000)} 'Stale sample accepted'
Reject {[PairTiming27]::ValidateCommit([PairTiming27]::DeadlineAfter(-100))} 'Past deadline accepted'
Reject {[PairTiming27]::ValidateCommit([PairTiming27]::DeadlineAfter(6000))} 'Distant deadline accepted'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../agent/Control_VM_Agent_v16.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
foreach($name in @('Measure-PairTiming','Commit-LocalAction','Run-ScheduledActionIfDue')) {
 $functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
 Invoke-Expression $functions[-1].Extent.Text
}
function Write-PairLog {param($Message)}
function Set-ControlsForBusyState {param($Busy)}
$script:clicks27=0;$script:closes27=0
function Fire-ArmedChartTraderClick {param($ArmedClick)$script:clicks27++}
function Invoke-PairEmergencyClose {param($Reason)$script:closes27++}
$executionStatus=[pscustomobject]@{Text='';ForeColor=[Drawing.Color]::Black}
$script:Busy=$false;$script:ScheduledAction=[pscustomobject]@{PairId='p';Side='BUY';ExecuteAtUtc=[DateTime]::MaxValue;ArmedTicks=[Diagnostics.Stopwatch]::GetTimestamp();ArmedClick=$null}
Commit-LocalAction 'p' ([DateTime]::UtcNow.AddYears(-1)) ([PairTiming27]::DeadlineAfter(1500))
Reject {Commit-LocalAction 'p' ([DateTime]::UtcNow) ([PairTiming27]::DeadlineAfter(1500))} 'Duplicate commit accepted'
Run-ScheduledActionIfDue;Check ($script:clicks27 -eq 0) 'Past wall clock fired early despite future monotonic deadline'
$script:ScheduledAction.ExecuteAtUtc=[DateTime]::UtcNow.AddYears(1);$script:ScheduledAction.ExecuteAtTicks=[PairTiming27]::DeadlineAfter(-10)
Run-ScheduledActionIfDue;Check ($script:clicks27 -eq 1 -and $null -eq $script:ScheduledAction) 'Future wall clock blocked due monotonic entry'
$script:ScheduledAction=[pscustomobject]@{PairId='p';Side='BUY';ExecuteAtUtc=[DateTime]::UtcNow;ExecuteAtTicks=[PairTiming27]::DeadlineAfter(-400);ArmedTicks=[Diagnostics.Stopwatch]::GetTimestamp();ArmedClick=$null}
Run-ScheduledActionIfDue;Check ($script:clicks27 -eq 1 -and $script:closes27 -eq 1) 'Late entry was not blocked and recovered'
$script:probes27=0
function Send-PeerRequest {
 param($Payload,$TimeoutMilliseconds)
 $script:probes27++
 if($script:probes27 -eq 1){throw 'Temporary timing failure'}
 $sample=Sample 2000 (($script:probes27-2)%3)
 return [pscustomobject]@{ok=$true;timingProtocol=27;clientStartTicks=$sample.StartTicks;clientEndTicks=$sample.EndTicks;callStartTicks=$sample.CallStartTicks;clientFrequency=$sample.LocalFrequency;peerTicks=$sample.PeerTicks;peerFrequency=$sample.PeerFrequency;clientStartUtc=$sample.StartUtc.ToString('o');clientEndUtc=$sample.EndUtc.ToString('o');timestampUtc=$sample.PeerUtc.ToString('o')}
}
Measure-PairTiming;Check ($script:probes27 -eq 4 -and $null -ne $script:TimingPlan27) 'One pre-arm recheck did not recover'
function Send-PeerRequest {param($Payload,$TimeoutMilliseconds)$script:probes27++;throw 'Unavailable'}
$script:probes27=0;Reject {Measure-PairTiming} 'Persistent timing fault accepted';Check ($script:probes27 -eq 2 -and $null -eq $script:TimingPlan27) 'Persistent failure was not bounded or retained old timer mapping'
'PASS: stable positive/negative clock offsets, RTT excludes setup, counter-frequency mapping, uncertainty/drift/clock-jump rejection, stale samples, duplicate commit, monotonic firing despite wall-clock shifts, late entry recovery, bounded pre-arm recheck.'
