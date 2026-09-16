'use strict';
(() => {
 const host=document.getElementById('vms-split'),divider=document.getElementById('vms-divider');
 if(!host||!divider)return;
 let share=80;
 function apply(value,save){share=Math.max(45,Math.min(85,Number.isFinite(value)?value:80));host.style.setProperty('--pair-share',share+'fr');host.style.setProperty('--activity-share',(100-share)+'fr');divider.setAttribute('aria-valuenow',String(Math.round(share)));if(save)try{localStorage.setItem('vms-list-share',String(share));}catch(_){} }
 try{const saved=localStorage.getItem('vms-list-share');if(saved!==null)share=Number(saved);}catch(_){}
 apply(share,false);
 divider.onpointerdown=e=>{if(e.button!==0)return;e.preventDefault();divider.setPointerCapture(e.pointerId);const bounds=host.getBoundingClientRect();
  divider.onpointermove=ev=>{if(bounds.width>10)apply((ev.clientX-bounds.left-5)/(bounds.width-10)*100,false);};
  divider.onpointerup=()=>{divider.onpointermove=null;apply(share,true);};divider.onpointercancel=divider.onlostpointercapture=()=>{divider.onpointermove=null;};};
 divider.onkeydown=e=>{if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();apply(e.key==='Home'?45:e.key==='End'?85:share+(e.key==='ArrowRight'?2:-2),true);};
})();

(() => {
 const host=document.getElementById('vm-events');if(!host)return;
 let previous='';
 window.addEventListener('fleet-updated',e=>{
  const events=e.detail.vmEvents||[],key=JSON.stringify(events);if(key===previous)return;previous=key;
  const scroll=host.scrollTop;host.replaceChildren();
  if(!events.length){const p=document.createElement('p');p.textContent='No activity yet.';host.append(p);return;}
  for(const entry of events){
   const row=document.createElement('div');row.className='event';
   const time=document.createElement('time');time.dateTime=entry.utc;
   time.textContent=new Intl.DateTimeFormat('en-US',{timeZone:'America/Chicago',month:'2-digit',day:'2-digit',hour:'numeric',minute:'2-digit',second:'2-digit'}).format(new Date(entry.utc));
   const text=document.createElement('span');text.textContent=entry.name+' · '+entry.message;
   row.append(time,text);host.append(row);
  }
  host.scrollTop=scroll;
 });
})();
