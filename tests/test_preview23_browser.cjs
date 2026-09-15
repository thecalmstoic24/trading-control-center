const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.TCC_BROWSER_PATH,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const accounts=[{id:'recA',fields:{id:'MFF-DEMO','Master Account':'MFF-DEMO',CurrentBalance:51000,stop:50000,'Trailing max drawdown':2000,tradingDays:3,largestProfitDay:500}}];
 const fleet=[{id:'mff',name:'MFF',online:true,fresh:true,position:'Flat',accounts:['MFF-DEMO'],refresh:{}}];
 const spec={left:'mff',right:null,accounts:{mff:'MFF-DEMO'},names:{mff:'MFF'},masters:{mff:'MFF'},quantities:{mff:1},ticker:'MNQ SEP26',stopLoss:100,profit:200,direction:'buy'};
 const queue={running:true,message:'Test only',history:[],rows:[{id:'PAIR-0001',key:'a'.repeat(32),spec,status:'Complete',completedUtc:'2026-09-15T22:42:08Z',dispatched:true},{id:'PAIR-0002',key:'b'.repeat(32),spec,status:'Awaiting results',dispatched:true},{id:'PAIR-0003',key:'c'.repeat(32),spec,status:'Waiting',dispatched:true}]};
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){
   const body=req.postDataJSON();writes.push({path:url.pathname,body});result={ok:true};
   if(url.pathname==='/api/queue/add'){const row={id:'DRAFT-'+body.draftKey,key:body.draftKey,spec:{...body,names:{mff:'MFF'},masters:{mff:'MFF'}},draft:body.draft,localDraft:true,status:'Queued'};queue.rows.push(row);result={id:row.id};}
   if(url.pathname==='/api/queue/edit-draft'){const row=queue.rows.find(r=>r.id===body.id);queue.rows=queue.rows.filter(r=>r!==row);result={draft:row};}
   if(url.pathname==='/api/queue/start')queue.rows.filter(r=>r.localDraft).forEach(r=>Object.assign(r,{id:'PAIR-0004',localDraft:false,dispatched:true}));
  }else if(url.pathname==='/api/state')result={fleet,pairs:[],events:[],limits:{vms:50,pairs:20}};
  else if(url.pathname==='/api/planning')result={rows:accounts,columns:Object.keys(accounts[0].fields).map(name=>({name})),updatedAt:1,error:'',busy:false};
  else if(url.pathname==='/api/queue')result=queue;
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
  await route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/');await page.locator('#tab-trading').click();
 const table=page.locator('#trading-queue-table');
 assert.match(await table.innerText(),/05:42:08 PM CDT|5:42:08 PM CDT/);
 assert.match(await table.innerText(),/Single Pair/);
 assert.equal(await table.locator('.awaiting-results').evaluate(n=>getComputedStyle(n).backgroundColor),'rgb(25, 100, 201)');
 assert.equal(await table.locator('.waiting').evaluate(n=>getComputedStyle(n).backgroundColor),'rgb(173, 22, 143)');
 assert.equal(await table.getByRole('button',{name:'Skip Results'}).count(),1);
 const handle=table.locator('th').nth(2).locator('.column-resizer'),box=await handle.boundingBox();
 await page.mouse.move(box.x+4,box.y+12);await page.mouse.down();await page.mouse.move(box.x+100,box.y+12);await page.mouse.up();
 const width=await table.locator('th').nth(2).evaluate(n=>n.style.width);assert.ok(parseFloat(width)>100);
 await page.reload();await page.locator('#tab-trading').click();assert.equal(await table.locator('th').nth(2).evaluate(n=>n.style.width),width);
 await page.locator('#tab-planning').click();await page.getByRole('checkbox',{name:'Select MFF-DEMO',exact:true}).check();await page.locator('#draft-left').click();
 const card=page.locator('.draft-card');assert.match(await card.innerText(),/Drawdown: \$3,000.00/);
 await card.locator('[data-value-key=profit]').fill('200');await card.locator('[data-value-key=stopLoss]').fill('100');
 await card.getByRole('button',{name:'Confirm Single Pair',exact:true}).click();
 await page.locator('#queue-table').getByRole('button',{name:'Edit',exact:true}).waitFor();
 const added=writes.find(w=>w.path==='/api/queue/add').body;assert.equal(added.localDraft,true);assert.equal(added.right,null);assert.deepEqual(Object.keys(added.accounts),['mff']);
 await page.locator('#queue-table').getByRole('button',{name:'Edit',exact:true}).click();
 await card.getByRole('button',{name:'Confirm Single Pair',exact:true}).waitFor();
 assert.equal(await card.locator('[data-value-key=profit]').inputValue(),'200');
 await card.getByRole('button',{name:'Confirm Single Pair',exact:true}).click();await page.locator('#queue-start').click();
 await page.locator('#trading-panel').waitFor({state:'visible'});assert.match(await table.innerText(),/PAIR-0004/);
 assert.deepEqual(errors,[]);await browser.close();console.log('Preview 23 browser: Single Pair, editable drafts, drawdown, status colors, Central Time and persistent column resizing passed.');
})().catch(e=>{console.error(e);process.exit(1)});
