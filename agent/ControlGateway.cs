using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Security.Cryptography;

// The UI thread owns all NinjaTrader operations. Network workers only authenticate,
// publish cached observations, and queue commands. Compatible with Windows PowerShell 5.1.
public sealed class ControlRequest11 {
    public string Id, Command, Body, Result;
    public long Created = Stopwatch.GetTimestamp();
    public ManualResetEventSlim Done = new ManualResetEventSlim(false);
    public double AgeSeconds { get { return (Stopwatch.GetTimestamp()-Created)/(double)Stopwatch.Frequency; } }
    public void Complete(string result) { Result=result; Done.Set(); }
}
public sealed class ControlGateway11 : IDisposable {
    private readonly TcpListener listener;
    private readonly X509Certificate2 certificate;
    private readonly string token;
    private readonly ConcurrentQueue<ControlRequest11> commands = new ConcurrentQueue<ControlRequest11>();
    private readonly ConcurrentQueue<ControlRequest11> closes = new ConcurrentQueue<ControlRequest11>();
    private readonly Dictionary<string,ControlRequest11> seen = new Dictionary<string,ControlRequest11>();
    private readonly object gate = new object();
    private volatile bool running;
    private string cached = "{\"ok\":false,\"position\":null}";
    private long cachedAt;
    private string peerCache = "{\"ok\":false,\"message\":\"No sample\"}";
    private long peerFreshUntil;
    private int clients;
    public ControlGateway11(int port, X509Certificate2 cert, string credential) {
        certificate=cert; token=credential;
        listener=new TcpListener(IPAddress.Loopback, port);
    }
    public ControlGateway11(int port, X509Certificate2 cert, string credential, string localAddress) {
        IPAddress address=IPAddress.Parse(localAddress);
        byte[] bytes=address.GetAddressBytes();
        if(bytes.Length!=4 || bytes[0]!=100 || bytes[1]<64 || bytes[1]>127) throw new ArgumentException("Private network address required");
        certificate=cert;token=credential;
        listener=new TcpListener(address,port);
    }
    public void Start() { listener.Start(16); running=true; new Thread(Accept){IsBackground=true}.Start(); }
    public void Publish(string json) { lock(gate) { cached=json; cachedAt=Stopwatch.GetTimestamp(); } }
    public void PublishPeer(string json, int remainingMs) { lock(gate) {
        peerCache=json;
        peerFreshUntil=Stopwatch.GetTimestamp()+(long)(Math.Max(0,remainingMs)*Stopwatch.Frequency/1000.0);
    } }
    // Peer-to-peer calls use the same pinned TLS envelope as the coordinator.
    public static Task<string> Send(string host,int port,string pin,string credential,string command,string body,int timeout) {
        return Task.Run(delegate {
            long callStart=Stopwatch.GetTimestamp();
            using(TcpClient c=new TcpClient()) {
                c.NoDelay=true;
                var connect=c.BeginConnect(host,port,null,null);
                using(WaitHandle ready=connect.AsyncWaitHandle) {
                    if(!ready.WaitOne(command=="peer_ping" ? 5000 : 2500)) throw new IOException("Peer TCP connection timed out before this request was sent (port 8789)");
                    c.EndConnect(connect);
                }
                c.ReceiveTimeout=timeout; c.SendTimeout=timeout;
                using(SslStream tls=new SslStream(c.GetStream(),false,delegate(object sender,X509Certificate cert,X509Chain chain,SslPolicyErrors errors){
                    if(cert==null) return false;
                    using(SHA256 h=SHA256.Create()) {
                        string actual=BitConverter.ToString(h.ComputeHash(cert.GetRawCertData())).Replace("-","").ToLowerInvariant();
                        return String.Equals(actual,pin,StringComparison.Ordinal);
                    }
                })) {
                    tls.ReadTimeout=timeout;tls.WriteTimeout=timeout;
                    tls.AuthenticateAsClient(host,null,SslProtocols.Tls12,false);
                    using(StreamReader reader=new StreamReader(tls,new UTF8Encoding(false),false,1024,true))
                    using(StreamWriter writer=new StreamWriter(tls,new UTF8Encoding(false),1024,true)) {
                        writer.AutoFlush=true;
                        long startTicks=Stopwatch.GetTimestamp(); DateTime startUtc=DateTime.UtcNow;
                        writer.WriteLine(credential);writer.WriteLine(Guid.NewGuid().ToString("N"));
                        writer.WriteLine(command);writer.WriteLine(body);
                        string answer=Line(reader,65536);
                        long endTicks=Stopwatch.GetTimestamp(); DateTime endUtc=DateTime.UtcNow;
                        if(command=="peer_ping" && answer.StartsWith("{")) {
                            string measurements="\"clientStartUtc\":\""+startUtc.ToString("o")+"\",\"clientEndUtc\":\""+endUtc.ToString("o")+"\",\"clientStartTicks\":"+startTicks+",\"clientEndTicks\":"+endTicks+",\"clientFrequency\":"+Stopwatch.Frequency+",\"callStartTicks\":"+callStart+",";
                            answer=answer.Insert(1,measurements);
                        }
                        return answer;
                    }
                }
            }
        });
    }
    public ControlRequest11 Take() {
        ControlRequest11 r;
        if (closes.TryDequeue(out r)) return r;
        if (commands.TryDequeue(out r)) return r;
        return null;
    }
    public void CancelQueued() {
        ControlRequest11 r;
        while(commands.TryDequeue(out r)) r.Complete("{\"ok\":false,\"message\":\"Cancelled by Close Both; prepare again.\"}");
    }
    private void Accept() {
        while(running) {
            try {
                TcpClient c=listener.AcceptTcpClient();
                if(Interlocked.Increment(ref clients)>8) { Interlocked.Decrement(ref clients); c.Close(); continue; }
                ThreadPool.QueueUserWorkItem(delegate { try { Handle(c); } catch {} finally { c.Close(); Interlocked.Decrement(ref clients); } });
            } catch { if(!running) return; }
        }
    }
    private static string Line(StreamReader r, int limit) {
        StringBuilder b=new StringBuilder();
        for(int i=0;i<=limit;i++) { int v=r.Read(); if(v<0) throw new IOException(); if(v==10) return b.ToString().TrimEnd('\r'); b.Append((char)v); }
        throw new IOException("Request too large");
    }
    private bool Auth(string supplied) {
        int difference=supplied.Length ^ token.Length;
        for(int i=0;i<token.Length;i++) difference |= token[i] ^ (i<supplied.Length ? supplied[i] : 0);
        return difference==0;
    }
    private void Handle(TcpClient client) {
        client.NoDelay=true;
        client.ReceiveTimeout=5000; client.SendTimeout=5000;
        using(SslStream tls=new SslStream(client.GetStream(),false)) {
            tls.ReadTimeout=5000; tls.WriteTimeout=5000;
            tls.AuthenticateAsServer(certificate,false,SslProtocols.Tls12,false);
            using(StreamReader reader=new StreamReader(tls,new UTF8Encoding(false),false,1024,true))
            using(StreamWriter writer=new StreamWriter(tls,new UTF8Encoding(false),1024,true)) {
                writer.AutoFlush=true;
                if(!Auth(Line(reader,128))) { writer.WriteLine("{\"ok\":false,\"message\":\"Authentication failed\"}"); return; }
                string id=Line(reader,64), command=Line(reader,32), body=Line(reader,8192);
                Guid parsed;
                if(!Guid.TryParseExact(id,"N",out parsed)) throw new IOException("Invalid request ID");
                if(command=="peer_ping") {
                    long ticks=Stopwatch.GetTimestamp();
                    writer.WriteLine("{\"ok\":true,\"version\":\"10.4\",\"timingProtocol\":27,\"peerTicks\":"+ticks+",\"peerFrequency\":"+Stopwatch.Frequency+",\"timestampUtc\":\""+DateTime.UtcNow.ToString("o")+"\"}");return;
                }
                if(command=="peer_monitor") {
                    lock(gate) writer.WriteLine(Stopwatch.GetTimestamp()<peerFreshUntil ? peerCache : "{\"ok\":false,\"message\":\"Peer state stale\",\"sampleAgeMs\":999999}");
                    return;
                }
                if(command=="status") {
                    lock(gate) {
                        long age=cachedAt==0 ? 999999 : (long)((Stopwatch.GetTimestamp()-cachedAt)*1000.0/Stopwatch.Frequency);
                        writer.WriteLine("{\"ok\":true,\"cacheAgeMs\":"+age+",\"state\":"+cached+"}");
                    }
                    return;
                }
                if(command!="skip_results" && command!="single_entry" && command!="bind_single" && command!="peer_check" && command!="prepare" && command!="entry" && command!="close" && command!="invalidate" && command!="bind_peer" && command!="unbind_peer" && command!="peer" && command!="peer_close" && command!="accounts" && command!="post_trade") { writer.WriteLine("{\"ok\":false,\"message\":\"Unsupported command. Update this VM agent.\"}"); return; }
                ControlRequest11 request;
                lock(gate) {
                    if(seen.ContainsKey(id)) {
                        request=seen[id];
                        if(request.Command!=command || request.Body!=body) throw new IOException("ID reuse mismatch");
                    } else {
                        List<string> expired=new List<string>();
                        foreach(var item in seen) if(item.Value.Done.IsSet && item.Value.AgeSeconds>600) expired.Add(item.Key);
                        foreach(string key in expired) seen.Remove(key);
                        if(seen.Count>=4096 || commands.Count+closes.Count>=16) throw new IOException("Queue full");
                        request=new ControlRequest11 { Id=id,Command=command,Body=body };
                        seen.Add(id,request);
                        if(command=="close" || command=="peer_close") { if(command=="close") CancelQueued(); closes.Enqueue(request); } else commands.Enqueue(request);
                    }
                }
                if(request.Done.Wait(90000)) writer.WriteLine(request.Result);
                else writer.WriteLine("{\"ok\":false,\"message\":\"Command outcome unknown; check both VMs. Do not repeat entry.\"}");
            }
        }
    }
    public void Dispose() { running=false; listener.Stop(); CancelQueued(); }
}

// Pure timing calculations are separated from networking and UI for deterministic tests.
public sealed class TimingSample27 {
 public long StartTicks,EndTicks,CallStartTicks,LocalFrequency,PeerTicks,PeerFrequency;
 public DateTime StartUtc,EndUtc,PeerUtc;
 public double RoundTripMs { get { return (EndTicks-StartTicks)*1000.0/LocalFrequency; } }
 public double MidTicks { get { return StartTicks+(EndTicks-StartTicks)/2.0; } }
 public double OffsetMs { get { return (PeerUtc-StartUtc).TotalMilliseconds-RoundTripMs/2; } }
}
public sealed class TimingPlan27 {
 public TimingSample27 Sample;
 public int LeadMs;
 public long CreatedTicks;
 public long PeerDeadline(long localDeadline) {
  if((Stopwatch.GetTimestamp()-CreatedTicks)/(double)Stopwatch.Frequency>10) throw new InvalidOperationException("Timing sample expired; check readiness again.");
  return checked((long)Math.Round(Sample.PeerTicks+(localDeadline-Sample.MidTicks)*Sample.PeerFrequency/Sample.LocalFrequency));
 }
}
public static class PairTiming27 {
 public static TimingPlan27 Evaluate(TimingSample27[] samples) {
  if(samples==null || samples.Length<3) throw new InvalidOperationException("Three timing samples are required.");
  TimingSample27 best=null;double maxCall=0;
  foreach(TimingSample27 s in samples) {
   if(s.LocalFrequency<=0 || s.PeerFrequency<=0 || s.StartTicks<=0 || s.PeerTicks<=0 || s.EndTicks<s.StartTicks || s.CallStartTicks>s.StartTicks) throw new InvalidOperationException("Invalid timing response.");
   if(s.RoundTripMs>500) throw new InvalidOperationException("Peer timing response is too slow; check VM load or network.");
   if(Math.Abs((s.EndUtc-s.StartUtc).TotalMilliseconds-s.RoundTripMs)>25) throw new InvalidOperationException("Windows time changed during measurement; rechecking is required.");
   maxCall=Math.Max(maxCall,(s.EndTicks-s.CallStartTicks)*1000.0/s.LocalFrequency);
   if(best==null || s.RoundTripMs<best.RoundTripMs)best=s;
  }
  if(best.RoundTripMs>150 || maxCall>1000) throw new InvalidOperationException("Timing uncertainty is too high; check VM load or network.");
  foreach(TimingSample27 s in samples) {
   if(s.LocalFrequency!=best.LocalFrequency || s.PeerFrequency!=best.PeerFrequency)throw new InvalidOperationException("Timer frequency changed.");
   double predicted=best.PeerTicks+(s.MidTicks-best.MidTicks)*best.PeerFrequency/best.LocalFrequency;
   if(Math.Abs(s.PeerTicks-predicted)*1000.0/best.PeerFrequency>100 || Math.Abs(s.OffsetMs-best.OffsetMs)>100)throw new InvalidOperationException("Peer timing is unstable; check VM load or clock changes.");
  }
  return new TimingPlan27 { Sample=best,LeadMs=(int)Math.Max(1500,4*maxCall+500),CreatedTicks=Stopwatch.GetTimestamp() };
 }
 public static long DeadlineAfter(int milliseconds) {return Stopwatch.GetTimestamp()+(long)(milliseconds*Stopwatch.Frequency/1000.0);}
 public static double RemainingMs(long deadline) {return (deadline-Stopwatch.GetTimestamp())*1000.0/Stopwatch.Frequency;}
 public static void ValidateCommit(long deadline) {double ahead=RemainingMs(deadline);if(ahead<100 || ahead>5000)throw new InvalidOperationException("Committed timer deadline must be 100 milliseconds to 5 seconds in the future.");}
}
