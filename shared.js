
(function(){
window.BABCO_LIVE='https://app-babco-agent-pilot-router-rnd-260921.azurewebsites.net/';
window.BUILTIN_AGENTS=[
 {n:'Babco Labs RCA Analysis Agent v5',m:'gpt-5.6-sol',e:'https://ca-babco-rca-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/mcp',c:['root cause analysis','diagnosis','failure analysis','evidence analysis','incident analysis'],d:'Evidence-first root-cause analysis and causal diagnosis.',builtIn:true},
 {n:'Babco Labs RCS Solver Agent v2',m:'gpt-5.6-sol',e:'https://ca-babco-rcs-agent-rnd.mangodesert-69aab027.eastus2.azurecontainerapps.io/mcp',c:['remediation','fix failure','recovery','correction','recurrence prevention'],d:'Verified correction, recovery and recurrence prevention.',builtIn:true}
];
window.getAgents=function(){
 var custom=[];try{custom=JSON.parse(localStorage.getItem('babcoAgentRegistry')||'[]')}catch(e){}
 return window.BUILTIN_AGENTS.concat(custom);
};
window.slug=function(s){return String(s||'item').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,60)||'item'};
window.downloadJson=function(name,obj){var b=new Blob([JSON.stringify(obj,null,2)],{type:'application/json'});var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=name;a.click();setTimeout(function(){URL.revokeObjectURL(a.href)},500)};
window.downloadSimplePdf=function(name,title,lines){
 var esc=function(s){return String(s).replace(/\\/g,'\\\\').replace(/\(/g,'\\(').replace(/\)/g,'\\)').replace(/[^\x20-\x7E]/g,'?')};
 var all=[title,''].concat(lines||[]).slice(0,58), content='BT /F1 10 Tf 42 800 Td 13 TL ';
 all.forEach(function(line,i){content+='('+esc(line)+') Tj T* '});content+='ET';
 var objs=[
  '<< /Type /Catalog /Pages 2 0 R >>',
  '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
  '<< /Length '+content.length+' >>\nstream\n'+content+'\nendstream',
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
 ],pdf='%PDF-1.4\n',offs=[0];
 objs.forEach(function(o,i){offs.push(pdf.length);pdf+=(i+1)+' 0 obj\n'+o+'\nendobj\n'});
 var xref=pdf.length;pdf+='xref\n0 '+(objs.length+1)+'\n0000000000 65535 f \n';
 for(var i=1;i<offs.length;i++)pdf+=String(offs[i]).padStart(10,'0')+' 00000 n \n';
 pdf+='trailer << /Size '+(objs.length+1)+' /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF';
 var blob=new Blob([pdf],{type:'application/pdf'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=name;a.click();setTimeout(function(){URL.revokeObjectURL(a.href)},500);
};
window.saveRepoEvidence=async function(kind,name,obj){
 try{
  var r=await fetch('/evidence-save.ashx',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({kind:kind,name:name,content:JSON.stringify(obj,null,2)})});
  var j=await r.json();return j;
 }catch(e){return {ok:false,error:e.message||String(e)}}
};
})();
