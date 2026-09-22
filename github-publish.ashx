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

    if (String.Equals(c.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase)) {
      Health(c);
      return;
    }
    if (!String.Equals(c.Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase)) {
      Err(c, 405, "GET or POST required.");
      return;
    }

    try {
      string raw;
      using (var sr = new StreamReader(c.Request.InputStream)) raw = sr.ReadToEnd();
      var b = Obj(raw);
      var files = Arr(b, "files");
      if (files.Count == 0) throw new Exception("files are required.");

      EnsureWebConfig(files);

      string token = Setting("BABCO_GITHUB_TOKEN");
      if (!SecretReady(token)) throw new InvalidOperationException("GitHub Key Vault reference is not resolved.");

      var meRaw = GH("GET", "https://api.github.com/user", token, null);
      var me = Obj(meRaw);
      string owner = S(me, "login");
      if (String.IsNullOrWhiteSpace(owner)) throw new Exception("GitHub authenticated user could not be resolved.");

      string repoName = Slug(S(b, "projectName"));
      if (String.IsNullOrWhiteSpace(repoName)) repoName = "pilot-project";
      repoName = Take(repoName + "-" + DateTime.UtcNow.ToString("MMdd-HHmmss"), 80).Trim('-');

      var body = new Dictionary<string, object>();
      body["name"] = repoName;
      body["description"] = "Created by Babco Agent Pilot Router";
      body["private"] = false;
      body["auto_init"] = true;

      var repo = Obj(GH("POST", "https://api.github.com/user/repos", token, J.Serialize(body)));
      Thread.Sleep(800);

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
        adapterVersion = "0.5.2",
        executor = "GitHub API",
        executionId = "github-" + S(repo, "id"),
        repoOwner = owner,
        repoName = repoName,
        repoUrl = repoUrl,
        packageRawUrl = rawPackage,
        result = "Repository created and source/package pushed."
      }));
    }
    catch (WebException e) { Err(c, 502, WebErr(e)); }
    catch (Exception e) { Err(c, 500, e.GetType().Name + ": " + e.Message); }
  }

  void Health(HttpContext c) {
    try {
      string token = Setting("BABCO_GITHUB_TOKEN");
      if (!SecretReady(token)) { Err(c, 503, "GitHub Key Vault reference is not resolved."); return; }

      var q = (HttpWebRequest)WebRequest.Create("https://api.github.com/user");
      q.Method = "GET";
      q.UserAgent = "Babco-Agent-Pilot-Router/0.5.2";
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
          adapterVersion = "0.5.2",
          tokenResolved = true,
          githubStatus = (int)r.StatusCode,
          githubUser = S(me, "login"),
          oauthScopes = r.Headers["X-OAuth-Scopes"] ?? "",
          acceptedOauthScopes = r.Headers["X-Accepted-OAuth-Scopes"] ?? ""
        }));
      }
    }
    catch (WebException e) { Err(c, 502, WebErr(e)); }
    catch (Exception e) { Err(c, 500, e.GetType().Name + ": " + e.Message); }
  }

  void PutFile(string owner, string repo, string path, byte[] data, string token, string message) {
    var b = new Dictionary<string, object>();
    b["message"] = message;
    b["content"] = Convert.ToBase64String(data);
    b["branch"] = "main";
    GH("PUT", "https://api.github.com/repos/" + owner + "/" + repo + "/contents/" + EncPath(path), token, J.Serialize(b));
  }

  byte[] ZipStore(ArrayList files) {
    using (var ms = new MemoryStream())
    using (var bw = new BinaryWriter(ms, Encoding.UTF8)) {
      var entries = new List<ZipEntryInfo>();
      DateTime now = DateTime.Now;
      ushort dosTime = (ushort)((now.Hour << 11) | (now.Minute << 5) | (now.Second / 2));
      ushort dosDate = (ushort)(((now.Year - 1980) << 9) | (now.Month << 5) | now.Day);

      foreach (var o in files) {
        var d = o as Dictionary<string, object>;
        if (d == null) continue;
        string path = S(d, "path");
        string content = SRaw(d, "content");
        ValidatePath(path);

        byte[] name = Encoding.UTF8.GetBytes(path);
        byte[] data = new UTF8Encoding(false).GetBytes(content);
        uint crc = Crc32(data);
        uint offset = (uint)ms.Position;

        bw.Write(0x04034b50u);
        bw.Write((ushort)20);
        bw.Write((ushort)0x0800);
        bw.Write((ushort)0);
        bw.Write(dosTime);
        bw.Write(dosDate);
        bw.Write(crc);
        bw.Write((uint)data.Length);
        bw.Write((uint)data.Length);
        bw.Write((ushort)name.Length);
        bw.Write((ushort)0);
        bw.Write(name);
        bw.Write(data);

        entries.Add(new ZipEntryInfo {
          Name = name, DataLength = (uint)data.Length, Crc = crc,
          Offset = offset, DosTime = dosTime, DosDate = dosDate
        });
      }

      uint centralOffset = (uint)ms.Position;
      foreach (var e in entries) {
        bw.Write(0x02014b50u);
        bw.Write((ushort)20);
        bw.Write((ushort)20);
        bw.Write((ushort)0x0800);
        bw.Write((ushort)0);
        bw.Write(e.DosTime);
        bw.Write(e.DosDate);
        bw.Write(e.Crc);
        bw.Write(e.DataLength);
        bw.Write(e.DataLength);
        bw.Write((ushort)e.Name.Length);
        bw.Write((ushort)0);
        bw.Write((ushort)0);
        bw.Write((ushort)0);
        bw.Write((ushort)0);
        bw.Write(0u);
        bw.Write(e.Offset);
        bw.Write(e.Name);
      }

      uint centralSize = (uint)ms.Position - centralOffset;
      bw.Write(0x06054b50u);
      bw.Write((ushort)0);
      bw.Write((ushort)0);
      bw.Write((ushort)entries.Count);
      bw.Write((ushort)entries.Count);
      bw.Write(centralSize);
      bw.Write(centralOffset);
      bw.Write((ushort)0);
      bw.Flush();
      return ms.ToArray();
    }
  }

  uint Crc32(byte[] data) {
    uint crc = 0xffffffffu;
    for (int i = 0; i < data.Length; i++) {
      crc ^= data[i];
      for (int k = 0; k < 8; k++) crc = (crc & 1u) != 0 ? (crc >> 1) ^ 0xedb88320u : crc >> 1;
    }
    return crc ^ 0xffffffffu;
  }

  void EnsureWebConfig(ArrayList files) {
    foreach (var o in files) {
      var d = o as Dictionary<string, object>;
      if (d != null && String.Equals(S(d, "path"), "web.config", StringComparison.OrdinalIgnoreCase)) return;
    }
    var w = new Dictionary<string, object>();
    w["path"] = "web.config";
    w["content"] = "<?xml version=\"1.0\" encoding=\"utf-8\"?><configuration><system.webServer><defaultDocument enabled=\"true\"><files><clear/><add value=\"index.html\"/></files></defaultDocument><staticContent><clientCache cacheControlMode=\"DisableCache\"/></staticContent></system.webServer></configuration>";
    files.Add(w);
  }

  string GH(string method, string url, string token, string json) {
    var q = (HttpWebRequest)WebRequest.Create(url);
    q.Method = method;
    q.UserAgent = "Babco-Agent-Pilot-Router/0.5.2";
    q.Accept = "application/vnd.github+json";
    q.ContentType = "application/json; charset=utf-8";
    q.Headers[HttpRequestHeader.Authorization] = "Bearer " + token;
    q.Headers["X-GitHub-Api-Version"] = "2022-11-28";
    q.Timeout = 120000;
    if (json != null) {
      var bytes = Encoding.UTF8.GetBytes(json);
      q.ContentLength = bytes.Length;
      using (var s = q.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
    }
    using (var r = (HttpWebResponse)q.GetResponse())
    using (var sr = new StreamReader(r.GetResponseStream())) return sr.ReadToEnd();
  }

  string Setting(string k) {
    var v = Environment.GetEnvironmentVariable(k);
    if (String.IsNullOrWhiteSpace(v)) v = ConfigurationManager.AppSettings[k];
    return (v ?? "").Trim();
  }
  bool SecretReady(string v) { return !String.IsNullOrWhiteSpace(v) && !v.StartsWith("@Microsoft.KeyVault", StringComparison.OrdinalIgnoreCase); }
  void ValidatePath(string p) {
    if (String.IsNullOrWhiteSpace(p) || p.StartsWith("/") || p.Contains("..") || p.Length > 220 || p.StartsWith(".git", StringComparison.OrdinalIgnoreCase))
      throw new Exception("Unsafe path: " + p);
  }
  string EncPath(string p) {
    var a = p.Split('/');
    for (int i = 0; i < a.Length; i++) a[i] = Uri.EscapeDataString(a[i]);
    return String.Join("/", a);
  }
  string Slug(string s) { var x = Regex.Replace((s ?? "").ToLowerInvariant(), "[^a-z0-9]+", "-").Trim('-'); return Take(x, 40).Trim('-'); }
  string Take(string s, int n) { return String.IsNullOrEmpty(s) ? s : (s.Length <= n ? s : s.Substring(0, n)); }
  Dictionary<string, object> Obj(string j) { return J.Deserialize<Dictionary<string, object>>(j) ?? new Dictionary<string, object>(); }
  ArrayList Arr(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v is ArrayList ? (ArrayList)v : new ArrayList(); }
  string S(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) && v != null ? Convert.ToString(v).Trim() : ""; }
  string SRaw(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) && v != null ? Convert.ToString(v) : ""; }

  string WebErr(WebException e) {
    try {
      var r = e.Response as HttpWebResponse;
      if (r == null) return e.Message;
      string body;
      using (var sr = new StreamReader(r.GetResponseStream())) body = sr.ReadToEnd();
      return "GitHub HTTP " + (int)r.StatusCode + " " + r.StatusDescription + ": " + body;
    } catch { return e.Message; }
  }

  void Err(HttpContext c, int code, string msg) {
    c.Response.StatusCode = code;
    c.Response.TrySkipIisCustomErrors = true;
    c.Response.Write(J.Serialize(new { ok = false, adapterVersion = "0.5.2", error = msg }));
  }

  class ZipEntryInfo {
    public byte[] Name;
    public uint DataLength;
    public uint Crc;
    public uint Offset;
    public ushort DosTime;
    public ushort DosDate;
  }
}