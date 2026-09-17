'use strict';
// Preserve editable trade settings and displayed metrics, never full Airtable records.
function compactPairDraft(d){
 const result={};
 if(d.suggestion?.strategy==='non-consistency-tests')result.suggestion={strategy:d.suggestion.strategy,reason:String(d.suggestion.reason||'').slice(0,500)};
 for(const k of ['key','ticker','direction','ratio','leftQuantity','rightQuantity','stopLoss','profit','rightStopLoss','rightProfit'])if(d[k]!==undefined)result[k]=d[k];
 for(const side of ['left','right']){
  const item=d[side];if(!item)continue;
  const slot={};for(const k of ['account','master','record','vm'])slot[k]=String(item[k]??'').slice(0,256);
  slot.balance=typeof item.balance==='number'&&Number.isFinite(item.balance)?item.balance:null;
  slot.metrics={};for(const k of ['CurrentBalance','Realized PnL','stop','Trailing max drawdown','largestProfitDay','tradingDays']){
   const value=item.metrics?.[k];slot.metrics[k]=typeof value==='number'&&Number.isFinite(value)?value:null;
  }
  if(result.suggestion){
   slot.metrics.firm=PairSuggestions.firm(item.metrics);
   for(const k of ['RealDrawdown','CurrentProfit','ProfitTarget','Consistency','CurrentPnL']){
    const v=item.metrics?.[k];slot.metrics[k]=typeof v==='number'&&Number.isFinite(v)?v:null;
   }
  }
  result[side]=slot;
 }
 return result;
}
