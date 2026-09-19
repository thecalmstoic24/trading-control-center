'use strict';
(() => {
 const el=id=>document.getElementById(id),node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 let fleet=[],queueRows=[];const open=new Set(),pending=new Set(),syncPending=new Set(),releasePending=new Set(),removing=new Set(),selected=new Set();
 async function refresh(id){
   if(pending.has(id))return;pending.add(id);render();
   try{await api('/api/vm-refresh',{id});await poll();}
   catch(e){el('vms-message').textContent=e.message;}
   finally{pending.delete(id);render();}
 }
 async function syncAirtable(id){
   if(syncPending.has(id))return;syncPending.add(id);render();
   try{const result=await api('/api/vm-sync',{id});el('vms-message').textContent=result.message||'Sync Airtable requested. Follow VM Activity for progress.';await poll();}
   catch(e){el('vms-message').textContent=e.message;}
   finally{syncPending.delete(id);render();}
 }
 async function removeVM(vm){
   if(removing.has(vm.id))return;
   if(!window.confirm('Remove '+vm.name+' from Control Center? This removes its saved connection, not its VM agent, Airtable accounts, or trade history. A disconnected VM must be checked separately for open trades.'))return;
   removing.add(vm.id);render();
   try{const result=await api('/api/vm-remove',{id:vm.id});selected.delete(vm.id);open.delete(vm.id);fleet=fleet.filter(v=>v.id!==vm.id);el('vms-message').textContent=result.message;await poll();}
   catch(e){el('vms-message').textContent=e.message;}
   finally{removing.delete(vm.id);render();}
 }
 let sorting={field:'name',direction:1};
 try{const saved=JSON.parse(localStorage.getItem('vm-sort-v1'));if(saved&&['name','connection','position','availability'].includes(saved.field)&&[1,-1].includes(saved.direction))sorting=saved;}catch(_){}
 function position(vm){return vm.fresh?vm.position:(vm.lastKnown?.position?vm.lastKnown.position+' (last known)':'Unknown');}
 function pairError(vm){return vm.pairId?queueRows.find(row=>row.pairId===vm.pairId&&row.status==='Error'):null;}
 function availability(vm){
   if(pairError(vm))return 'Error';
   if(pending.has(vm.id)||vm.refresh?.status==='running')return 'Refreshing…';
   if(vm.pairId)return 'Paired';
   if(vm.defaultAccount?.status==='running')return 'Selecting account…';
   if(vm.fresh&&!vm.account)return 'Account selection needed';
   return vm.online&&vm.fresh&&vm.position==='Flat'&&!!vm.account&&!vm.calibrationRequired&&!vm.busy&&!vm.scheduled&&!vm.pending&&!vm.closing&&!vm.pairActive&&vm.accounts?.length>0&&vm.refresh?.status!=='error'?'Ready · Available':'Needs attention';
 }
 function sortValue(vm){return sorting.field==='connection'?(vm.online?'Connected':'Disconnected'):sorting.field==='position'?position(vm):sorting.field==='availability'?availability(vm):vm.name;}
 let lastRender='';
 function render(){
   if(el('vms-panel').hidden)return;
   const key=JSON.stringify([fleet.map(v=>{const {ageMs,rttMs,...rest}=v;return rest;}),queueRows.map(r=>[r.key,r.id,r.pairId,r.status,r.message,r.errorReleased]),[...pending],[...syncPending],[...releasePending],[...removing],[...selected],[...open],sorting]);
   if(key===lastRender)return;lastRender=key;
   const list=el('vms-list'),scroll=list.scrollTop;list.replaceChildren();
   const headings=node('div');headings.className='vm-list-head';
   for(const label of ['','VM','Connection','Position','Status','Accounts','Last refresh','Actions'])headings.append(node('span',label));
   list.append(headings);
   for(const vm of fleet.slice().sort((a,b)=>String(sortValue(a)).localeCompare(String(sortValue(b)),undefined,{numeric:true,sensitivity:'base'})*sorting.direction||a.name.localeCompare(b.name))){
     const row=node('section');row.className='vm-list-row';row.dataset.vm=vm.id;
     const line=node('div');line.className='vm-list-summary';const box=node('input');box.type='checkbox';box.checked=selected.has(vm.id);box.setAttribute('aria-label','Select VM '+vm.name);box.onchange=()=>{box.checked?selected.add(vm.id):selected.delete(vm.id);el('vms-refresh-selected').disabled=!selected.size;};line.append(box,node('strong',vm.name));
     const connection=node('span',vm.online?'Connected':'Disconnected');connection.className=vm.online?'complete':'idle';line.append(connection);
     line.append(node('span',position(vm)));
     const busy=pending.has(vm.id)||vm.refresh?.status==='running';
     const error=pairError(vm),label=availability(vm);
     const availabilityLabel=node('span',label);availabilityLabel.className='vm-availability '+(error||vm.refresh?.status==='error'||!vm.online?'vm-error':vm.pairId?'vm-paired':label==='Ready · Available'?'vm-available':'vm-error');line.append(availabilityLabel);
     const button=node('button',busy?'Refreshing…':'Refresh');button.disabled=busy;button.onclick=()=>refresh(vm.id);
     const actions=node('div');actions.className='vm-row-actions';actions.append(button);
     const syncing=syncPending.has(vm.id)||vm.manualSyncPending;
     const syncButton=node('button',syncing?'Sync requested…':'Sync Airtable');
     syncButton.disabled=syncing||!vm.online||!vm.manualSync;syncButton.setAttribute('aria-label','Sync Airtable for '+vm.name);
     syncButton.title=!vm.manualSync?'Update this VM agent to enable remote sync.':syncing?'Sync is running or queued; follow VM Activity.':'Run Sync Airtable Now on this VM. Waits if trading automation is busy.';
     syncButton.onclick=()=>syncAirtable(vm.id);actions.append(syncButton);
     const release=node('button',releasePending.has(vm.id)?'Releasing…':'Release VMs');release.className='quiet';
     release.disabled=!vm.pairId||releasePending.has(vm.id);
     release.title=!vm.pairId?'No pair reservation to release.':releasePending.has(vm.id)?'Release verification is in progress.':'Release this pair after the server verifies it is safe.';
     release.setAttribute('aria-label','Release VMs for '+vm.name);
     release.onclick=async()=>{if(!vm.pairId||releasePending.has(vm.id))return;releasePending.add(vm.id);render();try{const result=await api('/api/vm-release',{id:vm.id});el('vms-message').textContent=result.message;window.dispatchEvent(new Event('queue-refresh'));await poll();}catch(e){el('vms-message').textContent=e.message;}finally{releasePending.delete(vm.id);render();}};actions.append(release);
     const accountToggle=node('button',(open.has(vm.id)?'▾ ':'▸ ')+(vm.accounts?.length||0)+' accounts');accountToggle.className='vm-account-toggle quiet';
     accountToggle.setAttribute('aria-expanded',String(open.has(vm.id)));accountToggle.setAttribute('aria-label','Show linked account IDs for '+vm.name);
     accountToggle.onclick=()=>{open.has(vm.id)?open.delete(vm.id):open.add(vm.id);render();};
     const fullMessage=error?`${error.id} · ${error.message||'Pair failed. Cancel or resolve the pair before reusing this VM.'}`:(vm.manualSync&&(vm.manualSyncPending||/^Sync failed|^Synced |^Exporting |^Sync requested/.test(vm.sync||''))?vm.sync:'')||vm.refresh?.message||vm.accountMessage||vm.message||'Refresh to verify accounts.';
     const message=node('span',fullMessage.replace(/^Accounts refreshed\.\s*/,'').replace(/ matched accounts? on [^.]+\./,' matched ·').replace(/\s*Sim101 remains available\.?/,' Sim101 available').trim());message.className='vm-refresh-summary';message.title=fullMessage;message.tabIndex=0;message.setAttribute('aria-label',fullMessage);
     line.append(accountToggle,message,actions);row.append(line);
     const accounts=node('div');accounts.className='linked-accounts';accounts.hidden=!open.has(vm.id);accounts.setAttribute('aria-label','Linked accounts for '+vm.name);
     for(const account of vm.accounts||[])accounts.append(node('div',account));
     if(!vm.accounts?.length)accounts.append(node('div','No linked account IDs. Refresh to verify accounts.'));
     row.append(accounts);list.append(row);
   }
   list.scrollTop=scroll;
   const select=el('vm-remove-select'),previous=select.value;select.replaceChildren();
   const blank=node('option','Select VM');blank.value='';select.append(blank);
   for(const vm of fleet.slice().sort((a,b)=>a.name.localeCompare(b.name))){const option=node('option',vm.name);option.value=vm.id;select.append(option);}
   select.value=fleet.some(v=>v.id===previous)?previous:'';
   el('vm-remove-action').disabled=!select.value||removing.has(select.value);
   el('vm-remove-action').textContent=removing.has(select.value)?'Removing…':'Remove';
   el('vms-refresh-selected').disabled=!fleet.some(vm=>selected.has(vm.id));
   if(!fleet.length)list.append(node('p','No registered VMs yet. Choose Register VM to add one.'));
 }
 el('vms-sort').value=sorting.field;el('vms-sort-direction').textContent=sorting.direction===1?'Ascending':'Descending';
 function saveSort(){try{localStorage.setItem('vm-sort-v1',JSON.stringify(sorting));}catch(_){}render();}
 el('vms-sort').onchange=()=>{sorting.field=el('vms-sort').value;saveSort();};
 el('vms-sort-direction').onclick=()=>{sorting.direction*=-1;el('vms-sort-direction').textContent=sorting.direction===1?'Ascending':'Descending';saveSort();};
 el('vms-refresh-selected').onclick=async()=>{const ids=fleet.filter(vm=>selected.has(vm.id)).map(vm=>vm.id);for(const id of ids)await refresh(id);};
 el('vm-remove-select').onchange=()=>{el('vm-remove-action').disabled=!el('vm-remove-select').value||removing.has(el('vm-remove-select').value);};
 el('vm-remove-action').onclick=()=>{const vm=fleet.find(v=>v.id===el('vm-remove-select').value);if(vm)return removeVM(vm);};
 el('vms-register').onclick=()=>el('connect-dialog').showModal();
 el('vms-refresh-all').onclick=async()=>{for(const vm of fleet)await refresh(vm.id);};
 window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];render();});
 window.addEventListener('queue-updated',e=>{queueRows=e.detail.rows||[];render();});
 window.addEventListener('control-tab-changed',()=>render());
 render();
})();
