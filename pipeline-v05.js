
(function(){
  window.CTX={};
  function byId(id){return T.find(function(x){return x.id===id;});}
  function safeJson(text){
    var t=String(text||'').trim();
    var fence=String.fromCharCode(96,96,96);
    if(t.indexOf(fence)===0){
      var nl=t.indexOf('\n'); if(nl>=0)t=t.substring(nl+1);
      var end=t.lastIndexOf(fence); if(end>=0)t=t.substring(0,end);
    }
    try{return JSON.parse(t.trim());}catch(e){return null;}
  }
  function usageVal(u,k){return Number(u&&u[k]||0);}
  async function postJson(url,obj){
    var r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(obj)});
    var j; try{j=await r.json();}catch(e){throw new Error('Invalid server response from '+url);}
    if(!r.ok||j.ok===false)throw new Error(j.error||j.result||('HTTP '+r.status));
    return j;
  }
  function setRoute(x,k,n,m,w){x.ro={k:k,n:n,m:m||'',w:w||''};}
  function baseProof(x,id,result,verified){
    x.proof.executor=true;x.proof.requestReceipt=true;x.proof.executionId=id||('exec-'+Date.now());
    x.proof.terminal=true;x.proof.result=!!result;x.proof.verification=verified!==false;
  }
  async function persistEvidence(x,extra){
    var e=await saveRepoEvidence('task',x.id+'-'+x.t,{prompt:promptText,task:x,context:window.CTX,extra:extra||null,savedAt:new Date().toISOString()});
    if(e&&e.ok){x.proof.evidence=e.url;return true;}
    x.res=(x.res||'')+' Evidence save failed: '+((e&&e.error)||'unknown error'); return false;
  }
  async function finalizeTask(x,data,verified){
    x.res=data.result||'Execution completed.';
    x.outUrl=data.outputUrl||data.repoUrl||data.liveUrl||x.outUrl||'';
    x.inp=usageVal(data.usage,'input_tokens');x.out=usageVal(data.usage,'output_tokens');x.c=Number(data.estimatedCost||0);
    baseProof(x,data.executionId,x.res,verified!==false);
    var ev=await persistEvidence(x,data);
    x.s=ev&&x.proof.terminal&&x.proof.result&&x.proof.verification?'Done':'Blocked';render();
  }
  async function markDerived(x,result,id){
    setRoute(x,'OpenAI API','OpenAI','Derived from planning','Derived from one real OpenAI planning execution.');
    x.res=String(result||'');x.inp=0;x.out=0;x.c=0;baseProof(x,id,x.res,true);
    var ev=await persistEvidence(x,{derived:true,sourceExecutionId:CTX.planningExecutionId});x.s=ev?'Done':'Blocked';render();
  }
  async function markSkipped(x,reason){
    setRoute(x,'Conditional Gate','Router','No invocation required','Condition was false; no model/agent call was needed.');
    x.res=reason;x.s='Skipped';x.inp=0;x.out=0;x.c=0;
    x.proof.executor=true;x.proof.requestReceipt=true;x.proof.executionId='skip-'+x.id+'-'+Date.now();
    x.proof.terminal=true;x.proof.result=true;x.proof.verification=true;
    await persistEvidence(x,{skipped:true,reason:reason});render();
  }

  window.doneProof=function(x){
    var p=x.proof||{};
    return x.s==='Done'&&p.executor&&p.requestReceipt&&p.executionId&&p.terminal&&p.result&&p.verification&&p.evidence&&(!x.requiresUrl||!!x.outUrl);
  };

  window.build=function(p){
    var x=[
      ['Router Control','0.1','Validate executor connectivity and authentication','Real preflight for OpenAI, GitHub, Azure and registered Agents.',[]],
      ['Router Control','0.2','Enforce proof-gated Done contract','Done requires receipt, execution ID, actual result, verification and durable evidence.',['0.1']],
      ['Discovery','1.1','Analyze project prompt','One real OpenAI planning execution creates analysis, build plan, decomposition and graph.',['0.2']],
      ['Planning','2.1','Create build plan','Derived from the real planning execution.',['1.1']],
      ['Architecture','3.1','Recursively decompose modules into executable tasks','Derived from the real planning execution.',['1.1']],
      ['Architecture','3.2','Resolve dependency graph and parallel lanes','Derived from the real planning execution.',['1.1']],
      ['Implementation','4.1','Generate executable website source','Real OpenAI execution produces self-contained prototype source files.',['2.1','3.1','3.2']],
      ['Delivery','4.2','Create GitHub repository and push source','Real GitHub API operation creates repository and deployment package.',['4.1']],
      ['Delivery','4.3','Deploy project to Azure App Service','Real Azure ARM deployment using Router managed identity.',['4.2']]
    ];
    var z=String(p||'').toLowerCase();
    if(/fail|error|root cause|solve|resolve|broken|stuck/.test(z)){
      x.push(['Reliability','4.4','Run RCA if deployment fails','Conditional: use RCA Agent when authorized; otherwise real OpenAI RCA fallback.',['4.3']]);
      x.push(['Reliability','4.5','Run remediation if deployment fails','Conditional: use RCS Agent when authorized; otherwise real OpenAI remediation fallback.',['4.4']]);
    }
    x.push(['Verification','5.1','Verify actual Azure project output','Must have a real HTTP-successful Azure live URL.',['4.3']]);
    x.push(['Evidence','5.2','Store final evidence and handoff','Persist execution receipts, outputs and verification.',['5.1']]);
    if(/azure/.test(z))x.push(['Final Delivery','6.1','Return verified Azure live site URL','Mandatory final output for Azure deployment requests.',['5.2']]);
    return x.map(function(r){
      var reqUrl=r[1]==='6.1';
      return {mo:r[0],id:r[1],t:r[2],d:r[3],dep:r[4],ro:route({t:r[2],d:r[3]}),s:'Planned',res:reqUrl?'Verified Azure live URL required.':'Not executed.',proof:proof(),inp:0,out:0,c:0,outUrl:'',requiresUrl:reqUrl};
    });
  };

  window.pfRow=function(name,o){
    o=o||{};var ready=o.ready===true,reach=o.reachable===true,fallback=o.fallback===true;
    var label=ready?'READY':fallback?'FALLBACK READY':reach?'AUTH PENDING':'BLOCKED';
    var cls=ready?'okText':fallback?'warnText':reach?'warnText':'badText';
    var msg=(reach?'Endpoint reachable. ':'')+(o.missing?esc(o.missing):(ready?'Configured and ready.':''));
    return '<div class="preflightRow"><b>'+name+'</b><span>'+msg+'</span><span class="'+cls+'">'+label+'</span></div>';
  };

  window.doPreflight=async function(){
    Q('#pb').textContent='Checking';proc(1,0,-1);
    var r=await fetch('/executor-preflight.ashx?ts='+Date.now(),{cache:'no-store'});PF=await r.json();
    Q('#preflight').innerHTML=pfRow('RCA',PF.rca)+pfRow('RCS',PF.rcs)+pfRow('OpenAI',PF.openai)+pfRow('GitHub',PF.github)+pfRow('Azure',PF.azure);
    var state=Q('#pipelineState');
    if(!state){state=document.createElement('div');state.id='pipelineState';Q('#preflight').parentNode.appendChild(state);}
    state.className=PF.pipelineReady?'pipelineOk':'pipelineBad';
    state.innerHTML=PF.pipelineReady?'<b>Core Pipeline READY:</b> OpenAI + GitHub + Azure can execute. RCA/RCS are conditional with explicit OpenAI fallback.':'<b>Core Pipeline BLOCKED:</b> OpenAI, GitHub or Azure adapter is not ready.';
    Q('#pb').textContent='Checked';return PF;
  };

  window.outputHtml=function(x){
    if(x.requiresUrl&&!x.outUrl)return '<div class="outputBox"><span class="red">REQUIRED FINAL OUTPUT MISSING</span><b>Verified Azure Live Site URL</b></div>';
    var h='<div class="outputBox">';
    if(x.s==='Done')h+='<button type="button" data-pdf="'+esc(x.id)+'">Download Result PDF</button>';
    if(x.outUrl)h+='<a href="'+esc(x.outUrl)+'" target="_blank">Open Project Output URL</a>';
    if(!x.outUrl&&x.s!=='Done')h+='<span class="muted">Output pending</span>';
    return h+'</div>';
  };

  window.render=function(){
    Q('#tb').innerHTML=T.map(function(x){
      var tagClass=x.ro.k==='Agent'?'agent':(x.ro.k.toLowerCase().indexOf('fallback')>=0?'fallback':'ai');
      return '<tr><td><b>'+esc(x.mo)+'</b></td><td>'+esc(x.id)+'</td><td><b>'+esc(x.t)+'</b><br><small>'+esc(x.d)+'</small></td><td><span class="tag '+tagClass+'">'+esc(x.ro.k)+'</span><br><b>'+esc(x.ro.n)+'</b><br><small>'+esc(x.ro.m||'')+'</small></td><td>'+esc(x.ro.w||'')+'</td><td><span class="st '+x.s.toLowerCase()+'">'+esc(x.s)+'</span><br><small class="resultText">'+esc(String(x.res||'').substring(0,1000))+'</small></td><td>'+proofHtml(x)+'</td><td>In '+x.inp+'<br>Out '+x.out+'<br><span class="red">'+M(x.c)+'</span></td><td>'+outputHtml(x)+'</td></tr>';
    }).join('');
    var d=T.filter(function(x){return x.s==='Done'}).length;
    Q('#st').textContent=T.length;Q('#sd').textContent=d;Q('#sa').textContent=getAgents().length;Q('#ts').textContent=T.length+' tasks - '+d+' done';
    renderCost();graph();
  };

  window.renderCost=function(){
    if(!T.length){Q('#costRows').innerHTML='<tr><td colspan="7">No execution yet.</td></tr>';Q('#costFoot').innerHTML='';return;}
    Q('#costRows').innerHTML=T.map(function(x){
      var ps=doneProof(x)?'<span class="green">PROVEN</span>':(x.s==='Skipped'?'<span class="muted">N/A</span>':'<span class="red">NOT PROVEN</span>');
      return '<tr><td>'+esc(x.id)+'</td><td>'+esc(x.ro.k)+' - '+esc(x.ro.n)+'</td><td>'+x.inp+'</td><td>'+x.out+'</td><td>'+(x.inp+x.out)+'</td><td class="red">'+M(x.c)+'</td><td>'+ps+'</td></tr>';
    }).join('');
    var inp=T.reduce(function(a,b){return a+b.inp},0),out=T.reduce(function(a,b){return a+b.out},0),cost=T.reduce(function(a,b){return a+b.c},0);
    Q('#costFoot').innerHTML='<tr><td colspan="2" class="costTotal">TOTAL</td><td>'+inp+'</td><td>'+out+'</td><td>'+(inp+out)+'</td><td class="red">'+M(cost)+'</td><td></td></tr>';
  };

  window.analyze=async function(){
    promptText=Q('#p').value.trim();if(!promptText)return Q('#p').focus();
    window.CTX={};var hasAzure=/azure/i.test(promptText);
    Q('#reqDetect').style.display='block';
    Q('#reqDetect').innerHTML=hasAzure?'<b>Requirement detected:</b> Azure deployment includes a mandatory final verified live URL.':'<b>Requirement:</b> No Azure deployment detected.';
    T=build(promptText);proc(0,-1,-1);render();setTimeout(function(){proc(-1,0,-1);},100);
  };

  window.run=async function(){
    if(!T.length)await analyze();if(!T.length)return;
    try{await doPreflight();}catch(e){
      var state=Q('#pipelineState');if(!state){state=document.createElement('div');state.id='pipelineState';Q('#preflight').parentNode.appendChild(state);}
      state.className='pipelineBad';state.textContent='Preflight failed: '+e.message;return;
    }
    if(!PF.pipelineReady){proc(-1,0,1);return;}
    proc(2,1,-1);

    var c1=byId('0.1');c1.res='Real preflight completed: core pipeline ready.';baseProof(c1,'preflight-'+Date.now(),c1.res,true);c1.s=(await persistEvidence(c1,PF))?'Done':'Blocked';
    var c2=byId('0.2');c2.res='Proof-gated Done contract active.';baseProof(c2,'contract-v0.5.0',c2.res,true);c2.s=(await persistEvidence(c2,{contract:'v0.5.0'}))?'Done':'Blocked';render();

    var x=byId('1.1');x.s='Running';setRoute(x,'OpenAI API','OpenAI',PF.openai.model||'gpt-5.6-sol','One real planning execution.');render();proc(3,2,-1);
    try{
      var p=await postJson('/openai-execute.ashx',{input:'Return ONLY valid JSON with keys projectName, analysis, buildPlan, decomposition, graph. Do not claim work has already been executed. PROJECT REQUEST: '+promptText});
      var pj=safeJson(p.result);if(!pj)pj={projectName:'Pilot Project',analysis:p.result,buildPlan:p.result,decomposition:p.result,graph:p.result};
      CTX.planning=pj;CTX.projectName=pj.projectName||'Pilot Project';CTX.planningExecutionId=p.executionId;p.result=String(pj.analysis||p.result||'Project analyzed.');await finalizeTask(x,p,true);
    }catch(e){x.s='Blocked';x.res='Planning failed: '+e.message;render();proc(-1,2,3);return;}

    await markDerived(byId('2.1'),CTX.planning.buildPlan,CTX.planningExecutionId+'-plan');
    await markDerived(byId('3.1'),CTX.planning.decomposition,CTX.planningExecutionId+'-decompose');
    await markDerived(byId('3.2'),CTX.planning.graph,CTX.planningExecutionId+'-graph');

    x=byId('4.1');x.s='Running';setRoute(x,'OpenAI API','OpenAI',PF.openai.model||'gpt-5.6-sol','Real source generation.');render();
    try{
      var g=await postJson('/openai-execute.ashx',{input:'Build a complete self-contained professional STATIC WEB PROTOTYPE for Azure App Service. Return ONLY valid JSON: {"projectName":"...","files":[{"path":"index.html","content":"..."}]}. Use HTML/CSS/JavaScript only, no CDN, no secrets, responsive UI, visible Prototype label, maximum 8 files. PROJECT REQUEST: '+promptText+' PLAN: '+JSON.stringify(CTX.planning)});
      var gd=safeJson(g.result);if(!gd||!Array.isArray(gd.files)||!gd.files.length)throw new Error('OpenAI did not return valid files JSON.');
      CTX.files=gd.files;CTX.projectName=gd.projectName||CTX.projectName;g.result='Generated '+gd.files.length+' project source files.';await finalizeTask(x,g,true);
    }catch(e){x.s='Blocked';x.res='Source generation failed: '+e.message;render();proc(-1,2,3);return;}

    x=byId('4.2');x.s='Running';setRoute(x,'GitHub API','GitHub','REST API','Real repository creation and source/package push.');render();
    try{
      var gh=await postJson('/github-publish.ashx',{projectName:CTX.projectName,files:CTX.files});
      CTX.repoOwner=gh.repoOwner;CTX.repoName=gh.repoName;CTX.repoUrl=gh.repoUrl;CTX.packageRawUrl=gh.packageRawUrl;gh.outputUrl=gh.repoUrl;gh.verified=true;gh.usage={input_tokens:0,output_tokens:0};gh.estimatedCost=0;await finalizeTask(x,gh,true);
    }catch(e){x.s='Blocked';x.res='GitHub publish failed: '+e.message;render();proc(-1,2,3);return;}

    x=byId('4.3');x.s='Running';setRoute(x,'Azure ARM','Azure App Service','Managed Identity','Real Azure App Service deployment.');render();
    var deploymentFailed=false;
    try{
      var az=await postJson('/azure-deploy.ashx',{projectName:CTX.projectName,packageRawUrl:CTX.packageRawUrl});
      CTX.appName=az.appName;CTX.liveUrl=az.liveUrl;CTX.verified=az.verified===true;az.outputUrl=az.liveUrl;az.usage={input_tokens:0,output_tokens:0};az.estimatedCost=0;
      if(!az.verified)throw new Error(az.result||'Azure HTTP verification failed.');
      await finalizeTask(x,az,true);
    }catch(e){deploymentFailed=true;CTX.deploymentError=e.message;x.s='Blocked';x.res='Azure deployment failed: '+e.message;render();}

    var rca=byId('4.4'),rcs=byId('4.5');
    if(rca){
      if(!deploymentFailed)await markSkipped(rca,'Deployment succeeded; RCA was not needed.');
      else{
        rca.s='Running';setRoute(rca,'OpenAI fallback','OpenAI (RCA unavailable)',PF.openai.model||'gpt-5.6-sol','RCA.Invoke app-role is not available to Router; real OpenAI fallback is explicit.');render();
        try{var ar=await postJson('/openai-execute.ashx',{input:'Perform evidence-based root cause analysis. Return concise root cause, causal chain, and next corrective action. PROJECT: '+promptText+' FAILURE EVIDENCE: '+CTX.deploymentError});CTX.fallbackRca=ar.result;await finalizeTask(rca,ar,true);}catch(e){rca.s='Blocked';rca.res='RCA fallback failed: '+e.message;render();}
      }
    }
    if(rcs){
      if(!deploymentFailed)await markSkipped(rcs,'Deployment succeeded; remediation was not needed.');
      else{
        rcs.s='Running';setRoute(rcs,'OpenAI fallback','OpenAI (RCS unavailable)',PF.openai.model||'gpt-5.6-sol','RCS delegated/OBO adapter is not available; real OpenAI fallback is explicit.');render();
        try{var rr=await postJson('/openai-execute.ashx',{input:'Provide a safe remediation plan for this Azure deployment failure. Do not claim changes were applied. PROJECT: '+promptText+' FAILURE: '+CTX.deploymentError+' RCA: '+String(CTX.fallbackRca||'')});await finalizeTask(rcs,rr,true);}catch(e){rcs.s='Blocked';rcs.res='RCS fallback failed: '+e.message;render();}
      }
    }

    x=byId('5.1');setRoute(x,'HTTP Verification','Azure Live Site','GET','Verification result returned by Azure deploy adapter.');
    if(CTX.verified&&CTX.liveUrl){x.res='Live site verified successfully.';x.outUrl=CTX.liveUrl;baseProof(x,'verify-'+Date.now(),x.res,true);x.s=(await persistEvidence(x,{liveUrl:CTX.liveUrl,verified:true}))?'Done':'Blocked';}
    else{x.s='Blocked';x.res='No verified Azure live output is available.';}render();

    x=byId('5.2');setRoute(x,'Evidence','GitHub Evidence Store','JSON','Durable final-run handoff.');
    var finalEv=await saveRepoEvidence('final-run','real-pipeline',{prompt:promptText,context:CTX,tasks:T,savedAt:new Date().toISOString()});
    if(finalEv.ok){x.res='Final execution evidence stored.';x.outUrl=finalEv.url;baseProof(x,'evidence-'+Date.now(),x.res,true);x.proof.evidence=finalEv.url;x.s='Done';}
    else{x.s='Blocked';x.res='Final evidence save failed: '+finalEv.error;}render();

    x=byId('6.1');
    if(x){
      setRoute(x,'Router Handoff','Verified Azure URL','Final Output','Prompt-required final deliverable.');
      if(CTX.verified&&CTX.liveUrl){x.res=CTX.liveUrl;x.outUrl=CTX.liveUrl;baseProof(x,'final-url-'+Date.now(),x.res,true);x.s=(await persistEvidence(x,{liveUrl:CTX.liveUrl}))?'Done':'Blocked';}
      else{x.s='Blocked';x.res='Verified Azure live URL is not available.';}render();
    }

    var state=Q('#pipelineState');
    if(CTX.verified){proc(-1,5,-1);state.className='pipelineOk';state.innerHTML='<b>PIPELINE COMPLETE.</b> Final Azure URL: <a target="_blank" href="'+esc(CTX.liveUrl)+'">'+esc(CTX.liveUrl)+'</a>';}
    else{proc(-1,3,4);state.className='pipelineBad';state.textContent='Pipeline stopped without a verified Azure live URL.';}
  };

  Q('#run').textContent='Run Real Pipeline';
  Q('#an').onclick=window.analyze;Q('#run').onclick=window.run;
  var footer=document.querySelector('footer');if(footer)footer.textContent='Babco Labs Prototype - Agent Pilot Router - Version 0.5.0';
  var mode=document.querySelector('.proofMode');if(mode)mode.textContent='REAL EXECUTION v0.5.0';
})();
