<%@ WebHandler Language="C#" Class="AzureDeploy" %>
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web;
using System.Web.Script.Serialization;

public class AzureDeploy : IHttpHandler {
  private readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=8*1024*1024};
  private const string Sub="0e27b0b7-22b9-4e96-8faa-897ca9f09e9c";
  private const string Rg="rg-babco-rnd-sandbox";
  private const string Plan="/subscriptions/0e27b0b7-22b9-4e96-8faa-897ca9f09e9c/resourceGroups/rg-babco-rnd-sandbox/providers/Microsoft.Web/serverfarms/plan-resolvedesk-kirti20260810";
  public bool IsReusable{get{return false;}}
  public void ProcessRequest(HttpContext c){
    c.Response.ContentType="application/json; charset=utf-8";c.Response.Cache.SetNoStore();c.Response.TrySkipIisCustomErrors=true;
    if(c.Request.HttpMethod!="POST"){Err(c,405,"POST required.");return;}
    try{
      ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
      string raw;using(var sr=new StreamReader(c.Request.InputStream))raw=sr.ReadToEnd();
      var b=J.Deserialize<Dictionary<string,object>>(raw)??new Dictionary<string,object>();
      string package=S(b,"packageRawUrl");if(String.IsNullOrWhiteSpace(package))throw new Exception("packageRawUrl is required.");
      string baseName=Slug(S(b,"projectName"));if(String.IsNullOrWhiteSpace(baseName))baseName="pilot";
      string app=Take("app-babco-"+baseName+"-"+DateTime.UtcNow.ToString("MMddHHmmss"),60).Trim('-');
      string token=ArmToken();
      string siteUrl="https://management.azure.com/subscriptions/"+Sub+"/resourceGroups/"+Rg+"/providers/Microsoft.Web/sites/"+app+"?api-version=2023-12-01";
      var props=new Dictionary<string,object>();props["serverFarmId"]=Plan;props["httpsOnly"]=true;props["siteConfig"]=new Dictionary<string,object>{{"alwaysOn",true},{"http20Enabled",true}};
      var site=new Dictionary<string,object>();site["location"]="centralindia";site["kind"]="app";site["properties"]=props;Arm("PUT",siteUrl,token,J.Serialize(site));
      string cfgUrl="https://management.azure.com/subscriptions/"+Sub+"/resourceGroups/"+Rg+"/providers/Microsoft.Web/sites/"+app+"/config/appsettings?api-version=2023-12-01";
      var settings=new Dictionary<string,object>{{"WEBSITE_RUN_FROM_PACKAGE",package}};
      Arm("PUT",cfgUrl,token,J.Serialize(new Dictionary<string,object>{{"properties",settings}}));
      string live="https://"+app+".azurewebsites.net/";int code=0;string sample="";string last="";
      for(int i=0;i<12;i++){try{var q=(HttpWebRequest)WebRequest.Create(live+"?verify="+DateTime.UtcNow.Ticks);q.Method="GET";q.UserAgent="Babco-Agent-Pilot-Router/0.5.0";q.Timeout=15000;q.AllowAutoRedirect=true;using(var r=(HttpWebResponse)q.GetResponse())using(var sr=new StreamReader(r.GetResponseStream())){code=(int)r.StatusCode;sample=sr.ReadToEnd();if(code>=200&&code<400)break;}}catch(Exception e){last=e.Message;}Thread.Sleep(5000);}
      bool verified=code>=200&&code<400;
      c.Response.Write(J.Serialize(new{ok=verified,executor="Azure ARM",executionId="azure-"+app,appName=app,liveUrl=live,verified=verified,httpStatus=code,result=verified?"Azure App Service deployed and HTTP verified.":"Azure resource was created but HTTP verification did not pass: "+last,sample=sample.Substring(0,Math.Min(300,sample.Length))}));
    }catch(WebException e){Err(c,502,WebErr(e));}catch(Exception e){Err(c,500,e.Message);}
  }
  string ArmToken(){string endpoint=Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT"),header=Environment.GetEnvironmentVariable("IDENTITY_HEADER");if(String.IsNullOrWhiteSpace(endpoint)||String.IsNullOrWhiteSpace(header))throw new Exception("Azure managed identity endpoint is unavailable.");string url=endpoint+"?resource="+HttpUtility.UrlEncode("https://management.azure.com/")+"&api-version=2019-08-01";var q=(HttpWebRequest)WebRequest.Create(url);q.Method="GET";q.Headers["X-IDENTITY-HEADER"]=header;q.Timeout=15000;using(var r=(HttpWebResponse)q.GetResponse())using(var sr=new StreamReader(r.GetResponseStream())){var o=J.Deserialize<Dictionary<string,object>>(sr.ReadToEnd());return S(o,"access_token");}}
  string Arm(string method,string url,string token,string json){var q=(HttpWebRequest)WebRequest.Create(url);q.Method=method;q.ContentType="application/json";q.Accept="application/json";q.Headers[HttpRequestHeader.Authorization]="Bearer "+token;q.Timeout=120000;var b=Encoding.UTF8.GetBytes(json);q.ContentLength=b.Length;using(var s=q.GetRequestStream())s.Write(b,0,b.Length);using(var r=(HttpWebResponse)q.GetResponse())using(var sr=new StreamReader(r.GetResponseStream()))return sr.ReadToEnd();}
  string Slug(string s){var x=Regex.Replace((s??"").ToLowerInvariant(),"[^a-z0-9]+","-").Trim('-');return Take(x,36).Trim('-');}
  string Take(string s,int n){return String.IsNullOrEmpty(s)?s:(s.Length<=n?s:s.Substring(0,n));}
  string S(Dictionary<string,object>d,string k){object v;return d!=null&&d.TryGetValue(k,out v)&&v!=null?Convert.ToString(v).Trim():"";}
  string WebErr(WebException e){try{var r=e.Response as HttpWebResponse;using(var sr=new StreamReader(r.GetResponseStream()))return((int)r.StatusCode)+" "+sr.ReadToEnd();}catch{return e.Message;}}
  void Err(HttpContext c,int code,string msg){c.Response.StatusCode=code;c.Response.Write(J.Serialize(new{ok=false,error=msg}));}
}