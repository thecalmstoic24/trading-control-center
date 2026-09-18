// Read-only account telemetry. No order submission/cancellation methods are used.
using System;
using System.IO;
using System.Text;
using System.Threading;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript;
namespace NinjaTrader.NinjaScript.AddOns
{
    public class TccOrderSafety : AddOnBase
    {
        private Timer timer;
        private int writing;
        protected override void OnStateChange()
        {
            if(State == State.SetDefaults) { Name="TccOrderSafety"; Description="Read-only order and position checks for Control Center release recovery."; }
            else if(State == State.Active) timer=new Timer(Snapshot,null,0,1000);
            else if(State == State.Terminated) { if(timer!=null) timer.Dispose(); timer=null; }
        }
        private static string Quote(string value) { return "\""+value.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r","\\r").Replace("\n","\\n")+"\""; }
        private void Snapshot(object state)
        {
            if(Interlocked.Exchange(ref writing,1)!=0)return;
            try
            {
                var json=new StringBuilder("{\"publishedUtc\":").Append(Quote(DateTime.UtcNow.ToString("o"))).Append(",\"accounts\":[");
                bool first=true;
                lock(Account.All)
                {
                    foreach(Account account in Account.All)
                    {
                        int orders=0,positions=0;
                        lock(account.Orders) foreach(Order order in account.Orders)
                            if(order.OrderState!=OrderState.Filled && order.OrderState!=OrderState.Cancelled && order.OrderState!=OrderState.Rejected) orders++;
                        lock(account.Positions) foreach(Position position in account.Positions)
                            if(position.MarketPosition!=MarketPosition.Flat)positions++;
                        if(!first)json.Append(',');first=false;
                        json.Append("{\"name\":").Append(Quote(account.Name)).Append(",\"connected\":").Append(account.Connection!=null && account.Connection.Status==ConnectionStatus.Connected?"true":"false");
                        json.Append(",\"workingOrders\":").Append(orders).Append(",\"openPositions\":").Append(positions).Append('}');
                    }
                }
                json.Append("]}");
                string folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"TradingControlCenter","telemetry");Directory.CreateDirectory(folder);
                string path=Path.Combine(folder,"orders.json"),temp=path+".tmp";File.WriteAllText(temp,json.ToString());
                if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);
            }
            catch { /* A failed read leaves an old timestamp, which blocks release. */ }
            finally { Interlocked.Exchange(ref writing,0); }
        }
    }
}
