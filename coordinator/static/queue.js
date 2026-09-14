'use strict';
(() => {
  const el=id=>document.getElementById(id), node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  let fleet=[],data={rows:[]},busy=false;
  const pending=r=>['Queued','Waiting'].includes(r.status);
  const dollars=v=>v===undefined?'—':new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(v);
  async function action(name,body={}){
    try{await api('/api/queue/'+name,body);await poll();}catch(e){el('queue-status').textContent=e.message;}
  }
  function render(){
    el('queue-status').textContent=(data.running?'Running · ':'Paused · ')+data.message;
    el('queue-start').disabled=data.running;el('queue-pause').disabled=!data.running;
    const table=el('queue-table');table.replaceChildren();const head=node('thead'),hr=node('tr');
    for(const label of ['Pair ID','Left master / account','Left balance','Right master / account','Right balance','Instrument / Qty','Status','Left P&L','Right P&L','Actions'])hr.append(node('th',label));
    head.append(hr);table.append(head);const body=node('tbody');
    for(const r of data.rows){
      const tr=node('tr'),s=r.spec;tr.append(node('td',r.id));
      for(const side of ['left','right']){const id=s[side];tr.append(node('td',`${s.masters[id]} / ${s.accounts[id]}`),node('td',dollars(((r.after?.[id]||r.before?.[id])?.balance ?? s.balances?.[id]))));}
      tr.append(node('td',`${s.ticker} · ${s.quantities[s.left]} / ${s.quantities[s.right]}`));
      const status=node('td',r.status);status.title=r.message;status.append(node('small',r.message));tr.append(status);
      for(const id of [s.left,s.right]){const v=r.results?.[id],td=node('td',dollars(v));td.className=v>0?'queue-win':v<0?'queue-loss':'';tr.append(td);}
      const actions=node('td');
      if(pending(r))for(const [label,name,extra] of [['↑','move',{delta:-1}],['↓','move',{delta:1}],['Remove','cancel',{}]]){
        const b=node('button',label);b.className='quiet';b.onclick=()=>action(name,{id:r.id,...extra});actions.append(b);
      }
      if(r.status==='Error'){const b=node('button','Resolve after closing');b.className='quiet';b.onclick=()=>action('resolve',{id:r.id});actions.append(b);}
      if(r.pairId){const b=node('button','View trade');b.className='quiet';b.onclick=()=>{selectView(r.pairId);el('tab-trading').click();};actions.append(b);}
      tr.append(actions);body.append(tr);
    }
    if(!data.rows.length){const tr=node('tr'),td=node('td','No planned pairs yet. Choose Plan a pair to add one.');td.colSpan=10;tr.append(td);body.append(tr);}
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
  el('queue-start').onclick=()=>action('start');el('queue-pause').onclick=()=>action('pause');el('queue-retry').onclick=()=>action('retry');
  window.addEventListener('queue-refresh',poll);setInterval(poll,3000);poll();
})();
