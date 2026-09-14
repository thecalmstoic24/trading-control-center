'use strict';
(() => {
  const el=id=>document.getElementById(id), make=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const storage='planning-draft-pairs-v1';let drafts=[],fleet=[],pairs=[],queued=[];
  try{const value=JSON.parse(localStorage.getItem(storage));if(Array.isArray(value))drafts=value.filter(d=>/^[a-f0-9]{32}$/.test(d.key));}catch(_){}
  for(const d of drafts){d.ratio=d.ratio||'1:1';PairRatio.amounts(d);}
  const inFlight=new Set();
  function save(){try{localStorage.setItem(storage,JSON.stringify(drafts));}catch(_){el('draft-message').textContent='Drafts cannot be saved in this browser. Keep this page open.';}}
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
      if(!d){d={key:crypto.randomUUID().replaceAll('-',''),ticker:'NQ SEP26',direction:'buy',ratio:'1:1',rightStopLoss:'0',rightProfit:'0',stopLoss:'0',profit:'0',leftQuantity:'1',rightQuantity:'1'};drafts.push(d);}
      d[side]={account,master:String(row.fields['Master Account']||''),record:row.id,balance:row.fields.CurrentBalance??null,vm:''};chooseVM(d[side]);
    }
    window.planningSelection.clear();el('draft-message').textContent='Accounts added to drafts.';save();render();usage();
  }
  function input(form,d,key,label,type='text',alias=key){
    const l=make('label',label),n=make('input');n.type=type;n.value=d[key];n.required=true;n.dataset.field=alias;n.dataset.valueKey=key;
    if(type==='number'){n.min=key.includes('Quantity')?'1':'0.01';n.max=key.includes('Quantity')?'1000':'100000';n.step=key.includes('Quantity')?'1':'0.01';}
    n.oninput=()=>{
      PairRatio.edit(d,key,n.value);
      for(const other of form.closest('form').querySelectorAll('input[data-value-key]')){
        if(other!==n||d.ticker==='MNQ SEP26')other.value=d[other.dataset.valueKey];
      }
      const card=form.closest('form');card.querySelector('[data-field=ticker]').value=d.ticker;card.querySelector('.draft-notice').textContent=d.notice||'';
      save();
    };l.append(n);form.append(l);
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
        const item=d[side],block=make('div');block.className='draft-account';block.dataset.side=side;
        block.append(make('strong',item?.master||'Select an account'));
        block.append(make('p',item?.account||'Add an account from the table'));
        const balance=make('p',item?.balance!=null&&Number.isFinite(Number(item.balance))?new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(Number(item.balance)):'Balance unavailable');balance.className='draft-balance';block.append(balance);
        const direction=make('button',(side==='left')===(d.direction==='buy')?'Buy':'Sell');direction.type='button';direction.className='quiet draft-direction';direction.title='Reverse trade direction';direction.onclick=()=>{d.direction=d.direction==='buy'?'sell':'buy';save();render();};block.append(direction);
        if(item){
          const choices=chooseVM(item);
          if(!choices.length)block.append(make('small','No registered VM lists this account yet. Refresh accounts in Trading.'));
          else if(!item.vm)block.append(make('small','Multiple VMs match this account. Resolve its VM registration before confirming.'));
        }
        const amounts=make('div');amounts.className='draft-amounts';
        input(amounts,d,side+'Quantity','Quantity','number');
        input(amounts,d,side==='left'?'profit':'rightProfit','Profit','number');
        input(amounts,d,side==='left'?'stopLoss':'rightStopLoss','Stop loss','number');
        if(side==='left')accountsGrid.append(block,amounts);else accountsGrid.append(amounts,block);
      }
      const footer=make('div');footer.className='draft-footer';disabled.append(footer);
      const instrumentLabel=make('label','Instrument'),instrument=make('select');instrument.dataset.field='ticker';
      for(const value of ['NQ SEP26','MNQ SEP26']){const opt=make('option',value);opt.value=value;instrument.append(opt);}instrument.value=d.ticker;
      instrument.onchange=()=>{
        const next=instrument.value,scale=next===d.ticker?1:next==='MNQ SEP26'?10:0.1;
        const l=Number(d.leftQuantity)*scale,r=Number(d.rightQuantity)*scale;
        if(!Number.isInteger(l)||!Number.isInteger(r)){d.notice='Cannot convert to whole NQ contracts. Adjust quantities first.';instrument.value=d.ticker;card.querySelector('.draft-notice').textContent=d.notice;return;}
        d.ticker=next;d.leftQuantity=String(l);d.rightQuantity=String(r);d.notice='';save();render();
      };instrumentLabel.append(instrument);footer.append(instrumentLabel);
      const confirm=make('button',inFlight.has(d.key)?'Adding…':'Confirm pair');confirm.type='submit';confirm.disabled=!d.left||!d.right;footer.append(confirm);
      const remove=make('button','Remove');remove.className='quiet';remove.type='button';remove.onclick=()=>{drafts=drafts.filter(x=>x!==d);save();render();usage();};footer.append(remove);
      const notice=make('p',d.notice||'');notice.className='draft-notice';notice.setAttribute('role','status');disabled.append(notice);
      const message=make('p',d.error||'');message.className='draft-error';message.setAttribute('role','status');disabled.append(message);
      card.onsubmit=async e=>{
        e.preventDefault();if(inFlight.has(d.key))return;
        if(d.left)chooseVM(d.left);if(d.right)chooseVM(d.right);
        const left=d.left?.vm,right=d.right?.vm;
        if(!left||!right||left===right){message.textContent='Both accounts need an unambiguous match on two different registered VMs.';return;}
        const [a,b]=d.ratio.split(':').map(Number);
        if(Number(d.leftQuantity)*b!==Number(d.rightQuantity)*a){message.textContent='Adjust quantity to whole contracts matching the ratio.';return;}
        inFlight.add(d.key);disabled.disabled=true;confirm.textContent='Adding…';
        try{
          await api('/api/queue/add',{draftKey:d.key,left,right,accounts:{[left]:d.left.account,[right]:d.right.account},quantities:{[left]:Number(d.leftQuantity),[right]:Number(d.rightQuantity)},ratio:d.ratio,ticker:d.ticker,direction:d.direction,stopLoss:Number(d.stopLoss),profit:Number(d.profit)});
          drafts=drafts.filter(x=>x.key!==d.key);save();el('draft-message').textContent='Pair added to the queue.';
          window.dispatchEvent(new Event('queue-refresh'));
        }catch(err){d.error=err.message;save();}finally{inFlight.delete(d.key);render();usage();}
      };
      list.append(card);
    });
  }
  window.addEventListener('planning-accounts-updated',e=>{
    const rows=new Map(e.detail.map(r=>[r.id,r]));
    for(const d of drafts)for(const side of ['left','right']){
      const item=d[side],row=rows.get(item?.record);if(!row)continue;
      item.balance=row.fields.CurrentBalance??null;
      const cell=el('draft-list').querySelector(`[data-key="${d.key}"] [data-side="${side}"] .draft-balance`);
      if(cell)cell.textContent=item.balance!=null&&Number.isFinite(Number(item.balance))?new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(Number(item.balance)):'Balance unavailable';
    }
    save();
  });
  el('draft-left').onclick=()=>add('left');el('draft-right').onclick=()=>add('right');
  window.addEventListener('fleet-updated',e=>{fleet=e.detail.fleet||[];pairs=e.detail.pairs||[];usage();});
  window.addEventListener('queue-updated',e=>{
    queued=e.detail.rows||[];const keys=new Set(queued.map(r=>r.key));const old=drafts.length;drafts=drafts.filter(d=>!keys.has(d.key));
    if(old!==drafts.length){save();render();}usage();
  });
  // Load VM choices once for restored drafts; polling never replaces typed inputs.
  api('/api/state').then(s=>{fleet=s.fleet||[];pairs=s.pairs||[];render();usage();}).catch(()=>{});
  render();usage();
})();
