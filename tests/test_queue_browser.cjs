const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.TCC_BROWSER_PATH,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const spec={left:'left',right:'right',accounts:{left:'Account-left',right:'Account-right'},names:{left:'VM left',right:'VM right'},masters:{left:'MFF',right:'LCD'},quantities:{left:3,right:3},ticker:'NQ SEP26',stopLoss:100,profit:200,direction:'buy'};
 const queue={running:false,message:'Queue paused.',history:[],rows:[{id:'PAIR-0001',spec,status:'Complete',message:'Results saved.',results:{left:900,right:-900},after:{left:{balance:50900},right:{balance:49100}}},{id:'PAIR-0002',spec,status:'Queued',message:'Waiting for Start Queue.'},{id:'PAIR-0003',spec,status:'Queued',message:'Waiting for Start Queue.'}]};
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){
   const body=req.postDataJSON();writes.push({path:url.pathname,body});
   if(url.pathname==='/api/queue/start'){queue.running=true;queue.rows.filter(r=>r.status==='Queued').forEach(r=>r.dispatched=true);}
   if(url.pathname==='/api/queue/pause')queue.running=false;
   if(url.pathname==='/api/queue/remove-selected'){
    queue.history.push(...queue.rows.filter(r=>body.ids.includes(r.id)).map(r=>({...r,status:'Cancelled',message:'Removed from Airtable.'})));
    queue.rows=queue.rows.filter(r=>!body.ids.includes(r.id));
   }
   if(url.pathname==='/api/queue/refresh')queue.rows=queue.rows.filter(r=>r.id!=='PAIR-0001');
   result={ok:true};
  }else if(url.pathname==='/api/state')result={fleet:[],pairs:[],events:[],limits:{vms:50,pairs:20}};
  else if(url.pathname==='/api/planning')result={rows:[],columns:[],updatedAt:null,error:'',busy:false};
  else if(url.pathname==='/api/queue')result=queue;
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
  await route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('#tab-planning').click();
 await page.locator('#queue-table [data-pair="PAIR-0002"]').waitFor();
 assert.equal(await page.locator('#queue-table [data-pair="PAIR-0001"]').count(),0);
 await page.locator('#queue-start').click();await page.locator('#trading-panel').waitFor({state:'visible'});
 assert.equal(await page.locator('#queue-table tr[data-pair]').count(),0);
 assert.equal(await page.locator('#trading-queue-table tr[data-pair]').count(),3);
 assert.equal(await page.locator('#select-pair').count(),0);
 assert.equal(await page.locator('#trading-queue-table .queue-win').textContent(),'$900.00');
 queue.rows.find(r=>r.id==='PAIR-0002').status='Trading';
 queue.rows.push({id:'PAIR-0004',spec,status:'Queued',message:'New plan'});
 await page.waitForFunction(()=>document.querySelector('#trading-queue-table').textContent.includes('Pairing'));
 assert.equal(await page.locator('#trading-queue-table [data-pair="PAIR-0002"] input').count(),0);
 await page.getByRole('checkbox',{name:'Select PAIR-0003',exact:true}).check();
 await page.locator('#trading-remove-selected').click();
 await page.waitForFunction(()=>document.querySelector('#trading-queue-table [data-pair="PAIR-0003"]').textContent.includes('Canceled'));
 await page.locator('#tab-planning').click();
 assert.equal(await page.locator('#queue-table tr[data-pair]').count(),1);
 await page.getByRole('checkbox',{name:'Select PAIR-0004',exact:true}).check();
 await page.locator('#queue-remove-selected').click();
 await page.waitForFunction(()=>document.querySelectorAll('#queue-table tr[data-pair]').length===0);
 await page.locator('#tab-trading').click();
 assert.equal(await page.locator('#trading-queue-table tr[data-pair]').count(),4);
 assert.deepEqual(writes.filter(w=>w.path==='/api/queue/remove-selected').map(w=>w.body.ids),[['PAIR-0003'],['PAIR-0004']]);
 assert.ok(!writes.some(w=>w.path==='/api/action'));
 await page.locator('#trading-refresh').click();
 await page.waitForFunction(()=>!document.querySelector('#trading-queue-table [data-pair="PAIR-0001"]'));
 assert.ok(writes.some(w=>w.path==='/api/queue/refresh'));
 await page.screenshot({path:'/tmp/queue-preview17.png',fullPage:true});
 assert.deepEqual(errors,[]);await browser.close();console.log('Queue browser: batch transfer, new plans isolated, completion/canceled history, bulk removal and active protection passed.');
})().catch(e=>{console.error(e);process.exit(1)});
