'use strict';
(() => {
  const el=id=>document.getElementById(id), node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  let fleet=[],data={rows:[]},busy=false,resizing=false,detailId='';const duplicateKeys=new Map();
  let sortColumn=10,sortDirection=-1;
  const selected=new Set();let mutating=false,toastTimer;
  function toast(count){const box=el('queue-toast');clearTimeout(toastTimer);box.textContent=count?`${count} ${count===1?'pair':'pairs'} started in the queue successfully.`:'No new pairs to start.';box.hidden=false;toastTimer=setTimeout(()=>{box.hidden=true;},5000);}
  const centralDay=value=>{const date=new Date(value);if(!Number.isFinite(date.getTime()))return '';const parts=new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);return ['year','month','day'].map(t=>parts.find(p=>p.type===t).value).join('-');};
  function tradingRows(){
    const rows=[...data.rows.filter(r=>!planned(r)),...(data.history||[])],select=el('trading-date'),value=select.value||'today';
    const dateOf=r=>centralDay(r.completedUtc||r.synced||r.cancelled||'');
    const dates=[...new Set(rows.map(dateOf).filter(Boolean))].sort().reverse();select.replaceChildren();
    for(const [v,label] of [['today','Today (Central Time)'],['all','All dates'],...dates.map(d=>[d,d])]){const option=node('option',label);option.value=v;select.append(option);}select.value=value;if(!select.value)select.value='today';
    const day=select.value==='today'?centralDay(Date.now()):select.value;
    return rows.filter(r=>!['Complete','Cancelled'].includes(r.status)||select.value==='all'||dateOf(r)===day);
  }
  const pending=r=>['Queued','Waiting'].includes(r.status);
  const dollars=v=>v===undefined?'—':new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(v);
  async function action(name,body={}){
    if(mutating)return;mutating=true;render();
    try{const result=await api('/api/queue/'+name,body);if(name==='start')toast(result.startedCount||0);await poll();}
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
    renderTable('trading-queue-table',tradingRows(),false);
    const activity=el('queue-activity');activity.replaceChildren();
    for(const r of [...data.rows,...(data.history||[])].slice().reverse()){
      if(!r.message)continue;const item=node('div');item.className='event';item.append(node('span',r.id+' · '+r.status+' · '+r.message));activity.append(item);
    }
    renderDetail();updateButtons();
  }
  function resizeColumns(table){
    let widths={};try{widths=JSON.parse(localStorage.getItem('pair-widths-'+table.id))||{};}catch(_){}
    table.style.tableLayout='fixed';
    [...table.querySelectorAll('th')].forEach((th,i)=>{
      if(widths[i])th.style.width=widths[i]+'px';th.style.position='relative';
      const handle=node('span');handle.onclick=e=>e.stopPropagation();handle.className='column-resizer';handle.title='Drag to resize column';
      handle.onpointerdown=e=>{resizing=true;e.preventDefault();e.stopPropagation();const start=e.clientX,width=th.getBoundingClientRect().width;handle.setPointerCapture(e.pointerId);
        handle.onpointermove=ev=>{widths[i]=Math.max(65,width+ev.clientX-start);th.style.width=widths[i]+'px';try{localStorage.setItem('pair-widths-'+table.id,JSON.stringify(widths));}catch(_){}};
        handle.onpointerup=handle.onpointercancel=()=>{resizing=false;handle.onpointermove=null;};};th.append(handle);
    });
  }
  function sortValue(r,column){
    const s=r.spec,slot=column<5?s.left:s.right;
    if(column===1)return r.id;
    if(column===2||column===4){const id=column===2?s.left:s.right;return id?`${s.masters[id]} / ${s.accounts[id]}`:null;}
    if(column===3||column===5)return slot?((r.after?.[slot]||r.before?.[slot])?.balance??s.balances?.[slot]??null):null;
    if(column===6)return `${s.ticker} · ${s.quantities[s.left]??''} / ${s.quantities[s.right]??''}`;
    if(column===7)return r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status;
    if(column===8||column===9)return r.results?.[column===8?s.left:s.right]??null;
    const time=Date.parse(r.completedUtc||r.synced||r.cancelled||'');return Number.isFinite(time)?time:null;
  }
  function sortedRows(rows){
    return rows.slice().sort((a,b)=>{
      const x=sortValue(a,sortColumn),y=sortValue(b,sortColumn);
      if(x===null||y===null)return x===y?b.id.localeCompare(a.id,undefined,{numeric:true}):x===null?1:-1;
      const result=typeof x==='number'&&typeof y==='number'?x-y:String(x).localeCompare(String(y),undefined,{numeric:true,sensitivity:'base'});
      return result*sortDirection||b.id.localeCompare(a.id,undefined,{numeric:true});
    });
  }
  function renderTable(id,rows,isPlanning){
    const table=el(id);table.replaceChildren();const head=node('thead'),hr=node('tr');
    if(!isPlanning)rows=sortedRows(rows);
    for(const [column,label] of ['Select','Pair ID','Left master / account','Left balance','Right master / account','Right balance','Instrument / Qty','Status','Left P&L','Right P&L','Completed Time','Actions'].entries()){
      const th=node('th');
      if(!isPlanning&&column>0&&column<11){
        th.setAttribute('aria-sort',column===sortColumn?(sortDirection===1?'ascending':'descending'):'none');
        const button=node('button',label+(column===sortColumn?(sortDirection===1?' ▲':' ▼'):''));button.className='column-sort';
        button.onclick=()=>{sortDirection=column===sortColumn?-sortDirection:column===10?-1:1;sortColumn=column;render();};th.append(button);
      }else th.textContent=label;
      hr.append(th);
    }
    head.append(hr);table.append(head);const body=node('tbody');
    for(const r of rows){
      const tr=node('tr'),s=r.spec,selection=node('td');tr.dataset.pair=r.id;if(!isPlanning){tr.classList.add('pair-select-row');tr.onclick=e=>{if(e.target.closest('button,input'))return;detailId=r.id;if(r.pairId)selectView(r.pairId);renderDetail();};}
      if(removable(r)){const box=node('input');box.type='checkbox';box.checked=selected.has(r.id);box.disabled=mutating;box.setAttribute('aria-label','Select '+r.id);box.onchange=()=>{box.checked?selected.add(r.id):selected.delete(r.id);updateButtons();};selection.append(box);}
      tr.append(selection,node('td',r.localDraft?'Draft':r.id));
      for(const side of ['left','right']){const slot=s[side];if(!slot){tr.append(node('td','—'),node('td','—'));continue;}tr.append(node('td',`${s.masters[slot]} / ${s.accounts[slot]}`),node('td',dollars(((r.after?.[slot]||r.before?.[slot])?.balance ?? s.balances?.[slot]))));}
      tr.append(node('td',`${(!s.left||!s.right)?'Single Pair · ':''}${s.ticker} · ${s.quantities[s.left]??'—'} / ${s.quantities[s.right]??'—'}`));
      const label=r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status;
      const status=node('td'),phase=node('span',label);phase.className='pair-phase '+r.status.toLowerCase().replaceAll(' ','-');status.append(phase);tr.append(status);
      for(const slot of [s.left,s.right]){const v=r.results?.[slot],td=node('td',dollars(v));td.className=v>0?'queue-win':v<0?'queue-loss':'';tr.append(td);}
      const completed=r.completedUtc||r.synced||r.cancelled;tr.append(node('td',completed?new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',year:'numeric',month:'2-digit',day:'2-digit',hour:'numeric',minute:'2-digit',second:'2-digit',timeZoneName:'short'}).format(new Date(completed)):''));
      const actions=node('td');actions.className='pair-actions';appendActions(actions,r);
      tr.append(actions);body.append(tr);
    }
    if(!rows.length){const tr=node('tr'),td=node('td',isPlanning?'No waiting plans. Build a pair to add one.':'Start Queue in Planning to see pairing, completed, and canceled pairs here.');td.colSpan=12;tr.append(td);body.append(tr);}
    table.append(body);resizeColumns(table);
  }
  function appendActions(target,r){
    const add=(label,name,extra={},blue=false)=>{const b=node('button',label);b.className=blue?'duplicate-button':'quiet';b.disabled=mutating;b.onclick=()=>action(name,{id:r.id,...extra});target.append(b);};
    if(r.localDraft&&r.draft){const b=node('button','Edit');b.className='quiet';b.disabled=mutating;b.onclick=async()=>{try{const result=await api('/api/queue/edit-draft',{id:r.id});window.dispatchEvent(new CustomEvent('edit-local-draft',{detail:result.draft.draft}));await poll();}catch(e){el('queue-status').textContent=e.message;}};target.append(b);}
    if(r.status==='Awaiting results'||(r.status==='Error'&&r.closed))add('Skip Results','skip-results');
    if(pending(r)){if(r.duplicateOf&&!r.dispatched)add('Start','start-one');add('Cancel','cancel');}
    if(r.status==='Removing')add('Cancel','cancel');
    if(r.status==='Error'){
      if(!r.started||r.canRetryReadiness)add('Retry','retry-prepare');
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
    const host=el('compact-pair'),rows=tradingRows();host.replaceChildren();
    const r=rows.find(r=>r.id===detailId)||rows[rows.length-1];host.hidden=!r;if(!r)return;
    const s=r.spec,label=r.status==='Awaiting results'?'Trade closed · Syncing results':r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status;
    host.append(node('h3',r.id+' · '+s.ticker+' · '+label));
    const cards=node('div');cards.className='compact-cards';
    const ratio=(s.ratio||'1:1').split(':').map(Number),factor=ratio[1]/ratio[0];
    for(const side of ['left','right']){
      const slot=s[side];if(!slot)continue;const card=node('article');card.className='compact-account';
      const direction=(side==='left')===(s.direction==='buy')?'Buy':'Sell';
      card.append(node('strong',(s.masters[slot]||s.names[slot])+' · '+direction),node('div',s.accounts[slot]));
      const f=s.metrics?.[slot]||{},dd=typeof f.RealDrawdown==='number'&&Number.isFinite(f.RealDrawdown)?f.RealDrawdown:undefined;const current=r.after?.[slot]||r.before?.[slot]||{},pnl=current.pnl??f['Realized PnL'];
      const line=node('div','Current Balance: '+dollars(current.balance??s.balances?.[slot])+' · '),realized=node('span','Realized P&L: '+dollars(pnl??undefined));realized.className='realized-pnl '+(pnl>0?'queue-win':pnl<0?'queue-loss':'');line.append(realized);card.append(line);
      const metrics=node('div','Drawdown: '+dollars(dd)+' · Largest profit day: '+dollars(f.largestProfitDay??undefined)+' · Trading days: '+(f.tradingDays??'—'));metrics.className='pair-secondary-metrics';card.append(metrics);
      const note=String(Object.entries(f).find(([k])=>k.replace(/[^a-z]/gi,'').toLowerCase()==='scrapernote')?.[1]??'').trim();if(note){const n=node('div',note);n.className='pair-scraper-note';card.append(n);}
      card.append(node('div','Quantity: '+s.quantities[slot]+' · Ratio: '+(s.ratio||'1:1')));
      card.append(node('div','Profit: '+dollars(side==='left'?s.profit:s.stopLoss*factor)+' · Stop: '+dollars(side==='left'?s.stopLoss:s.profit*factor)));
      const result=node('div','Result: '+dollars(r.results?.[slot]));result.className=r.results?.[slot]>0?'queue-win':r.results?.[slot]<0?'queue-loss':'';card.append(result);cards.append(card);
    }
    host.append(cards);const actions=node('div');actions.className='pair-actions';appendActions(actions,r);host.append(actions);
  }
  async function poll(){if(busy||resizing)return;busy=true;try{data=await api('/api/queue');render();window.dispatchEvent(new CustomEvent('queue-updated',{detail:data}));}catch(e){el('queue-status').textContent=e.message;}finally{busy=false;}}
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
  el('trading-date').onchange=()=>render();
  el('trading-refresh').onclick=()=>action('refresh');
  el('trading-resume').onclick=()=>action('resume');el('trading-pause').onclick=()=>action('pause');el('trading-retry').onclick=()=>action('retry');
  el('queue-start').onclick=()=>action('start');el('queue-pause').onclick=()=>action('pause');el('queue-retry').onclick=()=>action('retry');
  window.addEventListener('queue-refresh',poll);setInterval(poll,3000);poll();
})();
