'use strict';
(() => {
  const el=id=>document.getElementById(id), make=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const storage='planning-draft-pairs-v1';let drafts=[],fleet=[],pairs=[],queued=[];
  try{const value=JSON.parse(localStorage.getItem(storage));if(Array.isArray(value))drafts=value.filter(d=>/^[a-f0-9]{32}$/.test(d.key));}catch(_){}
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
  function chooseVM(item){const list=candidates(item.account);if(!item.vm&&list.length===1)item.vm=list[0].id;return list;}
  function add(side){
    const rows=window.planningSelection.rows();if(!rows.length){el('draft-message').textContent='Check an account in the table first.';return;}
    for(const row of rows){
      const account=String(row.fields.id||'');if(!account)continue;
      let d=drafts.find(d=>!d[side]&&!inFlight.has(d.key));
      if(!d){d={key:crypto.randomUUID().replaceAll('-',''),ticker:'NQ SEP26',direction:'buy',stopLoss:'0',profit:'0',leftQuantity:'1',rightQuantity:'1'};drafts.push(d);}
      d[side]={account,master:String(row.fields['Master Account']||''),record:row.id,vm:''};chooseVM(d[side]);
    }
    window.planningSelection.clear();el('draft-message').textContent='Accounts added to drafts.';save();render();usage();
  }
  function input(form,d,key,label,type='text'){
    const l=make('label',label),n=make('input');n.type=type;n.value=d[key];n.required=true;n.dataset.field=key;
    if(type==='number'){n.min=key.includes('Quantity')?'1':'0.01';n.max=key.includes('Quantity')?'1000':'100000';n.step=key.includes('Quantity')?'1':'0.01';}
    n.oninput=()=>{d[key]=n.value;save();};l.append(n);form.append(l);
  }
  function render(){
    const list=el('draft-list');list.replaceChildren();
    if(!drafts.length){list.append(make('p','No draft pairs yet. Add an account to each side.'));return;}
    drafts.forEach((d,index)=>{
      const card=make('form');card.className='draft-card';card.dataset.key=d.key;card.append(make('h3','Draft pair '+(index+1)));
      const disabled=make('fieldset');disabled.disabled=inFlight.has(d.key);card.append(disabled);
      const accountsGrid=make('div');accountsGrid.className='draft-grid';disabled.append(accountsGrid);
      for(const side of ['left','right']){
        const item=d[side],block=make('div');block.className='draft-account';block.append(make('strong',side==='left'?'Left':'Right'));
        block.append(make('p',item?item.master+' · '+item.account:'Select an account → Add to '+side));
        if(item){
          const choices=chooseVM(item),label=make('label','VM'),select=make('select');select.required=true;select.dataset.side=side;
          const blank=make('option','Choose matching VM');blank.value='';select.append(blank);
          for(const vm of choices){const opt=make('option',vm.name);opt.value=vm.id;select.append(opt);}select.value=item.vm;
          select.onchange=()=>{item.vm=select.value;save();};label.append(select);block.append(label);
          if(!choices.length)block.append(make('small','No registered VM lists this account yet. Refresh accounts in Trading.'));
          const remove=make('button','Clear '+side);remove.type='button';remove.className='quiet';remove.onclick=()=>{delete d[side];save();render();usage();};block.append(remove);
        }
        accountsGrid.append(block);
      }
      const qty=make('div');qty.className='draft-grid';input(qty,d,'leftQuantity','Left quantity','number');input(qty,d,'rightQuantity','Right quantity','number');disabled.append(qty);
      const settings=make('div');settings.className='draft-grid';disabled.append(settings);input(settings,d,'ticker','Instrument');
      const direction=make('label','Direction'),select=make('select');for(const [value,text] of [['buy','Buy left / Sell right'],['sell','Sell left / Buy right']]){const opt=make('option',text);opt.value=value;select.append(opt);}select.value=d.direction;select.onchange=()=>{d.direction=select.value;save();};direction.append(select);settings.append(direction);
      const amounts=make('div');amounts.className='draft-grid';input(amounts,d,'stopLoss','Left stop loss · USD','number');input(amounts,d,'profit','Left profit target · USD','number');disabled.append(amounts);
      disabled.append(make('small','Right stop loss = left profit target. Right profit target = left stop loss.'));
      const message=make('p',d.error||'');message.className='draft-error';message.setAttribute('role','status');disabled.append(message);
      const confirm=make('button',inFlight.has(d.key)?'Adding…':'Confirm pair');confirm.type='submit';confirm.disabled=!d.left||!d.right;disabled.append(confirm);
      const remove=make('button','Remove');remove.className='quiet';remove.type='button';remove.onclick=()=>{drafts=drafts.filter(x=>x!==d);save();render();usage();};disabled.append(remove);
      card.onsubmit=async e=>{
        e.preventDefault();if(inFlight.has(d.key))return;
        const left=d.left?.vm,right=d.right?.vm;
        if(!left||!right||left===right){message.textContent='Choose two different matching VMs.';return;}
        inFlight.add(d.key);disabled.disabled=true;confirm.textContent='Adding…';
        try{
          await api('/api/queue/add',{draftKey:d.key,left,right,accounts:{[left]:d.left.account,[right]:d.right.account},quantities:{[left]:Number(d.leftQuantity),[right]:Number(d.rightQuantity)},ticker:d.ticker,direction:d.direction,stopLoss:Number(d.stopLoss),profit:Number(d.profit)});
          drafts=drafts.filter(x=>x.key!==d.key);save();el('draft-message').textContent='Pair added to the queue.';
          window.dispatchEvent(new Event('queue-refresh'));
        }catch(err){d.error=err.message;save();}finally{inFlight.delete(d.key);render();usage();}
      };
      list.append(card);
    });
  }
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
