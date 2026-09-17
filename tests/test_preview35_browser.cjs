const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1920,height:1080}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const draft=key=>({key:key.repeat(32),ticker:'NQ',direction:'buy',ratio:'1:1',leftQuantity:'2',rightQuantity:'2',profit:'620',stopLoss:'520',rightProfit:'520',rightStopLoss:'620',left:{account:'MFF-EVAL-001',master:'MFF-DEMO',balance:52382.94,metrics:{RealDrawdown:1679.76,'Realized PnL':358.48,largestProfitDay:856.50,tradingDays:2},vm:'left'},right:{account:'FN-CHALLENGE-002',master:'FN-DEMO',balance:51802.84,metrics:{RealDrawdown:1071.52,'Realized PnL':428.48,largestProfitDay:823.92,tradingDays:3},vm:'right'}});
 const initial=draft('a');
 const fleet=['left','right'].map(side=>({id:side,name:initial[side].master,online:true,fresh:true,position:'Flat',account:'Sim101',accounts:[initial[side].account],refresh:{}}));
 const queue={rows:[],history:[],running:false,message:'Paused'};
 let saveMode='hold',startMode='hold',releaseSave,releaseStart;
 const rowFor=body=>{const d=body.draft;return {id:'DRAFT-'+d.key,key:d.key,localDraft:true,status:'Queued',draft:d,spec:{...body,left:'left',right:'right',masters:{left:d.left.master,right:d.right.master},accounts:{left:d.left.account,right:d.right.account},balances:{left:d.left.balance,right:d.right.balance},quantities:{left:2,right:2}}};};
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){
   const body=req.postDataJSON();writes.push({path:url.pathname,body});result={ok:true};
   if(url.pathname==='/api/queue/add'){
    if(saveMode==='hold')await new Promise(resolve=>releaseSave=resolve);
    if(saveMode==='fail')return route.fulfill({status:400,json:{error:'Save rejected'}});
    const row=rowFor(body);queue.rows.push(row);result={id:row.id,row};
    if(saveMode==='lost')return route.abort('failed');
   }
   if(url.pathname==='/api/queue/start'){
    await new Promise(resolve=>releaseStart=resolve);
    if(startMode==='fail')return route.fulfill({status:400,json:{error:'Start rejected'}});
    const batch=queue.rows.filter(r=>body.keys.includes(r.key)&&!r.dispatched);
    batch.forEach((r,i)=>Object.assign(r,{id:'PAIR-00'+(i+1),localDraft:false,dispatched:true}));queue.running=true;
    result={startedCount:batch.length,rows:batch};
   }
  }else if(url.pathname==='/api/state')result={version:'16.0-preview.35',fleet,pairs:[],events:[],vmEvents:[],limits:{vms:50,pairs:20}};
  else if(url.pathname==='/api/queue')result=queue;
  else if(url.pathname==='/api/planning')result={rows:[],columns:[],updatedAt:1,error:'',busy:false};
  else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
  return route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.addInitScript(d=>localStorage.setItem('planning-draft-pairs-v1',JSON.stringify([d])),initial);
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('.vm-list-row').first().waitFor();
 assert.equal(await page.locator('header').count(),0);assert.match(await page.locator('#control-center-title').textContent(),/Pair Execution.*V16.*Preview 35/);
 assert.equal(await page.locator('.vm-row-actions button').count(),4);assert.equal(await page.locator('#vm-remove-select option').count(),3);
 const intro=await page.locator('.intro').boundingBox(),contracts=await page.locator('.contract-settings').boundingBox();assert.ok(contracts.x>intro.x+intro.width);assert.ok(Math.abs(contracts.y-intro.y)<30);
 const first=await page.locator('#tab-vms').boundingBox(),last=await page.locator('#tab-trading').boundingBox();assert.ok(Math.abs((first.x+last.x+last.width)/2-960)<2);
 await page.locator('#tab-planning').click();const card=page.locator('.draft-card');await card.waitFor();
 const bounds=await card.boundingBox();assert.ok(bounds.height<190,'Compact card too tall: '+bounds.height);
 assert.equal(await card.locator('.suggestion-reason,.suggestion-firm,.suggestion-drawdown').count(),0);
 assert.equal(await card.locator('.draft-center .draft-footer button').count(),2);
 assert.match(await card.locator('[data-side=left]').textContent(),/Balance: \$52,382.94Realized: \$358.48DD: \$1,679.76/);
 const id=await card.locator('[data-side=left]>p').boundingBox(),balance=await card.locator('[data-side=left] .draft-values').boundingBox(),stats=await card.locator('[data-side=left] .draft-stats').boundingBox();assert.ok(balance.y>=id.y+id.height+6);assert.ok(stats.x>balance.x);
 // A long Planning page keeps navigation centered and attached to the top.
 await page.evaluate(()=>{document.getElementById('planning-panel').style.minHeight='2400px';window.scrollTo(0,1000);});
 await page.waitForFunction(()=>window.scrollY>900);assert.ok((await page.locator('.tabs').boundingBox()).y<=1);
 await page.locator('#tab-planning').click();await page.evaluate(()=>document.getElementById('planning-panel').style.minHeight='');
 assert.equal(await page.locator('#queue-pause,#queue-retry,#compact-pair').count(),0);
 assert.deepEqual(await page.locator('#queue-table th').evaluateAll(xs=>xs.map(x=>+x.dataset.column)),[0,1,2,3,4,5,6,7,11]);
 // Response is deliberately held: disappearance and Saving row must happen without it.
 await card.getByRole('button',{name:'Confirm pair',exact:true}).click();
 await page.locator('#queue-table .pair-phase').filter({hasText:'Saving…'}).waitFor();assert.equal(await card.count(),0);assert.equal(await page.locator('#queue-start').isDisabled(),true);
 assert.equal(queue.rows.length,0);assert.equal(writes.filter(w=>w.path==='/api/queue/add').length,1);
 saveMode='ok';releaseSave();await page.locator('#queue-table').getByRole('button',{name:'Edit',exact:true}).waitFor();
 assert.equal(await page.locator('#queue-start').isEnabled(),true);
 // Start failure restores the batch without losing settings.
 startMode='fail';await page.locator('#queue-start').click();await page.waitForFunction(()=>document.querySelectorAll('#queue-table tr[data-pair]').length===0);
 assert.equal(queue.rows[0].dispatched,undefined);await page.locator('#tab-trading').click();await page.locator('#trading-queue-table .pair-phase').filter({hasText:'Starting…'}).waitFor();
 releaseStart();await page.waitForFunction(()=>document.getElementById('trading-queue-status').textContent.includes('Start rejected'));
 await page.locator('#tab-planning').click();await page.locator('#queue-table tr[data-pair]').waitFor();
 // Starting snapshots its keys; a newly confirmed draft stays behind.
 startMode='ok';await page.locator('#queue-start').click();await page.waitForFunction(()=>document.querySelectorAll('#queue-table tr[data-pair]').length===0);
 await page.evaluate(d=>window.dispatchEvent(new CustomEvent('edit-local-draft',{detail:d})),draft('b'));
 await card.getByRole('button',{name:'Confirm pair',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#queue-table tr[data-key="'+ 'b'.repeat(32)+'"] .pair-phase')?.textContent==='Queued');
 releaseStart();await page.waitForFunction(()=>!document.getElementById('queue-start').disabled);
 assert.equal(queue.rows[0].dispatched,true);assert.equal(queue.rows[1].dispatched,undefined);
 assert.equal(await page.locator('#queue-table tr[data-pair]').count(),1);
 assert.deepEqual(writes.filter(w=>w.path==='/api/queue/start').at(-1).body.keys,['a'.repeat(32)]);
 // A rejected save restores the unchanged card; a lost success is reconciled by key.
 saveMode='fail';await page.evaluate(d=>window.dispatchEvent(new CustomEvent('edit-local-draft',{detail:d})),draft('c'));
 await card.getByRole('button',{name:'Confirm pair',exact:true}).click();await card.locator('.draft-error').filter({hasText:'Save rejected'}).waitFor();
 assert.equal(await card.locator('[data-value-key=profit]').inputValue(),'620');assert.equal(await card.getAttribute('data-key'),'c'.repeat(32));
 saveMode='lost';await card.getByRole('button',{name:'Confirm pair',exact:true}).click();await page.locator('#queue-table tr[data-key="'+ 'c'.repeat(32)+'"] button').first().waitFor();assert.equal(await card.count(),0);
 assert.equal(queue.rows.filter(r=>r.key==='c'.repeat(32)).length,1);
 // Trading formatting, conditional result sync and full-height scrolling panels.
 Object.assign(queue.rows[0],{status:'Complete',completedUtc:'2026-09-17T20:55:15Z',dirty:true,closed:'2026-09-17T20:55:15Z'});
 await page.evaluate(()=>window.dispatchEvent(new Event('queue-refresh')));await page.locator('#tab-trading').click();await page.locator('#trading-retry').waitFor();
 const table=page.locator('#trading-queue-table');await page.waitForFunction(()=>document.querySelector('#trading-queue-table td[data-column="10"]')?.textContent.includes('09/17/2026'));
 assert.equal(await table.locator('td[data-column="1"]').textContent(),'001');assert.equal(await table.locator('td[data-column="6"]').textContent(),'NQ 2/2');
 assert.deepEqual(await table.locator('td[data-column="10"]>div').allTextContents(),['09/17/2026','3:55:15 PM']);
 assert.equal(await table.locator('td[data-column="2"]>div').textContent(),'MFF-DEMO');assert.equal(await table.locator('.pair-account-number').first().textContent(),initial.left.account);
 assert.equal(await table.locator('.pair-settings .queue-win').first().evaluate(e=>getComputedStyle(e).color),'rgb(20, 116, 71)');assert.equal(await table.locator('.pair-settings .queue-loss').first().evaluate(e=>getComputedStyle(e).color),'rgb(180, 35, 50)');
 const split=await page.locator('#trading-split').boundingBox();assert.ok(split.y+split.height>=1065);assert.ok(split.height>850);
 assert.equal(await page.locator('.activity-scroll').evaluate(e=>getComputedStyle(e).overflowY),'auto');assert.equal(await page.locator('#trading-split .planning-scroll').evaluate(e=>getComputedStyle(e).overflowY),'auto');
 await page.screenshot({path:process.env.TEMP?path.join(process.env.TEMP,'preview35-trading.png'):'/tmp/preview35-trading.png'});
 assert.deepEqual(errors,[]);assert.ok(!writes.some(w=>w.path==='/api/action'));
 await browser.close();console.log('PASS: compact cards, centered sticky navigation, removed banner/detail, standalone VM removal, immediate pending-save/start UI, failed-save restoration, lost-response reconciliation, batch isolation, table formatting and full-height scroll panels.');
})().catch(e=>{console.error(e);process.exit(1)});
