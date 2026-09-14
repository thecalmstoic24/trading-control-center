'use strict';
const $ = id => document.getElementById(id);
const fragment = location.hash.slice(1);
if (/^[a-f0-9]{64}$/.test(fragment)) { sessionStorage.setItem('control-token', fragment); history.replaceState(null, '', '/'); }
const token = sessionStorage.getItem('control-token') || '';
let state, initialized = false, dirty = false, pending = false, lastEvent = '', lastJob = '', lost = true, closedSequence = null, pairKey = '', fleetKey = '', registeredId = '';
let fleetState, selectedPairId=sessionStorage.getItem('selected-pair')||'';
const drafts={}, pairJobs={};
const fields = ['left-stop','left-profit','right-stop','right-profit','instrument','left-account','right-account','left-quantity','right-quantity'];
function alertText(text, error=false) { $('alert').textContent=text; $('alert').classList.toggle('error',error); }
async function api(path, body) {
  const options = {headers:{'X-Control-Token':token},cache:'no-store'};
  if(body) { options.method='POST'; options.headers['Content-Type']='application/json'; options.body=JSON.stringify(body); }
  const response=await fetch(path,options); const result=await response.json();
  if(!response.ok) throw new Error(result.error || 'Request failed.');
  return result;
}
function changed(source) {
  const pairs={'left-stop':'right-profit','left-profit':'right-stop','right-stop':'left-profit','right-profit':'left-stop'};
  if(pairs[source]) $(pairs[source]).value=$(source).value;
  if(!dirty) api('/api/invalidate',{pairId:selectedPairId}).catch(e=>alertText(e.message,true));
  dirty=true; $('buy').disabled=true; $('sell').disabled=true;
  
  alertText('Settings changed. Prepare & Verify again.');
}
fields.forEach(id=>$(id).addEventListener('input',()=>changed(id)));
$('connections').onclick=()=>$('connect-dialog').showModal();
$('connection-code').addEventListener('input',()=>{
  registeredId=''; $('connection-result').textContent='Click Save & check connection to register this code.';
});
$('register-vm').onclick=async()=>{
  const button=$('register-vm'); button.disabled=true;
  registeredId=''; $('connection-result').textContent='Checking this registration…';
  try {
    const result=await api('/api/enroll',{code:$('connection-code').value});
    registeredId=result.id; $('connection-code').value='';
    $('connection-result').textContent='Registration saved. Waiting for a fresh agent response…'; await poll();
  } catch(e){$('connection-result').textContent=e.message;} finally{button.disabled=false;}
};
$('select-pair').onclick=async()=>{
  if(pending)return; pending=true;
  try {
    const result=await api('/api/pair',{left:$('pair-left').value,right:$('pair-right').value});
    saveDraft();selectedPairId=result.pairId;initialized=false;closedSequence=null;
     dirty=true; lastJob='';
    $('pair-result').textContent='Pair created. Prepare & Verify.';
  } catch(e){alertText(e.message,true);} finally{pending=false;await poll();}
};
function saveDraft(){
  if(selectedPairId&&initialized)drafts[selectedPairId]={values:fields.map(id=>$(id).value),dirty};
}
function selectView(id){
  saveDraft();selectedPairId=id;sessionStorage.setItem('selected-pair',id);
  initialized=false;closedSequence=null;lastEvent='';
  if(fleetState)render(fleetState);
}
$('release-pair').onclick=async()=>{
  const id=selectedPairId;
  try{await api('/api/release-pair',{pairId:id});delete drafts[id];delete pairJobs[id];if(selectedPairId===id){selectedPairId='';initialized=false;}await poll();}
  catch(e){$('pair-result').textContent=e.message;}
};
$('close-all').onclick=async()=>{
  try{
    const result=await api('/api/close-all',{});
    for(const [id,value] of Object.entries(result.pairs))if(value.job)pairJobs[id]=value.job;
    $('pair-result').textContent='Close requested on all pairs. Watch each pair until both positions are verified Flat.';await poll();
  }catch(e){$('pair-result').textContent=e.message;}
};
function renderRegistry(s) {
  const key=JSON.stringify(s.fleet.map(a=>[a.id,a.name,a.pairId]));
  if(key!==fleetKey){
    for(const [index,side] of ['left','right'].entries()){
      const select=$('pair-'+side), previous=select.value;select.replaceChildren();
      const placeholder=document.createElement('option');placeholder.value='';placeholder.textContent='Choose an available VM';select.append(placeholder);
      for(const a of s.fleet){const option=document.createElement('option');option.value=a.id;option.disabled=!!a.pairId;option.textContent=a.name+(a.pairId?' — assigned to a pair':'');select.append(option);}
      select.value=s.fleet.some(a=>a.id===previous&&!a.pairId)?previous:'';
    }
    fleetKey=key;
  }
  $('fleet-count').textContent=s.fleet.length+' / '+(s.limits?.vms||50);$('fleet').replaceChildren();
  for(const a of s.fleet){
    const item=document.createElement('div');item.className='fleet-item'+(a.fresh?' fresh':'');
    const name=document.createElement('strong');name.textContent=a.name;
    const status=document.createElement('span');status.textContent=(a.snapshotHeld?a.lastKnown.position+' (last known)':a.fresh?a.position:'Unknown / disconnected')+(a.pairId?' · paired':' · available');
    item.append(name,status);$('fleet').append(item);
  }
  if(!s.fleet.length)$('fleet').textContent='Register your first two VMs to create a pair.';
  for(const side of ['left','right'])$('pair-'+side).disabled=pending;
  $('pairs-count').textContent=s.pairs.length+' / '+(s.limits?.pairs||20);
  $('select-pair').disabled=pending||s.pairs.length>=(s.limits?.pairs||20)||s.fleet.filter(a=>!a.pairId).length<2;
  $('connections').disabled=false;
  const imported=s.fleet.find(a=>a.id===registeredId);
  if(imported)$('connection-result').textContent=imported.fresh?imported.name+' connected. Fresh position: '+imported.position+'.':imported.name+' saved, but no fresh status yet. '+(imported.message||'Check that the agent is running and both computers are connected to the same Tailscale network.');
  $('pair-list').replaceChildren();
  for(const pair of s.pairs){
    const row=document.createElement('div');row.className='pair-summary'+(pair.id===selectedPairId?' selected':'')+(pair.active?' active':'');
    const info=document.createElement('div'),title=document.createElement('strong'),detail=document.createElement('small');
    title.textContent=pair.name;
    const failed=pair.jobs.find(j=>j.status==='error');
    detail.textContent=pair.agents.map(a=>a.name+': '+(a.snapshotHeld?a.lastKnown.position+' (last known)':a.position||'Unknown')).join(' · ')+' · '+(pair.busy?'Operation running':pair.active?'Active / outcome awaiting verification':pair.prepared?'Prepared':'Ready to prepare');
    if(failed&&pair.active)detail.textContent+=' · '+failed.message;
    info.append(title,detail);
    const view=document.createElement('button');view.className='quiet';view.textContent=pair.id===selectedPairId?'Viewing':'View pair';view.onclick=()=>selectView(pair.id);
    row.append(info,view);$('pair-list').append(row);
  }
  if(!s.pairs.length)$('pair-list').textContent='Choose two available VMs above and create your first pair.';
  $('close-all').disabled=s.pairs.length===0;
}
function render(s){
  fleetState=s;lost=false;$('server-dot').classList.add('connected');$('server-state').textContent='Coordinator running';
  if(!s.pairs.some(p=>p.id===selectedPairId)){
    selectedPairId=s.pairs[0]?.id||'';initialized=false;closedSequence=null;
  }
  renderRegistry(s);
  const pair=s.pairs.find(p=>p.id===selectedPairId);
  $('pair-workspace').hidden=!pair;
  if(pair){
    let restoringDraft=false;
    $('selected-pair-title').textContent=pair.name;
    if(!initialized){
      const draft=drafts[pair.id];dirty=draft?.dirty||false;lastJob=pairJobs[pair.id]||'';
      if(draft){restoringDraft=true;fields.forEach((id,index)=>$(id).value=draft.values[index]);initialized=true;}
    }
    for(const [i,a] of pair.agents.entries()){
      const side=['left','right'][i], select=$(side+'-account');
      const wanted=restoringDraft?drafts[pair.id].values[fields.indexOf(side+'-account')]:initialized?select.value:(drafts[pair.id]?.values[fields.indexOf(side+'-account')]||pair.settings.accounts?.[a.id]||'Sim101');
      const values=[...new Set(['Sim101',...(a.accounts||[]),wanted])];
      if(select.dataset?.key!==JSON.stringify(values)){
        select.replaceChildren();for(const value of values){const o=document.createElement('option');o.value=value;o.textContent=value; o.disabled=value!=='Sim101'&&!(a.accounts||[]).includes(value);select.append(o);}
        if(select.dataset)select.dataset.key=JSON.stringify(values);select.value=wanted;
      }
      if(!initialized)$(side+'-quantity').value=pair.settings.quantities?.[a.id]||1;
      $(side+'-account-message').textContent=a.accountMessage||'Refresh accounts to read NinjaTrader and Airtable.';
      $(side+'-sync').textContent=a.sync||'';
    }
    renderPair(pair);
    pairJobs[pair.id]=lastJob;
    $('release-pair').disabled=pair.busy||pending||!(pair.agents.some(a=>(a.fresh?a.position:a.lastKnown?.position)==='Flat')&&pair.agents.every(a=>(!a.fresh||a.position==='Flat')&&!a.busy&&!a.scheduled&&!a.pending&&!a.closing));
  }else alertText('Register VMs and create a pair to get started.');
}
async function action(command) {
  if(pending && command!=='close') return;
  pending=true;
  $('buy').disabled=true; $('sell').disabled=true;
  const actionPairId=selectedPairId;
  const body={pairId:actionPairId,command};
  if(command==='prepare') Object.assign(body,{ticker:$('instrument').value,stopLoss:Number($('left-stop').value),profit:Number($('left-profit').value),accounts:Object.fromEntries(state.agents.map((a,i)=>[a.id,$(['left-account','right-account'][i]).value])),quantities:Object.fromEntries(state.agents.map((a,i)=>[a.id,Number($(['left-quantity','right-quantity'][i]).value)]))});
  try {
    const result=await api('/api/action',body);pairJobs[actionPairId]=result.job;
    if(actionPairId===selectedPairId){lastJob=result.job;if(command==='prepare')dirty=false;}
    if(command==='prepare'&&drafts[actionPairId])drafts[actionPairId].dirty=false;
    
    alertText(command==='close'?'Close requested independently on both VMs. Waiting for position verification.':'Request received by coordinator. Waiting for the VM results.');
  } catch(e) {alertText(e.message,true);} finally {pending=false;await poll();}
}
for(const command of ['prepare','buy','sell','close']) $(command).onclick=()=>action(command);
$('refresh-accounts').onclick=()=>action('accounts');
$('ack-flat').onclick=()=>action('ack_flat');
function renderPair(s) {
  state=s; lost=false; $('server-dot').classList.add('connected'); $('server-state').textContent='Coordinator running';
  if(!initialized) {
    $('instrument').value=s.settings.ticker; $('left-stop').value=$('right-profit').value=s.settings.stopLoss;
    $('left-profit').value=$('right-stop').value=s.settings.profit; initialized=true;
    alertText('Connect both VM agents, check working orders, then Prepare & Verify.');
  }
  if((closedSequence!==null && s.closedSequence!==closedSequence)||(closedSequence===null&&s.closedSequence>0&&!s.prepared&&!s.active)){
    lastJob='';dirty=true;
    alertText('Both positions verified Flat. Settings retained. Check working orders, then Prepare & Verify for the next trade.');
  }
  closedSequence=s.closedSequence;
  for(const [index,a] of s.agents.entries()){
    const root=$(['vm-left','vm-right'][index]), status=root.querySelector('.status'), position=root.querySelector('.position');
    root.querySelector('h2').textContent=a.name;
    const held=!s.active&&!s.prepared&&!s.busy&&a.lastKnown?.position;
    const display=held?a.lastKnown:a;
    status.textContent=held?'Last known status':a.fresh?'Fresh status':a.online?'Status unknown':a.configured?'Disconnected':'Not connected';
    status.classList.toggle('fresh',a.fresh); position.textContent=display.position || 'Unknown'; position.classList.toggle('fresh',a.fresh);
    for(const key of ['account','quantity','ticker'])root.querySelector('.'+key).textContent=display[key]??'—';
    root.querySelector('.sample').textContent=held?'Cached — Prepare & Verify checks again':a.fresh?'Observed '+(a.ageMs/1000).toFixed(1)+'s ago':'No fresh position observation';
    root.querySelector('.latency').textContent=a.rttMs==null?'— ms':a.rttMs+' ms RTT';
    root.querySelector('.vm-message').textContent=a.message || a.execution || (a.configured?'Waiting for agent status.':'Import this VM’s connection code to begin.');
  }
  $('buy').textContent='Buy '+s.agents[0].name+' / Sell '+s.agents[1].name;
  $('sell').textContent='Sell '+s.agents[0].name+' / Buy '+s.agents[1].name;
  const ready=s.canEnter&&!dirty&&!pending;
  $('buy').disabled=$('sell').disabled=!ready;
  $('prepare').disabled=s.busy||s.active||pending;
  $('refresh-accounts').disabled=s.busy||s.active||pending;

  fields.forEach(id=>$(id).disabled=s.active||s.busy||pending);
  $('ack-flat').disabled=s.busy||pending;
  $('close').disabled=!s.agents.some(a=>a.configured);
  $('readiness').textContent=ready?'Ready for paired entry.':s.active?'This pair is active or unresolved. Other pairs remain available above.':'Both VMs must be fresh, flat, and prepared before entry.';
  const latest=s.events[0];
  if(latest && JSON.stringify(latest)!==lastEvent){
    lastEvent=JSON.stringify(latest);$('events').replaceChildren();
    for(const e of s.events){const row=document.createElement('div');row.className='event';const time=document.createElement('time');time.textContent=e.time;const message=document.createElement('span');message.textContent=e.message;row.append(time,message);$('events').append(row);}
  }
  const job=s.jobs.find(j=>j.id===lastJob);
  if(job && job.status!=='running'){alertText(job.status==='error'?job.message:(latest?.message||job.message),job.status==='error');lastJob='';}
  else if(!lastJob&&!dirty&&s.active)alertText('This pair is active or awaiting verification. You can view or create another independent pair above.');
}
let polling=false;
async function poll(){
  if(polling)return;polling=true;
  try{render(await api('/api/state'));}
  catch(e){lost=true;$('server-dot').classList.remove('connected');$('server-state').textContent='Coordinator unavailable';$('buy').disabled=$('sell').disabled=$('prepare').disabled=$('select-pair').disabled=true;alertText(e.message+' Check both VMs if a pair is active.',true);
    for(const id of ['vm-left','vm-right']){const root=$(id);root.querySelector('.position').textContent='Unknown';root.querySelector('.position').classList.remove('fresh');root.querySelector('.status').textContent='Status unknown';root.querySelector('.status').classList.remove('fresh');}}
  finally{polling=false;}
}
poll();setInterval(poll,1000);
