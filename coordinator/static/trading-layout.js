'use strict';
(() => {
 const host=document.getElementById('trading-split'),divider=document.getElementById('trading-divider');
 if(!host||!divider)return;
 let share=75;
 function apply(value,save){share=Math.max(45,Math.min(85,Number.isFinite(value)?value:75));host.style.setProperty('--pair-share',share+'fr');host.style.setProperty('--activity-share',(100-share)+'fr');divider.setAttribute('aria-valuenow',String(Math.round(share)));if(save)try{localStorage.setItem('trading-pair-share',String(share));}catch(_){} }
 try{const saved=localStorage.getItem('trading-pair-share');if(saved!==null)share=Number(saved);}catch(_){}
 apply(share,false);
 divider.onpointerdown=e=>{if(e.button!==0)return;e.preventDefault();divider.setPointerCapture(e.pointerId);const bounds=host.getBoundingClientRect();
  divider.onpointermove=ev=>{if(bounds.width>10)apply((ev.clientX-bounds.left-5)/(bounds.width-10)*100,false);};
  divider.onpointerup=()=>{divider.onpointermove=null;apply(share,true);};divider.onpointercancel=divider.onlostpointercapture=()=>{divider.onpointermove=null;};};
 divider.onkeydown=e=>{if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();apply(e.key==='Home'?45:e.key==='End'?85:share+(e.key==='ArrowRight'?2:-2),true);};
})();
