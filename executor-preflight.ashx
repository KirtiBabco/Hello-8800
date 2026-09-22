<%@ WebHandler Language="C#" Class="ExecutorPreflight" %>
using System;
using System.Configuration;
using System.Net;
using System.Web;
using System.Web.Script.Serialization;

public class ExecutorPreflight : IHttpHandler {
  public bool IsReusable{get{return false;}}
  public void ProcessRequest(HttpContext c){
    c.Response.ContentType="application/json";c.Response.Cache.SetNoStore();ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
    var js=new JavaScriptSerializer();var rca=Probe("https://ca-babco-rca-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/healthz");var rcs=Probe("https://ca-babco-rcs-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/healthz");
    bool openai=Ready(Setting("OPENAI_API_KEY")),github=Ready(Setting("BABCO_GITHUB_TOKEN")),azure=!String.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT"))&&!String.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("IDENTITY_HEADER"));
    c.Response.Write(js.Serialize(new{
      checkedAtUtc=DateTime.UtcNow.ToString("o"),
      rca=new{reachable=rca.reachable,httpStatus=rca.status,ready=false,fallback=openai,missing="RCA workload call requires RCA.Invoke app-role. OpenAI fallback will be used only if RCA becomes necessary."},
      rcs=new{reachable=rcs.reachable,httpStatus=rcs.status,ready=false,fallback=openai,missing="RCS requires delegated access_as_user/OBO. OpenAI fallback will be used only if remediation becomes necessary."},
      openai=new{ready=openai,model=Setting("OPENAI_MODEL_ROUTER"),missing=openai?"":"OpenAI Key Vault reference unresolved."},
      github=new{ready=github,missing=github?"":"GitHub Key Vault reference unresolved."},
      azure=new{ready=azure,role="Website Contributor",missing=azure?"":"Managed identity endpoint unavailable."},
      pipelineReady=openai&&github&&azure
    }));
  }
  string Setting(string k){var v=Environment.GetEnvironmentVariable(k);if(String.IsNullOrWhiteSpace(v))v=ConfigurationManager.AppSettings[k];return(v??"").Trim();}
  bool Ready(string v){return !String.IsNullOrWhiteSpace(v)&&!v.StartsWith("@Microsoft.KeyVault",StringComparison.OrdinalIgnoreCase);}
  P Probe(string url){try{var q=(HttpWebRequest)WebRequest.Create(url);q.Method="GET";q.Timeout=10000;using(var r=(HttpWebResponse)q.GetResponse())return new P{reachable=true,status=(int)r.StatusCode};}catch(WebException e){var r=e.Response as HttpWebResponse;return new P{reachable=r!=null,status=r==null?0:(int)r.StatusCode};}catch{return new P();}}
  class P{public bool reachable;public int status;}
}