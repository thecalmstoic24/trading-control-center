const assert=require('node:assert/strict');
global.PairSuggestions=require('../coordinator/static/suggestions.js');
const F=require('../coordinator/static/funded-suggestions.js');
const row=(id,firm,more={})=>({id:'rec'+id,fields:{id,firm,RealStage:'Funded',NoConsistency:1,RealCurrentBalance:50000,CurrentBalance:999,RealDrawdown:1501.23,...more}});
let seed=19;const random=()=>((seed=Math.imul(seed,1664525)+1013904223>>>0)/2**32);
// Exhaustively verify maximum cardinality for unbalanced firm pools.
for(let a=0;a<=7;a++)for(let b=0;b<=7;b++)for(let c=0;c<=7;c++){
 const rows=[a,b,c].flatMap((n,f)=>Array.from({length:n},(_,i)=>row(f+'-'+i,'F'+f)));
 const result=F.suggest(rows,[],random),total=a+b+c,expected=Math.min(Math.floor(total/2),total-Math.max(a,b,c));
 assert.equal(result.pairs.length,expected,`${a},${b},${c}`);
 const ids=result.pairs.flatMap(p=>[p.a.id,p.b.id]);assert.equal(ids.length,new Set(ids).size);
 for(const p of result.pairs){assert.notEqual(p.a.firm,p.b.firm);const d=F.draft(p,'a'.repeat(32));assert.equal(F.validateDraft(d),'');assert.equal(d.profit,d.rightStopLoss);assert.equal(d.stopLoss,d.rightProfit);assert.equal(d.left.balance,50000);assert.equal(d.profit,'1510');}
}
for(const balance of [48700,50300])assert.doesNotThrow(()=>F.account(row('a','A',{RealCurrentBalance:balance})));
for(const balance of [48699.99,50300.01,null,'',false])assert.throws(()=>F.account(row('a','A',{RealCurrentBalance:balance})));
for(const stage of ['Evaluation','Funded pending','',null])assert.throws(()=>F.account(row('a','A',{RealStage:stage})));
for(const nc of [0,2,null,false,''])assert.throws(()=>F.account(row('a','A',{NoConsistency:nc})));
assert.equal(F.account(row('a','A',{RealDrawdown:1500})).loss,150000);
assert.equal(F.account(row('a','A',{RealDrawdown:1500.01})).loss,151000);
const source=[row('a','A'),row('b','B'),row('c','C')];
assert.equal(F.suggest([...source,row('a','D')],['b'],random).pairs.length,0);
const lefts=new Set();for(let i=0;i<40;i++)lefts.add(F.suggest(source.slice(0,2),[],random).pairs[0].a.id);assert.equal(lefts.size,2);
const d=F.draft(F.suggest(source.slice(0,2),[],random).pairs[0],'b'.repeat(32));d.profit='2000';assert.match(F.validateDraft(d),/exceed/);
console.log('Funded strategy: eligibility, 512 pool shapes, unique maximum matching, rounding and randomized sides passed.');
