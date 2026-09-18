'use strict';
// New Non-consistency: complete multipartite matching, with randomized ties.
(() => {
 const STRATEGY='new-non-consistency',REVISION=37;
 const scalar=v=>Array.isArray(v)&&v.length===1?scalar(v[0]):v&&typeof v==='object'&&!Array.isArray(v)?v.name:v;
 function numeric(v,name){v=scalar(v);if(typeof v==='string'&&v.trim())v=Number(v);if(typeof v!=='number'||!Number.isFinite(v))throw Error('Missing or invalid '+name+'.');return v;}
 function account(row){
  const f=row.fields||{},id=String(f.id||'').trim();
  if(!id||!row.id)throw Error('Missing account ID or Airtable record.');
  if(String(scalar(f.RealStage)||'').trim().toLowerCase()!=='funded')throw Error('RealStage must be Funded.');
  if(numeric(f.NoConsistency,'NoConsistency')!==1)throw Error('NoConsistency must equal 1.');
  const balance=numeric(f.RealCurrentBalance,'RealCurrentBalance');
  if(balance<48700||balance>50300)throw Error('RealCurrentBalance must be between $48,700 and $50,300, inclusive.');
  const firm=PairSuggestions.firm(f);if(!firm)throw Error('Missing or ambiguous firm.');
  const dd=numeric(f.RealDrawdown,'RealDrawdown');
  if(dd<=0||dd>100000)throw Error('RealDrawdown must be positive and at most $100,000.');
  const loss=Math.ceil((Math.round(dd*100)-1e-7)/1000)*1000;
  if(loss<=0)throw Error('RealDrawdown must be at least one cent.');
  return {id,firm,row,balance,drawdown:Math.round(dd*100),loss};
 }
 function suggest(rows,excluded=[],random=Math.random,history=[]){
  if(rows.length>1000)throw Error('Select at most 1,000 accounts for this beta suggestion batch.');
  const blocked=new Set(excluded),counts=new Map(),groups=new Map(),skipped=[],sideUse=new Map();
  for(const row of rows){const id=String(row.fields?.id||'').trim();counts.set(id,(counts.get(id)||0)+1);}
  const seenHistory=new Set();
  for(const r of history){
   const key=r.key||r.id;if(!key||seenHistory.has(key)||r.status==='Cancelled')continue;seenHistory.add(key);
   for(const side of ['left','right']){const id=r.spec?.accounts?.[r.spec?.[side]];if(id)sideUse.set(id,(sideUse.get(id)||0)+(side==='left'?1:-1));}
  }
  for(const row of rows){const id=String(row.fields?.id||'').trim();try{
   if(counts.get(id)>1)throw Error('Duplicate account ID in this list.');
   if(blocked.has(id))throw Error('Already in Build Pairs, the queue, or an assigned pair.');
   const a=account(row);if(!groups.has(a.firm))groups.set(a.firm,[]);groups.get(a.firm).push(a);
  }catch(e){skipped.push({account:id||String(row.id||'Unknown account'),reason:e.message});}}
  const pairs=[],firmSides=new Map();
  while(true){
   // Taking from the two largest remaining firms guarantees the maximum pair
   // count: min(floor(total/2), total - largestFirm). No greedy stranded firms.
   const ranked=[...groups].filter(([,a])=>a.length).map(([firm,items])=>({firm,items,tie:random()})).sort((a,b)=>b.items.length-a.items.length||a.tie-b.tie);
   if(ranked.length<2)break;
   const ga=ranked[0],gb=ranked[1];let choice=null;
   for(let i=0;i<ga.items.length;i++)for(let j=0;j<gb.items.length;j++){
    const a=ga.items[i],b=gb.items[j],cost=Math.abs(a.loss-b.loss),tie=random();
    if(!choice||cost<choice.cost||(cost===choice.cost&&tie<choice.tie))choice={i,j,cost,tie};
   }
   let a=ga.items.splice(choice.i,1)[0],b=gb.items.splice(choice.j,1)[0];
   const score=(l,r)=>Math.abs((sideUse.get(l.id)||0)+1)+Math.abs((sideUse.get(r.id)||0)-1)+Math.abs((firmSides.get(l.firm)||0)+1)+Math.abs((firmSides.get(r.firm)||0)-1);
   const ab=score(a,b),ba=score(b,a);if(ba<ab||(ba===ab&&random()<.5))[a,b]=[b,a];
   sideUse.set(a.id,(sideUse.get(a.id)||0)+1);sideUse.set(b.id,(sideUse.get(b.id)||0)-1);
   firmSides.set(a.firm,(firmSides.get(a.firm)||0)+1);firmSides.set(b.firm,(firmSides.get(b.firm)||0)-1);
   pairs.push({a,b,gainA:b.loss,gainB:a.loss,reason:'Funded · NoConsistency 1 · different firms. Currency targets use the opposing RealDrawdown rounded up to the next $10.'});
  }
  for(const items of groups.values())for(const a of items)skipped.push({account:a.id,reason:'No different-firm partner remains; maximum possible pair count reached.'});
  return {pairs,skipped};
 }
 function draft(pair,key){const d=PairSuggestions.draft(pair,key);d.suggestion={strategy:STRATEGY,revision:REVISION,reason:pair.reason};for(const side of ['left','right'])d[side].balance=d[side].metrics.RealCurrentBalance;return d;}
 function validateDraft(d){
  if(d.suggestion?.strategy!==STRATEGY)return '';
  if(d.suggestion.revision!==REVISION)return 'Older suggestion: remove it and click Suggest pairs again.';
  try{
   if(!d.left||!d.right)throw Error('New Non-consistency requires two accounts.');
   const a=account({id:d.left.record,fields:{...d.left.metrics,id:d.left.account}}),b=account({id:d.right.record,fields:{...d.right.metrics,id:d.right.account}});
   if(a.id===b.id)throw Error('Choose two different accounts.');
   if(a.firm===b.firm)throw Error('Same fund');
   for(const [own,other,gain,loss] of [[a,b,d.profit,d.stopLoss],[b,a,d.rightProfit,d.rightStopLoss]]){
    const g=numeric(gain,'Profit'),l=numeric(loss,'Stop loss');
    if(g<=0||l<=0||Math.round(g*100)>other.loss||Math.round(l*100)>own.loss)throw Error(own.id+': amounts exceed the rounded drawdown preset. Refresh Planning or adjust amounts.');
   }
  }catch(e){return e.message;}
  return '';
 }
 const api={STRATEGY,REVISION,account,suggest,draft,validateDraft};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else window.FundedSuggestions=api;
})();
