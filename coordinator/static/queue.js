'use strict';
(() => {
  const el=id=>document.getElementById(id), node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  let fleet=[],data={rows:[]},busy=false,resizing=false,dragging=false,detailId='';const duplicateKeys=new Map();
  let sortColumn=10,sortDirection=-1;
  const statusFilters=new Set(),tableCache=new Map();let visibleLimit=250,dateOptionsKey='',sessionInitialized=false,lastSnapshot=null,lastQueueEvent='',dayKey=null;
  const statusName=r=>r.status==='Trading'?'Pairing':r.status==='Cancelled'?'Canceled':r.status==='Error'?'Errored':r.status;
  const selected=new Set(),saving=new Map(),acknowledged=new Map(),starting=new Set();let mutating=false,toastTimer;
  function toast(count){const box=el('queue-toast');clearTimeout(toastTimer);box.textContent=count?`${count} ${count===1?'pair':'pairs'} started in the queue successfully.`:'No new pairs to start.';box.hidden=false;toastTimer=setTimeout(()=>{box.hidden=true;},5000);}
  const centralDay=value=>{const date=new Date(value);if(!Number.isFinite(date.getTime()))return '';const parts=new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);return ['year','month','day'].map(t=>parts.find(p=>p.type===t).value).join('-');};
  function tradingRows(){
    const rows=[...data.rows.filter(r=>!planned(r)||starting.has(r.key)),...(data.history||[])],select=el('trading-date');
    if(!sessionInitialized){sessionInitialized=true;if(data.activeSession)select.dataset.session=data.activeSession;}
    const value=select.dataset?.session?'session:'+select.dataset.session:select.value||'today';
    if(select.dataset)delete select.dataset.session;
    const dateOf=r=>centralDay(r.completedUtc||r.synced||r.cancelled||r.dispatchedAt||r.created||'');
    const dates=[...new Set(rows.map(dateOf).filter(Boolean))].sort().reverse();
    const options=[['today','Today (Central Time)'],['all','All dates'],...(data.sessions||[]).slice().reverse().map(s=>['session:'+s.id,new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',month:'2-digit',day:'2-digit',year:'numeric',hour:'numeric',minute:'2-digit',second:'2-digit'}).format(new Date(s.startedAt))+' · Session']),...dates.map(d=>[d,d])];
    const key=JSON.stringify(options);if(key!==dateOptionsKey){dateOptionsKey=key;select.replaceChildren();for(const [v,label] of options){const option=node('option',label);option.value=v;select.append(option);}}
    select.value=value;if(!select.value)select.value='today';
    if(select.value.startsWith('session:')){const id=select.value.slice(8);return rows.filter(r=>r.sessionId===id);}
    const day=select.value==='today'?centralDay(Date.now()):select.value;
    return rows.filter(r=>!['Complete','Cancelled'].includes(r.status)||select.value==='all'||dateOf(r)===day);
  }
  function progress(rows){
    const counts={complete:0,pairing:0,waiting:0,error:0,awaiting:0};
    for(const r of rows){if(r.status==='Cancelled')continue;if(r.status==='Complete')counts.complete++;
      else if(r.status==='Error')counts.error++;else if(['Queued','Waiting'].includes(r.status))counts.waiting++;
      else if(r.status==='Awaiting results')counts.awaiting++;else counts.pairing++;}
    const total=Object.values(counts).reduce((a,b)=>a+b,0),percent=total?Math.round(100*counts.complete/total):0;
    const host=el('progress-counts');host.replaceChildren();
    for(const [label,cls] of [[`${counts.complete} out of ${total} complete`,'queue-win'],[`${counts.pairing} pairing`,'progress-pairing-text'],[`${counts.waiting} waiting`,'progress-waiting-text'],...(counts.error?[[`${counts.error} ${counts.error===1?'error':'errors'}`,'progress-errors']]:[]),...(counts.awaiting?[[`${counts.awaiting} awaiting results`,'progress-waiting-text']]:[])]){const n=node('span',label);n.className=cls;host.append(n);}
    el('progress-percent').textContent=percent+'%';const track=el('progress-track');track.setAttribute('aria-valuenow',String(percent));track.setAttribute('aria-valuetext',`${counts.complete} of ${total} complete, ${counts.pairing} pairing, ${counts.waiting} waiting, ${counts.error} errors, ${counts.awaiting} awaiting results`);
    for(const name of ['complete','pairing','waiting','error'])track.querySelector('.progress-'+name).style.width=(total?counts[name]*100/total:0)+'%';
  }
  const pending=r=>['Queued','Waiting'].includes(r.status);
  const dollars=v=>v==null?'—':new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(v);
  async function action(name,body={}){
    if(mutating)return;mutating=true;render();
    try{const result=await api('/api/queue/'+name,body);if(['cancel','remove-selected','resolve'].includes(name)){const ids=body.ids||[body.id];for(const row of data.rows)if(ids.includes(row.id))acknowledged.delete(row.key);}if(name==='start')toast(result.startedCount||0);await poll();}
    catch(e){data.message=e.message;el('queue-status').textContent=el('trading-queue-status').textContent=e.message;}
    finally{mutating=false;render();}
  }
  const removable=r=>pending(r)||r.status==='Removing';
  const planned=r=>!r.dispatched&&!r.duplicateOf&&(pending(r)||r.status==='Removing');
  function updateButtons(){
    el('trading-refresh').disabled=mutating;
    const anyPlans=data.rows.some(r=>planned(r)&&!starting.has(r.key));
    el('queue-start').disabled=mutating||!anyPlans;
    el('trading-pause').disabled=mutating||!data.running;
    el('trading-resume').disabled=mutating||data.running||!data.rows.some(r=>r.dispatched&&!['Complete','Cancelled'].includes(r.status));
    for(const [id,isPlanning] of [['queue-remove-selected',true],['trading-remove-selected',false]])
      el(id).disabled=mutating||!data.rows.some(r=>planned(r)===isPlanning&&removable(r)&&selected.has(r.id));
  }
  function render(){
    el('queue-status').textContent=el('trading-queue-status').textContent=(data.running?'Running · ':'Paused · ')+data.message;
    const valid=new Set(data.rows.filter(removable).map(r=>r.id));for(const id of selected)if(!valid.has(id))selected.delete(id);
    if(!el('planning-panel').hidden)renderTable('queue-table',[...data.rows.filter(r=>planned(r)&&!starting.has(r.key)),...saving.values()].filter((r,i,rs)=>rs.findIndex(x=>(x.key||x.id)===(r.key||r.id))===i),true);
    el('trading-retry').hidden=!data.rows.some(r=>!r.localDraft&&r.dirty&&(r.closed||r.released22||r.afterId||['Complete','Cancelled'].includes(r.status)));
    const sessionRows=tradingRows();
    if(!el('trading-panel').hidden){
    progress(sessionRows);
    const filtered=sessionRows.filter(r=>!statusFilters.size||statusFilters.has(statusName(r)));
    renderTable('trading-queue-table',sortedRows(filtered).slice(0,visibleLimit),false);
    el('trading-load-more').hidden=filtered.length<=visibleLimit;
    const activity=el('queue-activity');activity.replaceChildren();
    for(const r of sessionRows.slice().reverse().slice(0,100)){
      if(!r.message)continue;const item=node('div');item.className='event';item.append(node('span',r.id+' · '+r.status+' · '+r.message));activity.append(item);
    }
    }
    updateButtons();
  }
  function resizeColumns(table){
    let widths={};try{widths=JSON.parse(localStorage.getItem('pair-widths-'+table.id))||{};}catch(_){}
    table.style.tableLayout='fixed';
    [...table.querySelectorAll('th')].forEach(th=>{const i=Number(th.dataset.column);
      if(widths[i])th.style.width=widths[i]+'px';th.style.position='relative';
      const handle=node('span');handle.onclick=e=>e.stopPropagation();handle.className='column-resizer';handle.title='Drag to resize column';
      handle.onpointerdown=e=>{resizing=true;th.draggable=false;e.preventDefault();e.stopPropagation();const start=e.clientX,width=th.getBoundingClientRect().width;handle.setPointerCapture(e.pointerId);
        handle.onpointermove=ev=>{widths[i]=Math.max(65,width+ev.clientX-start);th.style.width=widths[i]+'px';try{localStorage.setItem('pair-widths-'+table.id,JSON.stringify(widths));}catch(_){}};
        handle.onpointerup=handle.onpointercancel=()=>{resizing=false;th.draggable=table.id==='trading-queue-table';handle.onpointermove=null;};};th.append(handle);
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
  const columnLabels=['Select','Pair ID','Left master / account','Left balance','Right master / account','Right balance','Instrument / Qty','Status','Left P&L','Right P&L','Completed Time','Actions'];
  function columnOrder(id){let saved=[];try{saved=JSON.parse(localStorage.getItem('pair-column-order-'+id))||[];}catch(_){}return [...new Set([...(Array.isArray(saved)?saved:[]).filter(n=>Number.isInteger(n)&&n>=0&&n<12),...columnLabels.map((_,i)=>i)])];}
  function tradeSettings(s,side){
    const [a,b]=String(s.ratio||'1:1').split(':').map(Number),factor=a>0&&b>0?b/a:1;
    const values=side==='right'?[Number(s.stopLoss)*factor,Number(s.profit)*factor]:[Number(s.profit),Number(s.stopLoss)];
    const money=v=>Number.isFinite(v)?new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',minimumFractionDigits:0,maximumFractionDigits:2}).format(Math.round((v+Number.EPSILON)*100)/100):'—';
    return 'P '+money(values[0])+' L '+money(values[1]);
  }
  function renderTable(id,rows,isPlanning){
    const table=el(id);const head=node('thead'),hr=node('tr');
    if(!isPlanning)rows=sortedRows(rows);
    const order=isPlanning?[0,1,2,3,4,5,6,7,11]:columnOrder(id);
    let cache=tableCache.get(id);if(!cache){cache={rows:new Map()};tableCache.set(id,cache);}
    const headKey=JSON.stringify([order,sortColumn,sortDirection]);
    if(cache.headKey!==headKey){
    table.querySelector('thead')?.remove();
    for(const column of order){
      const label=columnLabels[column],th=node('th');th.dataset.column=column;
      if(!isPlanning){th.draggable=true;th.title='Drag to rearrange column';
        th.ondragstart=e=>{dragging=true;e.dataTransfer.setData('application/x-pair-column',JSON.stringify({id,column}));};
        th.ondragend=()=>{dragging=false;};
        th.ondragover=e=>{if(Array.from(e.dataTransfer.types).includes('application/x-pair-column'))e.preventDefault();};
        th.ondrop=e=>{e.preventDefault();dragging=false;let source;try{source=JSON.parse(e.dataTransfer.getData('application/x-pair-column'));}catch(_){return;}if(source.id!==id||!order.includes(source.column)||source.column===column)return;const next=order.slice();next.splice(next.indexOf(source.column),1);next.splice(order.indexOf(column),0,source.column);try{localStorage.setItem('pair-column-order-'+id,JSON.stringify(next));}catch(_){}render();};
      }
      if(!isPlanning&&column>0&&column<11){
        th.setAttribute('aria-sort',column===sortColumn?(sortDirection===1?'ascending':'descending'):'none');
        const button=node('button',label+(column===sortColumn?(sortDirection===1?' ▲':' ▼'):''));button.className='column-sort';
        button.onclick=()=>{sortDirection=column===sortColumn?-sortDirection:column===10?-1:1;sortColumn=column;render();};th.append(button);
      }else th.textContent=label;
      if(!isPlanning&&column===7){
        const details=node('details');details.className='status-filter';const summary=node('summary',statusFilters.size?'Filter ('+statusFilters.size+')':'Filter');details.append(summary);const menu=node('div');menu.className='status-filter-menu';
        for(const name of ['All','Queued','Waiting','Preparing','Pairing','Complete','Awaiting results','Errored','Canceled','Removing']){const label=node('label'),box=node('input');box.type='checkbox';box.checked=name==='All'?!statusFilters.size:statusFilters.has(name);box.onchange=()=>{if(name==='All')statusFilters.clear();else box.checked?statusFilters.add(name):statusFilters.delete(name);for(const x of menu.querySelectorAll('input'))x.checked=x.dataset.status==='All'?!statusFilters.size:statusFilters.has(x.dataset.status);summary.textContent=statusFilters.size?'Filter ('+statusFilters.size+')':'Filter';visibleLimit=250;render();};box.dataset.status=name;label.append(box,document.createTextNode(name));menu.append(label);}details.append(menu);details.ondragstart=e=>e.preventDefault();details.onclick=e=>e.stopPropagation();th.append(details);
      }
      hr.append(th);
    }
    head.append(hr);table.prepend(head);cache.headKey=headKey;cache.rows.clear();table.querySelector('tbody')?.replaceChildren();resizeColumns(table);
    }
    let body=table.querySelector('tbody');if(!body){body=node('tbody');table.append(body);}
    const keep=new Set();let position=0;
    for(const empty of body.querySelectorAll('.queue-empty'))empty.remove();
    for(const r of rows){
      const key=r.key||r.id,signature=JSON.stringify([r,mutating,selected.has(r.id),starting.has(r.key),order]);keep.add(key);
      const old=cache.rows.get(key);if(old?.signature===signature){if(body.children[position]!==old.tr)body.insertBefore(old.tr,body.children[position]||null);position++;continue;}
      const tr=node('tr'),s=r.spec,selection=node('td');tr.dataset.pair=r.id;tr.dataset.key=r.key||'';
      if(removable(r)){const box=node('input');box.type='checkbox';box.checked=selected.has(r.id);box.disabled=mutating;box.setAttribute('aria-label','Select '+r.id);box.onchange=()=>{box.checked?selected.add(r.id):selected.delete(r.id);updateButtons();};selection.append(box);}
      tr.append(selection,node('td',r.localDraft?'Draft':r.id.replace(/^PAIR-/, '')));
      for(const side of ['left','right']){const slot=s[side];if(!slot){tr.append(node('td','—'),node('td','—'));continue;}
        const balance=node('td',dollars(((r.after?.[slot]||r.before?.[slot])?.balance ?? s.balances?.[slot]))),settings=node('small');settings.className='pair-settings';
        const [profit,loss]=tradeSettings(s,side).split(' L ');const p=node('span',profit),l=node('span','L '+loss);p.className='queue-win';l.className='queue-loss';settings.append(p,document.createTextNode(' '),l);balance.append(settings);
        const account=node('td');account.append(node('div',s.masters[slot]||s.names?.[slot]||'—'));const number=node('small',s.accounts[slot]);number.className='pair-account-number';account.append(number);tr.append(account,balance);
      }
      tr.append(node('td',`${s.ticker.split(' ')[0]} ${s.quantities[s.left]??'—'}/${s.quantities[s.right]??'—'}`));
      const label=starting.has(r.key)?'Starting…':statusName(r);
      const status=node('td'),phase=node('span',label);phase.className='pair-phase '+r.status.toLowerCase().replaceAll(' ','-');status.append(phase);tr.append(status);
      for(const slot of [s.left,s.right]){const v=r.results?.[slot],td=node('td',dollars(v));td.className=v>0?'queue-win':v<0?'queue-loss':'';tr.append(td);}
      const completed=r.completedUtc||r.synced||r.cancelled,completedCell=node('td');
      if(completed){const date=new Date(completed);if(Number.isFinite(date.getTime())){completedCell.append(node('div',new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',year:'numeric',month:'2-digit',day:'2-digit'}).format(date)),node('div',new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',hour:'numeric',minute:'2-digit',second:'2-digit'}).format(date)));}}
      tr.append(completedCell);
      const actions=node('td');actions.className='pair-actions';appendActions(actions,r);
      tr.append(actions);const cells=Array.from(tr.children);tr.replaceChildren();for(const column of order){cells[column].dataset.column=column;tr.append(cells[column]);}if(old)old.tr.remove();body.insertBefore(tr,body.children[position]||null);cache.rows.set(key,{signature,tr});position++;
    }
    for(const [key,entry] of cache.rows)if(!keep.has(key)){entry.tr.remove();cache.rows.delete(key);}
    if(!rows.length){const tr=node('tr');tr.className='queue-empty';const td=node('td',isPlanning?'No waiting plans. Build a pair to add one.':'Start Queue in Planning to see pairing, completed, and canceled pairs here.');td.colSpan=order.length;tr.append(td);body.append(tr);}

  }
  function appendActions(target,r){
    if(r.status==='Saving…'||starting.has(r.key))return;
    const add=(label,name,extra={},blue=false)=>{const b=node('button',label);b.className=blue?'duplicate-button':'quiet';b.disabled=mutating;b.onclick=()=>action(name,{id:r.id,...extra});target.append(b);};
    if(r.localDraft&&r.draft){const b=node('button','Edit');b.className='quiet';b.disabled=mutating;b.onclick=async()=>{try{const result=await api('/api/queue/edit-draft',{id:r.id});acknowledged.delete(r.key);window.dispatchEvent(new CustomEvent('edit-local-draft',{detail:result.draft.draft}));await poll();}catch(e){el('queue-status').textContent=e.message;}};target.append(b);}
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
      b.onclick=async()=>{if(!duplicateKeys.has(r.id))duplicateKeys.set(r.id,crypto.randomUUID().replaceAll('-',''));const key=duplicateKeys.get(r.id);await action('duplicate',{id:r.id,draftKey:key});if(data.rows.some(x=>x.key===key)){detailId=data.rows.find(x=>x.key===key).id;duplicateKeys.delete(r.id);}};target.append(b);
    }
  }
  async function poll(){if(busy||resizing||dragging)return;busy=true;try{const fresh=await api('/api/queue');
      for(const [key,row] of acknowledged){const seen=[...(fresh.rows||[]),...(fresh.history||[])].find(r=>r.key===key);if(seen&&(!row.dispatched||seen.dispatched))acknowledged.delete(key);else{fresh.rows=fresh.rows.filter(r=>r.key!==key);fresh.rows.push(row);}}
      if(fresh===lastSnapshot&&!acknowledged.size)return;lastSnapshot=fresh;data=fresh;render();const key=JSON.stringify(data);if(key!==lastQueueEvent){lastQueueEvent=key;window.dispatchEvent(new CustomEvent('queue-updated',{detail:data}));}}catch(e){el('queue-status').textContent=e.message;}finally{busy=false;}}
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
  el('trading-date').onchange=()=>{visibleLimit=250;render();};
  el('trading-load-more').onclick=()=>{visibleLimit+=250;render();};
  el('trading-start-day').onclick=async()=>{
    const button=el('trading-start-day');if(button.disabled)return;button.disabled=true;
    if(!dayKey)dayKey=crypto.randomUUID().replaceAll('-','');
    try{const result=await api('/api/queue/start-day',{key:dayKey});dayKey=null;await poll();data.sessions=[...(data.sessions||[]).filter(s=>s.id!==result.session.id),result.session];data.activeSession=result.session.id;el('trading-date').dataset.session=result.session.id;visibleLimit=250;render();}
    catch(e){el('trading-queue-status').textContent=e.message;}finally{button.disabled=false;}
  };
  window.addEventListener('control-tab-changed',()=>render());
  el('trading-refresh').onclick=()=>action('refresh');
  el('trading-resume').onclick=()=>action('resume');el('trading-pause').onclick=()=>action('pause');el('trading-retry').onclick=()=>action('retry');
  el('queue-start').onclick=async()=>{
    if(mutating)return;
    const keys=data.rows.filter(r=>planned(r)&&!starting.has(r.key)).map(r=>r.key);if(!keys.length)return;
    keys.forEach(k=>starting.add(k));mutating=true;render();
    try{const result=await api('/api/queue/start',{keys});
      for(const row of result.rows||[]){acknowledged.set(row.key,row);data.rows=data.rows.filter(r=>r.key!==row.key);data.rows.push(row);}
      toast(result.startedCount||0);await poll();}
    catch(e){await poll();data.message=e.message;}
    finally{keys.forEach(k=>starting.delete(k));mutating=false;render();}
  };
  window.addEventListener('queue-saving',e=>{
    const d=e.detail,s={left:d.left?'left':null,right:d.right?'right':null,ticker:d.ticker,ratio:d.ratio,profit:+d.profit,stopLoss:+d.stopLoss,accounts:{},masters:{},balances:{},quantities:{}};
    for(const side of ['left','right'])if(d[side]){s.accounts[side]=d[side].account;s.masters[side]=d[side].master;s.balances[side]=d[side].balance;s.quantities[side]=+d[side+'Quantity'];}
    saving.set(d.key,{id:'DRAFT-'+d.key,key:d.key,localDraft:true,status:'Saving…',spec:s});render();
  });
  window.addEventListener('queue-saved',e=>{
    const {key,row}=e.detail;saving.delete(key);
    if(row){acknowledged.set(key,row);data.rows=data.rows.filter(r=>r.key!==key);data.rows.push(row);}
    render();
  });
  window.addEventListener('queue-save-failed',e=>{saving.delete(e.detail.key);render();});
  window.addEventListener('queue-refresh',poll);setInterval(()=>{if(!document.hidden)poll();},3000);poll();
})();
