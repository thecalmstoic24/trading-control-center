const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try{
 const page=await browser.newPage({viewport:{width:1920,height:1080}}),errors=[],writes=[];page.on('pageerror',e=>errors.push(e.message));
 let config={enabled:false,vm:'left',bars:10,multiplier:1};
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
   if(url.pathname==='/api/queue/add')result={row:{key:body.draftKey}};
  }else if(url.pathname==='/api/state')result={version:'16.0-preview.38',dashboard:true,fleet,pairs:[],events:[],vmEvents:[]};
  else if(url.pathname==='/api/queue')result={rows:[],running:false,message:'Paused',sessions:[]};
  else if(url.pathname==='/api/planning')result={rows:[],columns:[],views:[{key:'test',name:'Test'}],viewKey:'test',updatedAt:1,busy:false,error:''};
  else if(url.pathname==='/api/auto-quantity')result=config;
  else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);return route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));
 await page.getByRole('button',{name:'Release VMs',exact:true}).first().click();assert.ok(writes.some(w=>w.path==='/api/vm-release'&&w.body.id==='left'));
 await page.locator('#tab-planning').click();
 const card=page.locator('.draft-card');await card.waitFor();
 const input=card.locator('[data-value-key=profit]');await input.fill('100000');assert.ok((await input.boundingBox()).width>=75);
 await page.locator('.auto-settings input[type=checkbox]').check();await page.getByRole('button',{name:'Save sizing settings'}).click();
 await page.waitForFunction(()=>document.body.classList.contains('auto-enabled'));
 assert.equal(await card.locator('[data-value-key=leftQuantity]').isVisible(),false);
 assert.equal(await card.locator('[data-field=ticker]').isVisible(),false);
 assert.equal(await card.locator('[data-field=ratio]').isVisible(),true);
 await card.locator('[data-field=ratio]').selectOption('2:3');await input.fill('800');
 await page.waitForFunction(()=>document.querySelector('.draft-notice').textContent.includes('Auto estimate'));
 await card.getByRole('button',{name:'Confirm pair',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('.draft-card'));
 const submission=writes.find(w=>w.path==='/api/queue/add');assert.equal(submission.body.autoQuantity.vm,'left');assert.equal(submission.body.ratio,'2:3');assert.equal(submission.body.draft.leftQuantity,'20');
 await page.locator('#tab-trading').click();assert.equal(await page.locator('iframe.tv-chart').count(),1);
 assert.equal(await page.locator('.tabs #trading-progress').count(),1);assert.deepEqual(errors,[]);
 await page.screenshot({path:path.join(process.env.TEMP||'/tmp','preview38-trading.png')});
 console.log('PASS: VM Release action; six-digit inputs; shared Auto Quantity settings, sizing, ratio, hidden controls, confirmation and chart placement.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
