'use strict';
(() => {
 const el=id=>document.getElementById(id),node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 let fleet=[];const open=new Set(),pending=new Set();
 async function refresh(id){
   if(pending.has(id))return;pending.add(id);render();
   try{await api('/api/vm-refresh',{id});await poll();}
   catch(e){el('vms-message').textContent=e.message;}
   finally{pending.delete(id);render();}
 }
 function render(){
   const list=el('vms-list');list.replaceChildren();
   for(const vm of fleet){
     const row=node('section');row.className='vm-list-row';row.dataset.vm=vm.id;
     const line=node('div');line.className='vm-list-summary';line.append(node('strong',vm.name));
     const connection=node('span',vm.online?'Connected':'Disconnected');connection.className=vm.online?'complete':'idle';line.append(connection);
     line.append(node('span',vm.fresh?vm.position:(vm.lastKnown?.position?vm.lastKnown.position+' (last known)':'Unknown')));
     const busy=pending.has(vm.id)||vm.refresh?.status==='running';
     const ready=vm.online&&vm.fresh&&vm.position==='Flat'&&!vm.pairId&&!vm.busy&&!vm.scheduled&&!vm.pending&&!vm.closing&&!vm.pairActive&&!busy&&vm.accounts?.length>0&&vm.refresh?.status!=='error';
     line.append(node('span',busy?'Refreshing…':vm.pairId?'Paired':ready?'Ready · Available':'Needs attention'));
     const button=node('button',busy?'Refreshing…':'Refresh');button.disabled=busy;button.onclick=()=>refresh(vm.id);line.append(button);row.append(line);
     const details=node('details'),summary=node('summary',`${vm.accounts?.length||0} accounts · Show linked account IDs`);details.open=open.has(vm.id);details.ontoggle=()=>{if(details.open)open.add(vm.id);else open.delete(vm.id);};details.append(summary);
     const accounts=node('div');accounts.className='linked-accounts';for(const account of vm.accounts||[])accounts.append(node('div',account));details.append(accounts);row.append(details);
     row.append(node('p',vm.refresh?.message||vm.accountMessage||vm.message||'Refresh to verify accounts.'));list.append(row);
   }
   if(!fleet.length)list.append(node('p','No registered VMs yet. Choose Register VM to add one.'));
 }
 el('vms-register').onclick=()=>el('connect-dialog').showModal();
 el('vms-refresh-all').onclick=async()=>{for(const vm of fleet)await refresh(vm.id);};
 window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];render();});
 render();
})();
