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
const d={ratio:'2:3',ticker:'NQ SEP26',leftQuantity:'1'};r.quantities(d);assert.equal(d.ticker,'MNQ SEP26');assert.equal(d.leftQuantity,'10');assert.equal(d.rightQuantity,'15');
const e={ratio:'3:4',ticker:'NQ SEP26',leftQuantity:'1'};r.quantities(e);assert.match(e.notice,/fractional/);assert.equal(e.ticker,'NQ SEP26');
console.log('All ratios: amounts, bidirectional quantities, swaps, MNQ conversion and fractional rejection passed.');
