const assert=require('node:assert/strict');
const S=require('../coordinator/static/suggestions.js');
const row=(id,firm,values={})=>{const profit=values.CurrentProfit??0,today=values['Realized PnL']??0,current=values.CurrentBalance??(50000+profit);return {id:'rec'+id,fields:{id,firm,'Master Account':firm+'-TEST',CurrentBalance:current,balance:current,InitialBalance:current-today,'Realized PnL':today,stop:48000,'Trailing max drawdown':999,RealDrawdown:1500,CurrentProfit:0,ProfitTarget:3000,Consistency:0,CurrentPnL:0,...values}};};
const fn=(id,values={})=>row(id,'FN',{ProfitTarget:2500,Consistency:.4,largestProfitDay:900,...values});
const a=S.account(fn('A'));assert.equal(a.allowance,95000);assert.equal(a.remaining,250000);
assert.equal(S.account(fn('A',{'Realized PnL':-300})).allowance,125000);
assert.equal(S.account(fn('A',{'Realized PnL':400})).allowance,55000);
assert.equal(S.account(fn('A',{largestProfitDay:1020})).required,255000);
assert.equal(S.account(fn('A',{largestProfitDay:1020})).allowance,97000);
assert.throws(()=>S.account(fn('A',{largestProfitDay:1200})),/allowed \$100/);
for(const Consistency of [0,'0','',null,undefined]){
 const a=S.account(row('A','FFF',{Consistency,CurrentProfit:-678.96}));assert.equal(a.remaining,367896);assert.equal(a.allowance,Infinity);
}
assert.equal(S.account(row('A','FFF',{CurrentProfit:2401.96,'Realized PnL':159.76})).remaining,59804);
assert.equal(S.firm({firm:[' fn ']}),'FN');assert.equal(S.firm({Firm:{name:'FN'}}),'FN');assert.equal(S.firm({firm:['FN','FFF']}),'');
for(const values of [{firm:''},{firm:['A','B']},{CurrentProfit:null},{RealDrawdown:null},{ProfitTarget:0},{Consistency:40},{Consistency:-.1},{Consistency:.4,'Realized PnL':null},{Consistency:.4,largestProfitDay:null},{Consistency:true},{RealDrawdown:8.48},{RealDrawdown:-1},{CurrentProfit:3000}]){
 assert.throws(()=>S.account(row('BAD','FFF',values)),JSON.stringify(values));
}
const rows=[row('FFF892070','FFF',{RealDrawdown:8.48,CurrentProfit:-1491.52}),row('FFF322630','FFF',{RealDrawdown:612.72,CurrentProfit:472.52}),row('FFF993110','FFF',{CurrentProfit:-159.76,'Realized PnL':159.76}),row('FFF236159','FFF',{RealDrawdown:1183.48,CurrentProfit:2401.96}),fn('FN27255',{RealDrawdown:1107.72,CurrentProfit:919.36,largestProfitDay:790.44}),fn('FN19087',{CurrentProfit:1139.36,largestProfitDay:848.48}),fn('FN20889',{RealDrawdown:1138.92,CurrentProfit:1402.52,largestProfitDay:975.44}),fn('FN67282',{CurrentProfit:968.48,largestProfitDay:968.48})];
const saved=JSON.stringify(rows),result=S.suggest(rows,[],()=>.5);
assert.equal(result.pairs.length,3);assert.equal(result.pairs[0].a.id,'FFF236159');assert.equal(result.pairs[0].gainA,60000);assert.equal(result.pairs[0].priority,0);
assert.ok(result.skipped.some(x=>x.account==='FFF892070'&&x.reason.includes('$100 minimum')));assert.equal(JSON.stringify(rows),saved);
for(const p of result.pairs){
 assert.notEqual(p.a.firm,p.b.firm);assert.ok(p.gainA<=p.b.drawdown&&p.gainB<=p.a.drawdown);
 assert.ok(p.gainA<=p.a.allowance&&p.gainB<=p.b.allowance);assert.equal(p.gainA%1000,0);assert.equal(p.gainB%1000,0);
 const d=S.draft(p,'a'.repeat(32));assert.equal(d.leftQuantity,'2');assert.equal(d.rightQuantity,'2');assert.equal(d.profit,d.rightStopLoss);assert.equal(d.stopLoss,d.rightProfit);assert.equal(d.ticker,'NQ');assert.equal(d.ratio,'1:1');
}
assert.equal(new Set(result.pairs.flatMap(p=>[p.a.id,p.b.id])).size,6);
assert.ok(!S.suggest(rows,['FFF236159']).pairs.some(p=>p.a.id==='FFF236159'||p.b.id==='FFF236159'));
assert.equal(S.suggest([row('X',' FfF '),row('Y','fff')]).pairs.length,0);
// Firm, not the master name or ID prefix, controls suggestion eligibility.
assert.equal(S.suggest([row('FFF-A','ONE',{'Master Account':'SAME'}),row('FFF-B','TWO',{'Master Account':'SAME'})]).pairs.length,1);
assert.equal(S.suggest([row('A','SAME',{'Master Account':'FFF'}),row('B','SAME',{'Master Account':'FN'})]).pairs.length,0);
assert.equal(S.suggest([row('A','FFF'),row('A','FN')]).pairs.length,0);
// Closest infeasible finish must not outrank a feasible one-win finish.
const priority=S.suggest([fn('A',{CurrentProfit:2400,'Realized PnL':949}),row('B','FFF',{CurrentProfit:2800}),fn('C',{CurrentProfit:2000})],[],()=>.5);
assert.equal(priority.pairs[0].a.id,'B');assert.ok(priority.skipped.some(x=>x.account==='A'));
// Deterministic tie breaker can be randomized, never overrides distance priority.
const ties=[row('A','FFF'),fn('B'),fn('C')];let count=0;
const one=S.suggest(ties,[],()=>++count/10),two=S.suggest(ties,[],()=>--count/10);
assert.notEqual(one.pairs[0].a.id,two.pairs[0].a.id);
// Fractional remaining profit can only round up if BOTH caps allow it.
const near=S.account(row('N','FFF',{CurrentProfit:2401.96})),tight=S.account(fn('T',{RealDrawdown:598.04}));
assert.equal(S.gainAgainst(near,tight),59000);assert.ok(S.gainAgainst(near,tight)<near.remaining);
// All generated amounts respect the caps across varied account states.
let seed=17;const random=()=>((seed=(seed*1664525+1013904223)>>>0)/2**32);
const many=Array.from({length:100},(_,i)=>row('A'+i,['FFF','FN','MFF'][i%3],{CurrentProfit:Math.round((random()*5000-2000)*100)/100,RealDrawdown:Math.round(random()*200000)/100,Consistency:i%2?.4:0,largestProfitDay:random()*1000,'Realized PnL':random()*1200-500}));
const batch=S.suggest(many,[],random);const ids=new Set();
for(const p of batch.pairs){assert.notEqual(p.a.firm,p.b.firm);for(const [a,b,gain] of [[p.a,p.b,p.gainA],[p.b,p.a,p.gainB]]){assert.ok(gain>=10000&&gain<=a.allowance&&gain<=b.drawdown&&gain<=a.headroom);assert.equal(gain%1000,0);assert.ok(!ids.has(a.id));ids.add(a.id);}}
// Exact reported screenshots: daily losses restore allowance; website refreshes
// do not double-count realized P&L or reset total progress.
const mff=row('MFFUEVRPD608112146','MFF',{balance:52024.46,CurrentProfit:2024.46,CurrentBalance:52382.94,InitialBalance:52024.46,'Realized PnL':358.48,RealDrawdown:1679.76});
const fnLoss=fn('FNFTCHHAINGUYEN81629',{balance:51816.40,CurrentProfit:1816.40,CurrentBalance:51364.88,InitialBalance:51816.40,'Realized PnL':-451.52,RealDrawdown:1048.48,largestProfitDay:913.48});
assert.equal(S.account(mff).profit,238294);assert.equal(S.account(mff).remaining,61706);
assert.equal(S.gainAgainst(S.account(mff),S.account(fnLoss)),62000);
assert.equal(S.account(fnLoss).allowance,140152);assert.equal(S.account(fnLoss).remaining,113512);
const refreshed=JSON.parse(JSON.stringify(mff));refreshed.fields.balance=52382.94;refreshed.fields.CurrentProfit=2382.94;
assert.equal(S.account(refreshed).profit,S.account(mff).profit);
assert.equal(S.account(refreshed).remaining,S.account(mff).remaining);
assert.throws(()=>S.account(fn('DAILY927',{CurrentProfit:927.72,'Realized PnL':927.72,CurrentPnL:0})),/below the \$100 minimum/);
assert.equal(S.account(fn('DAILY600',{'Realized PnL':600,CurrentPnL:0})).allowance,35000);
assert.equal(S.account(fn('IGNORED',{CurrentPnL:-99999})).allowance,95000);
for(const bad of [{InitialBalance:null},{InitialBalance:50000},{'Realized PnL':null},{balance:null},{CurrentBalance:null}]){
 assert.throws(()=>S.account({...mff,fields:{...mff.fields,...bad}}));
}
const almost=S.account(row('ALMOST','MFF',{CurrentProfit:2999.99}));
assert.equal(S.gainAgainst(almost,S.account(fn('PARTNER'))),10000);
assert.equal(almost.headroom,10001);
assert.equal(S.suggest([row('LOW','FFF',{RealDrawdown:99.99}),fn('PARTNER')]).pairs.length,0);
const suggestion=S.draft(S.suggest([mff,fnLoss]).pairs[0],'b'.repeat(32));
assert.equal(S.validateDraft(suggestion),'');
assert.match(S.validateDraft({...suggestion,suggestion:{strategy:S.STRATEGY}}),/Older suggestion/);
const changed=JSON.parse(JSON.stringify(suggestion));changed.profit='99';assert.match(S.validateDraft(changed),/at least \$100/);
const mffSide=suggestion.left.account===mff.fields.id?'left':'right';
const over=JSON.parse(JSON.stringify(suggestion));over[mffSide==='left'?'profit':'rightProfit']='980';assert.match(S.validateDraft(over),/more than \$100/);
const stale=JSON.parse(JSON.stringify(suggestion));stale[mffSide].metrics.InitialBalance=stale[mffSide].metrics.CurrentBalance;assert.match(S.validateDraft(stale),/Daily P&L mismatch/);
console.log('PASS: consistency branches, losses, $50 buffer, prior largest day, caps, rounding, zero/tiny drawdown, firm isolation, priorities, random ties, exclusions, duplicate IDs and immutable input.');
