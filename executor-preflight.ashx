<%@ WebHandler Language="C#" Class="ExecutorPreflight" %>
using System;
using System.Web;
using System.Net;
using System.Configuration;
using System.Collections.Generic;
using System.Web.Script.Serialization;

public class ExecutorPreflight : IHttpHandler {
  public bool IsReusable { get { return false; } }
  public void ProcessRequest(HttpContext c) {
    c.Response.ContentType="application/json";
    ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
    var js=new JavaScriptSerializer();
    var rca=Probe("https://ca-babco-rca-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/mcp");
    var rcs=Probe("https://ca-babco-rcs-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/mcp");
    string openAiKey=Environment.GetEnvironmentVariable("OPENAI_API_KEY_DEVELOPMENT");
    if(String.IsNullOrWhiteSpace(openAiKey)) openAiKey=Environment.GetEnvironmentVariable("OPENAI_API_KEY");
    if(String.IsNullOrWhiteSpace(openAiKey)) openAiKey=ConfigurationManager.AppSettings["OPENAI_API_KEY_DEVELOPMENT"];
    if(String.IsNullOrWhiteSpace(openAiKey)) openAiKey=ConfigurationManager.AppSettings["OPENAI_API_KEY"];
    c.Response.Write(js.Serialize(new {
      checkedAtUtc=DateTime.UtcNow.ToString("o"),
      rca=new { endpoint=rca.endpoint, reachable=rca.reachable, httpStatus=rca.status, authenticated=false, ready=false, missing="Website Entra invocation adapter / RCA.Invoke authorization" },
      rcs=new { endpoint=rcs.endpoint, reachable=rcs.reachable, httpStatus=rcs.status, authenticated=false, ready=false, missing="Website Entra invocation adapter / allowed client authorization" },
      openai=new { configured=!String.IsNullOrWhiteSpace(openAiKey), ready=!String.IsNullOrWhiteSpace(openAiKey), missing=String.IsNullOrWhiteSpace(openAiKey)?"Server-side OPENAI_API_KEY is not configured":"", model=ConfigurationManager.AppSettings["OPENAI_MODEL_ROUTER"] ?? "" },
      proofContract=new { required=true, fields=new[]{"executor","requestReceipt","executionId","terminalStatus","actualResultOrArtifact","verification","evidenceReference"} }
    }));
  }
  P Probe(string url){
    try{
      var q=(HttpWebRequest)WebRequest.Create(url); q.Method="GET"; q.Timeout=10000; q.AllowAutoRedirect=false;
      using(var r=(HttpWebResponse)q.GetResponse()) return new P{endpoint=url,reachable=true,status=(int)r.StatusCode};
    }catch(WebException ex){
      var r=ex.Response as HttpWebResponse;
      if(r!=null) return new P{endpoint=url,reachable=true,status=(int)r.StatusCode};
      return new P{endpoint=url,reachable=false,status=0};
    }catch{return new P{endpoint=url,reachable=false,status=0};}
  }
  class P{public string endpoint;public bool reachable;public int status;}
}