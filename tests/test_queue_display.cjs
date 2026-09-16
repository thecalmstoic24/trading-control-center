const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Element {
 constructor(){this.children=[];this.hidden=true;this._value='';}
 append(child){this.children.push(child);if(this.children.length===1&&!this._value)this._value=child.value;}
 replaceChildren(){this.children=[];this._value='';}
 set value(value){this._value=this.children.some(c=>c.value===value)?value:'';}
 get value(){return this._value;}
}
const elements=new Map();const get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
let callback,delay,apiResult={startedCount:5},fail=false,cleared=0;
const context={document:{getElementById:get,createElement:()=>({})},setTimeout(fn,ms){callback=fn;delay=ms;return 1;},clearTimeout(){cleared++;},api:async()=>{if(fail)throw Error('Failed to start');return apiResult;},Intl,Date,Map,Set};
let source=fs.readFileSync('coordinator/static/queue.js','utf8');
source=source.slice(0,source.indexOf("  async function poll()"))+`\nrender=()=>{};async function poll(){};globalThis.test={centralDay,tradingRows,toast,action,setData(value){data=value;}};})();`;
vm.runInNewContext(source,context);
const t=context.test,day=t.centralDay(Date.now());
assert.equal(t.centralDay('2026-09-16T03:00:00Z'),'2026-09-15');
assert.equal(t.centralDay('2026-01-16T05:30:00Z'),'2026-01-15');
assert.equal(t.centralDay('invalid'),'');
const old={id:'old',status:'Complete',completedUtc:'2025-01-01T12:00:00Z'},today={id:'today',status:'Complete',completedUtc:new Date().toISOString()},active={id:'active',status:'Error',created:'2025-01-01'},plan={id:'plan',status:'Queued'};
t.setData({rows:[today,active,plan],history:[old]});
assert.deepEqual(Array.from(t.tradingRows(),r=>r.id),['today','active']);
get('trading-date').value='2025-01-01';assert.deepEqual(Array.from(t.tradingRows(),r=>r.id),['active','old']);
get('trading-date').value='all';assert.equal(t.tradingRows().length,3);
get('trading-date').value='today';assert.equal(t.tradingRows().length,2);
(async()=>{
 await t.action('start');assert.match(get('queue-toast').textContent,/5 pairs started/);assert.equal(delay,5000);assert.equal(get('queue-toast').hidden,false);assert.equal(elements.has('tab-trading'),false);
 callback();assert.equal(get('queue-toast').hidden,true);
 apiResult={startedCount:1};await t.action('start');assert.match(get('queue-toast').textContent,/1 pair started/);assert.ok(cleared>=2);
 callback();fail=true;await t.action('start');assert.equal(get('queue-toast').hidden,true);assert.equal(get('queue-status').textContent,'Failed to start');
 console.log('PASS: Central dates/DST; Today/history/all; unfinished pairs; planning excludes drafts; counted toast, five-second expiry, no navigation, errors.');
})().catch(e=>{console.error(e);process.exitCode=1;});
