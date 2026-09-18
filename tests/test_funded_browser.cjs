const {chromium}=require('playwright'),{spawn}=require('node:child_process'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const server=spawn('python',['-u',path.join(__dirname,'http_assets_server.py')],{stdio:['ignore','pipe','inherit']});let browser;
 try{
  await new Promise((resolve,reject)=>{server.once('error',reject);server.stdout.once('data',resolve);server.once('exit',()=>reject(Error('Fixture exited')));});
  browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[],writes=[];
  page.on('pageerror',e=>errors.push(e.message));
  const rows=['MFF','MFF','FN','LCD'].map((firm,i)=>({id:'rec'+i,fields:{id:firm+'-'+i,firm,'Master Account':firm+'-TEST',RealStage:'Funded',NoConsistency:1,RealCurrentBalance:50000,CurrentBalance:51000,RealDrawdown:1500.01+i}}));
  await page.route('http://127.0.0.1:8788/api/**',route=>{
   const req=route.request(),url=new URL(req.url());let result={};
   if(req.method()==='POST'){writes.push({path:url.pathname,body:req.postDataJSON()});result={ok:true};}
   else if(url.pathname==='/api/state')result={version:'16.0-preview.37',fleet:[],pairs:[],events:[],vmEvents:[],limits:{vms:50,pairs:20}};
   else if(url.pathname==='/api/planning')result={rows,columns:[{name:'id'}],updatedAt:1,error:'',busy:false};
   else if(url.pathname==='/api/queue')result={rows:[],history:[],running:false};
   else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
   return route.fulfill({json:result});
  });
  await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('#tab-planning').click();
  await page.getByRole('checkbox',{name:'Select MFF-0',exact:true}).waitFor();
  await page.locator('#suggestion-strategy').selectOption('new-non-consistency');
  assert.equal(await page.locator('#test-strategy-info').evaluate(e=>e.hidden),true);
  await page.locator('#suggest-pairs').click();await page.locator('.draft-card').nth(1).waitFor();
  assert.equal(await page.locator('.draft-card').count(),2);assert.deepEqual(writes,[]);
  const card=page.locator('.draft-card').first();assert.equal(await card.locator('[data-value-key=profit]').inputValue(),'1510');
  assert.equal(await card.locator('[data-value-key=stopLoss]').inputValue(),'1510');
  await card.locator('button[type=submit]').click();
  await page.waitForFunction(()=>document.getElementById('draft-message').textContent.includes('added to the queue'));
  assert.equal(writes.length,1);assert.equal(writes[0].path,'/api/queue/add');
  const d=writes[0].body.draft;assert.equal(d.suggestion.strategy,'new-non-consistency');
  assert.equal(d.left.metrics.RealCurrentBalance,50000);assert.equal(d.left.metrics.RealStage,'Funded');assert.equal(d.left.metrics.NoConsistency,1);
  assert.equal(await page.locator('.draft-card').count(),1);
  assert.deepEqual(errors,[]);console.log('Funded browser: selection, presets, confirmation and exact field payload passed.');
 }finally{if(browser)await browser.close();server.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
