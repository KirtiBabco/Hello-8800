<%@ WebHandler Language="C#" Class="GitHubPublish" %>
<%@ Assembly Name="System.IO.Compression" %>
using System;
using System.Collections;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web;
using System.Web.Script.Serialization;

public class GitHubPublish : IHttpHandler {
  private readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=32*1024*1024};
  public bool IsReusable{get{return false;}}
  public void ProcessRequest(HttpContext c){
    c.Response.ContentType="application/json; charset=utf-8";c.Response.Cache.SetNoStore();c.Response.TrySkipIisCustomErrors=true;
    if(c.Request.HttpMethod!="POST"){Err(c,405,"POST required.");return;}
    try{
      ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
      string raw;using(var sr=new StreamReader(c.Request.InputStream))raw=sr.ReadToEnd();
      var b=Obj(raw);var files=Arr(b,"files");if(files.Count==0)throw new Exception("files are required.");
      EnsureWebConfig(files);
      string token=Setting("BABCO_GITHUB_TOKEN");if(!SecretReady(token))throw new InvalidOperationException("GitHub Key Vault reference is not resolved.");
      var me=Obj(GH("GET","https://api.github.com/user",token,null));string owner=S(me,"login");if(String.IsNullOrWhiteSpace(owner))throw new Exception("GitHub user could not be resolved.");
      string repoName=Slug(S(b,"projectName"));if(String.IsNullOrWhiteSpace(repoName))repoName="pilot-project";
      repoName=Take(repoName+"-"+DateTime.UtcNow.ToString("MMdd-HHmmss"),80).Trim('-');
      var body=new Dictionary<string,object>();body["name"]=repoName;body["description"]="Created by Babco Agent Pilot Router";body["private"]=false;body["auto_init"]=true;
      var repo=Obj(GH("POST","https://api.github.com/user/repos",token,J.Serialize(body)));Thread.Sleep(1000);
      foreach(var o in files){var d=o as Dictionary<string,object>;if(d==null)continue;string path=S(d,"path"),content=SRaw(d,"content");ValidatePath(path);PutFile(owner,repoName,path,Encoding.UTF8.GetBytes(content),token,"Pilot Router: add "+path);}
      byte[] zip=Zip(files);string packagePath="deploy/site.zip";PutFile(owner,repoName,packagePath,zip,token,"Pilot Router: deployment package");
      string repoUrl="https://github.com/"+owner+"/"+repoName;string rawPackage="https://raw.githubusercontent.com/"+owner+"/"+repoName+"/main/"+packagePath;
      c.Response.Write(J.Serialize(new{ok=true,executor="GitHub API",executionId="github-"+S(repo,"id"),repoOwner=owner,repoName=repoName,repoUrl=repoUrl,packageRawUrl=rawPackage,result="Repository created and source/package pushed."}));
    }catch(WebException e){Err(c,502,WebErr(e));}catch(Exception e){Err(c,500,e.Message);}
  }
  void PutFile(string owner,string repo,string path,byte[] data,string token,string message){var b=new Dictionary<string,object>();b["message"]=message;b["content"]=Convert.ToBase64String(data);b["branch"]="main";GH("PUT","https://api.github.com/repos/"+owner+"/"+repo+"/contents/"+EncPath(path),token,J.Serialize(b));}
  byte[] Zip(ArrayList files){using(var ms=new MemoryStream()){using(var z=new ZipArchive(ms,ZipArchiveMode.Create,true)){foreach(var o in files){var d=o as Dictionary<string,object>;if(d==null)continue;string path=S(d,"path"),content=SRaw(d,"content");ValidatePath(path);var e=z.CreateEntry(path,CompressionLevel.Fastest);using(var w=new StreamWriter(e.Open(),new UTF8Encoding(false)))w.Write(content);}}return ms.ToArray();}}
  void EnsureWebConfig(ArrayList files){foreach(var o in files){var d=o as Dictionary<string,object>;if(d!=null&&String.Equals(S(d,"path"),"web.config",StringComparison.OrdinalIgnoreCase))return;}files.Add(new Dictionary<string,object>{{"path","web.config"},{"content","<?xml version=\"1.0\" encoding=\"utf-8\"?><configuration><system.webServer><defaultDocument enabled=\"true\"><files><clear/><add value=\"index.html\"/></files></defaultDocument><staticContent><clientCache cacheControlMode=\"DisableCache\"/></staticContent></system.webServer></configuration>"}});}
  string GH(string method,string url,string token,string json){var q=(HttpWebRequest)WebRequest.Create(url);q.Method=method;q.UserAgent="Babco-Agent-Pilot-Router/0.5.0";q.Accept="application/vnd.github+json";q.ContentType="application/json; charset=utf-8";q.Headers[HttpRequestHeader.Authorization]="Bearer "+token;q.Headers["X-GitHub-Api-Version"]="2022-11-28";q.Timeout=120000;if(json!=null){var bytes=Encoding.UTF8.GetBytes(json);q.ContentLength=bytes.Length;using(var s=q.GetRequestStream())s.Write(bytes,0,bytes.Length);}using(var r=(HttpWebResponse)q.GetResponse())using(var sr=new StreamReader(r.GetResponseStream()))return sr.ReadToEnd();}
  string Setting(string k){var v=Environment.GetEnvironmentVariable(k);if(String.IsNullOrWhiteSpace(v))v=ConfigurationManager.AppSettings[k];return(v??"").Trim();}
  bool SecretReady(string v){return !String.IsNullOrWhiteSpace(v)&&!v.StartsWith("@Microsoft.KeyVault",StringComparison.OrdinalIgnoreCase);}
  void ValidatePath(string p){if(String.IsNullOrWhiteSpace(p)||p.StartsWith("/")||p.Contains("..")||p.Length>220||p.StartsWith(".git",StringComparison.OrdinalIgnoreCase))throw new Exception("Unsafe path: "+p);}
  string EncPath(string p){var a=p.Split('/');for(int i=0;i<a.Length;i++)a[i]=Uri.EscapeDataString(a[i]);return String.Join("/",a);}
  string Slug(string s){var x=Regex.Replace((s??"").ToLowerInvariant(),"[^a-z0-9]+","-").Trim('-');return Take(x,40).Trim('-');}
  string Take(string s,int n){return String.IsNullOrEmpty(s)?s:(s.Length<=n?s:s.Substring(0,n));}
  Dictionary<string,object> Obj(string j){return J.Deserialize<Dictionary<string,object>>(j)??new Dictionary<string,object>();}
  ArrayList Arr(Dictionary<string,object>d,string k){object v;return d.TryGetValue(k,out v)&&v is ArrayList?(ArrayList)v:new ArrayList();}
  string S(Dictionary<string,object>d,string k){object v;return d.TryGetValue(k,out v)&&v!=null?Convert.ToString(v).Trim():"";}
  string SRaw(Dictionary<string,object>d,string k){object v;return d.TryGetValue(k,out v)&&v!=null?Convert.ToString(v):"";}
  string WebErr(WebException e){try{var r=e.Response as HttpWebResponse;using(var sr=new StreamReader(r.GetResponseStream()))return((int)r.StatusCode)+" "+sr.ReadToEnd();}catch{return e.Message;}}
  void Err(HttpContext c,int code,string msg){c.Response.StatusCode=code;c.Response.Write(J.Serialize(new{ok=false,error=msg}));}
}