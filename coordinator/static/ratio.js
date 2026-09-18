'use strict';
(() => {
 const options=['1:1','2:1','1:2','2:3','3:2','3:4','4:3','2:5','5:2','3:5','5:3','4:5','5:4'];
 const round=n=>Math.ceil(n-1e-9);
 function factor(d){const [a,b]=(d.ratio||'1:1').split(':').map(Number);return b/a;}
 function amounts(d){d.rightStopLoss=String(round(Number(d.profit)*factor(d)));d.rightProfit=String(round(Number(d.stopLoss)*factor(d)));}
 function quantities(d,side='left'){
   const q=Number(d[side+'Quantity']);d.notice='';
   const opposite=side==='left'?'rightQuantity':'leftQuantity';
   if(!Number.isFinite(q)||q<=0||!Number.isInteger(q)){d[opposite]='';d.notice='Enter a positive whole-contract quantity.';return;}
   let l=side==='left'?q:q/factor(d),r=side==='right'?q:q*factor(d);
   const whole=n=>Math.abs(n-Math.round(n))<1e-8;
   if((!whole(l)||!whole(r))&&/^NQ(?: |$)/.test(d.ticker)&&whole(l*10)&&whole(r*10)){
     l*=10;r*=10;d.ticker=d.ticker.replace(/^NQ/,'MNQ');
     d.notice='Switched both sides to MNQ at 10 MNQ per NQ so both quantities are whole contracts.';
   }
   if(!whole(l)||!whole(r)){
     d[opposite]='';
     d.notice=/^NQ(?: |$)/.test(d.ticker)?'This ratio still needs fractional contracts after a 10:1 MNQ conversion. Adjust the entered quantity or ratio.':'This ratio needs fractional contracts. Adjust the entered quantity or ratio.';
     return;
   }
   d.leftQuantity=String(Math.round(l));d.rightQuantity=String(Math.round(r));
 }
 function edit(d,key,value){d[key]=value;if(key.includes('Quantity'))quantities(d,key.startsWith('left')?'left':'right');
   else {if(key==='rightProfit')d.stopLoss=String(round(Number(value)/factor(d)));if(key==='rightStopLoss')d.profit=String(round(Number(value)/factor(d)));amounts(d);}}
 function swap(d){[d.left,d.right]=[d.right,d.left];[d.leftQuantity,d.rightQuantity]=[d.rightQuantity,d.leftQuantity];
   [d.stopLoss,d.profit,d.rightStopLoss,d.rightProfit]=[d.rightStopLoss,d.rightProfit,d.stopLoss,d.profit];d.ratio=(d.ratio||'1:1').split(':').reverse().join(':');}
 function setInstrument(d,ticker){d.ticker=ticker;d.notice='';}
 const api={options,amounts,quantities,edit,swap,setInstrument};if(typeof module!=='undefined')module.exports=api;else window.PairRatio=api;
})();
