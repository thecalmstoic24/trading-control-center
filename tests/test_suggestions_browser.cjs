const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const row=(id,firm,values={})=>({id:'rec'+id,fields:{id,firm,'Master Account':firm+'-TEST',CurrentBalance:50000,RealDrawdown:1500,CurrentProfit:0,ProfitTarget:3000,Consistency:0,CurrentPnL:0,...values}});
 const fn=(id,values={})=>row(id,'FN',{ProfitTarget:2500,Consistency:.4,largestProfitDay:900,...values});
 const rows=[row('FFF892070','FFF',{RealDrawdown:8.48,CurrentProfit:-1491.52}),row('FFF322630','FFF',{RealDrawdown:612.72,CurrentProfit:472.52}),row('FFF993110','FFF',{CurrentProfit:-159.76,CurrentPnL:159.76}),row('FFF236159','FFF',{RealDrawdown:1183.48,CurrentProfit:2401.96}),fn('FN27255',{RealDrawdown:1107.72,CurrentProfit:919.36}),fn('FN19087',{CurrentProfit:1139.36}),fn('FN20889',{RealDrawdown:1138.92,CurrentProfit:1402.52}),fn('FN67282',{CurrentProfit:968.48})];
 let queue={rows:[],history:[],running:false,message:'Paused'},writes=[],error='',busy=false;
 const errors=[];
 async function open(){
  const context=await browser.newContext({viewport:{width:1920,height:1080}}),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.route('http://127.0.0.1:8788/**',async route=>{
   const request=route.request(),url=new URL(request.url());let result;
   if(request.method()==='POST'){
    const body=request.postDataJSON();writes.push({path:url.pathname,body});result={ok:true};
    if(url.pathname==='/api/queue/add'){
     const d=body.draft;assert.ok(Buffer.byteLength(request.postData())<16384);
     queue.rows.push({id:'DRAFT-'+body.draftKey,key:body.draftKey,draft:d,localDraft:true,status:'Queued',spec:{...body,left:d.left?'left':null,right:d.right?'right':null,accounts:{left:d.left?.account,right:d.right?.account},quantities:{left:+d.leftQuantity,right:+d.rightQuantity},names:{left:'Unassigned VM',right:'Unassigned VM'},masters:{left:d.left?.master,right:d.right?.master}}});
    }
   }else if(url.pathname==='/api/state')result={fleet:[],pairs:[],events:[],vmEvents:[],limits:{vms:50,pairs:20}};
   else if(url.pathname==='/api/planning')result={rows,columns:['id','firm','CurrentBalance'].map(name=>({name})),updatedAt:1,error,busy};
   else if(url.pathname==='/api/queue')result=queue;
   else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
   if(result)return route.fulfill({json:result});
   const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
   await route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
  });
  await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('#tab-planning').click();await page.getByRole('checkbox',{name:'Select FFF236159',exact:true}).waitFor();return {page,context};
 }
 let {page,context}=await open();
 assert.equal(await page.locator('.draft-card').count(),0);assert.deepEqual(writes,[]);
 await page.getByRole('checkbox',{name:'Select FFF322630',exact:true}).check();await page.locator('#draft-left').click();
 const manual=page.locator('.draft-card').first();await manual.locator('[data-value-key=profit]').fill('777');await manual.locator('[data-value-key=stopLoss]').fill('333');
 const original=await manual.locator('[data-side=left] > p').first().textContent();
 await page.locator('#suggestion-strategy').selectOption('non-consistency-tests');assert.equal(await page.locator('.draft-card').count(),1);
 await page.locator('#suggest-pairs').click();await page.waitForFunction(()=>document.querySelector('#suggestion-status').textContent.includes('2 suggested pairs'));
 assert.deepEqual(writes,[]);assert.equal(await page.locator('.draft-card').count(),3);assert.equal(await page.locator('#planning-panel').isVisible(),true);
 assert.equal(await manual.locator('[data-value-key=profit]').inputValue(),'777');assert.equal(await manual.locator('[data-value-key=stopLoss]').inputValue(),'333');assert.equal(await manual.locator('[data-side=left] > p').first().textContent(),original);
 const first=page.locator('.draft-card').nth(1);assert.match(await first.locator('.suggestion-reason').textContent(),/FFF236159.*one winning trade/);
 assert.equal(await first.locator('[data-value-key=profit]').inputValue(),'600');assert.equal(await first.locator('[data-value-key=stopLoss]').inputValue(),'950');
 assert.equal(await first.locator('[data-value-key=leftQuantity]').inputValue(),'2');assert.equal(await first.locator('[data-value-key=rightQuantity]').inputValue(),'2');
 assert.equal(await first.locator('[data-field=ticker]').inputValue(),'NQ');assert.equal(await first.locator('[data-field=ratio]').inputValue(),'1:1');
 for(const card of await page.locator('.draft-card').all())if(await card.locator('.suggestion-firm').count()){const firms=await card.locator('.suggestion-firm').allTextContents();assert.notEqual(firms[0],firms[1]);}
 assert.match(await page.locator('#suggestion-skipped-list').textContent(),/FFF892070.*one price tick/);
 await page.locator('#suggest-pairs').click();await page.waitForFunction(()=>document.querySelector('#suggestion-status').textContent.startsWith('0 suggested'));
 assert.equal(await page.locator('.draft-card').count(),3);assert.deepEqual(writes,[]);
 await first.locator('[data-value-key=profit]').fill('650');assert.equal(await first.locator('[data-value-key=rightStopLoss]').inputValue(),'650');
 await first.getByRole('button',{name:'Confirm pair',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.draft-card').length===2);
 assert.equal(writes.length,1);assert.equal(writes[0].path,'/api/queue/add');assert.equal(writes[0].body.profit,650);assert.equal(writes[0].body.draft.suggestion.strategy,'non-consistency-tests');assert.equal(writes[0].body.deferVM,true);
 assert.notEqual(writes[0].body.draft.left.metrics.firm,writes[0].body.draft.right.metrics.firm);
 await page.reload();await page.locator('#tab-planning').click();await page.waitForFunction(()=>document.querySelectorAll('.draft-card').length===2);
 assert.equal(await page.locator('.suggestion-reason').count(),1);assert.equal(writes.length,1);
 await page.setViewportSize({width:740,height:900});assert.ok(await page.locator('#suggest-pairs').isVisible());
 await context.close();
 // Only explicitly checked accounts are considered; same-firm lists never produce a card.
 queue={rows:[],history:[],running:false,message:'Paused'};writes=[];({page,context}=await open());
 for(const id of ['FFF236159','FFF993110'])await page.getByRole('checkbox',{name:'Select '+id,exact:true}).check();
 await page.locator('#suggest-pairs').click();await page.waitForFunction(()=>document.querySelector('#suggestion-status').textContent.startsWith('0 suggested'));
 assert.equal(await page.locator('.draft-card').count(),0);
 await page.getByRole('checkbox',{name:'Select FFF993110',exact:true}).uncheck();await page.getByRole('checkbox',{name:'Select FN19087',exact:true}).check();
 await page.locator('#suggest-pairs').click();await page.waitForFunction(()=>document.querySelectorAll('.draft-card').length===1);
 assert.match(await page.locator('.draft-card').textContent(),/FFF236159/);assert.match(await page.locator('.draft-card').textContent(),/FN19087/);assert.deepEqual(writes,[]);
 // A firm change in refreshed data disables confirmation without altering manual trade behavior.
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('planning-accounts-updated',{detail:[{id:'recFN19087',fields:{id:'FN19087',firm:'FFF',CurrentBalance:50000,RealDrawdown:1500}}]})));
 assert.equal(await page.getByRole('button',{name:'Same fund',exact:true}).isDisabled(),true);
 await context.close();
 // A failed Planning snapshot cannot generate drafts from stale data.
 error='Airtable unavailable';({page,context}=await open());await page.locator('#suggest-pairs').click();await page.waitForFunction(()=>document.querySelector('#suggestion-status').textContent.includes('refresh the Planning view'));
 assert.equal(await page.locator('.draft-card').count(),0);assert.deepEqual(writes,[]);
 assert.deepEqual(errors,[]);await context.close();await browser.close();
 console.log('PASS: click-only beta drafts, manual settings retained, closest-one-win priority, firm checks, checked/current-view pools, double-click/reload exclusions, tiny drawdown, editable amounts, one manual confirmation only and no execution writes.');
})().catch(e=>{console.error(e);process.exit(1)});
