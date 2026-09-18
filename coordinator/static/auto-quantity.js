'use strict';
(() => {
 const node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 let config={enabled:false,vm:'',bars:10,multiplier:1,reference:'',timeframe:1,excludeAboveMedian:0},fleet=[];
 const host=node('section');host.className='auto-settings';host.setAttribute('aria-label','Auto Quantity settings');
 const header=node('div');header.className='auto-heading';header.append(node('h2','Auto Quantity'));
 const enable=node('input');enable.type='checkbox';const enabledLabel=node('label','Enable · Beta ');enabledLabel.append(enable);header.append(enabledLabel);
 const source=node('select');source.setAttribute('aria-label','Candle source VM');
 const reference=node('input');reference.setAttribute('list','auto-reference-options');reference.placeholder='NQ DEC26';reference.setAttribute('aria-label','Reference instrument and contract');
 const referenceOptions=node('datalist');referenceOptions.id='auto-reference-options';
 const timeframe=node('select');for(const n of [1,3,5,15]){const o=node('option',n+' min');o.value=n;timeframe.append(o);}
 const number=(min,max,step,value)=>{const n=node('input');n.type='number';Object.assign(n,{min,max,step,value});return n;};
 const bars=number(1,100,1,10),multiplier=number(.1,20,.1,1),exclusion=number(0,20,.1,0);
 const save=node('button','Save sizing settings');save.type='button';
 const preview=node('button','Preview sizing');preview.type='button';preview.className='quiet';
 const message=node('p','Off by default. Select a source chart with the same reference and timeframe.');message.setAttribute('role','status');
 const label=(text,input)=>{const l=node('label',text);l.append(input);return l;};
 const fields=node('div');fields.className='auto-fields';fields.append(label('Source VM',source),label('Reference',reference),label('Timeframe',timeframe),label('Lookback · bars',bars),label('Distance · ×',multiplier),label('Exclude above median · × (0 = off)',exclusion));
 const actions=node('div');actions.className='auto-actions';actions.append(save,preview);
 host.append(header,fields,referenceOptions,node('p','Anchor: left profit target · Auto NQ / MNQ · Preserve ratio. Recalculate before each trade; lock at Preparing.'),actions,message);
 const accounts=document.querySelector('.planning-accounts'),intro=node('div');intro.className='planning-intro';
 const controls=node('div');controls.className='planning-intro-controls';
 while(accounts.firstChild&&!accounts.firstChild.classList?.contains('planning-scroll'))controls.append(accounts.firstChild);
 intro.append(controls,host);accounts.prepend(intro);
 function apply(){enable.checked=config.enabled;bars.value=config.bars;multiplier.value=config.multiplier;reference.value=config.reference||reference.value;timeframe.value=config.timeframe||1;exclusion.value=config.excludeAboveMedian||0;source.value=config.vm;document.body.classList.toggle('auto-enabled',config.enabled);window.dispatchEvent(new Event('auto-quantity-changed'));}
 function sources(){const previous=source.value||config.vm;source.replaceChildren();const blank=node('option','Select VM');blank.value='';source.append(blank);for(const vm of fleet){const o=node('option',vm.name);o.value=vm.id;source.append(o);}source.value=previous;}
 const settings=()=>({enabled:enable.checked,vm:source.value,bars:Number(bars.value),multiplier:Number(multiplier.value),reference:reference.value.trim().toUpperCase(),timeframe:Number(timeframe.value),excludeAboveMedian:Number(exclusion.value)});
 window.autoQuantity={configuration:()=>({...config}),estimate:async d=>{
   if(!config.enabled)return;
   const result=await api('/api/auto-quantity/estimate',{config,spec:{ticker:d.ticker,profit:Number(d.profit),ratio:d.ratio}});
   d.ticker=result.ticker;d.leftQuantity=String(result.leftQuantity);d.rightQuantity=String(result.rightQuantity);
   d.notice=`Auto estimate: ${result.leftQuantity}/${result.rightQuantity} ${result.ticker}; ${result.distance.toFixed(2)} points. Recalculated before Preparing.`;
   return result;
 }};
 save.onclick=async()=>{save.disabled=true;try{config=await api('/api/auto-quantity',settings());apply();message.textContent='Saved. New pairs use these settings; confirmed pairs retain theirs.';}catch(e){message.textContent=e.message;}finally{save.disabled=false;}};
 preview.onclick=async()=>{preview.disabled=true;try{
   const card=document.querySelector('.draft-card'),profit=Number(card?.querySelector('[data-value-key=profit]')?.value),ratio=card?.querySelector('[data-field=ratio]')?.value||'1:1';
   if(!card||!(profit>0))throw Error('Add a pair and enter its left profit target to preview sizing.');
   const result=await api('/api/auto-quantity/estimate',{config:{...settings(),enabled:true},spec:{ticker:card.querySelector('[data-field=ticker]').value,profit,ratio}});
   message.textContent=`Preview: ${result.leftQuantity}/${result.rightQuantity} ${result.ticker} · ${result.distance.toFixed(2)} points · ${result.usedBars??result.bars} candles used. Settings are not saved by previewing.`;
 }catch(e){message.textContent=e.message;}finally{preview.disabled=false;}};
 window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];sources();});
 api('/api/contracts').then(c=>{for(const v of Object.values(c.symbols)){const o=node('option');o.value=v;referenceOptions.append(o);}if(!reference.value)reference.value=c.symbols.NQ;}).catch(()=>{});
 api('/api/auto-quantity').then(value=>{config=value;sources();apply();}).catch(e=>message.textContent=e.message);
 const frame=node('iframe');frame.className='tv-chart';frame.title='Live TradingView Nasdaq futures chart';frame.loading='lazy';frame.referrerPolicy='no-referrer';
 // TradingView's iframe configuration is JSON in the URL fragment, not query settings.
 frame.src='https://www.tradingview-widget.com/embed-widget/advanced-chart/#'+encodeURIComponent(JSON.stringify({symbol:'CME_MINI:NQ1!',interval:'1',timezone:'America/Chicago',theme:'light',style:'1',locale:'en',allow_symbol_change:true,hide_top_toolbar:false,save_image:false,withdateranges:false}));
 document.getElementById('trading-panel').append(frame);
 const leftPanel=document.querySelector('#trading-split>.queue-section');
 const alignChart=()=>{const width=leftPanel.getBoundingClientRect().width;if(width>0)frame.style.width=width+'px';};
 new ResizeObserver(alignChart).observe(leftPanel);alignChart();
 const errors=document.getElementById('nav-errors');let rows=[];
 function showErrors(){const ids=new Set(rows.filter(r=>['Error','Need check'].includes(r.status)&&!r.errorReleased).flatMap(r=>Object.values(r.spec?.names||{})));for(const vm of fleet)if(!vm.online||vm.refresh?.status==='error')ids.add(vm.name);errors.textContent=ids.size?'Error · '+[...ids].join(', '):'';}
 window.addEventListener('fleet-updated',showErrors);window.addEventListener('queue-updated',e=>{rows=e.detail.rows||[];showErrors();});
})();
