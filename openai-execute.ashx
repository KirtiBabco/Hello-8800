<%@ WebHandler Language="C#" Class="OpenAiExecute" %>
using System;
using System.Collections;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;

public class OpenAiExecute : IHttpHandler {
  private readonly JavaScriptSerializer J = new JavaScriptSerializer { MaxJsonLength = 32 * 1024 * 1024 };
  public bool IsReusable { get { return false; } }
  public void ProcessRequest(HttpContext c) {
    c.Response.ContentType="application/json; charset=utf-8"; c.Response.Cache.SetNoStore(); c.Response.TrySkipIisCustomErrors=true;
    if(c.Request.HttpMethod!="POST"){Err(c,405,"POST required.");return;}
    try{
      ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
      string raw; using(var sr=new StreamReader(c.Request.InputStream))raw=sr.ReadToEnd();
      var b=J.Deserialize<Dictionary<string,object>>(raw)??new Dictionary<string,object>();
      string input=S(b,"input"); if(String.IsNullOrWhiteSpace(input))throw new Exception("input is required.");
      string key=Setting("OPENAI_API_KEY"); if(!SecretReady(key))throw new InvalidOperationException("OPENAI_API_KEY Key Vault reference is not resolved.");
      string model=Setting("OPENAI_MODEL_ROUTER"); if(String.IsNullOrWhiteSpace(model))model="gpt-5.6-sol";
      var req=new Dictionary<string,object>(); req["model"]=model; req["input"]=input;
      req["reasoning"]=new Dictionary<string,object>{{"effort","low"}};
      var q=(HttpWebRequest)WebRequest.Create("https://api.openai.com/v1/responses"); q.Method="POST"; q.ContentType="application/json"; q.Accept="application/json"; q.Timeout=180000;
      q.Headers[HttpRequestHeader.Authorization]="Bearer "+key;
      var bytes=Encoding.UTF8.GetBytes(J.Serialize(req)); q.ContentLength=bytes.Length; using(var s=q.GetRequestStream())s.Write(bytes,0,bytes.Length);
      string responseRaw; using(var r=(HttpWebResponse)q.GetResponse())using(var sr=new StreamReader(r.GetResponseStream()))responseRaw=sr.ReadToEnd();
      var response=J.Deserialize<Dictionary<string,object>>(responseRaw)??new Dictionary<string,object>();
      var usage=Dict(response,"usage"); long inputTokens=L(usage,"input_tokens"), outputTokens=L(usage,"output_tokens");
      double estimatedCost=(inputTokens*4.0+outputTokens*20.0)/1000000.0;
      c.Response.Write(J.Serialize(new{ok=true,executor="OpenAI API",model=S(response,"model")==""?model:S(response,"model"),executionId=S(response,"id"),result=Extract(response),usage=usage,estimatedCost=estimatedCost}));
    }catch(WebException e){Err(c,502,WebErr(e));}catch(Exception e){Err(c,500,e.Message);}
  }
  string Extract(Dictionary<string,object> r){object v;if(r.TryGetValue("output_text",out v)&&v!=null)return Convert.ToString(v);object ov;if(!r.TryGetValue("output",out ov))return"";var a=ov as ArrayList;if(a==null)return"";var sb=new StringBuilder();foreach(var x in a){var o=x as Dictionary<string,object>;if(o==null)continue;object cv;if(!o.TryGetValue("content",out cv))continue;var ca=cv as ArrayList;if(ca==null)continue;foreach(var y in ca){var d=y as Dictionary<string,object>;if(d==null)continue;object tv;if(d.TryGetValue("text",out tv)&&tv!=null)sb.Append(Convert.ToString(tv));}}return sb.ToString();}
  string Setting(string k){var v=Environment.GetEnvironmentVariable(k);if(String.IsNullOrWhiteSpace(v))v=ConfigurationManager.AppSettings[k];return(v??"").Trim();}
  bool SecretReady(string v){return !String.IsNullOrWhiteSpace(v)&&!v.StartsWith("@Microsoft.KeyVault",StringComparison.OrdinalIgnoreCase);}
  Dictionary<string,object> Dict(Dictionary<string,object>d,string k){object v;return d.TryGetValue(k,out v)&&v is Dictionary<string,object>?(Dictionary<string,object>)v:new Dictionary<string,object>();}
  string S(Dictionary<string,object>d,string k){object v;return d.TryGetValue(k,out v)&&v!=null?Convert.ToString(v).Trim():"";}
  long L(Dictionary<string,object>d,string k){object v;long n;return d.TryGetValue(k,out v)&&v!=null&&long.TryParse(Convert.ToString(v),out n)?n:0;}
  string WebErr(WebException e){try{var r=e.Response as HttpWebResponse;using(var sr=new StreamReader(r.GetResponseStream()))return((int)r.StatusCode)+" "+sr.ReadToEnd();}catch{return e.Message;}}
  void Err(HttpContext c,int code,string msg){c.Response.StatusCode=code;c.Response.Write(J.Serialize(new{ok=false,error=msg}));}
}