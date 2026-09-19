const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try{
 const page=await browser.newPage({viewport:{width:1920,height:1080}}),errors=[],writes=[];page.on('pageerror',e=>errors.push(e.message));
 let config={enabled:false,vm:'left',bars:10,multiplier:1,reference:'NQ DEC26',timeframe:1,excludeAboveMedian:0};const queue={rows:[],running:false,message:'Background result upload pending: Airtable request failed (HTTP 422): ROW_DOES_NOT_EXIST',sessions:[]};
 const fleet=['left','right'].map(id=>({id,name:id,online:true,fresh:true,position:'Flat',accounts:['Sim101'],refresh:{},pairId:'pair'}));
 const draft={key:'a'.repeat(32),ticker:'NQ',direction:'buy',ratio:'1:1',leftQuantity:'2',rightQuantity:'2',profit:'800',stopLoss:'600',left:{account:'A',master:'MFF-TEST'},right:{account:'B',master:'FN-TEST'}};
 await page.addInitScript(d=>localStorage.setItem('planning-draft-pairs-v1',JSON.stringify([d])),draft);
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){
   const body=req.postDataJSON();writes.push({path:url.pathname,body});result={ok:true};
   if(url.pathname==='/api/auto-quantity'){config=body;result=config;}
   if(url.pathname==='/api/auto-quantity/estimate')result={ticker:'MNQ DEC26',leftQuantity:20,rightQuantity:30,distance:20};
   if(url.pathname==='/api/vm-release')result={ok:true,message:'Pair reservations released'};
   if(url.pathname==='/api/queue/add'){
    const row={id:'DRAFT-'+body.draftKey,key:body.draftKey,localDraft:true,status:'Queued',spec:{...body,left:'left',right:'right',accounts:{left:'A',right:'B'},masters:{left:'MFF-TEST',right:'FN-TEST'},quantities:{left:+body.draft.leftQuantity,right:+body.draft.rightQuantity},balances:{}}};
    queue.rows.push(row);result={row};
   }
  }else if(url.pathname==='/api/state')result={version:'16.0-preview.40',dashboard:true,fleet,pairs:[],events:[],vmEvents:[]};
  else if(url.pathname==='/api/queue')result=queue;
  else if(url.pathname==='/api/planning')result={rows:[],columns:[],views:[{key:'test',name:'Test'}],viewKey:'test',updatedAt:1,busy:false,error:''};
  else if(url.pathname==='/api/auto-quantity')result=config;
  else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);return route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.svg')?'image/svg+xml':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));
 await page.getByRole('button',{name:'Release VMs for left',exact:true}).click();assert.ok(writes.some(w=>w.path==='/api/vm-release'&&w.body.id==='left'));
 await page.locator('#tab-planning').click();
 const card=page.locator('.draft-card');await card.waitFor();
 const input=card.locator('[data-value-key=profit]');await input.fill('9999');assert.ok((await input.boundingBox()).width>=40);
 assert.equal(await page.locator('.draft-panel .auto-settings').count(),0);
 assert.equal(await page.locator('.auto-fields > label').count(),5);
 await card.locator('[data-field=priority]').selectOption('2');
 assert.equal(await page.locator('#queue-status + .queue-notice').isVisible(),true);
 assert.equal(await page.locator('#queue-status + .queue-notice pre').isVisible(),false);
 for(const width of [700,510,340]){
   await page.locator('.draft-panel').evaluate((n,w)=>{n.style.width=w+'px';},width);
   await page.waitForTimeout(50);
   const boxes=await card.locator('.draft-account,.draft-amounts,.draft-center').evaluateAll(nodes=>nodes.map(n=>{const r=n.getBoundingClientRect();return {x:r.x,y:r.y,r:r.right,b:r.bottom};}));
   for(let a=0;a<boxes.length;a++)for(let b=a+1;b<boxes.length;b++){const x=boxes[a],y=boxes[b];assert.ok(x.r<=y.x+1||y.r<=x.x+1||x.b<=y.y+1||y.b<=x.y+1,'Card sections must not overlap');}
   assert.equal(await card.locator('.draft-account').evaluateAll(ns=>ns.every(n=>n.scrollWidth<=n.clientWidth+1)),true);
 }
 await page.locator('.draft-panel').evaluate(n=>{n.style.width='';});
 await page.screenshot({path:path.join(process.env.TEMP||'/tmp','preview40-planning.png')});
 await page.locator('.auto-settings input[type=checkbox]').check();assert.equal(await card.locator('[data-field=ticker]').isVisible(),false);await page.getByRole('button',{name:'Save',exact:true}).click();
 await page.waitForFunction(()=>document.body.classList.contains('auto-enabled'));
 assert.equal(await card.locator('[data-value-key=leftQuantity]').isVisible(),false);
 assert.equal(await card.locator('[data-field=ticker]').isVisible(),false);
 assert.equal(await card.locator('[data-field=ratio]').isVisible(),true);
 await card.locator('[data-field=ratio]').selectOption('2:3');await input.fill('800');
 await page.waitForFunction(()=>document.querySelector('.draft-notice').textContent.includes('Auto estimate'));
 await card.getByRole('button',{name:'Confirm pair',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('.draft-card'));
 const submission=writes.find(w=>w.path==='/api/queue/add');assert.equal(submission.body.priority,2);assert.equal(submission.body.autoQuantity.vm,'left');assert.equal(submission.body.ratio,'2:3');assert.equal(submission.body.draft.leftQuantity,'20');
 await page.locator('#tab-trading').click();assert.equal(await page.locator('iframe.tv-chart').count(),0);
 assert.equal(await page.locator('#trading-queue-table th[data-column=0]').count(),0);
 assert.equal(submission.body.autoQuantity.excludeAboveMedian,3);
 assert.match(await page.locator('.activity .section-title').textContent(),/Central Time/);
 assert.equal(await page.locator('.tabs #trading-progress').count(),1);assert.deepEqual(errors,[]);
 await page.screenshot({path:path.join(process.env.TEMP||'/tmp','preview40-trading.png')});
 console.log('PASS: VM Release action; four-digit inputs; shared Auto Quantity settings, sizing, ratio, hidden controls, confirmation and chart removal.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
