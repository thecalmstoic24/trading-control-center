'use strict';
(() => {
 const node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 let config={enabled:false,vm:'',bars:10,multiplier:1},fleet=[];
 const host=node('section');host.className='auto-settings';
 const enable=node('input');enable.type='checkbox';const enabledLabel=node('label','Auto Quantity Beta ');enabledLabel.append(enable);
 const source=node('select');source.setAttribute('aria-label','Candle source VM');
 const bars=node('input');bars.type='number';bars.min=1;bars.max=100;bars.value=10;
 const multiplier=node('input');multiplier.type='number';multiplier.min=.1;multiplier.max=20;multiplier.step=.1;multiplier.value=1;
 const save=node('button','Save sizing settings');save.type='button';const message=node('p','Off by default. Uses completed 1-minute NinjaTrader candles from one VM.');
 const label=(text,input)=>{const l=node('label',text);l.append(input);return l;};
 host.append(enabledLabel,label('Candle source VM',source),label('Completed bars',bars),label('Distance multiplier',multiplier),save,message);
 document.getElementById('draft-list').before(host);
 function apply(){enable.checked=config.enabled;bars.value=config.bars;multiplier.value=config.multiplier;source.value=config.vm;document.body.classList.toggle('auto-enabled',config.enabled);window.dispatchEvent(new Event('auto-quantity-changed'));}
 function sources(){const previous=source.value||config.vm;source.replaceChildren();const blank=node('option','Select VM');blank.value='';source.append(blank);for(const vm of fleet){const o=node('option',vm.name);o.value=vm.id;source.append(o);}source.value=previous;}
 window.autoQuantity={configuration:()=>({...config}),estimate:async d=>{
   if(!config.enabled)return;
   const result=await api('/api/auto-quantity/estimate',{config,spec:{ticker:d.ticker,profit:Number(d.profit),ratio:d.ratio}});
   d.ticker=result.ticker;d.leftQuantity=String(result.leftQuantity);d.rightQuantity=String(result.rightQuantity);
   d.notice=`Auto estimate: ${result.leftQuantity}/${result.rightQuantity} ${result.ticker}; ${result.distance.toFixed(2)} points. Recalculated before Preparing.`;
   return result;
 }};
 save.onclick=async()=>{save.disabled=true;try{config=await api('/api/auto-quantity',{enabled:enable.checked,vm:source.value,bars:Number(bars.value),multiplier:Number(multiplier.value)});apply();message.textContent='Saved. New pairs use these settings; confirmed pairs retain theirs.';}catch(e){message.textContent=e.message;}finally{save.disabled=false;}};
 window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];sources();});
 api('/api/auto-quantity').then(value=>{config=value;sources();apply();}).catch(e=>message.textContent=e.message);
 const frame=node('iframe');frame.className='tv-chart';frame.title='Live TradingView Nasdaq futures chart';frame.loading='lazy';frame.src='https://www.tradingview.com/widgetembed/?symbol=CME_MINI%3ANQ1!&interval=1&theme=light&style=1&locale=en';
 document.getElementById('trading-panel').append(frame);
 const errors=document.getElementById('nav-errors');let rows=[];
 function showErrors(){const ids=new Set(rows.filter(r=>['Error','Need check'].includes(r.status)&&!r.errorReleased).flatMap(r=>Object.values(r.spec?.names||{})));for(const vm of fleet)if(!vm.online||vm.refresh?.status==='error')ids.add(vm.name);errors.textContent=ids.size?'Error · '+[...ids].join(', '):'';}
 window.addEventListener('fleet-updated',showErrors);window.addEventListener('queue-updated',e=>{rows=e.detail.rows||[];showErrors();});
})();
