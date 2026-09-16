const assert=require('node:assert/strict'),r=require('../coordinator/static/ratio.js');
for(const ratio of r.options){
 const [a,b]=ratio.split(':').map(Number),d={left:{account:'A'},right:{account:'B'},ratio,ticker:'NQ SEP26',leftQuantity:String(a),rightQuantity:String(b),stopLoss:'600',profit:'300'};
 r.amounts(d);assert.equal(+d.rightProfit,Math.round(600*b/a*100)/100);
 r.edit(d,'rightProfit',String(b*100));assert.equal(+d.stopLoss,a*100);
 r.edit(d,'rightStopLoss',String(b*200));assert.equal(+d.profit,a*200);
 r.edit(d,'leftQuantity',String(a*2));assert.equal(+d.rightQuantity,b*2);
 r.edit(d,'rightQuantity',String(b*3));assert.equal(+d.leftQuantity,a*3);
 const before={...d};r.swap(d);assert.equal(d.ratio,b+':'+a);assert.equal(d.stopLoss,before.rightStopLoss);r.swap(d);assert.deepEqual(d,before);
}
const d={ratio:'2:3',ticker:'NQ SEP26',leftQuantity:'1'};r.quantities(d);assert.equal(d.ticker,'MNQ SEP26');assert.equal(d.leftQuantity,'10');assert.equal(d.rightQuantity,'15');assert.match(d.notice,/10 MNQ per NQ/);
const e={ratio:'3:4',ticker:'NQ SEP26',leftQuantity:'1'};r.quantities(e);assert.match(e.notice,/fractional/);assert.equal(e.ticker,'NQ SEP26');assert.equal(e.rightQuantity,'');
for(const ticker of ['NQ','NQ DEC26','NQ MAR27']){const d={ratio:'2:3',ticker,leftQuantity:'1'};r.quantities(d);assert.equal(d.ticker,ticker.replace(/^NQ/,'MNQ'));assert.equal(d.leftQuantity,'10');assert.equal(d.rightQuantity,'15');}
// 3:2 with 2 on the left gives 1 1/3, which cannot be represented by whole MNQ.
const thirds={ratio:'3:2',ticker:'NQ',leftQuantity:'2',rightQuantity:'1'};r.quantities(thirds);
assert.equal(thirds.ticker,'NQ');assert.equal(thirds.leftQuantity,'2');assert.equal(thirds.rightQuantity,'');assert.match(thirds.notice,/10:1/);
// Editing the right side converts both sides by exactly ten when needed.
const fromRight={ratio:'3:2',ticker:'NQ DEC26',rightQuantity:'1',leftQuantity:'3',stopLoss:'1200',profit:'2000'};r.quantities(fromRight,'right');
assert.equal(fromRight.ticker,'MNQ DEC26');assert.equal(fromRight.leftQuantity,'15');assert.equal(fromRight.rightQuantity,'10');assert.equal(fromRight.stopLoss,'1200');assert.equal(fromRight.profit,'2000');
r.quantities(fromRight,'right');assert.equal(fromRight.leftQuantity,'15');assert.equal(fromRight.rightQuantity,'10');
const micros={ratio:'3:2',ticker:'MNQ',leftQuantity:'2',rightQuantity:'1'};r.quantities(micros);assert.equal(micros.ticker,'MNQ');assert.equal(micros.rightQuantity,'');
// All offered ratios, either edited side: exact 10:1 conversion or no computed fraction.
for(const ratio of r.options)for(const side of ['left','right'])for(const quantity of [1,2,3,4,5]){
 const [a,b]=ratio.split(':').map(Number),opposite=side==='left'?'rightQuantity':'leftQuantity',value=side==='left'?quantity*b/a:quantity*a/b;
 const draft={ratio,ticker:'NQ',leftQuantity:'1',rightQuantity:'1',[side+'Quantity']:String(quantity)};r.quantities(draft,side);
 const whole=x=>Math.abs(x-Math.round(x))<1e-8;
 if(whole(value)){assert.equal(draft.ticker,'NQ');assert.equal(+draft[opposite],Math.round(value));}
 else if(whole(value*10)){assert.equal(draft.ticker,'MNQ');assert.equal(+draft[side+'Quantity'],quantity*10);assert.equal(+draft[opposite],Math.round(value*10));}
 else{assert.equal(draft.ticker,'NQ');assert.equal(draft[opposite],'');}
}
// Reported case: switching 2 MNQ / 1 MNQ to NQ keeps the user's contract counts.
for(const ratio of r.options){
 const [a,b]=ratio.split(':');
 const d={ratio,ticker:'MNQ',leftQuantity:a,rightQuantity:b,profit:'2000',stopLoss:'1200'};r.amounts(d);
 const before={...d};
 for(const ticker of ['NQ','NQ DEC26','MNQ','MNQ MAR27']){
  r.setInstrument(d,ticker);
  assert.deepEqual(d,{...before,ticker,notice:''});
 }
}
const single={ticker:'MNQ',leftQuantity:'1',rightQuantity:'0.5',ratio:'2:1',right:null};
r.setInstrument(single,'NQ');assert.equal(single.ticker,'NQ');assert.equal(single.leftQuantity,'1');assert.equal(single.rightQuantity,'0.5');
console.log('PASS: all ratios and both edited sides; exact 10:1 automatic MNQ conversion only when needed; no computed fractions or rounding; manual instrument changes keep valid contract counts.');
