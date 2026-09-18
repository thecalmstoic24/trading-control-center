// Attach to ONE matching minute NQ/MNQ chart on the designated candle source VM.
// This indicator reads completed bars; it never places or changes orders.
using System;
using System.IO;
using System.Text;
using System.Globalization;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;
namespace NinjaTrader.NinjaScript.Indicators
{
    public class TccTelemetry : Indicator
    {
        private readonly CultureInfo invariant = CultureInfo.InvariantCulture;
        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "TccTelemetry";
                Description = "Completed minute candle exporter for Trading Control Center Auto Quantity Beta.";
                Calculate = Calculate.OnBarClose;
                IsOverlay = true;
                IsSuspendedWhileInactive = false;
            }
        }
        protected override void OnBarUpdate()
        {
            if (State != State.Realtime || BarsInProgress != 0 || CurrentBar < 1
                || BarsPeriod.BarsPeriodType != BarsPeriodType.Minute || (BarsPeriod.Value != 1 && BarsPeriod.Value != 3 && BarsPeriod.Value != 5 && BarsPeriod.Value != 15)) return;
            if (Instrument.MasterInstrument.Name != "NQ" && Instrument.MasterInstrument.Name != "MNQ") return;
            try
            {
                string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TradingControlCenter", "telemetry");
                Directory.CreateDirectory(folder);
                string path = Path.Combine(folder,"candles.json");
                var json = new StringBuilder("{\"periodMinutes\":");
                json.Append(BarsPeriod.Value.ToString(invariant)).Append(",\"instrument\":\"");
                json.Append(Instrument.FullName.Replace("\\", "\\\\").Replace("\"", "\\\""));
                json.Append("\",\"publishedUtc\":\"").Append(DateTime.UtcNow.ToString("o",invariant)).Append("\",\"bars\":[");
                int count=Math.Min(100,CurrentBar+1);
                for(int i=count-1;i>=0;i--)
                {
                    if(i<count-1) json.Append(',');
                    json.Append("{\"time\":\"").Append(TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(Time[i],DateTimeKind.Unspecified),NinjaTrader.Core.Globals.GeneralOptions.TimeZoneInfo).ToString("o",invariant));
                    json.Append("\",\"high\":").Append(High[i].ToString("R",invariant));
                    json.Append(",\"low\":").Append(Low[i].ToString("R",invariant)).Append('}');
                }
                json.Append("]}");
                string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
                File.WriteAllText(temp,json.ToString());
                try { if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path); }
                finally { if(File.Exists(temp)) File.Delete(temp); }
            }
            catch(Exception e) { Print("TccTelemetry: "+e.Message); }
        }
    }
}
