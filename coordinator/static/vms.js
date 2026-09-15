'use strict';
(() => {
 const el=id=>document.getElementById(id),node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 let fleet=[];const open=new Set(),pending=new Set(),selected=new Set();
 async function refresh(id){
   if(pending.has(id))return;pending.add(id);render();
   try{await api('/api/vm-refresh',{id});await poll();}
   catch(e){el('vms-message').textContent=e.message;}
   finally{pending.delete(id);render();}
 }
 let sorting={field:'name',direction:1};
 try{const saved=JSON.parse(localStorage.getItem('vm-sort-v1'));if(saved&&['name','connection','position','availability'].includes(saved.field)&&[1,-1].includes(saved.direction))sorting=saved;}catch(_){}
 function position(vm){return vm.fresh?vm.position:(vm.lastKnown?.position?vm.lastKnown.position+' (last known)':'Unknown');}
 function availability(vm){
   if(pending.has(vm.id)||vm.refresh?.status==='running')return 'Refreshing…';
   if(vm.pairId)return 'Paired';
   return vm.online&&vm.fresh&&vm.position==='Flat'&&!vm.busy&&!vm.scheduled&&!vm.pending&&!vm.closing&&!vm.pairActive&&vm.accounts?.length>0&&vm.refresh?.status!=='error'?'Ready · Available':'Needs attention';
 }
 function sortValue(vm){return sorting.field==='connection'?(vm.online?'Connected':'Disconnected'):sorting.field==='position'?position(vm):sorting.field==='availability'?availability(vm):vm.name;}
 function render(){
   const list=el('vms-list'),scroll=list.scrollTop;list.replaceChildren();
   for(const vm of fleet.slice().sort((a,b)=>String(sortValue(a)).localeCompare(String(sortValue(b)),undefined,{numeric:true,sensitivity:'base'})*sorting.direction||a.name.localeCompare(b.name))){
     const row=node('section');row.className='vm-list-row';row.dataset.vm=vm.id;
     const line=node('div');line.className='vm-list-summary';const box=node('input');box.type='checkbox';box.checked=selected.has(vm.id);box.setAttribute('aria-label','Select VM '+vm.name);box.onchange=()=>{box.checked?selected.add(vm.id):selected.delete(vm.id);el('vms-refresh-selected').disabled=!selected.size;};line.append(box,node('strong',vm.name));
     const connection=node('span',vm.online?'Connected':'Disconnected');connection.className=vm.online?'complete':'idle';line.append(connection);
     line.append(node('span',position(vm)));
     const busy=pending.has(vm.id)||vm.refresh?.status==='running';
     const availabilityLabel=node('span',availability(vm));availabilityLabel.className='vm-availability '+(vm.refresh?.status==='error'||!vm.online?'vm-error':vm.pairId?'vm-paired':availability(vm)==='Ready · Available'?'vm-available':'vm-error');line.append(availabilityLabel);
     const button=node('button',busy?'Refreshing…':'Refresh');button.disabled=busy;button.onclick=()=>refresh(vm.id);line.append(button);row.append(line);
     const details=node('details'),summary=node('summary',`${vm.accounts?.length||0} accounts · Show linked account IDs`);details.open=open.has(vm.id);details.ontoggle=()=>{if(!details.isConnected)return;if(details.open)open.add(vm.id);else open.delete(vm.id);};details.append(summary);
     const accounts=node('div');accounts.className='linked-accounts';for(const account of vm.accounts||[])accounts.append(node('div',account));details.append(accounts);row.append(details);
     row.append(node('p',vm.refresh?.message||vm.accountMessage||vm.message||'Refresh to verify accounts.'));list.append(row);
   }
   list.scrollTop=scroll;
   if(!fleet.length)list.append(node('p','No registered VMs yet. Choose Register VM to add one.'));
 }
 el('vms-sort').value=sorting.field;el('vms-sort-direction').textContent=sorting.direction===1?'Ascending':'Descending';
 function saveSort(){try{localStorage.setItem('vm-sort-v1',JSON.stringify(sorting));}catch(_){}render();}
 el('vms-sort').onchange=()=>{sorting.field=el('vms-sort').value;saveSort();};
 el('vms-sort-direction').onclick=()=>{sorting.direction*=-1;el('vms-sort-direction').textContent=sorting.direction===1?'Ascending':'Descending';saveSort();};
 el('vms-refresh-selected').onclick=async()=>{const ids=fleet.filter(vm=>selected.has(vm.id)).map(vm=>vm.id);for(const id of ids)await refresh(id);};
 el('vms-register').onclick=()=>el('connect-dialog').showModal();
 el('vms-refresh-all').onclick=async()=>{for(const vm of fleet)await refresh(vm.id);};
 window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];render();});
 render();
})();
