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
        listener=new TcpListener(IPAddress.Any, port);
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
            using(TcpClient c=new TcpClient()) {
                var connect=c.BeginConnect(host,port,null,null);
                using(WaitHandle ready=connect.AsyncWaitHandle) {
                    if(!ready.WaitOne(2500)) throw new IOException("TLS peer connection timed out");
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
                        writer.WriteLine(credential);writer.WriteLine(Guid.NewGuid().ToString("N"));
                        writer.WriteLine(command);writer.WriteLine(body);
                        return Line(reader,65536);
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
                    writer.WriteLine("{\"ok\":true,\"version\":\"10.4\",\"timestampUtc\":\""+DateTime.UtcNow.ToString("o")+"\"}");return;
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
                if(command!="prepare" && command!="entry" && command!="close" && command!="invalidate" && command!="bind_peer" && command!="unbind_peer" && command!="peer" && command!="peer_close" && command!="accounts" && command!="post_trade") { writer.WriteLine("{\"ok\":false,\"message\":\"Unsupported command. Update this VM agent.\"}"); return; }
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
