const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1920,height:1080}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 const accounts=['FFF236159','FNTEST'].map((id,i)=>({id:'rec'+i,fields:{id,'Master Account':i?'FN-JASON':'FFF-TRINH',CurrentBalance:52000,stop:50000,'Trailing max drawdown':1500,'Realized PnL':-25,Notes:'x'.repeat(30000)}}));
 const fleet=accounts.map((a,i)=>({id:'vm'+i,name:a.fields['Master Account'],online:true,fresh:true,position:'Flat',accounts:[a.fields.id],refresh:{}}));
 const vmEvents=[{id:1,utc:'2026-09-16T15:00:00Z',vm:'vm0',name:'FFF-TRINH',message:'Accounts refreshed'}];
 const queue={rows:[],history:[],running:false,message:'Paused'};
 await page.route('http://127.0.0.1:8788/**',async route=>{
  const req=route.request(),url=new URL(req.url());let result;
  if(req.method()==='POST'){
   const body=req.postDataJSON();writes.push({path:url.pathname,body});result={ok:true};
   if(url.pathname==='/api/queue/add'){
    assert.ok(Buffer.byteLength(req.postData())<16384,'Confirmation exceeded server limit');
    queue.rows.push({id:'DRAFT-'+body.draftKey,key:body.draftKey,draft:body.draft,localDraft:true,status:'Queued',spec:{...body,names:{vm0:'FFF-TRINH',vm1:'FN-JASON'},masters:{vm0:'FFF-TRINH',vm1:'FN-JASON'}}});
   }
   if(url.pathname==='/api/queue/edit-draft'){const row=queue.rows.find(r=>r.id===body.id);queue.rows=queue.rows.filter(r=>r!==row);result={draft:row};}
  } else if(url.pathname==='/api/state')result={fleet,pairs:[],events:[],vmEvents,limits:{vms:50,pairs:20}};
  else if(url.pathname==='/api/planning')result={rows:accounts,columns:['id','Master Account','CurrentBalance'].map(name=>({name})),updatedAt:1,error:'',busy:false};
  else if(url.pathname==='/api/queue')result=queue;
  else if(url.pathname==='/api/contracts')result={month:'DEC26',symbols:{NQ:'NQ DEC26',MNQ:'MNQ DEC26'}};
  if(result)return route.fulfill({json:result});
  const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
  await route.fulfill({body:fs.readFileSync(path.join(__dirname,'../coordinator/static',file)),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://127.0.0.1:8788/#'+'a'.repeat(64));
 await page.locator('#vm-events').getByText('FFF-TRINH · Accounts refreshed',{exact:true}).waitFor();
 const left=await page.locator('.vm-list-pane').boundingBox(),right=await page.locator('.vm-log-pane').boundingBox();
 assert.ok(Math.abs(left.width/right.width-4)<.1);assert.ok(right.x>left.x+left.width);
 assert.ok((await page.locator('main').boundingBox()).width>1850);
 const divider=await page.locator('#vms-divider').boundingBox();
 await page.mouse.move(divider.x+5,divider.y+30);await page.mouse.down();await page.mouse.move(divider.x-150,divider.y+30);await page.mouse.up();
 const saved=await page.evaluate(()=>localStorage.getItem('vms-list-share'));assert.ok(+saved<80);
 await page.reload();await page.locator('#vm-events .event').waitFor();assert.equal(await page.locator('#vms-divider').getAttribute('aria-valuenow'),String(Math.round(+saved)));
 await page.locator('#vms-divider').focus();await page.keyboard.press('ArrowRight');assert.equal(await page.locator('#vms-divider').getAttribute('aria-valuenow'),String(Math.round(+saved+2)));
 await page.locator('#tab-trading').click();assert.ok((await page.locator('#trading-split').boundingBox()).width>1800);
 await page.locator('#tab-planning').click();
 await page.getByRole('checkbox',{name:'Select FFF236159',exact:true}).check();await page.locator('#draft-left').click();
 await page.getByRole('checkbox',{name:'Select FNTEST',exact:true}).check();await page.locator('#draft-right').click();
 const card=page.locator('.draft-card');await card.locator('[data-value-key=profit]').fill('350');await card.locator('[data-value-key=stopLoss]').fill('400');
 await card.getByRole('button',{name:'Confirm pair',exact:true}).click();
 await page.locator('#queue-table').getByRole('button',{name:'Edit',exact:true}).waitFor();
 const sent=writes.find(w=>w.path==='/api/queue/add').body;assert.equal(sent.ticker,'NQ');assert.equal(sent.quantities.vm0,1);assert.equal(sent.draft.left.metrics.Notes,undefined);assert.equal(sent.draft.left.metrics['Realized PnL'],-25);
 await page.locator('#queue-table').getByRole('button',{name:'Edit',exact:true}).click();await card.waitFor();
 assert.equal(await card.locator('[data-value-key=profit]').inputValue(),'350');assert.equal(await card.locator('[data-value-key=stopLoss]').inputValue(),'400');assert.equal(await card.locator('[data-value-key=leftQuantity]').inputValue(),'1');
 await page.setViewportSize({width:740,height:900});await page.locator('#tab-vms').click();assert.equal(await page.locator('#vms-divider').isVisible(),false);
 assert.ok((await page.locator('.vm-log-pane').boundingBox()).y>(await page.locator('.vm-list-pane').boundingBox()).y);
 assert.deepEqual(errors,[]);assert.ok(!writes.some(w=>w.path==='/api/action'));
 await browser.close();console.log('PASS: full-page width, VM 80/20 panel, resizing and persistence, timestamped activity, narrow-screen stacking, oversized-record confirmation and editable settings.');
})().catch(e=>{console.error(e);process.exit(1)});
