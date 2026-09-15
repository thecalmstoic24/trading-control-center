'use strict';
(() => {
  const defaultView='appzvICrv7LLlZdxm/tbl1u1mKMpVLmTqQP/viw6K3jRjU5PJpWM4';
  let viewKey=defaultView,key='planning-viw6K3jRjU5PJpWM4-v1',viewSignature='',requestGeneration=0;
  function display(value){
    if(value==null)return '';
    if(Array.isArray(value))return value.map(display).join(', ');
    if(typeof value==='object')return value.name || value.filename || value.url || JSON.stringify(value);
    return String(value);
  }
  function monetary(column){
    const name=column.name.replace(/[^a-z]/gi,'').toLowerCase();
    if(column.type==='percent'||/percent|percentage|ratio|days|date|time|count/.test(name))return false;
    return column.type==='currency'||/balance|pnl|profit|drawdown|payout|target|currency|amount/.test(name)||['stop','stoploss','stock'].includes(name);
  }
  function cellDisplay(value,column){
    if(monetary(column)&&value!==null&&value!==undefined&&value!==''&&['number','string'].includes(typeof value)){
      const numeric=typeof value==='number'?value:Number(value.replace(/[$,]/g,''));
      if(Number.isFinite(numeric))return new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(numeric);
    }
    return display(value);
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
  if(typeof module!=='undefined'&&module.exports){module.exports={display,ordered,reconcile,monetary,cellDisplay};return;}
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
  function loadLayout(){
    let result={hidden:[],order:[],columns:[],widths:{},split:65,sort:null};
    try{const saved=JSON.parse(localStorage.getItem(key));
      if(saved&&Array.isArray(saved.hidden)&&Array.isArray(saved.order))result={hidden:saved.hidden,order:saved.order,columns:Array.isArray(saved.columns)?saved.columns:[],widths:saved.widths&&typeof saved.widths==='object'?saved.widths:{},split:Number(saved.split)||65,sort:saved.sort||null};
    }catch(_){}return result;
  }
  let layout=loadLayout();
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
      box.onchange=()=>{if(box.checked)selected.add(row.id);else selected.delete(row.id);};
      let draggedRow=false;tr.onpointerdown=()=>{draggedRow=false;};
      tr.onclick=e=>{if(draggedRow||e.target.closest('input,button,a,select')||window.getSelection().toString())return;box.checked=!box.checked;box.onchange();};select.className='account-select';select.append(box);tr.append(select);
      tr.ondragstart=e=>{draggedRow=true;dragId=row.id;e.dataTransfer.setData('text/plain',row.id);e.dataTransfer.effectAllowed='move';};
      tr.ondragover=e=>{if(!layout.sort)e.preventDefault();};
      tr.ondrop=e=>{e.preventDefault();move(dragId,row.id);dragId='';};
      const order=node('td');order.className='row-order';order.append(node('span',String(i+1)));

      const usageCell=node('td');usageCell.className='usage-cell';tr.append(order);for(const c of cols){if(c.name==='id')tr.append(usageCell);const value=row.fields[c.name],td=node('td',cellDisplay(value,c));if(c.name.replace(/[^a-z]/gi,'').toLowerCase()==='realizedpnl'&&typeof value==='number')td.className=value<0?'pnl-negative':value>0?'pnl-positive':'';tr.append(td);}body.append(tr);
    });
    if(!rows.length){const tr=node('tr'),td=node('td',data.updatedAt?'No accounts in this Airtable view.':'Refresh Planning or open Airtable setup to load accounts.');td.colSpan=cols.length+3;tr.append(td);body.append(tr);}
    table.append(body);resizeColumns(table,cols);decorate();el('planning-manual').textContent=layout.sort?'Return to Manual Order':'Manual Order ✓';
  }
  function resizeColumns(table,cols){
    const names=['Select','Order'];for(const c of cols){if(c.name==='id')names.push('Pair status');names.push('field:'+c.name);}
    const group=node('colgroup'),headers=table.querySelectorAll('thead th'),widths=names.map(name=>Math.max(60,Math.min(1000,Number(layout.widths[name])||(name.startsWith('field:')?180:name==='Pair status'?110:70))));
    const apply=()=>{Array.from(group.children).forEach((col,i)=>col.style.width=widths[i]+'px');table.style.width=widths.reduce((a,b)=>a+b,0)+'px';};
    names.forEach((name,i)=>{
      group.append(node('col'));const th=headers[i],handle=node('span');th.setAttribute('aria-label',th.textContent);handle.className='column-resize';handle.tabIndex=0;handle.setAttribute('role','separator');handle.setAttribute('aria-orientation','vertical');handle.setAttribute('aria-label','Resize '+name.replace(/^field:/,''));
      let startX=0,startWidth=0,active=false,wasDraggable=false;
      const commit=()=>{layout.widths[name]=widths[i];save();};
      handle.onpointerdown=e=>{e.preventDefault();e.stopPropagation();active=true;wasDraggable=th.draggable;th.draggable=false;startX=e.clientX;startWidth=widths[i];handle.setPointerCapture(e.pointerId);};
      handle.onpointermove=e=>{if(!active)return;e.stopPropagation();widths[i]=Math.max(60,Math.min(1000,startWidth+e.clientX-startX));apply();};
      const finish=()=>{if(!active)return;active=false;th.draggable=wasDraggable;commit();};handle.onpointerup=finish;handle.onpointercancel=finish;
      handle.onclick=e=>{e.preventDefault();e.stopPropagation();};handle.ondragstart=e=>{e.preventDefault();e.stopPropagation();};
      handle.onkeydown=e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();e.stopPropagation();widths[i]=Math.max(60,Math.min(1000,widths[i]+(e.key==='ArrowLeft'?-10:10)));apply();commit();}};
      th.append(handle);
    });table.prepend(group);apply();
  }
  async function poll(){
    if(polling)return;polling=true;const generation=requestGeneration;
    try{
      const snapshot=await api('/api/planning');if(generation!==requestGeneration)return;
      const next=snapshot.viewKey||defaultView;
      if(next!==viewKey){save();viewKey=next;key=next===defaultView?'planning-viw6K3jRjU5PJpWM4-v1':'planning-'+next+'-v1';layout=loadLayout();selected.clear();dragId='';lastUpdate=undefined;el('view-save-status').textContent='';resize(layout.split);}
      data=snapshot;
      const views=data.views||[{key:defaultView,name:'Accounts'}],signature=JSON.stringify(views);
      if(signature!==viewSignature){viewSignature=signature;el('planning-view').replaceChildren();for(const v of views){const option=node('option',v.name);option.value=v.key;el('planning-view').append(option);}}
      el('planning-view').value=viewKey;
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
  for(const tab of ['vms','planning','trading'])el('tab-'+tab).onclick=()=>{
    for(const name of ['vms','planning','trading']){el(name+'-panel').hidden=name!==tab;el('tab-'+name).setAttribute('aria-selected',String(name===tab));}
    document.querySelector('main').classList.toggle('planning-wide',tab==='planning');
    document.querySelector('main').classList.toggle('vm-view',tab==='vms');
    if(tab==='planning')poll();
  };
  const split=el('planning-divider'),layoutBox=document.querySelector('.planning-layout');
  function resize(value){layout.split=Math.max(30,Math.min(78,value));layoutBox.style.setProperty('--planning-split',layout.split+'%');split.setAttribute('aria-valuenow',Math.round(layout.split));}
  resize(layout.split||65);
  split.onpointerdown=e=>{split.setPointerCapture(e.pointerId);split.dataset.dragging='true';e.preventDefault();};
  split.onpointermove=e=>{if(split.dataset.dragging!=='true')return;const box=layoutBox.getBoundingClientRect();resize((e.clientX-box.left)/box.width*100);};
  split.onpointerup=()=>{delete split.dataset.dragging;save();};
  split.onpointercancel=()=>{delete split.dataset.dragging;};
  split.onkeydown=e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();resize(layout.split+(e.key==='ArrowLeft'?-2:2));save();}};
  el('planning-save-view').onclick=()=>{try{localStorage.setItem(key,JSON.stringify(layout));el('view-save-status').textContent='View saved';}catch(_){el('view-save-status').textContent='Unable to save view: browser storage is unavailable.';}};
  async function changeView(body){
    requestGeneration++;el('planning-view').disabled=true;el('planning-view-save').disabled=true;
    try{await api('/api/planning/view',body);await poll();el('planning-view-dialog').close();}
    catch(e){el('planning-view-error').textContent=e.message;el('planning-status').textContent=e.message;el('planning-view').value=viewKey;}
    finally{el('planning-view').disabled=false;el('planning-view-save').disabled=false;}
  }
  el('planning-view').onchange=()=>changeView({key:el('planning-view').value});
  el('planning-add-view').onclick=()=>{el('planning-view-link').value='';el('planning-view-name').value='';el('planning-view-error').textContent='';el('planning-view-dialog').showModal();};
  el('planning-view-cancel').onclick=()=>el('planning-view-dialog').close();
  el('planning-view-save').onclick=()=>changeView({link:el('planning-view-link').value.trim(),name:el('planning-view-name').value.trim()});
  el('planning-refresh').onclick=()=>refresh();
  el('planning-manual').onclick=()=>{layout.sort=null;save();renderTable();};
  el('planning-setup').onclick=()=>el('planning-dialog').showModal();
  el('planning-cancel').onclick=()=>{el('planning-token').value='';el('planning-dialog').close();};
  el('planning-dialog').addEventListener('close',()=>{el('planning-token').value='';});
  el('planning-save').onclick=async()=>{
    const value=el('planning-token').value.trim();el('planning-token').value='';el('planning-save').disabled=true;
    try{await refresh({token:value});}finally{el('planning-save').disabled=false;}
  };
  renderTable();poll();setInterval(poll,3000);
})();
