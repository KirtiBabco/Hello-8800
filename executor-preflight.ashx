<%@ WebHandler Language="C#" Class="ExecutorPreflight" %>
using System;
using System.Configuration;
using System.IO;
using System.Net;
using System.Web;
using System.Web.Script.Serialization;

public class ExecutorPreflight : IHttpHandler {
  public bool IsReusable { get { return false; } }

  public void ProcessRequest(HttpContext c) {
    c.Response.ContentType = "application/json; charset=utf-8";
    c.Response.Cache.SetNoStore();
    c.Response.TrySkipIisCustomErrors = true;
    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

    var js = new JavaScriptSerializer();
    var rca = Probe("https://ca-babco-rca-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/healthz");
    var rcs = Probe("https://ca-babco-rcs-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/healthz");

    bool openai = Ready(Setting("OPENAI_API_KEY"));
    var gh = GitHubProbe();
    bool azure = !String.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT")) &&
                 !String.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("IDENTITY_HEADER"));

    c.Response.Write(js.Serialize(new {
      checkedAtUtc = DateTime.UtcNow.ToString("o"),
      adapterVersion = "0.5.1",
      rca = new {
        reachable = rca.reachable,
        httpStatus = rca.status,
        ready = false,
        fallback = openai,
        missing = "RCA workload call requires RCA.Invoke app-role. OpenAI fallback will be used only if RCA becomes necessary."
      },
      rcs = new {
        reachable = rcs.reachable,
        httpStatus = rcs.status,
        ready = false,
        fallback = openai,
        missing = "RCS requires delegated access_as_user/OBO. OpenAI fallback will be used only if remediation becomes necessary."
      },
      openai = new {
        ready = openai,
        model = Setting("OPENAI_MODEL_ROUTER"),
        missing = openai ? "" : "OpenAI Key Vault reference unresolved."
      },
      github = new {
        ready = gh.ready,
        githubUser = gh.user,
        httpStatus = gh.status,
        oauthScopes = gh.scopes,
        missing = gh.ready ? "" : gh.error
      },
      azure = new {
        ready = azure,
        role = "Website Contributor",
        missing = azure ? "" : "Managed identity endpoint unavailable."
      },
      pipelineReady = openai && gh.ready && azure
    }));
  }

  G GitHubProbe() {
    string token = Setting("BABCO_GITHUB_TOKEN");
    if (!Ready(token)) return new G { ready = false, error = "GitHub Key Vault reference unresolved." };
    try {
      var q = (HttpWebRequest)WebRequest.Create("https://api.github.com/user");
      q.Method = "GET";
      q.UserAgent = "Babco-Agent-Pilot-Router/0.5.1";
      q.Accept = "application/vnd.github+json";
      q.Headers[HttpRequestHeader.Authorization] = "Bearer " + token;
      q.Headers["X-GitHub-Api-Version"] = "2022-11-28";
      q.Timeout = 30000;
      using (var r = (HttpWebResponse)q.GetResponse())
      using (var sr = new StreamReader(r.GetResponseStream())) {
        var body = sr.ReadToEnd();
        var me = new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(body);
        object login;
        return new G {
          ready = (int)r.StatusCode == 200,
          status = (int)r.StatusCode,
          user = me != null && me.TryGetValue("login", out login) && login != null ? Convert.ToString(login) : "",
          scopes = r.Headers["X-OAuth-Scopes"] ?? "",
          error = ""
        };
      }
    } catch (WebException e) {
      var r = e.Response as HttpWebResponse;
      string body = "";
      try { if (r != null) using (var sr = new StreamReader(r.GetResponseStream())) body = sr.ReadToEnd(); } catch {}
      return new G {
        ready = false,
        status = r == null ? 0 : (int)r.StatusCode,
        error = "GitHub authentication failed" + (r == null ? "" : " HTTP " + (int)r.StatusCode) + (String.IsNullOrWhiteSpace(body) ? "" : ": " + body)
      };
    } catch (Exception e) {
      return new G { ready = false, error = e.GetType().Name + ": " + e.Message };
    }
  }

  string Setting(string k) {
    var v = Environment.GetEnvironmentVariable(k);
    if (String.IsNullOrWhiteSpace(v)) v = ConfigurationManager.AppSettings[k];
    return (v ?? "").Trim();
  }

  bool Ready(string v) {
    return !String.IsNullOrWhiteSpace(v) && !v.StartsWith("@Microsoft.KeyVault", StringComparison.OrdinalIgnoreCase);
  }

  P Probe(string url) {
    try {
      var q = (HttpWebRequest)WebRequest.Create(url);
      q.Method = "GET";
      q.Timeout = 10000;
      using (var r = (HttpWebResponse)q.GetResponse()) return new P { reachable = true, status = (int)r.StatusCode };
    } catch (WebException e) {
      var r = e.Response as HttpWebResponse;
      return new P { reachable = r != null, status = r == null ? 0 : (int)r.StatusCode };
    } catch { return new P(); }
  }

  class P { public bool reachable; public int status; }
  class G { public bool ready; public int status; public string user = ""; public string scopes = ""; public string error = ""; }
}