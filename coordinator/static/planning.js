'use strict';
(() => {
  const key='planning-viw6K3jRjU5PJpWM4-v1';
  function display(value){
    if(value==null)return '';
    if(Array.isArray(value))return value.map(display).join(', ');
    if(typeof value==='object')return value.name || value.filename || value.url || JSON.stringify(value);
    return String(value);
  }
  function ordered(rows,layout,columns){
    const ranks=new Map(layout.order.map((id,i)=>[id,i]));
    const result=rows.slice().sort((a,b)=>(ranks.get(a.id)??Infinity)-(ranks.get(b.id)??Infinity));
    if(!layout.sort)return result;
    const name=layout.sort.name, type=columns.find(c=>c.name===name)?.type || 'auto';
    return result.sort((a,b)=>{
      const av=a.fields[name],bv=b.fields[name],as=display(av),bs=display(bv);
      if(!as||!bs)return as? -1 : bs?1:0;
      let cmp;
      if(typeof av==='number'&&typeof bv==='number')cmp=av-bv;
      else if(['number','currency','percent','duration','rating','count','autoNumber'].includes(type)&&Number.isFinite(Number(as))&&Number.isFinite(Number(bs)))cmp=Number(as)-Number(bs);
      else if(['date','dateTime','createdTime','lastModifiedTime'].includes(type)&&Number.isFinite(Date.parse(as))&&Number.isFinite(Date.parse(bs)))cmp=Date.parse(as)-Date.parse(bs);
      else cmp=as.localeCompare(bs,undefined,{numeric:true,sensitivity:'base'});
      return cmp*layout.sort.direction;
    });
  }
  function reconcile(order,rows){return [...new Set([...order,...rows.map(r=>r.id)])];}
  if(typeof module!=='undefined'&&module.exports){module.exports={display,ordered,reconcile};return;}
  const el=id=>document.getElementById(id);
  const selected=new Set();let usage={};
  window.planningSelection={rows:()=>data.rows.filter(r=>selected.has(r.id)),clear:()=>{selected.clear();renderTable();}};
  window.addEventListener('account-usage',e=>{usage=e.detail;decorate();});
  function decorate(){
    for(const tr of el('planning-table').querySelectorAll('tbody tr[data-record]')){
      const u=usage[tr.dataset.account]||{};tr.classList.toggle('account-used',!!u.used);
      const td=tr.querySelector('.usage-cell');if(!td)continue;td.replaceChildren();
      if(u.status){const badge=document.createElement('span');badge.className='account-badge '+u.status.toLowerCase();badge.textContent=u.status;td.append(badge);}
    }
  }
  let layout={hidden:[],order:[],columns:[],sort:null};
  try{
    const saved=JSON.parse(localStorage.getItem(key));
    if(saved&&Array.isArray(saved.hidden)&&Array.isArray(saved.order))layout={hidden:saved.hidden,order:saved.order,columns:Array.isArray(saved.columns)?saved.columns:[],sort:saved.sort||null};
  }catch(_){}
  let data={rows:[],columns:[]},lastUpdate=null,dragId='',polling=false,signature=null,eventTimer=null;
  function save(){try{localStorage.setItem(key,JSON.stringify(layout));}catch(_){el('planning-status').textContent='Browser storage is unavailable; layout will last for this session.';}}
  function node(tag,text){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
  function move(id,target){
    if(layout.sort||id===target)return;
    const ids=ordered(data.rows,layout,data.columns).map(r=>r.id),from=ids.indexOf(id),to=ids.indexOf(target);
    if(from<0||to<0)return;
    ids.splice(from,1);ids.splice(to,0,id);layout.order=ids;save();renderTable();
  }
  function columnOrder(){
    const ranks=new Map(layout.columns.map((name,i)=>[name,i]));
    return data.columns.slice().sort((a,b)=>(ranks.get(a.name)??(a.name==='id'?-1:Infinity))-(ranks.get(b.name)??(b.name==='id'?-1:Infinity)));
  }
  function moveColumn(name,target){
    const names=columnOrder().map(c=>c.name),from=names.indexOf(name),to=names.indexOf(target);
    if(from<0||to<0||from===to)return;
    names.splice(from,1);names.splice(to,0,name);layout.columns=names;save();renderColumns();renderTable();
  }
  function renderColumns(){
    const container=el('planning-columns');container.replaceChildren();
    for(const column of columnOrder()){
      const label=node('label'),box=node('input');box.type='checkbox';box.checked=column.name==='id'||!layout.hidden.includes(column.name);box.disabled=column.name==='id';
      box.onchange=()=>{layout.hidden=layout.hidden.filter(n=>n!==column.name);if(!box.checked)layout.hidden.push(column.name);save();renderTable();};
      label.append(box,document.createTextNode(' '+column.name));container.append(label);
      const names=columnOrder().map(c=>c.name),i=names.indexOf(column.name);
      for(const [text,delta] of [['←',-1],['→',1]]){
        const move=node('button',text);move.className='quiet';move.disabled=!names[i+delta];move.setAttribute('aria-label','Move '+column.name+' column '+(delta<0?'earlier':'later'));
        move.onclick=()=>moveColumn(column.name,names[i+delta]);container.append(move);
      }
    }
  }
  function renderTable(){
    const table=el('planning-table');table.replaceChildren();
    const cols=columnOrder().filter(c=>c.name==='id'||!layout.hidden.includes(c.name));
    const head=node('thead'),hr=node('tr');hr.append(node('th','Select'),node('th','Order'));
    for(const c of cols){
      if(c.name==='id')hr.append(node('th','Pair status'));
      const th=node('th'),active=layout.sort?.name===c.name;
      th.setAttribute('aria-sort',active?(layout.sort.direction===1?'ascending':'descending'):'none');
      const b=node('button',c.name+(active?(layout.sort.direction===1?' ↑':' ↓'):''));b.className='quiet';
      b.onclick=()=>{layout.sort={name:c.name,direction:active?-layout.sort.direction:1};save();renderTable();};th.append(b);th.draggable=true;
      th.ondragstart=e=>{e.dataTransfer.setData('application/x-planning-column',c.name);};
      th.ondragover=e=>{if(Array.from(e.dataTransfer.types).includes('application/x-planning-column'))e.preventDefault();};
      th.ondrop=e=>{e.preventDefault();moveColumn(e.dataTransfer.getData('application/x-planning-column'),c.name);};hr.append(th);
    }
    head.append(hr);table.append(head);const body=node('tbody');
    const rows=ordered(data.rows,layout,data.columns);
    rows.forEach((row,i)=>{
      const tr=node('tr');tr.draggable=!layout.sort;tr.dataset.record=row.id;tr.dataset.account=display(row.fields.id);
      const select=node('td'),box=node('input');box.type='checkbox';box.checked=selected.has(row.id);box.setAttribute('aria-label','Select '+display(row.fields.id));
      box.onchange=()=>{if(box.checked)selected.add(row.id);else selected.delete(row.id);};select.className='account-select';select.append(box);tr.append(select);
      tr.ondragstart=e=>{dragId=row.id;e.dataTransfer.setData('text/plain',row.id);e.dataTransfer.effectAllowed='move';};
      tr.ondragover=e=>{if(!layout.sort)e.preventDefault();};
      tr.ondrop=e=>{e.preventDefault();move(dragId,row.id);dragId='';};
      const order=node('td');order.className='row-order';order.append(node('span',String(i+1)));
      for(const [label,delta] of [['↑',-1],['↓',1]]){
        const b=node('button',label);b.className='quiet';b.disabled=!!layout.sort||!rows[i+delta];b.setAttribute('aria-label',`Move row ${i+1} ${delta<0?'up':'down'}`);
        b.onclick=()=>{move(row.id,rows[i+delta].id);const buttons=table.querySelectorAll('tbody tr');buttons[i+delta]?.querySelector('button')?.focus();};order.append(b);
      }
      const usageCell=node('td');usageCell.className='usage-cell';tr.append(order);for(const c of cols){if(c.name==='id')tr.append(usageCell);tr.append(node('td',display(row.fields[c.name])));}body.append(tr);
    });
    if(!rows.length){const tr=node('tr'),td=node('td',data.updatedAt?'No accounts in this Airtable view.':'Refresh Planning or open Airtable setup to load accounts.');td.colSpan=cols.length+3;tr.append(td);body.append(tr);}
    table.append(body);decorate();el('planning-manual').textContent=layout.sort?'Return to Manual Order':'Manual Order ✓';
  }
  async function poll(){
    if(polling)return;polling=true;
    try{
      const snapshot=await api('/api/planning');data=snapshot;
      window.dispatchEvent(new CustomEvent('planning-accounts-updated',{detail:data.rows}));
      el('planning-refresh').disabled=!!data.busy;
      el('planning-status').textContent=`${data.rows.length} accounts · ${data.updatedAt?'Updated '+new Date(data.updatedAt*1000).toLocaleString():'Not loaded yet'}${data.busy?' · Refreshing…':''}${data.error?' · '+data.error:''}`;
      if(el('planning-dialog').open)el('planning-setup-status').textContent=data.busy?'Checking Airtable…':data.error||(data.configured?'Airtable connected.':'');
      if(lastUpdate!==data.updatedAt){lastUpdate=data.updatedAt;layout.order=reconcile(layout.order,data.rows);save();renderColumns();renderTable();}
    }catch(e){el('planning-status').textContent='Planning: '+e.message;}finally{polling=false;}
  }
  async function refresh(body={}){
    el('planning-refresh').disabled=true;el('planning-status').textContent='Requesting latest Airtable data…';
    try{await api('/api/planning/refresh',body);await poll();}catch(e){el('planning-status').textContent=e.message;el('planning-setup-status').textContent=e.message;el('planning-refresh').disabled=false;}
  }
  for(const tab of ['trading','planning'])el('tab-'+tab).onclick=()=>{
    for(const name of ['trading','planning']){el(name+'-panel').hidden=name!==tab;el('tab-'+name).setAttribute('aria-selected',String(name===tab));}
    document.querySelector('main').classList.toggle('planning-wide',tab==='planning');
    if(tab==='planning')poll();
  };
  el('planning-refresh').onclick=()=>refresh();
  el('planning-manual').onclick=()=>{layout.sort=null;save();renderTable();};
  el('planning-setup').onclick=()=>el('planning-dialog').showModal();
  el('planning-cancel').onclick=()=>{el('planning-token').value='';el('planning-dialog').close();};
  el('planning-dialog').addEventListener('close',()=>{el('planning-token').value='';});
  el('planning-save').onclick=async()=>{
    const value=el('planning-token').value.trim();el('planning-token').value='';el('planning-save').disabled=true;
    try{await refresh({token:value});}finally{el('planning-save').disabled=false;}
  };
  window.addEventListener('fleet-updated',e=>{
    const s=e.detail;
    const next=JSON.stringify([...(s.fleet||[]).map(a=>[a.id,a.sync]),...(s.pairs||[]).map(p=>[p.id,p.closedSequence])]);
    if(signature!==null&&signature!==next){clearTimeout(eventTimer);eventTimer=setTimeout(()=>refresh(),1500);}
    signature=next;
  });
  renderTable();poll();setInterval(poll,3000);
})();
