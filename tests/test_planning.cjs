const assert=require('node:assert/strict');
const {display,ordered,reconcile,cellDisplay}=require('../coordinator/static/planning.js');
const rows=[{id:'a',fields:{Balance:100,Date:'2026-09-14'}},{id:'b',fields:{Balance:9,Date:'2025-12-31'}},{id:'c',fields:{}}];
const layout={order:['c','b','a'],hidden:[],sort:null};
assert.deepEqual(ordered(rows,layout,[]).map(r=>r.id),['c','b','a']);
layout.sort={name:'Balance',direction:1};assert.deepEqual(ordered(rows,layout,[]).map(r=>r.id),['b','a','c']);
layout.sort.direction=-1;assert.deepEqual(ordered(rows,layout,[]).map(r=>r.id),['a','b','c']);
layout.sort={name:'Date',direction:1};assert.deepEqual(ordered(rows,layout,[{name:'Date',type:'date'}]).map(r=>r.id),['b','a','c']);
assert.deepEqual(reconcile(['c','b','a'],[{id:'d'},{id:'a'},{id:'b'}]),['c','b','a','d']);
assert.equal(display([{name:'one'},'two',0]),'one, two, 0');
assert.deepEqual(rows.map(r=>r.id),['a','b','c'],'sorting must not mutate source order');
console.log('Planning: manual order, numeric/date sorting, empty values and refresh reconciliation passed.');

for(const name of ['Realized PnL','CurrentBalance','TargetBul','balance','stop','stock','largestProfitDay','Trailing max drawdown'])assert.equal(cellDisplay(-1234.5,{name}),'-$1,234.50');
assert.equal(cellDisplay(0,{name:'Realized PnL'}),'$0.00');
assert.equal(cellDisplay(3,{name:'tradingDays'}),'3');assert.equal(cellDisplay(1234,{name:'id'}),'1234');
assert.equal(cellDisplay(10,{name:'Target percent',type:'percent'}),'10');
assert.equal(cellDisplay(null,{name:'balance'}),'');
