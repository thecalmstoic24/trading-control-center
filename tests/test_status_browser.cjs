const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.TCC_BROWSER_PATH||undefined,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1440,height:1050}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const agent=(id,name)=>({id,name,pairId:'a',configured:true,online:true,fresh:true,position:'3',account:'Sim101',quantity:3,ticker:'NQ SEP26',ageMs:1,accounts:['Sim101'],lastKnown:{position:'3',account:'Sim101',quantity:3,ticker:'NQ SEP26'}});
 const agents=[agent('left','VM left'),agent('right','VM right')];
 const pair={id:'a',name:'VM left / VM right',settings:{ticker:'NQ SEP26',stopLoss:1000,profit:1500,accounts:{},quantities:{left:3,right:3}},agents,pair:['left','right'],closedSequence:0,canEnter:false,active:true,busy:false,events:[],jobs:[],accountRefresh:{}};
 const state={fleet:agents,pairs:[pair],events:[]};
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){writes.push(url.pathname);assert.equal(url.pathname,'/api/planning/refresh');result={ok:true};}
  else if(url.pathname==='/api/state')result=state;
  else if(url.pathname==='/api/queue')result={rows:[],running:false,message:'Paused'};
  else if(url.pathname==='/api/planning')result={rows:[],columns:[],updatedAt:null,error:'',busy:false};
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
  await route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('#tab-trading').click();
 await page.waitForFunction(()=>document.querySelector('#vm-left .position').textContent==='Pairing');
 assert.equal(await page.locator('#vm-right .position').textContent(),'Pairing');
 assert.equal(await page.locator('#left-quantity').inputValue(),'3');
 assert.equal(await page.locator('#pair-status-label').textContent(),'Pairing');
 const cards=await page.locator('.pair').boundingBox(),sidebar=await page.locator('.pair-status-panel').boundingBox();assert.ok(sidebar.x>=cards.x+cards.width);
 assert.equal(await page.locator('#vm-left .position').evaluate(e=>getComputedStyle(e).color),'rgb(165, 78, 0)');
 pair.active=false;pair.closedSequence=1;pair.busy=true;for(const a of agents){a.position='Flat';a.lastKnown.position='Flat';pair.accountRefresh[a.id]='Refreshing accounts';}
 await page.evaluate(s=>render(s),state);
 assert.equal(await page.locator('#pair-status-label').textContent(),'Complete');
 assert.equal(await page.locator('#vm-left .position').evaluate(e=>getComputedStyle(e).color),'rgb(20, 116, 71)');
 assert.equal(await page.locator('#prepare').isDisabled(),true);
 pair.busy=false;for(const a of agents)pair.accountRefresh[a.id]='Account refresh finished';
 await page.evaluate(s=>render(s),state);
 assert.equal(await page.locator('#prepare').isDisabled(),false);
 assert.equal(await page.locator('#buy').isDisabled(),true,'automatic refresh must not authorize entry');
 await page.screenshot({path:'/tmp/status-preview6.png',fullPage:true});
 assert.deepEqual(errors,[]);assert.ok(writes.every(p=>p==='/api/planning/refresh'));
 await browser.close();console.log('Status browser: sidebar placement, Pairing/Complete colors, quantity preservation and next-trade readiness passed.');
})().catch(e=>{console.error(e);process.exit(1)});
