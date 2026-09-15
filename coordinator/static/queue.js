'use strict';
(() => {
  const el=id=>document.getElementById(id), node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  let fleet=[],data={rows:[]},busy=false;
  const selected=new Set();let mutating=false;
  const pending=r=>['Queued','Waiting'].includes(r.status);
  const dollars=v=>v===undefined?'—':new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(v);
  async function action(name,body={}){
    if(mutating)return;mutating=true;render();
    try{await api('/api/queue/'+name,body);await poll();if(name==='start')el('tab-trading').click();}
    catch(e){el('queue-status').textContent=el('trading-queue-status').textContent=e.message;}
    finally{mutating=false;updateButtons();}
  }
  const removable=r=>pending(r)||r.status==='Removing';
  const planned=r=>!r.dispatched&&(pending(r)||r.status==='Removing');
  function updateButtons(){
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
    updateButtons();
  }
  function renderTable(id,rows,isPlanning){
    const table=el(id);table.replaceChildren();const head=node('thead'),hr=node('tr');
    for(const label of ['Select','Pair ID','Left master / account','Left balance','Right master / account','Right balance','Instrument / Qty','Status','Left P&L','Right P&L','Actions'])hr.append(node('th',label));
    head.append(hr);table.append(head);const body=node('tbody');
    for(const r of rows){
      const tr=node('tr'),s=r.spec,selection=node('td');tr.dataset.pair=r.id;
      if(removable(r)){const box=node('input');box.type='checkbox';box.checked=selected.has(r.id);box.disabled=mutating;box.setAttribute('aria-label','Select '+r.id);box.onchange=()=>{box.checked?selected.add(r.id):selected.delete(r.id);updateButtons();};selection.append(box);}
      tr.append(selection,node('td',r.id));
      for(const side of ['left','right']){const slot=s[side];tr.append(node('td',`${s.masters[slot]} / ${s.accounts[slot]}`),node('td',dollars(((r.after?.[slot]||r.before?.[slot])?.balance ?? s.balances?.[slot]))));}
      tr.append(node('td',`${s.ticker} · ${s.quantities[s.left]} / ${s.quantities[s.right]}`));
      const label=r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status;
      const status=node('td'),phase=node('span',label);phase.className='pair-phase '+r.status.toLowerCase();status.append(phase,node('small',r.message));tr.append(status);
      for(const slot of [s.left,s.right]){const v=r.results?.[slot],td=node('td',dollars(v));td.className=v>0?'queue-win':v<0?'queue-loss':'';tr.append(td);}
      const actions=node('td');
      const button=(label,name,extra={})=>{const b=node('button',label);b.className='quiet';b.disabled=mutating;b.onclick=()=>action(name,{id:r.id,...extra});actions.append(b);};
      if(pending(r)){button('↑','move',{delta:-1});button('↓','move',{delta:1});button('Remove','cancel');}
      if(r.status==='Removing')button('Retry Remove','cancel');
      if(r.status==='Error')button('Resolve after closing','resolve');
      if(r.pairId&&!['Complete','Cancelled'].includes(r.status)){const b=node('button','View trade');b.className='quiet';b.onclick=()=>{selectView(r.pairId);el('tab-trading').click();};actions.append(b);}
      tr.append(actions);body.append(tr);
    }
    if(!rows.length){const tr=node('tr'),td=node('td',isPlanning?'No waiting plans. Build a pair to add one.':'Start Queue in Planning to see pairing, completed, and canceled pairs here.');td.colSpan=11;tr.append(td);body.append(tr);}
    table.append(body);
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
  el('trading-resume').onclick=()=>action('resume');el('trading-pause').onclick=()=>action('pause');el('trading-retry').onclick=()=>action('retry');
  el('queue-start').onclick=()=>action('start');el('queue-pause').onclick=()=>action('pause');el('queue-retry').onclick=()=>action('retry');
  window.addEventListener('queue-refresh',poll);setInterval(poll,3000);poll();
})();
