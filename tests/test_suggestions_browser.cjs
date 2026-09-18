const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
let assetServer;
async function waitCount(locator,expected){const deadline=Date.now()+30000;while(Date.now()<deadline){if(await locator.count()===expected)return;await new Promise(resolve=>setTimeout(resolve,50));}assert.equal(await locator.count(),expected);}
const path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 assetServer=spawn('python',['-u',path.join(__dirname,'http_assets_server.py')],{stdio:['ignore','pipe','inherit']});
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('HTTP fixture startup timed out')),20000);assetServer.once('error',reject);assetServer.once('exit',code=>reject(new Error('HTTP fixture exited: '+code)));assetServer.stdout.once('data',()=>{clearTimeout(timer);resolve();});});
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const row=(id,firm,values={})=>{const profit=values.CurrentProfit??0,today=values['Realized PnL']??0,current=values.CurrentBalance??(50000+profit);return {id:'rec'+id,fields:{id,firm,stage:'Evaluation','Master Account':firm+'-TEST',CurrentBalance:current,balance:current,InitialBalance:current-today,'Realized PnL':today,stop:48000,'Trailing max drawdown':999,RealDrawdown:1500,CurrentProfit:0,ProfitTarget:3000,Consistency:0,CurrentPnL:0,...values}};};
 const fn=(id,values={})=>row(id,'FN',{ProfitTarget:2500,Consistency:.4,largestProfitDay:900,...values});
 const rows=[row('FFF892070','FFF',{RealDrawdown:8.48,CurrentProfit:-1491.52}),row('FFF322630','FFF',{RealDrawdown:612.72,CurrentProfit:472.52}),row('FFF993110','FFF',{CurrentProfit:-159.76,'Realized PnL':159.76}),row('FFF236159','FFF',{'scraper note':'Review payout date <b>plain text</b>',RealDrawdown:1183.48,CurrentProfit:2401.96}),fn('FN27255',{RealDrawdown:1107.72,CurrentProfit:919.36}),fn('FN19087',{CurrentProfit:1139.36}),fn('FN20889',{RealDrawdown:1138.92,CurrentProfit:1402.52}),fn('FN67282',{CurrentProfit:968.48})];
 let rejectAccount='';
 let queue={rows:[],history:[],running:false,message:'Paused'},writes=[],error='',busy=false;
 const errors=[];
 async function open(){
  const context=await browser.newContext({viewport:{width:1920,height:1080}}),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.route('http://127.0.0.1:8788/**',async route=>{
   const request=route.request(),url=new URL(request.url());let result;
   if(request.method()==='POST'){
    const body=request.postDataJSON();writes.push({path:url.pathname,body});result={ok:true};
    if(url.pathname==='/api/queue/add'){
     const d=body.draft;if(d.left?.account===rejectAccount)return route.fulfill({status:400,json:{error:'Test account rejected'}});assert.ok(Buffer.byteLength(request.postData())<16384);
     queue.rows.push({id:'DRAFT-'+body.draftKey,key:body.draftKey,draft:d,localDraft:true,status:'Queued',spec:{...body,left:d.left?'left':null,right:d.right?'right':null,accounts:{left:d.left?.account,right:d.right?.account},quantities:{left:+d.leftQuantity,right:+d.rightQuantity},names:{left:'Unassigned VM',right:'Unassigned VM'},masters:{left:d.left?.master,right:d.right?.master}}});
    }
   }else if(url.pathname==='/api/state')result={version:'16.0-preview.36',fleet:[],pairs:[],events:[],vmEvents:[],limits:{vms:50,pairs:20}};
   else if(url.pathname==='/api/planning')result={rows,columns:['id','firm','CurrentBalance'].map(name=>({name})),updatedAt:1,error,busy};
   else if(url.pathname==='/api/queue')result=queue;
   else if(url.pathname==='/api/auto-quantity')result={enabled:false,vm:'',bars:10,multiplier:1};
   else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
   if(result)return route.fulfill({json:result});
   // Serve HTML and scripts through the production handler, including its allowlist.
   await route.continue();
  });
  await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('#tab-planning').click();await page.getByRole('checkbox',{name:'Select '+rows[0].fields.id,exact:true}).waitFor();return {page,context};
 }
 let {page,context}=await open();
 assert.equal(await page.locator('.draft-card').count(),0);assert.deepEqual(writes,[]);
 assert.match(await page.title(),/Preview 36/);
 assert.match(await page.locator('#control-center-title').textContent(),/Preview 36/);
 await page.getByRole('checkbox',{name:'Select FFF322630',exact:true}).click();
 await page.getByRole('checkbox',{name:'Select FN19087',exact:true}).click({modifiers:['Shift']});
 assert.equal(await page.locator('#planning-table tbody input:checked').count(),5);
 await page.locator('#planning-clear-selection').click();
 await page.locator('#planning-table thead button').filter({hasText:/^id/}).click();
 const ordered=await page.locator('#planning-table tbody tr').evaluateAll(rs=>rs.map(r=>r.dataset.account));
 await page.getByRole('checkbox',{name:'Select '+ordered[1],exact:true}).click();
 await page.getByRole('checkbox',{name:'Select '+ordered[3],exact:true}).click({modifiers:['Shift']});
 assert.deepEqual(await page.locator('#planning-table tbody input:checked').evaluateAll(xs=>xs.map(x=>x.closest('tr').dataset.account)),ordered.slice(1,4));
 await page.locator('#planning-select-all').click();assert.equal(await page.locator('#planning-table tbody input:checked').count(),8);
 await page.locator('#planning-clear-selection').click();assert.equal(await page.locator('#planning-table tbody input:checked').count(),0);

 await page.getByRole('checkbox',{name:'Select FFF322630',exact:true}).check();await page.locator('#draft-left').click();
 const manual=page.locator('.draft-card').first();await manual.locator('[data-value-key=profit]').fill('777');await manual.locator('[data-value-key=stopLoss]').fill('333');
 const original=await manual.locator('[data-side=left] > p').first().textContent();
 await page.locator('#suggestion-strategy').selectOption('non-consistency-tests');assert.equal(await page.locator('.draft-card').count(),1);
 await page.locator('#suggest-pairs').click();await page.locator('#suggestion-status').filter({hasText:'2 suggested pairs'}).waitFor();
 assert.deepEqual(writes,[]);assert.equal(await page.locator('.draft-card').count(),3);assert.equal(await page.locator('#planning-panel').isVisible(),true);
 assert.equal(await manual.locator('[data-value-key=profit]').inputValue(),'777');assert.equal(await manual.locator('[data-value-key=stopLoss]').inputValue(),'333');assert.equal(await manual.locator('[data-side=left] > p').first().textContent(),original);
 const first=page.locator('.draft-card').nth(1);assert.equal(await first.locator('.suggestion-reason').count(),0);assert.match(await first.locator('[data-side=left]').textContent(),/FFF236159/);
 assert.equal(await first.locator('[data-value-key=profit]').inputValue(),'630');assert.equal(await first.locator('[data-value-key=stopLoss]').inputValue(),'950');
 assert.equal(await first.locator('[data-value-key=leftQuantity]').inputValue(),'2');assert.equal(await first.locator('[data-value-key=rightQuantity]').inputValue(),'2');
 assert.match(await first.locator('[data-side=left] .draft-metrics').textContent(),/DD: \$1,183.48/);
 assert.doesNotMatch(await first.locator('.draft-metrics').first().textContent(),/Stop:/);
 assert.equal(await first.locator('.pair-scraper-note').textContent(),'Review payout date <b>plain text</b>');
 assert.equal(await first.locator('.pair-scraper-note b').count(),0);
 assert.equal(await manual.locator('.pair-scraper-note').count(),0);
 assert.equal(await first.locator('[data-field=ticker]').inputValue(),'NQ');assert.equal(await first.locator('[data-field=ratio]').inputValue(),'1:1');
 for(const card of await page.locator('.draft-card').all())if(await card.locator('.suggestion-firm').count()){const firms=await card.locator('.suggestion-firm').allTextContents();assert.notEqual(firms[0],firms[1]);}
 assert.match(await page.locator('#suggestion-skipped-list').textContent(),/FFF892070.*\$100 minimum/);
 await page.locator('#suggest-pairs').click();await page.locator('#suggestion-status').filter({hasText:/^0 suggested/}).waitFor();
 assert.equal(await page.locator('.draft-card').count(),3);assert.deepEqual(writes,[]);
 await first.locator('[data-value-key=profit]').fill('650');assert.equal(await first.locator('[data-value-key=rightStopLoss]').inputValue(),'650');
 await first.getByRole('button',{name:'Confirm pair',exact:true}).click();await waitCount(page.locator('.draft-card'),2);
 assert.equal(writes.length,1);assert.equal(writes[0].path,'/api/queue/add');assert.equal(writes[0].body.profit,650);assert.equal(writes[0].body.draft.suggestion.strategy,'non-consistency-tests');assert.equal(writes[0].body.deferVM,true);
 assert.notEqual(writes[0].body.draft.left.metrics.firm,writes[0].body.draft.right.metrics.firm);
 await page.reload();await page.locator('#tab-planning').click();await waitCount(page.locator('.draft-card'),2);
 assert.equal(await page.locator('.suggestion-reason').count(),0);assert.equal(writes.length,1);
 // Clearing drafts requires confirmation, preserves queue, and persists across reload.
 page.once('dialog',dialog=>dialog.dismiss());await page.locator('#draft-remove-all').click();
 assert.equal(await page.locator('.draft-card').count(),2);
 const queuedBefore=JSON.stringify(queue),writesBefore=writes.length;
 page.once('dialog',dialog=>dialog.accept());await page.locator('#draft-remove-all').click();
 assert.equal(await page.locator('.draft-card').count(),0);assert.equal(JSON.stringify(queue),queuedBefore);assert.equal(writes.length,writesBefore);
 await page.reload();await page.locator('#tab-planning').click();assert.equal(await page.locator('.draft-card').count(),0);
 assert.equal(await page.locator('#draft-remove-all').isDisabled(),true);
 await page.setViewportSize({width:740,height:900});assert.ok(await page.locator('#suggest-pairs').isVisible());
 await context.close();
 // Only explicitly checked accounts are considered; same-firm lists never produce a card.
 queue={rows:[],history:[],running:false,message:'Paused'};writes=[];({page,context}=await open());
 for(const id of ['FFF236159','FFF993110'])await page.getByRole('checkbox',{name:'Select '+id,exact:true}).check();
 await page.locator('#suggest-pairs').click();await page.locator('#suggestion-status').filter({hasText:/^0 suggested/}).waitFor();
 assert.equal(await page.locator('.draft-card').count(),0);
 await page.getByRole('checkbox',{name:'Select FFF993110',exact:true}).uncheck();await page.getByRole('checkbox',{name:'Select FN19087',exact:true}).check();
 await page.locator('#suggest-pairs').click();await waitCount(page.locator('.draft-card'),1);
 assert.match(await page.locator('.draft-card').textContent(),/FFF236159/);assert.match(await page.locator('.draft-card').textContent(),/FN19087/);assert.deepEqual(writes,[]);
 // A firm change in refreshed data disables confirmation without altering manual trade behavior.
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('planning-accounts-updated',{detail:[{id:'recFN19087',fields:{id:'FN19087',firm:'FFF',CurrentBalance:50000,stop:48000,'Trailing max drawdown':999,RealDrawdown:1500}}]})));
 assert.equal(await page.getByRole('button',{name:'Same fund',exact:true}).isDisabled(),true);
 await context.close();
 // Batch confirmation preserves invalid/rejected drafts, and never starts the queue.
 queue={rows:[],history:[],running:false,message:'Paused'};writes=[];({page,context}=await open());
 await page.locator('#suggest-pairs').click();await waitCount(page.locator('.draft-card'),3);
 const cards=page.locator('.draft-card');const invalidKey=await cards.nth(2).getAttribute('data-key');
 await cards.nth(2).locator('[data-value-key=profit]').fill('0');
 rejectAccount=await cards.nth(1).locator('[data-side=left] > p').first().textContent();
 await page.locator('#draft-add-all').click();
 await page.locator('#draft-message').filter({hasText:'1 pair added to queue. 2 draft(s) remain'}).waitFor();
 assert.equal(writes.length,2);assert.ok(writes.every(w=>w.path==='/api/queue/add'));
 assert.equal(await cards.count(),2);assert.match(await page.locator(`[data-key="${invalidKey}"] .draft-error`).textContent(),/positive profit and loss/);
 assert.match(await page.locator('#draft-list').textContent(),/Test account rejected/);
 assert.equal(queue.running,false);rejectAccount='';
 await page.locator(`[data-key="${invalidKey}"] [data-value-key=profit]`).fill('100');
 await page.locator('#draft-add-all').click();await waitCount(page.locator('.draft-card'),0);
 assert.equal(queue.rows.length,3);assert.equal(new Set(queue.rows.map(r=>r.key)).size,3);assert.equal(queue.running,false);
 await context.close();
 // A failed Planning snapshot cannot generate drafts from stale data.
 writes=[];error='Airtable unavailable';({page,context}=await open());await page.locator('#suggest-pairs').click();await page.locator('#suggestion-status').filter({hasText:'refresh the Planning view'}).waitFor();
 assert.equal(await page.locator('.draft-card').count(),0);assert.deepEqual(writes,[]);
 await context.close();
 // Preview 34: exact user examples, current website snapshot correction, and
 // realized-PnL daily budget even when the legacy CurrentPnL remains zero.
 rows.splice(0,rows.length,
  row('MFF-EXAMPLE','MFF',{balance:52024.46,CurrentProfit:2024.46,CurrentBalance:52382.94,InitialBalance:52024.46,'Realized PnL':358.48,RealDrawdown:1679.76}),
  fn('FN-LOSS',{balance:51816.40,CurrentProfit:1816.40,CurrentBalance:51364.88,InitialBalance:51816.40,'Realized PnL':-451.52,RealDrawdown:1048.48,largestProfitDay:913.48}),
  fn('FN-927',{CurrentProfit:927.72,'Realized PnL':927.72,CurrentPnL:0}),
  row('MISSING-OPEN','FFF',{InitialBalance:null}));
 error='';writes=[];queue={rows:[],history:[],running:false,message:'Paused'};({page,context}=await open());
 await page.locator('#suggest-pairs').click();await waitCount(page.locator('.draft-card'),1);
 assert.equal(await page.locator('[data-value-key=profit]').inputValue(),'650');
 assert.equal(await page.locator('[data-value-key=rightProfit]').inputValue(),'1170');
 assert.match(await page.locator('#suggestion-skipped-list').textContent(),/FN-927.*below the \$100 minimum/);
 assert.match(await page.locator('#suggestion-skipped-list').textContent(),/MISSING-OPEN.*InitialBalance/);
 await page.locator('[data-value-key=profit]').fill('980');
 assert.equal(await page.locator('.draft-card button[type=submit]').isDisabled(),true);
 assert.match(await page.locator('.draft-notice').textContent(),/more than \$100/);
 await page.locator('[data-value-key=profit]').fill('650');assert.equal(await page.locator('.draft-card button[type=submit]').isDisabled(),false);
 // Refreshed mismatching fields block the existing suggestion, not just new cards.
 const mismatch={...rows[0],fields:{...rows[0].fields,InitialBalance:52382.94}};
 await page.evaluate(row=>window.dispatchEvent(new CustomEvent('planning-accounts-updated',{detail:[row]})),mismatch);
 assert.equal(await page.locator('.draft-card button[type=submit]').isDisabled(),true);assert.match(await page.locator('.draft-notice').textContent(),/Daily P&L mismatch/);
 await page.evaluate(row=>window.dispatchEvent(new CustomEvent('planning-accounts-updated',{detail:[row]})),rows[0]);
 assert.equal(await page.locator('.draft-card button[type=submit]').isDisabled(),false);
 // Previous-release suggestions cannot silently retain the old daily input mapping.
 await page.evaluate(()=>{const drafts=JSON.parse(localStorage.getItem('planning-draft-pairs-v1'));delete drafts[0].suggestion.revision;localStorage.setItem('planning-draft-pairs-v1',JSON.stringify(drafts));});
 await page.reload();await page.locator('#tab-planning').click();
 assert.equal(await page.locator('.draft-card button[type=submit]').isDisabled(),true);assert.match(await page.locator('.draft-notice').textContent(),/Older suggestion/);
 assert.deepEqual(writes,[]);
 assert.deepEqual(errors,[]);await context.close();await browser.close();assetServer.kill();
 console.log('PASS: click-only beta drafts, manual settings retained, closest-one-win priority, firm checks, checked/current-view pools, double-click/reload exclusions, tiny drawdown, editable amounts, one manual confirmation only and no execution writes.');
})().catch(e=>{if(assetServer)assetServer.kill();console.error(e);process.exit(1)});
