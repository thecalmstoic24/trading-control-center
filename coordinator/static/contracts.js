
'use strict';
(() => {
 const input=document.getElementById('contract-month'),button=document.getElementById('contract-save'),status=document.getElementById('contract-status');
 let loading=true;button.disabled=true;
 const show=s=>{input.value=s.month;status.textContent=`NQ → ${s.symbols.NQ} · MNQ → ${s.symbols.MNQ}`;};
 api('/api/contracts').then(show).catch(e=>{status.textContent=e.message;}).finally(()=>{loading=false;button.disabled=false;});
 button.onclick=async()=>{if(loading)return;button.disabled=true;try{show(await api('/api/contracts',{month:input.value}));}catch(e){status.textContent=e.message;}finally{button.disabled=false;}};
})();
