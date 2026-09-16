'use strict';
(() => {
  const el=id=>document.getElementById(id), make=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const storage='planning-draft-pairs-v1';let drafts=[],fleet=[],pairs=[],queued=[];
  try{const value=JSON.parse(localStorage.getItem(storage));if(Array.isArray(value))drafts=value.filter(d=>/^[a-f0-9]{32}$/.test(d.key)&&(d.left||d.right));}catch(_){}
  for(const d of drafts){d.ratio=d.ratio||'1:1';PairRatio.amounts(d);}
  const inFlight=new Set();
  function save(){drafts=drafts.filter(d=>d.left||d.right);try{localStorage.setItem(storage,JSON.stringify(drafts));}catch(_){el('draft-message').textContent='Drafts cannot be saved in this browser. Keep this page open.';}}
  function usage(){
    const map={};const mark=(account,status)=>{if(!account)return;const u=map[account]||(map[account]={used:true,status:''});if(status==='Pairing'||!u.status)u.status=status;};
    for(const d of drafts)for(const side of ['left','right'])mark(d[side]?.account,'');
    for(const r of queued){if(['Complete','Cancelled'].includes(r.status))continue;for(const a of Object.values(r.spec.accounts||{}))mark(a,['Trading','Awaiting results'].includes(r.status)?'Pairing':'Queue');}
    for(const p of pairs){if(p.closedSequence>0&&!p.active&&!p.prepared)continue;for(const a of Object.values(p.settings?.accounts||{}))mark(a,'Pairing');}
    window.dispatchEvent(new CustomEvent('account-usage',{detail:map}));
  }
  function candidates(account){return fleet.filter(v=>(v.accounts||v.lastKnown?.accounts||[]).includes(account));}
  function chooseVM(item){const list=candidates(item.account);if(!list.some(v=>v.id===item.vm))item.vm='';if(!item.vm&&list.length===1)item.vm=list[0].id;return list;}
  function add(side){
    const rows=window.planningSelection.rows();if(!rows.length){el('draft-message').textContent='Check an account in the table first.';return;}
    for(const row of rows){
      const account=String(row.fields.id||'');if(!account)continue;
      let d=drafts.find(d=>!d[side]&&!inFlight.has(d.key));
      if(!d){d={key:crypto.randomUUID().replaceAll('-',''),ticker:'NQ',direction:'buy',ratio:'1:1',rightStopLoss:'0',rightProfit:'0',stopLoss:'0',profit:'0',leftQuantity:'1',rightQuantity:'1'};drafts.push(d);}
      d[side]={account,master:String(row.fields['Master Account']||''),record:row.id,balance:row.fields.CurrentBalance??null,metrics:row.fields,vm:''};chooseVM(d[side]);
    }
    window.planningSelection.clear();el('draft-message').textContent='Accounts added to drafts.';save();render();usage();
  }
  function fillSlot(d,side){
    if(d[side]||inFlight.has(d.key))return;
    const rows=window.planningSelection.rows();
    if(rows.length!==1){el('draft-message').textContent='Select exactly one account in the table, then click the empty box.';return;}
    const row=rows[0],account=String(row.fields.id||'');if(!account)return;
    d[side]={account,master:String(row.fields['Master Account']||''),record:row.id,balance:row.fields.CurrentBalance??null,metrics:row.fields,vm:''};chooseVM(d[side]);
    window.planningSelection.clear();el('draft-message').textContent='Selected account added to this slot.';save();render();usage();
  }
  const fund=item=>{const name=(item?.master||'').trim().toUpperCase();return name.match(/^(MFF|LCD|FN|BUL|APEX|TOPSTEP|OX)/)?.[0]||name.split(/[-_\s]+/)[0];};
  function problem(d){
    if(d.left&&d.right&&fund(d.left)&&fund(d.left)===fund(d.right))return 'Same fund';
    const l=Number(d.leftQuantity),r=Number(d.rightQuantity),[a,b]=d.ratio.split(':').map(Number);
    if(!Number.isInteger(l)||!Number.isInteger(r)||l<1||r<1||l>1000||r>1000||l*b!==r*a)return 'Invalid quantity';
    return '';
  }
  function validateCard(card,d){
    const error=problem(d),button=card.querySelector('button[type=submit]');
    if(!button)return;
    button.disabled=!!error||(!d.left&&!d.right)||inFlight.has(d.key);
    button.textContent=inFlight.has(d.key)?'Adding…':error==='Same fund'?'Same fund':(!d.left||!d.right)?'Confirm Single Pair':'Confirm pair';
    card.querySelector('.draft-notice').textContent=error==='Invalid quantity'?(d.notice||'Invalid quantity: whole contracts only. Adjust quantity or ratio.'):d.notice||'';
  }
  let dragged=null;
  function input(form,d,key,label,type='text',alias=key){
    const l=make('label',label),n=make('input');n.type=type;n.value=d[key];n.required=true;n.dataset.field=alias;n.dataset.valueKey=key;
    if(type==='number'){n.min=key.includes('Quantity')?'1':'0.01';n.max=key.includes('Quantity')?'1000':'100000';n.step=key.includes('Quantity')?'1':'0.01';}
    n.oninput=()=>{
      PairRatio.edit(d,key,n.value);
      for(const other of form.closest('form').querySelectorAll('input[data-value-key]')){
        if(other!==n||/^MNQ(?: |$)/.test(d.ticker))other.value=d[other.dataset.valueKey];
      }
      const card=form.closest('form');card.querySelector('[data-field=ticker]').value=d.ticker;card.querySelector('.draft-notice').textContent=d.notice||'';
      validateCard(card,d);save();
    };l.append(n);form.append(l);
  }
  function updateMetrics(host,item){
    const f=item?.metrics||{},fmt=v=>v==null?'—':new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(v);
    host.replaceChildren();
    const line=make('p');line.className='draft-balance';line.append(make('span','Current Balance: '+fmt(item?.balance)+' · '));
    const pnl=f['Realized PnL'],value=make('span','Realized P&L: '+fmt(pnl));value.className='realized-pnl '+(pnl>0?'queue-win':pnl<0?'queue-loss':'');line.append(value);host.append(line);
    if(item?.metrics){const dd=[f.CurrentBalance,f.stop,f['Trailing max drawdown']].every(v=>typeof v==='number'&&Number.isFinite(v))?f.CurrentBalance-f.stop+f['Trailing max drawdown']:null;
      for(const [label,value] of [['Drawdown',fmt(dd)],['Stop',fmt(f.stop)],['Largest profit day',fmt(f.largestProfitDay)],['Trading days',f.tradingDays??'—']]){const metric=make('div',label+': '+value);metric.className='pair-secondary-metrics';host.append(metric);}
    }
  }
  function render(){
    const list=el('draft-list');list.replaceChildren();
    if(!drafts.length){list.append(make('p','No planned pairs yet. Add two accounts to begin.'));return;}
    drafts.forEach(d=>{
      const card=make('form');card.className='draft-card';card.dataset.key=d.key;
      const disabled=make('fieldset');disabled.disabled=inFlight.has(d.key);card.append(disabled);
      const accountsGrid=make('div');accountsGrid.className='draft-pair-grid';disabled.append(accountsGrid);
      for(const side of ['left','right']){
        if(side==='right'){
          const swap=make('button','⇄');swap.type='button';swap.className='draft-swap';swap.title='Swap accounts and their settings';swap.setAttribute('aria-label','Swap accounts and their settings');
          swap.onclick=()=>{PairRatio.swap(d);save();render();usage();};
          const center=make('div');center.className='draft-center';center.append(swap);
          const label=make('label','Ratio'),select=make('select');select.dataset.field='ratio';select.setAttribute('aria-label','Pair ratio');
          for(const value of PairRatio.options){const opt=make('option',value);opt.value=value;select.append(opt);}select.value=d.ratio;
          select.onchange=()=>{d.ratio=select.value;PairRatio.amounts(d);PairRatio.quantities(d);save();render();};label.append(select);center.append(label);accountsGrid.append(center);
        }
        const item=d[side],block=make('div');block.className='draft-account';block.dataset.side=side;block.classList.toggle('empty',!item);block.draggable=!!item&&!inFlight.has(d.key);
        block.ondragstart=e=>{dragged={key:d.key,side};e.dataTransfer.setData('application/x-pair-account',JSON.stringify(dragged));e.dataTransfer.effectAllowed='move';};
        block.ondragend=()=>{dragged=null;document.querySelectorAll('.drop-target').forEach(n=>n.classList.remove('drop-target'));};
        block.ondragover=e=>{if(dragged&&!inFlight.has(d.key)){e.preventDefault();block.classList.add('drop-target');}};
        block.ondragleave=()=>block.classList.remove('drop-target');
        block.ondrop=e=>{
          e.preventDefault();block.classList.remove('drop-target');if(!dragged||inFlight.has(d.key))return;
          const source=drafts.find(x=>x.key===dragged.key),from=dragged.side;dragged=null;
          if(!source||inFlight.has(source.key)||!source[from]||(source===d&&from===side))return;
          const previous=d[side];d[side]=source[from];if(previous)source[from]=previous;else delete source[from];
          save();render();usage();
        };
        block.append(make('strong',item?.master||'Select an account'));
        block.append(make('p',item?.account||'Add an account from the table'));
        const metrics=make('div');metrics.className='draft-metrics';updateMetrics(metrics,item);block.append(metrics);
        const direction=make('button',(side==='left')===(d.direction==='buy')?'Buy':'Sell');direction.type='button';direction.className='quiet draft-direction';direction.title='Reverse trade direction';direction.onclick=()=>{d.direction=d.direction==='buy'?'sell':'buy';save();render();};block.append(direction);
        if(item){
          const remove=make('button','×');remove.type='button';remove.className='quiet account-remove';remove.setAttribute('aria-label','Remove account '+item.account);
          remove.onclick=()=>{delete d[side];save();render();usage();};block.append(remove);
          const choices=chooseVM(item);
          const note=make('small',!choices.length?'No registered VM lists this account yet. Refresh it in VMs.':!item.vm?'Multiple VMs match this account. Resolve its registration before confirming.':'');note.className='vm-match-note';block.append(note);
        }
        if(!item){
          const add=make('button','+ Add selected account');add.type='button';add.className='empty-add';add.onclick=e=>{e.stopPropagation();fillSlot(d,side);};block.append(add);
          block.onclick=e=>{if(e.target.closest('button'))return;fillSlot(d,side);};
        }
        const amounts=make('div');amounts.className='draft-amounts';
        input(amounts,d,side+'Quantity','Quantity','number');
        input(amounts,d,side==='left'?'profit':'rightProfit','Profit','number');
        input(amounts,d,side==='left'?'stopLoss':'rightStopLoss','Stop loss','number');
        if(side==='left')accountsGrid.append(block,amounts);else accountsGrid.append(amounts,block);
      }
      const footer=make('div');footer.className='draft-footer';disabled.append(footer);
      const instrumentLabel=make('label','Instrument'),instrument=make('select');instrument.dataset.field='ticker';
      const companion=d.ticker.replace(/^(?:MNQ|NQ)(?= |$)/,root=>root==='NQ'?'MNQ':'NQ');
      for(const value of [...new Set(['NQ','MNQ',d.ticker,companion])]){const opt=make('option',value);opt.value=value;instrument.append(opt);}instrument.value=d.ticker;
      instrument.onchange=()=>{
        PairRatio.setInstrument(d,instrument.value);save();render();
      };instrumentLabel.append(instrument);footer.append(instrumentLabel);
      const confirm=make('button',inFlight.has(d.key)?'Adding…':'Confirm pair');confirm.type='submit';confirm.disabled=!d.left||!d.right;footer.append(confirm);
      const remove=make('button','Remove');remove.className='quiet';remove.type='button';remove.onclick=()=>{drafts=drafts.filter(x=>x!==d);save();render();usage();};footer.append(remove);
      const notice=make('p',d.notice||'');notice.className='draft-notice';notice.setAttribute('role','status');disabled.append(notice);
      const message=make('p',d.error||'');message.className='draft-error';message.setAttribute('role','status');disabled.append(message);
      validateCard(card,d);
      card.onsubmit=async e=>{
        e.preventDefault();if(inFlight.has(d.key)||problem(d))return;
        if(d.left)chooseVM(d.left);if(d.right)chooseVM(d.right);
        const left=d.left?.vm,right=d.right?.vm;
        if((d.left&&!left)||(d.right&&!right)||left===right){message.textContent='Both accounts need an unambiguous match on two different registered VMs.';return;}
        const [a,b]=d.ratio.split(':').map(Number);
        if(Number(d.leftQuantity)*b!==Number(d.rightQuantity)*a){message.textContent='Adjust quantity to whole contracts matching the ratio.';return;}
        inFlight.add(d.key);disabled.disabled=true;confirm.textContent='Adding…';
        try{
          await api('/api/queue/add',{localDraft:true,draft:JSON.parse(JSON.stringify(d)),draftKey:d.key,left:left||null,right:right||null,accounts:{...(left?{[left]:d.left.account}:{}),...(right?{[right]:d.right.account}:{})},quantities:{...(left?{[left]:Number(d.leftQuantity)}:{}),...(right?{[right]:Number(d.rightQuantity)}:{})},ratio:d.ratio,ticker:d.ticker,direction:d.direction,stopLoss:Number(d.stopLoss),profit:Number(d.profit)});
          drafts=drafts.filter(x=>x.key!==d.key);save();el('draft-message').textContent='Pair added to the queue.';
          window.dispatchEvent(new Event('queue-refresh'));
        }catch(err){d.error=err.message;save();}finally{inFlight.delete(d.key);render();usage();}
      };
      list.append(card);
    });
  }
  window.addEventListener('edit-local-draft',e=>{const d=e.detail;if(!drafts.some(x=>x.key===d.key))drafts.push(d);save();render();usage();});
  window.addEventListener('planning-accounts-updated',e=>{
    const rows=new Map(e.detail.map(r=>[r.id,r]));
    for(const d of drafts)for(const side of ['left','right']){
      const item=d[side],row=rows.get(item?.record);if(!row)continue;
      item.balance=row.fields.CurrentBalance??null;item.metrics=row.fields;
      const cell=el('draft-list').querySelector(`[data-key="${d.key}"] [data-side="${side}"] .draft-metrics`);
      if(cell)updateMetrics(cell,item);
    }
    save();
  });
  el('draft-left').onclick=()=>add('left');el('draft-right').onclick=()=>add('right');
  window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];pairs=e.detail.pairs||[];
    for(const d of drafts)for(const side of ['left','right'])if(d[side]){
      const choices=chooseVM(d[side]),note=el('draft-list').querySelector(`[data-key="${d.key}"] [data-side="${side}"] .vm-match-note`);
      if(note)note.textContent=!choices.length?'No registered VM lists this account yet. Refresh it in VMs.':!d[side].vm?'Multiple VMs match this account. Resolve its registration before confirming.':'';
    }usage();});
  window.addEventListener('queue-updated',e=>{
    queued=e.detail.rows||[];const keys=new Set(queued.map(r=>r.key));const old=drafts.length;drafts=drafts.filter(d=>!keys.has(d.key));
    if(old!==drafts.length){save();render();}usage();
  });
  // Load VM choices once for restored drafts; polling never replaces typed inputs.
  api('/api/state').then(s=>{fleet=s.fleet||[];pairs=s.pairs||[];render();usage();}).catch(()=>{});
  render();usage();
})();
