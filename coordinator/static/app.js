'use strict';
const $ = id => document.getElementById(id);
const fragment = location.hash.slice(1);
if (/^[a-f0-9]{64}$/.test(fragment)) { sessionStorage.setItem('control-token', fragment); history.replaceState(null, '', '/'); }
const token = sessionStorage.getItem('control-token') || '';
let state, initialized = false, dirty = false, pending = false, lastEvent = '', lastJob = '', lost = true;
const fields = ['left-stop','left-profit','right-stop','right-profit','instrument'];
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
  if(!dirty) api('/api/invalidate',{}).catch(e=>alertText(e.message,true));
  dirty=true; $('buy').disabled=true; $('sell').disabled=true;
  $('orders-checked').checked=false;
  alertText('Settings changed. Check working orders, then Prepare & Verify again.');
}
fields.forEach(id=>$(id).addEventListener('input',()=>changed(id)));
$('connections').onclick=()=>$('connect-dialog').showModal();
for(const side of ['left','right']) {
  $('save-'+side).onclick=async()=>{
    const button=$('save-'+side); button.disabled=true;
    try { await api('/api/enroll',{id:'vm-'+side,code:$('code-'+side).value}); $('code-'+side).value=''; $('connection-result').textContent='VM '+side+' saved. Checking the connection…'; await poll(); }
    catch(e){$('connection-result').textContent=e.message;} finally{button.disabled=false;}
  };
}
async function action(command) {
  if(pending && command!=='close') return;
  pending=true;
  $('buy').disabled=true; $('sell').disabled=true;
  const body={command,noWorkingOrders:$('orders-checked').checked};
  if(command==='prepare') Object.assign(body,{ticker:$('instrument').value,stopLoss:Number($('left-stop').value),profit:Number($('left-profit').value)});
  try {
    const result=await api('/api/action',body); lastJob=result.job;
    if(command==='prepare') dirty=false;
    if(['buy','sell','close'].includes(command)) $('orders-checked').checked=false;
    alertText(command==='close'?'Close requested independently on both VMs. Waiting for position verification.':'Request received by coordinator. Waiting for the VM results.');
  } catch(e) {alertText(e.message,true);} finally {pending=false;await poll();}
}
for(const command of ['prepare','buy','sell','close']) $(command).onclick=()=>action(command);
$('ack-flat').onclick=()=>action('ack_flat');
function render(s) {
  state=s; lost=false; $('server-dot').classList.add('connected'); $('server-state').textContent='Coordinator running';
  if(!initialized) {
    $('instrument').value=s.settings.ticker; $('left-stop').value=$('right-profit').value=s.settings.stopLoss;
    $('left-profit').value=$('right-stop').value=s.settings.profit; initialized=true;
    alertText('Connect both VM agents, check working orders, then Prepare & Verify.');
  }
  for(const a of s.agents){
    const root=$(a.id), status=root.querySelector('.status'), position=root.querySelector('.position');
    status.textContent=a.fresh?'Fresh status':a.online?'Status unknown':a.configured?'Disconnected':'Not connected';
    status.classList.toggle('fresh',a.fresh); position.textContent=a.position || 'Unknown'; position.classList.toggle('fresh',a.fresh);
    for(const key of ['account','quantity','ticker'])root.querySelector('.'+key).textContent=a[key]??'—';
    root.querySelector('.sample').textContent=a.fresh?'Observed '+(a.ageMs/1000).toFixed(1)+'s ago':'No fresh position observation';
    root.querySelector('.latency').textContent=a.rttMs==null?'— ms':a.rttMs+' ms RTT';
    root.querySelector('.vm-message').textContent=a.message || a.execution || (a.configured?'Waiting for agent status.':'Import this VM’s connection code to begin.');
  }
  const ready=s.canEnter&&!dirty&&!pending;
  $('buy').disabled=$('sell').disabled=!ready;
  $('prepare').disabled=s.busy||s.active||pending||!s.agents.every(a=>a.fresh);
  $('connections').disabled=s.active||s.busy;
  fields.forEach(id=>$(id).disabled=s.active||s.busy||pending);
  $('ack-flat').disabled=s.busy||pending;
  $('close').disabled=!s.agents.some(a=>a.configured);
  $('readiness').textContent=ready?'Ready for paired entry.':s.active?'Pair outcome must be verified before another entry.':'Both VMs must be fresh, flat, and prepared before entry.';
  const latest=s.events[0];
  if(latest && JSON.stringify(latest)!==lastEvent){
    lastEvent=JSON.stringify(latest);$('events').replaceChildren();
    for(const e of s.events){const row=document.createElement('div');row.className='event';const time=document.createElement('time');time.textContent=e.time;const message=document.createElement('span');message.textContent=e.message;row.append(time,message);$('events').append(row);}
  }
  const job=s.jobs.find(j=>j.id===lastJob);
  if(job && job.status!=='running'){alertText(job.status==='error'?job.message:(latest?.message||job.message),job.status==='error');lastJob='';}
  else if(!lastJob&&!dirty&&s.events.length===1)alertText('Connect both VM agents to get started. No trade has been requested.');
}
let polling=false;
async function poll(){
  if(polling)return;polling=true;
  try{render(await api('/api/state'));}
  catch(e){lost=true;$('server-dot').classList.remove('connected');$('server-state').textContent='Coordinator unavailable';$('buy').disabled=$('sell').disabled=$('prepare').disabled=true;alertText(e.message+' Check both VMs if a pair is active.',true);
    for(const id of ['vm-left','vm-right']){const root=$(id);root.querySelector('.position').textContent='Unknown';root.querySelector('.position').classList.remove('fresh');root.querySelector('.status').textContent='Status unknown';root.querySelector('.status').classList.remove('fresh');}}
  finally{polling=false;}
}
poll();setInterval(poll,1000);
