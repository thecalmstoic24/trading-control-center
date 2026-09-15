'use strict';
(() => {
  const el=id=>document.getElementById(id), node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  let fleet=[],data={rows:[]},busy=false,detailId='';const duplicateKeys=new Map();
  const selected=new Set();let mutating=false;
  const pending=r=>['Queued','Waiting'].includes(r.status);
  const dollars=v=>v===undefined?'—':new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(v);
  async function action(name,body={}){
    if(mutating)return;mutating=true;render();
    try{await api('/api/queue/'+name,body);await poll();if(name==='start')el('tab-trading').click();}
    catch(e){data.message=e.message;el('queue-status').textContent=el('trading-queue-status').textContent=e.message;}
    finally{mutating=false;render();}
  }
  const removable=r=>pending(r)||r.status==='Removing';
  const planned=r=>!r.dispatched&&!r.duplicateOf&&(pending(r)||r.status==='Removing');
  function updateButtons(){
    el('trading-refresh').disabled=mutating;
    const anyPlans=data.rows.some(planned);
    el('queue-start').disabled=mutating||!anyPlans;
    el('queue-pause').disabled=el('trading-pause').disabled=mutating||!data.running;
    el('trading-resume').disabled=mutating||data.running||!data.rows.some(r=>r.dispatched&&!['Complete','Cancelled'].includes(r.status));
    for(const [id,isPlanning] of [['queue-remove-selected',true],['trading-remove-selected',false]])
      el(id).disabled=mutating||!data.rows.some(r=>planned(r)===isPlanning&&removable(r)&&selected.has(r.id));
  }
  function render(){
    el('queue-status').textContent=el('trading-queue-status').textContent=(data.running?'Running · ':'Paused · ')+data.message;
    const valid=new Set(data.rows.filter(removable).map(r=>r.id));for(const id of selected)if(!valid.has(id))selected.delete(id);
    renderTable('queue-table',data.rows.filter(planned),true);
    renderTable('trading-queue-table',[...data.rows.filter(r=>!planned(r)),...(data.history||[])],false);
    const activity=el('queue-activity');activity.replaceChildren();
    for(const r of [...data.rows,...(data.history||[])].slice().reverse()){
      if(!r.message)continue;const item=node('div');item.className='event';item.append(node('span',r.id+' · '+r.status+' · '+r.message));activity.append(item);
    }
    renderDetail();updateButtons();
  }
  function renderTable(id,rows,isPlanning){
    const table=el(id);table.replaceChildren();const head=node('thead'),hr=node('tr');
    for(const label of ['Select','Pair ID','Left master / account','Left balance','Right master / account','Right balance','Instrument / Qty','Status','Left P&L','Right P&L','Actions'])hr.append(node('th',label));
    head.append(hr);table.append(head);const body=node('tbody');
    for(const r of rows){
      const tr=node('tr'),s=r.spec,selection=node('td');tr.dataset.pair=r.id;if(!isPlanning){tr.classList.add('pair-select-row');tr.onclick=e=>{if(e.target.closest('button,input'))return;detailId=r.id;if(r.pairId)selectView(r.pairId);renderDetail();};}
      if(removable(r)){const box=node('input');box.type='checkbox';box.checked=selected.has(r.id);box.disabled=mutating;box.setAttribute('aria-label','Select '+r.id);box.onchange=()=>{box.checked?selected.add(r.id):selected.delete(r.id);updateButtons();};selection.append(box);}
      tr.append(selection,node('td',r.id));
      for(const side of ['left','right']){const slot=s[side];tr.append(node('td',`${s.masters[slot]} / ${s.accounts[slot]}`),node('td',dollars(((r.after?.[slot]||r.before?.[slot])?.balance ?? s.balances?.[slot]))));}
      tr.append(node('td',`${s.ticker} · ${s.quantities[s.left]} / ${s.quantities[s.right]}`));
      const label=r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status;
      const status=node('td'),phase=node('span',label);phase.className='pair-phase '+r.status.toLowerCase();status.append(phase);tr.append(status);
      for(const slot of [s.left,s.right]){const v=r.results?.[slot],td=node('td',dollars(v));td.className=v>0?'queue-win':v<0?'queue-loss':'';tr.append(td);}
      const actions=node('td');actions.className='pair-actions';appendActions(actions,r);
      tr.append(actions);body.append(tr);
    }
    if(!rows.length){const tr=node('tr'),td=node('td',isPlanning?'No waiting plans. Build a pair to add one.':'Start Queue in Planning to see pairing, completed, and canceled pairs here.');td.colSpan=11;tr.append(td);body.append(tr);}
    table.append(body);
  }
  function appendActions(target,r){
    const add=(label,name,extra={},blue=false)=>{const b=node('button',label);b.className=blue?'duplicate-button':'quiet';b.disabled=mutating;b.onclick=()=>action(name,{id:r.id,...extra});target.append(b);};
    if(pending(r)){if(r.duplicateOf&&!r.dispatched)add('Start','start-one');add('Cancel','cancel');}
    if(r.status==='Removing')add('Cancel','cancel');
    if(r.status==='Error'){
      if(!r.started)add('Retry','retry-prepare');
      else if(r.closed&&r.afterId)add('Retry sync','retry');
      add('Cancel','resolve');
    }
    if(r.pairId&&(r.status==='Trading'||(r.status==='Error'&&r.started&&!r.closed))){
      const b=node('button','Close Pair');b.className='close';b.disabled=mutating;
      b.onclick=async()=>{try{await api('/api/action',{command:'close',pairId:r.pairId});await poll();}catch(e){el('trading-queue-status').textContent=e.message;}};target.append(b);
    }
    if(['Complete','Cancelled'].includes(r.status)){
      const b=node('button','Duplicate');b.className='duplicate-button';b.disabled=mutating;
      b.onclick=async()=>{if(!duplicateKeys.has(r.id))duplicateKeys.set(r.id,crypto.randomUUID().replaceAll('-',''));const key=duplicateKeys.get(r.id);await action('duplicate',{id:r.id,draftKey:key});if(data.rows.some(x=>x.key===key)){detailId=data.rows.find(x=>x.key===key).id;duplicateKeys.delete(r.id);renderDetail();}};target.append(b);
    }
  }
  function renderDetail(){
    const host=el('compact-pair'),rows=[...data.rows.filter(r=>!planned(r)),...(data.history||[])];host.replaceChildren();
    const r=rows.find(r=>r.id===detailId)||rows[rows.length-1];host.hidden=!r;if(!r)return;
    const s=r.spec,label=r.status==='Awaiting results'?'Trade closed · Syncing results':r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status;
    host.append(node('h3',r.id+' · '+s.ticker+' · '+label));
    const cards=node('div');cards.className='compact-cards';
    const ratio=(s.ratio||'1:1').split(':').map(Number),factor=ratio[1]/ratio[0];
    for(const side of ['left','right']){
      const slot=s[side],card=node('article');card.className='compact-account';
      const direction=(side==='left')===(s.direction==='buy')?'Buy':'Sell';
      card.append(node('strong',(s.masters[slot]||s.names[slot])+' · '+direction),node('div',s.accounts[slot]));
      card.append(node('div','Quantity: '+s.quantities[slot]+' · Ratio: '+(s.ratio||'1:1')));
      card.append(node('div','Profit: '+dollars(side==='left'?s.profit:s.stopLoss*factor)+' · Stop: '+dollars(side==='left'?s.stopLoss:s.profit*factor)));
      const result=node('div','Result: '+dollars(r.results?.[slot]));result.className=r.results?.[slot]>0?'queue-win':r.results?.[slot]<0?'queue-loss':'';card.append(result);cards.append(card);
    }
    host.append(cards);const actions=node('div');actions.className='pair-actions';appendActions(actions,r);host.append(actions);
  }
  async function poll(){if(busy)return;busy=true;try{data=await api('/api/queue');render();window.dispatchEvent(new CustomEvent('queue-updated',{detail:data}));}catch(e){el('queue-status').textContent=e.message;}finally{busy=false;}}
  function accounts(side){const vm=fleet.find(v=>v.id===el('queue-'+side).value),select=el('queue-'+side+'-account');select.replaceChildren();for(const a of vm?.accounts||['Sim101']){const o=node('option',a);o.value=a;select.append(o);}select.value='Sim101';}
  el('queue-add').onclick=async()=>{
    try{fleet=(await api('/api/state')).fleet;for(const side of ['left','right']){const select=el('queue-'+side);select.replaceChildren();for(const vm of fleet){const o=node('option',vm.name);o.value=vm.id;select.append(o);}if(side==='right'&&fleet[1])select.value=fleet[1].id;accounts(side);}el('queue-form-status').textContent='';el('queue-dialog').showModal();}catch(e){el('queue-status').textContent=e.message;}
  };
  for(const side of ['left','right'])el('queue-'+side).onchange=()=>accounts(side);
  el('queue-cancel').onclick=()=>el('queue-dialog').close();
  el('queue-form').onsubmit=async e=>{
    e.preventDefault();el('queue-save').disabled=true;
    const left=el('queue-left').value,right=el('queue-right').value;
    const body={left,right,ticker:el('queue-instrument').value,direction:el('queue-direction').value,
      accounts:{[left]:el('queue-left-account').value,[right]:el('queue-right-account').value},
      quantities:{[left]:Number(el('queue-left-quantity').value),[right]:Number(el('queue-right-quantity').value)},
      stopLoss:Number(el('queue-stop').value),profit:Number(el('queue-profit').value)};
    try{await api('/api/queue/add',body);el('queue-dialog').close();await poll();}catch(err){el('queue-form-status').textContent=err.message;}finally{el('queue-save').disabled=false;}
  };
  for(const [id,isPlanning] of [['queue-remove-selected',true],['trading-remove-selected',false]])el(id).onclick=()=>action('remove-selected',{ids:data.rows.filter(r=>planned(r)===isPlanning&&removable(r)&&selected.has(r.id)).map(r=>r.id)});
  el('trading-refresh').onclick=()=>action('refresh');
  el('trading-resume').onclick=()=>action('resume');el('trading-pause').onclick=()=>action('pause');el('trading-retry').onclick=()=>action('retry');
  el('queue-start').onclick=()=>action('start');el('queue-pause').onclick=()=>action('pause');el('queue-retry').onclick=()=>action('retry');
  window.addEventListener('queue-refresh',poll);setInterval(poll,3000);poll();
})();
