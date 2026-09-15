const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.TCC_BROWSER_PATH,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const original='appzvICrv7LLlZdxm/tbl1u1mKMpVLmTqQP/viw6K3jRjU5PJpWM4',added='appzvICrv7LLlZdxm/tbl1u1mKMpVLmTqQP/viwDqzyeYiDPtrdHA';
 let active=original;
 const views=[{key:original,name:'Accounts'}];
 const snapshots={};
 function snap(key){return snapshots[key]??={rows:[{id:'recA',fields:{id:'A',Balance:50000,Note:'First'}},{id:'recB',fields:{id:'B',Balance:51000,Note:'Second'}}],columns:[{name:'id'},{name:'Balance',type:'currency'},{name:'Note'}],updatedAt:1,error:'',busy:false,configured:true};}
 await page.addInitScript(()=>localStorage.setItem('planning-viw6K3jRjU5PJpWM4-v1',JSON.stringify({hidden:['Note'],columns:['Balance','id','Note'],order:['recB','recA'],widths:{'field:Balance':330},split:60,sort:null})));
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){
   const b=req.postDataJSON();writes.push({path:url.pathname,body:b});
   if(url.pathname==='/api/planning/view'){
    if(b.link==='bad')return route.fulfill({status:400,json:{error:'Use an Airtable view link or ID.'}});
    active=b.key||(b.link.startsWith('https://')?new URL(b.link).pathname.slice(1):'appzvICrv7LLlZdxm/tbl1u1mKMpVLmTqQP/'+b.link);
    if(!views.some(v=>v.key===active))views.push({key:active,name:b.name||b.link});
   }else if(url.pathname==='/api/planning/refresh')snap(active).updatedAt++;
   else assert.fail('Unexpected write '+url.pathname);
   result={ok:true};
  }else if(url.pathname==='/api/state')result={fleet:[],pairs:[],events:[]};
  else if(url.pathname==='/api/queue')result={rows:[],running:false,message:'Paused'};
  else if(url.pathname==='/api/planning')result={...snap(active),viewKey:active,views};
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
  await route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));await page.locator('#tab-planning').click();
 await page.getByRole('columnheader',{name:'Balance',exact:true}).waitFor();
 assert.equal(await page.getByRole('columnheader',{name:'Note',exact:true}).count(),0);
 assert.ok((await page.getByRole('columnheader',{name:'Balance',exact:true}).boundingBox()).width>=330);
 await page.getByRole('checkbox',{name:'Select B',exact:true}).check();
 await page.locator('#planning-add-view').click();await page.locator('#planning-view-link').fill('viwDqzyeYiDPtrdHA');await page.locator('#planning-view-name').fill('Funded');await page.locator('#planning-view-save').click();
 await page.getByRole('columnheader',{name:'Note',exact:true}).waitFor();
 assert.equal(await page.locator('#planning-view').inputValue(),added);
 assert.equal(await page.getByRole('checkbox',{name:'Select B',exact:true}).isChecked(),false);
 assert.ok((await page.getByRole('columnheader',{name:'Balance',exact:true}).boundingBox()).width<330);
 await page.locator('#planning-panel summary').click();await page.getByRole('checkbox',{name:'Balance',exact:true}).uncheck();
 await page.getByRole('separator',{name:'Resize id',exact:true}).focus();await page.keyboard.press('ArrowRight');
 await page.getByRole('button',{name:'Note',exact:true}).click();await page.locator('#planning-save-view').click();
 await page.locator('#planning-view').selectOption(original);
 await page.getByRole('columnheader',{name:'Balance',exact:true}).waitFor();
 assert.equal(await page.getByRole('columnheader',{name:'Note',exact:true}).count(),0);
 assert.ok((await page.getByRole('columnheader',{name:'Balance',exact:true}).boundingBox()).width>=330);
 assert.equal(await page.locator('#planning-table tbody tr').first().getAttribute('data-record'),'recB');
 await page.locator('#planning-view').selectOption(added);await page.getByRole('button',{name:'Note ↑',exact:true}).waitFor();
 assert.equal(await page.getByRole('columnheader',{name:'Balance',exact:true}).count(),0);
 assert.ok((await page.getByRole('columnheader',{name:'id',exact:true}).boundingBox()).width>=190);
 await page.reload();await page.locator('#tab-planning').click();await page.getByRole('button',{name:'Note ↑',exact:true}).waitFor();
 assert.equal(await page.getByRole('columnheader',{name:'Balance',exact:true}).count(),0);
 await page.locator('#planning-refresh').click();await page.waitForTimeout(100);
 assert.equal(await page.getByRole('columnheader',{name:'Balance',exact:true}).count(),0);
 // The same viw ID on another table has a separate layout key.
 await page.locator('#planning-add-view').click();await page.locator('#planning-view-link').fill('https://airtable.com/appzvICrv7LLlZdxm/tblOther123/viwDqzyeYiDPtrdHA');await page.locator('#planning-view-name').fill('Other table');await page.locator('#planning-view-save').click();
 await page.getByRole('columnheader',{name:'Balance',exact:true}).waitFor();
 assert.equal(await page.getByRole('button',{name:'Note ↑',exact:true}).count(),0);
 await page.locator('#planning-add-view').click();await page.locator('#planning-view-link').fill('bad');await page.locator('#planning-view-save').click();
 await page.waitForFunction(()=>document.querySelector('#planning-view-error').textContent.includes('Use an Airtable'));
 await page.locator('#planning-view-cancel').click();
 await page.screenshot({path:'/tmp/planning-preview15.png',fullPage:true});
 assert.deepEqual(errors,[]);assert.ok(writes.every(w=>['/api/planning/view','/api/planning/refresh'].includes(w.path)));
 await browser.close();console.log('Multiple views: add/switch, legacy layout, separate table layouts, widths/sort/hide/order, reload, refresh, validation and selection isolation passed.');
})().catch(e=>{console.error(e);process.exit(1)});
