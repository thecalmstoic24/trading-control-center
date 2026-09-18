$ErrorActionPreference='Stop'
# SDK-shaped compile check only; actual NinjaTrader integration requires its runtime.
$stubs=@'
using System;
using System.Collections.Generic;
namespace NinjaTrader.Data { public enum BarsPeriodType { Minute } public class BarsPeriod { public BarsPeriodType BarsPeriodType; public int Value; } }
namespace NinjaTrader.Core { public static class Globals { public static Options GeneralOptions=new Options(); } public class Options { public TimeZoneInfo TimeZoneInfo=TimeZoneInfo.Utc; } }
namespace NinjaTrader.Cbi {
 public enum OrderState { Filled,Cancelled,Rejected,Working } public enum MarketPosition { Flat,Long,Short } public enum ConnectionStatus { Connected,Disconnected }
 public class Order {public OrderState OrderState;} public class Position {public MarketPosition MarketPosition;}
 public class Connection {public ConnectionStatus Status;}
 public class Account {public static List<Account> All=new List<Account>(); public string Name="Sim101"; public Connection Connection; public List<Order> Orders=new List<Order>(); public List<Position> Positions=new List<Position>();}
}
namespace NinjaTrader.NinjaScript {
 public enum State { SetDefaults,Active,Terminated,Realtime } public enum Calculate { OnBarClose }
 public class AddOnBase {public State State;public string Name,Description;protected virtual void OnStateChange(){} }
 public class Instrument {public MasterInstrument MasterInstrument=new MasterInstrument();public string FullName="NQ 12-26";} public class MasterInstrument {public string Name="NQ";}
 public class Indicator : AddOnBase {public Calculate Calculate;public bool IsOverlay,IsSuspendedWhileInactive;public int BarsInProgress,CurrentBar; public NinjaTrader.Data.BarsPeriod BarsPeriod=new NinjaTrader.Data.BarsPeriod();public Instrument Instrument=new Instrument();public DateTime[] Time=new DateTime[101];public double[] High=new double[101],Low=new double[101];protected virtual void OnBarUpdate(){} protected void Print(string value){} }
}
'@
$root=Split-Path $PSScriptRoot -Parent
$combined=$stubs
foreach($name in @('TccTelemetry.cs','TccOrderSafety.cs')){
 $text=Get-Content (Join-Path $root ('agent\'+$name)) -Raw
 # Each unit retains its usings inside its namespace when compiled together.
 $usings=([regex]::Matches($text,'(?m)^using .*?;') | ForEach-Object {$_.Value}) -join "`n"
 $body=[regex]::Replace($text,'(?m)^using .*?;','')
 $body=[regex]::Replace($body,'(namespace [^\r\n]+\r?\n\{)',('$1'+"`n"+$usings),1)
 $combined+="`n"+$body
}
Add-Type -TypeDefinition $combined
Write-Host 'PASS: telemetry C# compiles against SDK-shaped interfaces. This does not certify the live NinjaTrader runtime.'
