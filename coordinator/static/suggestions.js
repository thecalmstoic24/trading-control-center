'use strict';
// Beta: calculations and editable drafts only. No network or execution calls.
(() => {
 const STRATEGY='non-consistency-tests', REVISION=36, TICK_CENTS=1000, MIN_GAIN=10000, MAX_OVERSHOOT=10000, MAX_CENTS=10000000;
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
 function stage(fields){
  const keys=Object.keys(fields||{}).filter(k=>k.trim().toLowerCase()==='stage');
  if(keys.length!==1)return '';
  const text=value=>typeof value==='string'?value:value&&typeof value==='object'?String(value.name||''):'';
  const value=fields[keys[0]];return (Array.isArray(value)?value.map(text).join(' / '):text(value)).trim();
 }
 function account(row){
  const f=row.fields||{},id=typeof f.id==='string'?f.id.trim():'';
  if(!id||!row.id)throw Error('Missing account ID or Airtable record.');
  if(!/evaluation|challenge/i.test(stage(f)))throw Error('Stage must include Evaluation or Challenge.');
  const company=firm(f);if(!company)throw Error('Missing or ambiguous firm.');
  const drawdown=cents(f.RealDrawdown,'RealDrawdown'),target=cents(f.ProfitTarget,'ProfitTarget');
  const current=cents(f.CurrentBalance,'CurrentBalance'),opening=cents(f.InitialBalance,'InitialBalance');
  const websiteBalance=cents(f.balance,'balance'),websiteProfit=cents(f.CurrentProfit,'CurrentProfit');
  const today=cents(f['Realized PnL'],'Realized PnL'),balanceChange=current-opening;
  if(Math.min(current,opening,websiteBalance)<=0)throw Error('Balance fields must be positive.');
  if(Math.abs(balanceChange-today)>1)throw Error('Daily P&L mismatch: CurrentBalance minus InitialBalance is '+money(balanceChange)+', but Realized PnL is '+money(today)+'. Check today’s opening balance, flat positions, fees and sync before suggesting.');
  // balance and CurrentProfit must be from the SAME website snapshot. Anchor the
  // website profit to today's frozen opening balance, then apply today's change.
  // Never treat InitialBalance (day opening) as the original account size.
  const openingProfit=websiteProfit-(websiteBalance-opening);
  const profit=openingProfit+balanceChange;
  if(target<=0)throw Error('ProfitTarget must be positive.');
  const raw=f.Consistency, consistency=raw==null||(typeof raw==='string'&&!raw.trim())?0:number(raw,'Consistency');
  if(consistency<0||consistency>=1)throw Error('Consistency must be a decimal from 0 to below 1, for example 0.40.');
  let required=target,allowance=Infinity;
  if(consistency>0){
   const largest=cents(f.largestProfitDay,'largestProfitDay');
   if(largest<0)throw Error('largestProfitDay cannot be negative.');
   required=Math.max(target,Math.ceil(Math.max(largest,today)/consistency-1e-7));
   allowance=Math.max(0,Math.floor(required*consistency-5000-today+1e-7));
  }
  if(required>target+MAX_OVERSHOOT)throw Error('Consistency requires more than the allowed $100 above ProfitTarget. Review this account separately.');
  const headroom=Math.max(0,target+MAX_OVERSHOOT-profit);
  const remaining=Math.max(0,required-profit),loss=Math.min(MAX_CENTS,floorTick(Math.max(0,drawdown)));
  if(!remaining)throw Error('Profit requirement already reached.');
  if(loss<MIN_GAIN)throw Error('RealDrawdown cannot support a partner’s $100 minimum profit, before costs.');
  if(floorTick(allowance)<MIN_GAIN)throw Error('Remaining consistency allowance is below the $100 minimum profit today.');
  if(floorTick(headroom)<MIN_GAIN)throw Error('Less than $100 fits within the maximum target overshoot.');
  return {id,firm:company,row,drawdown,remaining,allowance,loss,required,headroom,profit,today,openingProfit};
 }
 function gainAgainst(a,b){
  // Round remaining profit UP to reach the target, but never round a risk cap up.
  let gain=Math.min(Math.max(MIN_GAIN,ceilTick(a.remaining+2500)),floorTick(a.allowance),b.loss,floorTick(a.headroom),MAX_CENTS);
  // A finishing trade must include the requested $25 cushion. Never exceed a cap.
  if(gain>=a.remaining&&gain<a.remaining+2500)gain=floorTick(a.remaining-1);
  return gain;
 }
 function suggest(rows,excluded=[],random=Math.random,history=[]){
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
   const gainA=gainAgainst(a,b),gainB=gainAgainst(b,a);if(Math.min(gainA,gainB)<MIN_GAIN)continue;
   const finishA=gainA>=a.remaining,finishB=gainB>=b.remaining;
   const priority=finishA||finishB?0:1;
   const distance=priority===0?Math.min(finishA?a.remaining:Infinity,finishB?b.remaining:Infinity):Math.min(a.remaining,b.remaining);
   const other=Math.max(a.remaining,b.remaining);
   edges.push({a,b,gainA,gainB,finishA,finishB,priority,distance,other,tie:random()});
  }
  const poolCounts=new Map(),firmUse=new Map(),accountUse=new Map();
  const accountFirm=new Map(accounts.map(a=>[a.id,a.firm]));
  for(const a of accounts)poolCounts.set(a.firm,(poolCounts.get(a.firm)||0)+1);
  const seenHistory=new Set();
  for(const r of history){
   const key=r.key||r.id;if(seenHistory.has(key)||r.status==='Cancelled')continue;seenHistory.add(key);
   for(const id of Object.values(r.spec?.accounts||{})){
    accountUse.set(id,(accountUse.get(id)||0)+1);const firm=accountFirm.get(id);
    if(firm)firmUse.set(firm,(firmUse.get(firm)||0)+1);
   }
  }
  const used=new Set(),pairs=[];
  const fairness=e=>(firmUse.get(e.a.firm)||0)/poolCounts.get(e.a.firm)+(firmUse.get(e.b.firm)||0)/poolCounts.get(e.b.firm);
  const reuse=e=>(accountUse.get(e.a.id)||0)+(accountUse.get(e.b.id)||0);
  const compare=(a,b)=>a.priority-b.priority||reuse(a)-reuse(b)||fairness(a)-fairness(b)||a.distance-b.distance||a.other-b.other||a.tie-b.tie;
  while(true){
   let edge=null;
   for(const candidate of edges)if(!used.has(candidate.a.id)&&!used.has(candidate.b.id)&&(!edge||compare(candidate,edge)<0))edge=candidate;
   if(!edge)break;
   for(const a of [edge.a,edge.b])firmUse.set(a.firm,(firmUse.get(a.firm)||0)+1);
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
   suggestion:{strategy:STRATEGY,revision:REVISION,reason:pair.reason}};
 }
 function validateDraft(d){
  if(d.suggestion?.strategy!==STRATEGY)return '';
  if(d.suggestion.revision!==REVISION)return 'Older suggestion: remove it and click Suggest pairs again.';
  if(!d.left||!d.right)return 'Suggested pairs need both accounts. Remove and suggest again.';
  try{
   const a=account({id:d.left.record,fields:{...d.left.metrics,id:d.left.account}}),b=account({id:d.right.record,fields:{...d.right.metrics,id:d.right.account}});
   if(a.firm===b.firm)return 'Same fund';
   for(const [own,partner,gainValue,lossValue] of [[a,b,d.profit,d.stopLoss],[b,a,d.rightProfit,d.rightStopLoss]]){
    const gain=cents(gainValue,'Profit'),loss=cents(lossValue,'Stop loss');
    if(gain<MIN_GAIN)return 'Suggested profit must be at least $100 on both sides.';
    if(gain>=own.remaining&&gain<own.remaining+2500)return own.id+': a final trade needs at least $25 above the remaining profit requirement.';
    if(gain>own.allowance)return own.id+': profit exceeds today’s consistency allowance. Refresh Planning and suggest again.';
    if(gain>own.headroom)return own.id+': profit exceeds ProfitTarget by more than $100. Refresh Planning and suggest again.';
    if(gain>partner.drawdown||loss>own.drawdown)return own.id+': suggested amounts exceed RealDrawdown. Refresh Planning and suggest again.';
   }
  }catch(e){return e.message;}
  return '';
 }
 const api={STRATEGY,REVISION,TICK_CENTS,MIN_GAIN,MAX_OVERSHOOT,firm,stage,account,gainAgainst,suggest,draft,validateDraft};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else window.PairSuggestions=api;
})();
