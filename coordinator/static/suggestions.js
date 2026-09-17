'use strict';
// Beta: calculations and editable drafts only. No network or execution calls.
(() => {
 const STRATEGY='non-consistency-tests', TICK_CENTS=1000, MAX_CENTS=10000000;
 const money=c=>new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(c/100);
 function number(value,name){
  if(typeof value==='string'&&/^-?\d+(?:\.\d+)?$/.test(value.trim()))value=Number(value);
  if(typeof value!=='number'||!Number.isFinite(value))throw Error('Missing or invalid '+name+'.');
  return value;
 }
 function cents(value,name){const n=number(value,name);if(Math.abs(n)>10000000)throw Error(name+' is outside the supported range.');return Math.round(n*100);}
 function firm(fields){
  const keys=Object.keys(fields||{}).filter(k=>k.trim().toLowerCase()==='firm');if(keys.length!==1)return '';
  let value=fields[keys[0]];
  if(Array.isArray(value)){if(value.length!==1)return '';value=value[0];}
  if(value&&typeof value==='object')value=value.name;
  return typeof value==='string'?value.trim().replace(/\s+/g,' ').toUpperCase():'';
 }
 const floorTick=n=>Math.floor((n+1e-7)/TICK_CENTS)*TICK_CENTS;
 const ceilTick=n=>Math.ceil((n-1e-7)/TICK_CENTS)*TICK_CENTS;
 function account(row){
  const f=row.fields||{},id=typeof f.id==='string'?f.id.trim():'';
  if(!id||!row.id)throw Error('Missing account ID or Airtable record.');
  const company=firm(f);if(!company)throw Error('Missing or ambiguous firm.');
  const drawdown=cents(f.RealDrawdown,'RealDrawdown'),profit=cents(f.CurrentProfit,'CurrentProfit'),target=cents(f.ProfitTarget,'ProfitTarget');
  if(target<=0)throw Error('ProfitTarget must be positive.');
  const raw=f.Consistency, consistency=raw==null||(typeof raw==='string'&&!raw.trim())?0:number(raw,'Consistency');
  if(consistency<0||consistency>=1)throw Error('Consistency must be a decimal from 0 to below 1, for example 0.40.');
  let required=target,allowance=Infinity;
  if(consistency>0){
   const today=cents(f.CurrentPnL,'CurrentPnL'),largest=cents(f.largestProfitDay,'largestProfitDay');
   if(largest<0)throw Error('largestProfitDay cannot be negative.');
   required=Math.max(target,Math.ceil(Math.max(largest,today)/consistency-1e-7));
   allowance=Math.max(0,Math.floor(required*consistency-5000-today+1e-7));
  }
  const remaining=Math.max(0,required-profit),loss=Math.min(MAX_CENTS,floorTick(Math.max(0,drawdown)));
  if(!remaining)throw Error('Profit requirement already reached.');
  if(loss<TICK_CENTS)throw Error('RealDrawdown is below one price tick for 2 NQ ($10), before costs.');
  if(floorTick(allowance)<TICK_CENTS)throw Error('No remaining consistency allowance for 2 NQ today.');
  return {id,firm:company,row,drawdown,remaining,allowance,loss,required};
 }
 function gainAgainst(a,b){
  // Round remaining profit UP to reach the target, but never round a risk cap up.
  return Math.min(ceilTick(a.remaining),floorTick(a.allowance),b.loss,MAX_CENTS);
 }
 function suggest(rows,excluded=[],random=Math.random){
  if(rows.length>1000)throw Error('Select at most 1,000 accounts for this beta suggestion batch.');
  const blocked=new Set(excluded),seen=new Map(),skipped=[],accounts=[];
  for(const row of rows){const id=String(row.fields?.id||'').trim();seen.set(id,(seen.get(id)||0)+1);}
  for(const row of rows){
   const id=String(row.fields?.id||'').trim();
   try{
    if(seen.get(id)>1)throw Error('Duplicate account ID in this list.');
    if(blocked.has(id))throw Error('Already in Build Pairs, the queue, or an assigned pair.');
    accounts.push(account(row));
   }catch(e){skipped.push({account:id||String(row.id||'Unknown account'),reason:e.message});}
  }
  const edges=[];
  for(let i=0;i<accounts.length;i++)for(let j=i+1;j<accounts.length;j++){
   const a=accounts[i],b=accounts[j];if(a.firm===b.firm)continue;
   const gainA=gainAgainst(a,b),gainB=gainAgainst(b,a);if(Math.min(gainA,gainB)<TICK_CENTS)continue;
   const finishA=gainA>=a.remaining,finishB=gainB>=b.remaining;
   const priority=finishA||finishB?0:1;
   const distance=priority===0?Math.min(finishA?a.remaining:Infinity,finishB?b.remaining:Infinity):Math.min(a.remaining,b.remaining);
   const other=Math.max(a.remaining,b.remaining);
   edges.push({a,b,gainA,gainB,finishA,finishB,priority,distance,other,tie:random()});
  }
  edges.sort((a,b)=>a.priority-b.priority||a.distance-b.distance||a.other-b.other||a.tie-b.tie);
  const used=new Set(),pairs=[];
  for(const edge of edges){
   if(used.has(edge.a.id)||used.has(edge.b.id))continue;
   const preferred=(edge.finishB&&!edge.finishA)||((edge.finishA===edge.finishB)&&edge.b.remaining<edge.a.remaining);
   if(preferred){[edge.a,edge.b]=[edge.b,edge.a];[edge.gainA,edge.gainB]=[edge.gainB,edge.gainA];[edge.finishA,edge.finishB]=[edge.finishB,edge.finishA];}
   edge.reason=edge.priority===0?edge.a.id+': '+money(edge.a.remaining)+' remaining; one winning trade can reach the profit requirement before costs.':edge.a.id+': '+money(edge.a.remaining)+' remaining; target limited by consistency or the partner’s drawdown.';
   pairs.push(edge);used.add(edge.a.id);used.add(edge.b.id);
  }
  for(const a of accounts)if(!used.has(a.id))skipped.push({account:a.id,reason:'No unused different-firm partner with compatible gain and loss limits.'});
  return {pairs,skipped};
 }
 function draft(pair,key){
  const item=a=>({account:a.id,master:String(a.row.fields['Master Account']||''),record:a.row.id,balance:a.row.fields.CurrentBalance??null,metrics:{...a.row.fields},vm:''});
  return {key,ticker:'NQ',direction:'buy',ratio:'1:1',leftQuantity:'2',rightQuantity:'2',
   left:item(pair.a),right:item(pair.b),profit:String(pair.gainA/100),stopLoss:String(pair.gainB/100),rightProfit:String(pair.gainB/100),rightStopLoss:String(pair.gainA/100),
   suggestion:{strategy:STRATEGY,reason:pair.reason}};
 }
 const api={STRATEGY,TICK_CENTS,firm,account,gainAgainst,suggest,draft};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else window.PairSuggestions=api;
})();
