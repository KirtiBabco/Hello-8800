<%@ WebHandler Language="C#" Class="EvidenceSave" %>
using System;
using System.Web;
using System.Net;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Configuration;
using System.Collections.Generic;

public class EvidenceSave : IHttpHandler {
  public bool IsReusable { get { return false; } }
  public void ProcessRequest(HttpContext context) {
    context.Response.ContentType="application/json";
    var js=new JavaScriptSerializer();
    try {
      if (context.Request.HttpMethod!="POST") { context.Response.StatusCode=405; context.Response.Write(js.Serialize(new {ok=false,error="POST required"})); return; }
      string body=new StreamReader(context.Request.InputStream).ReadToEnd();
      var req=js.Deserialize<Dictionary<string,object>>(body);
      string kind=Get(req,"kind","evidence");
      string name=Get(req,"name",kind);
      string content=Get(req,"content","{}");
      string token=ConfigurationManager.AppSettings["BABCO_GITHUB_TOKEN"] ?? "";
      string repo=ConfigurationManager.AppSettings["EVIDENCE_REPO"] ?? "KirtiBabco/Hello-8800";
      string branch=ConfigurationManager.AppSettings["EVIDENCE_BRANCH"] ?? "agent-pilot-router";
      string prefix=ConfigurationManager.AppSettings["EVIDENCE_PREFIX"] ?? "evidence/runtime";
      if (String.IsNullOrWhiteSpace(token) || token.StartsWith("@Microsoft.KeyVault")) {
        context.Response.StatusCode=503; context.Response.Write(js.Serialize(new {ok=false,error="GitHub token is not resolved from Key Vault yet."})); return;
      }
      string slug=Regex.Replace((kind+"-"+name).ToLowerInvariant(),"[^a-z0-9]+","-").Trim('-');
      if (slug.Length>70) slug=slug.Substring(0,70);
      string path=prefix.TrimEnd('/')+"/"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff")+"-"+slug+".json";
      string url="https://api.github.com/repos/"+repo+"/contents/"+path;
      var payload=new Dictionary<string,object>();
      payload["message"]="Agent Router evidence: "+kind+" - "+name;
      payload["content"]=Convert.ToBase64String(Encoding.UTF8.GetBytes(content));
      payload["branch"]=branch;
      byte[] bytes=Encoding.UTF8.GetBytes(js.Serialize(payload));
      var wr=(HttpWebRequest)WebRequest.Create(url);
      wr.Method="PUT"; wr.UserAgent="Babco-Agent-Pilot-Router"; wr.Accept="application/vnd.github+json";
      wr.Headers["Authorization"]="Bearer "+token; wr.ContentType="application/json"; wr.ContentLength=bytes.Length;
      using(var s=wr.GetRequestStream()) s.Write(bytes,0,bytes.Length);
      using(var resp=(HttpWebResponse)wr.GetResponse()) using(var sr=new StreamReader(resp.GetResponseStream())) { sr.ReadToEnd(); }
      string html="https://github.com/"+repo+"/blob/"+branch+"/"+path;
      context.Response.Write(js.Serialize(new {ok=true,path=path,url=html}));
    } catch(WebException ex) {
      string detail=ex.Message;
      try { using(var sr=new StreamReader(ex.Response.GetResponseStream())) detail=sr.ReadToEnd(); } catch {}
      context.Response.StatusCode=500; context.Response.Write(js.Serialize(new {ok=false,error=detail}));
    } catch(Exception ex) {
      context.Response.StatusCode=500; context.Response.Write(js.Serialize(new {ok=false,error=ex.Message}));
    }
  }
  string Get(Dictionary<string,object> d,string k,string def){ object v; return d!=null && d.TryGetValue(k,out v) && v!=null ? Convert.ToString(v) : def; }
}