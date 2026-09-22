<%@ WebHandler Language="C#" Class="GitHubPublish" %>
using System;
using System.Collections;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web;
using System.Web.Script.Serialization;

public class GitHubPublish : IHttpHandler {
  private readonly JavaScriptSerializer J = new JavaScriptSerializer { MaxJsonLength = 32 * 1024 * 1024 };
  public bool IsReusable { get { return false; } }

  public void ProcessRequest(HttpContext c) {
    c.Response.ContentType = "application/json; charset=utf-8";
    c.Response.Cache.SetNoStore();
    c.Response.TrySkipIisCustomErrors = true;
    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
    if (String.Equals(c.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase)) { Health(c); return; }
    if (!String.Equals(c.Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase)) { Err(c, 405, "GET or POST required."); return; }
    try {
      string raw; using (var sr = new StreamReader(c.Request.InputStream)) raw = sr.ReadToEnd();
      var b = Obj(raw);
      var files = Arr(b, "files");
      if (files.Count == 0) throw new Exception("files are required.");
      EnsureWebConfig(files);

      string token = Setting("BABCO_GITHUB_TOKEN");
      if (!SecretReady(token)) throw new InvalidOperationException("GitHub token Key Vault reference is not resolved. Check App Service managed identity access to kv-babco-github-prod / BABCO-GITHUB-TOKEN.");

      var me = Obj(GH("GET", "https://api.github.com/user", token, null));
      string owner = S(me, "login");
      if (String.IsNullOrWhiteSpace(owner)) throw new Exception("GitHub user could not be resolved from token.");

      string repoName = Slug(S(b, "projectName"));
      if (String.IsNullOrWhiteSpace(repoName)) repoName = "pilot-project";
      repoName = Take(repoName + "-" + DateTime.UtcNow.ToString("MMdd-HHmmss"), 80).Trim('-');

      var createBody = new Dictionary<string, object>();
      createBody["name"] = repoName;
      createBody["description"] = "Created by Babco Agent Pilot Router";
      createBody["private"] = false;
      createBody["auto_init"] = true;

      var repoObj = Obj(GH("POST", "https://api.github.com/user/repos", token, J.Serialize(createBody)));
      Thread.Sleep(1000);

      foreach (var o in files) {
        var d = o as Dictionary<string, object>;
        if (d == null) continue;
        string path = S(d, "path");
        string content = SRaw(d, "content");
        ValidatePath(path);
        PutFile(owner, repoName, path, Encoding.UTF8.GetBytes(content), token, "Pilot Router: add " + path);
      }

      byte[] zip = ZipStore(files);
      string packagePath = "deploy/site.zip";
      PutFile(owner, repoName, packagePath, zip, token, "Pilot Router: deployment package");

      string repoUrl = "https://github.com/" + owner + "/" + repoName;
      string rawPackage = "https://raw.githubusercontent.com/" + owner + "/" + repoName + "/main/" + packagePath;
      c.Response.StatusCode = 200;
      c.Response.Write(J.Serialize(new {
        ok = true,
        executor = "GitHub API",
        executionId = "github-" + S(repoObj, "id"),
        repoOwner = owner,
        repoName = repoName,
        repoUrl = repoUrl,
        packageRawUrl = rawPackage,
        fileCount = files.Count,
        zipBytes = zip.Length,
        result = "Repository created and source/package pushed."
      }));
    }
    catch (WebException e) { Err(c, 502, WebErr(e)); }
    catch (Exception e) { Err(c, 500, e.GetType().Name + ": " + e.Message); }
  }

  private void Health(HttpContext c) {
    try {
      string token = Setting("BABCO_GITHUB_TOKEN");
      if (!SecretReady(token)) { Err(c, 503, "GitHub token Key Vault reference is not resolved."); return; }
      var q = (HttpWebRequest)WebRequest.Create("https://api.github.com/user");
      q.Method = "GET";
      q.UserAgent = "Babco-Agent-Pilot-Router/0.5.3";
      q.Accept = "application/vnd.github+json";
      q.Headers[HttpRequestHeader.Authorization] = "Bearer " + token;
      q.Headers["X-GitHub-Api-Version"] = "2022-11-28";
      q.Timeout = 30000;
      using (var r = (HttpWebResponse)q.GetResponse())
      using (var sr = new StreamReader(r.GetResponseStream())) {
        var me = Obj(sr.ReadToEnd());
        c.Response.StatusCode = 200;
        c.Response.Write(J.Serialize(new {
          ok = true,
          adapterVersion = "0.5.3",
          githubStatus = (int)r.StatusCode,
          githubUser = S(me, "login"),
          oauthScopes = r.Headers["X-OAuth-Scopes"] ?? ""
        }));
      }
    } catch (WebException e) { Err(c, 502, WebErr(e)); }
      catch (Exception e) { Err(c, 500, e.GetType().Name + ": " + e.Message); }
  }

  private void PutFile(string owner, string repo, string path, byte[] data, string token, string message) {
    var body = new Dictionary<string, object>();
    body["message"] = message;
    body["content"] = Convert.ToBase64String(data);
    body["branch"] = "main";
    GH("PUT", "https://api.github.com/repos/" + owner + "/" + repo + "/contents/" + EncPath(path), token, J.Serialize(body));
  }

  private byte[] ZipStore(ArrayList files) {
    var localParts = new List<byte[]>();
    var centralParts = new List<byte[]>();
    int offset = 0;
    foreach (var o in files) {
      var d = o as Dictionary<string, object>;
      if (d == null) continue;
      string path = S(d, "path");
      string content = SRaw(d, "content");
      ValidatePath(path);
      byte[] name = Encoding.UTF8.GetBytes(path.Replace('\\', '/'));
      byte[] data = Encoding.UTF8.GetBytes(content);
      uint crc = Crc32(data);
      byte[] local = LocalHeader(name, data, crc);
      byte[] central = CentralHeader(name, data, crc, offset);
      localParts.Add(Concat(local, name, data));
      centralParts.Add(Concat(central, name));
      offset += local.Length + name.Length + data.Length;
    }
    byte[] body = Concat(localParts.ToArray());
    byte[] cd = Concat(centralParts.ToArray());
    byte[] end = EndRecord(centralParts.Count, cd.Length, body.Length);
    return Concat(body, cd, end);
  }

  private byte[] LocalHeader(byte[] name, byte[] data, uint crc) {
    var ms = new MemoryStream();
    W32(ms, 0x04034b50); W16(ms, 20); W16(ms, 0); W16(ms, 0); W16(ms, DosTime()); W16(ms, DosDate());
    W32(ms, crc); W32(ms, (uint)data.Length); W32(ms, (uint)data.Length); W16(ms, name.Length); W16(ms, 0);
    return ms.ToArray();
  }
  private byte[] CentralHeader(byte[] name, byte[] data, uint crc, int offset) {
    var ms = new MemoryStream();
    W32(ms, 0x02014b50); W16(ms, 20); W16(ms, 20); W16(ms, 0); W16(ms, 0); W16(ms, DosTime()); W16(ms, DosDate());
    W32(ms, crc); W32(ms, (uint)data.Length); W32(ms, (uint)data.Length); W16(ms, name.Length); W16(ms, 0); W16(ms, 0); W16(ms, 0); W16(ms, 0); W32(ms, 0); W32(ms, (uint)offset);
    return ms.ToArray();
  }
  private byte[] EndRecord(int count, int cdSize, int cdOffset) {
    var ms = new MemoryStream();
    W32(ms, 0x06054b50); W16(ms, 0); W16(ms, 0); W16(ms, count); W16(ms, count); W32(ms, (uint)cdSize); W32(ms, (uint)cdOffset); W16(ms, 0);
    return ms.ToArray();
  }
  private ushort DosDate() { DateTime d = DateTime.UtcNow; return (ushort)(((d.Year - 1980) << 9) | (d.Month << 5) | d.Day); }
  private ushort DosTime() { DateTime d = DateTime.UtcNow; return (ushort)((d.Hour << 11) | (d.Minute << 5) | (d.Second / 2)); }
  private void W16(Stream s, int v) { s.WriteByte((byte)(v & 255)); s.WriteByte((byte)((v >> 8) & 255)); }
  private void W32(Stream s, uint v) { s.WriteByte((byte)(v & 255)); s.WriteByte((byte)((v >> 8) & 255)); s.WriteByte((byte)((v >> 16) & 255)); s.WriteByte((byte)((v >> 24) & 255)); }
  private byte[] Concat(params byte[][] parts) { int n = 0; foreach (var p in parts) if (p != null) n += p.Length; byte[] outb = new byte[n]; int o = 0; foreach (var p in parts) { if (p == null) continue; Buffer.BlockCopy(p, 0, outb, o, p.Length); o += p.Length; } return outb; }
  private uint Crc32(byte[] bytes) { uint c = 0xffffffff; for (int i = 0; i < bytes.Length; i++) { c ^= bytes[i]; for (int k = 0; k < 8; k++) c = ((c & 1) != 0) ? (0xedb88320 ^ (c >> 1)) : (c >> 1); } return c ^ 0xffffffff; }

  private void EnsureWebConfig(ArrayList files) {
    foreach (var o in files) {
      var d = o as Dictionary<string, object>;
      if (d != null && String.Equals(S(d, "path"), "web.config", StringComparison.OrdinalIgnoreCase)) return;
    }
    files.Add(new Dictionary<string, object> {
      { "path", "web.config" },
      { "content", "<?xml version=\"1.0\" encoding=\"utf-8\"?><configuration><system.webServer><defaultDocument enabled=\"true\"><files><clear/><add value=\"index.html\"/></files></defaultDocument><staticContent><clientCache cacheControlMode=\"DisableCache\"/></staticContent></system.webServer></configuration>" }
    });
  }

  private string GH(string method, string url, string token, string json) {
    var q = (HttpWebRequest)WebRequest.Create(url);
    q.Method = method;
    q.UserAgent = "Babco-Agent-Pilot-Router/0.5.3";
    q.Accept = "application/vnd.github+json";
    q.ContentType = "application/json; charset=utf-8";
    q.Headers[HttpRequestHeader.Authorization] = "Bearer " + token;
    q.Headers["X-GitHub-Api-Version"] = "2022-11-28";
    q.Timeout = 120000;
    if (json != null) { byte[] bytes = Encoding.UTF8.GetBytes(json); q.ContentLength = bytes.Length; using (var s = q.GetRequestStream()) s.Write(bytes, 0, bytes.Length); }
    using (var r = (HttpWebResponse)q.GetResponse()) using (var sr = new StreamReader(r.GetResponseStream())) return sr.ReadToEnd();
  }
  private string Setting(string k) { var v = Environment.GetEnvironmentVariable(k); if (String.IsNullOrWhiteSpace(v)) v = ConfigurationManager.AppSettings[k]; return (v ?? "").Trim(); }
  private bool SecretReady(string v) { return !String.IsNullOrWhiteSpace(v) && !v.StartsWith("@Microsoft.KeyVault", StringComparison.OrdinalIgnoreCase); }
  private void ValidatePath(string p) { if (String.IsNullOrWhiteSpace(p) || p.StartsWith("/") || p.Contains("..") || p.Length > 220 || p.StartsWith(".git", StringComparison.OrdinalIgnoreCase)) throw new Exception("Unsafe path: " + p); }
  private string EncPath(string p) { var a = p.Split('/'); for (int i = 0; i < a.Length; i++) a[i] = Uri.EscapeDataString(a[i]); return String.Join("/", a); }
  private string Slug(string s) { var x = Regex.Replace((s ?? "").ToLowerInvariant(), "[^a-z0-9]+", "-").Trim('-'); return Take(x, 40).Trim('-'); }
  private string Take(string s, int n) { return String.IsNullOrEmpty(s) ? s : (s.Length <= n ? s : s.Substring(0, n)); }
  private Dictionary<string, object> Obj(string j) { return J.Deserialize<Dictionary<string, object>>(j) ?? new Dictionary<string, object>(); }
  private ArrayList Arr(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v is ArrayList ? (ArrayList)v : new ArrayList(); }
  private string S(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? Convert.ToString(v).Trim() : ""; }
  private string SRaw(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? Convert.ToString(v) : ""; }
  private string WebErr(WebException e) { try { var r = e.Response as HttpWebResponse; using (var sr = new StreamReader(r.GetResponseStream())) return "GitHub HTTP " + ((int)r.StatusCode) + ": " + sr.ReadToEnd(); } catch { return e.Message; } }
  private void Err(HttpContext c, int code, string msg) { c.Response.StatusCode = code; c.Response.Write(J.Serialize(new { ok = false, adapterVersion = "0.5.3", error = msg })); }
}
