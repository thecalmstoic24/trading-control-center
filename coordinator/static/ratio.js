'use strict';
(() => {
 const options=['1:1','2:1','1:2','2:3','3:2','3:4','4:3','2:5','5:2','3:5','5:3','4:5','5:4'];
 const round=n=>Math.round((n+Number.EPSILON)*100)/100;
 function factor(d){const [a,b]=(d.ratio||'1:1').split(':').map(Number);return b/a;}
 function amounts(d){d.rightStopLoss=String(round(Number(d.profit)*factor(d)));d.rightProfit=String(round(Number(d.stopLoss)*factor(d)));}
 function quantities(d,side='left'){
   const q=Number(d[side+'Quantity']);d.notice='';
   if(!Number.isFinite(q)||q<=0)return;
   let l=side==='left'?q:q/factor(d),r=side==='right'?q:q*factor(d);
   const whole=n=>Math.abs(n-Math.round(n))<1e-8;
   if((!whole(l)||!whole(r))&&/^NQ(?: |$)/.test(d.ticker)&&whole(l*10)&&whole(r*10)){
     l*=10;r*=10;d.ticker=d.ticker.replace(/^NQ/,'MNQ');d.notice='Switched both accounts to MNQ to preserve exposure with whole contracts.';
   }
   d.leftQuantity=String(whole(l)?Math.round(l):round(l));d.rightQuantity=String(whole(r)?Math.round(r):round(r));
   if(!whole(l)||!whole(r))d.notice='This ratio needs fractional contracts. Adjust quantity; contracts will not be rounded.';
 }
 function edit(d,key,value){d[key]=value;if(key.includes('Quantity'))quantities(d,key.startsWith('left')?'left':'right');
   else {if(key==='rightProfit')d.stopLoss=String(round(Number(value)/factor(d)));if(key==='rightStopLoss')d.profit=String(round(Number(value)/factor(d)));amounts(d);}}
 function swap(d){[d.left,d.right]=[d.right,d.left];[d.leftQuantity,d.rightQuantity]=[d.rightQuantity,d.leftQuantity];
   [d.stopLoss,d.profit,d.rightStopLoss,d.rightProfit]=[d.rightStopLoss,d.rightProfit,d.stopLoss,d.profit];d.ratio=(d.ratio||'1:1').split(':').reverse().join(':');}
 const api={options,amounts,quantities,edit,swap};if(typeof module!=='undefined')module.exports=api;else window.PairRatio=api;
})();
