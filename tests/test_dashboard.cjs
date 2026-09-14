const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Element {
  constructor(){this.value='';this.checked=false;this.disabled=false;this.textContent='';this.children=[];this.parts={};this.classList={add(){},remove(){},toggle(){}};}
  addEventListener(event,fn){this[event]=fn;} showModal(){} replaceChildren(){this.children=[];} append(...children){this.children.push(...children);}
  querySelector(key){return this.parts[key]??=(new Element());}
}
const elements={},get=id=>{assert.notEqual(id,'orders-checked','removed checkbox must never be accessed');return elements[id]??=(new Element());};
const context=vm.createContext({document:{getElementById:get,createElement:()=>new Element()},location:{hash:''},sessionStorage:{getItem:()=>'',setItem(){}},history:{replaceState(){}},setInterval(){},fetch:()=>new Promise(()=>{}),console});
vm.runInContext(fs.readFileSync('coordinator/static/app.js','utf8'),context);
function render(s){context.fixture=s;vm.runInContext('render(fixture)',context);}
const agent=(id,name,pairId)=>({id,name,pairId,configured:true,online:true,fresh:true,position:'Flat',account:'Sim101',quantity:1,ticker:'MNQ',ageMs:1});
const a=agent('vm-left','MFFLocDao','a'),b=agent('vm-right','LCDLocDao','a'),c=agent('fnthu','FNThu','b'),d=agent('fnsean','FNSean','b');
const pair=(id,agents,sl,pt)=>({id,name:agents.map(a=>a.name).join(' / '),settings:{ticker:'MNQ',stopLoss:sl,profit:pt},agents,pair:agents.map(a=>a.id),closedSequence:0,canEnter:false,active:false,busy:false,events:[],jobs:[]});
const pa=pair('a',[a,b],123,456),pb=pair('b',[c,d],333,444);
const s={fleet:[a,b,c,d],pairs:[pa,pb],events:[]};
render(s);assert.equal(get('vm-left').querySelector('h2').textContent,'MFFLocDao');
pa.active=true;a.position='1 L';b.position='1 S';render(s);
assert.equal(get('left-stop').disabled,true);assert.equal(get('pair-left').disabled,false,'new-pair selector must remain usable while another pair is open');
vm.runInContext("selectView('b')",context);
assert.equal(get('vm-left').querySelector('h2').textContent,'FNThu');assert.match(get('buy').textContent,/Buy FNThu \/ Sell FNSean/);
assert.equal(get('left-stop').value,333);assert.equal(get('left-stop').disabled,false);assert.equal(get('prepare').disabled,false);
get('left-stop').value='777';vm.runInContext("changed('left-stop')",context);
vm.runInContext("selectView('a');selectView('b')",context);assert.equal(get('left-stop').value,'777','draft settings must stay with their own pair');
pb.active=true;render(s);assert.equal(get('release-pair').disabled,false,'unresolved but idle Flat pair must allow release');

pb.active=false;pb.closedSequence=1;render(s);
assert.equal(get('left-stop').value,'777');assert.equal(get('buy').disabled,true);assert.equal(get('prepare').disabled,false);assert.match(get('alert').textContent,/Both positions verified Flat/);
assert.equal(pa.active,true,'reset of B must not change A');
vm.runInContext("registeredId='fnthu'",context);render(s);
assert.match(get('connection-result').textContent,/FNThu connected/);
get('connection-code').input();
get('connection-result').textContent='Registration rejected: unresolved pair';
render(s);
assert.equal(get('connection-result').textContent,'Registration rejected: unresolved pair','polling must not overwrite a new registration error with old success');
c.lastKnown={position:'Flat',account:'Sim101',quantity:1,ticker:'MNQ'};
c.fresh=false;c.position='Unknown';pb.active=false;render(s);
assert.equal(get('vm-left').querySelector('.position').textContent,'Flat');
assert.equal(get('vm-left').querySelector('.status').textContent,'Last known status');
assert.equal(get('prepare').disabled,false,'stale idle status must allow a new verification request');
assert.equal(get('release-pair').disabled,false,'Flat / Unknown permits release request');
pb.active=true;render(s);
assert.equal(get('vm-left').querySelector('.position').textContent,'Unknown','active pair must expose missing status');
pb.active=false;
(async()=>{
  const calls=[];
  context.fetch=async(path,options)=>{calls.push([path,JSON.parse(options.body)]);return {ok:true,json:async()=>({job:'test-job'})};};
  await vm.runInContext("action('prepare')",context);
  assert.equal(calls[0][1].pairId,'b');assert.equal(calls[0][1].stopLoss,777);
  assert.equal(get('pair-list').children.length,2);
  context.fetch=async(path)=>path==='/api/pair'?{ok:false,json:async()=>({error:'New pair requires two fresh, idle Flat agents.'})}:{ok:true,json:async()=>({fleet:[],pairs:[],events:[]})};
  await get('select-pair').onclick();
  assert.match(get('pair-result').textContent,/New pair requires/,'pair failure must survive automatic polling');
  console.log('Dashboard: independent pair switching, explicit command routing, draft isolation and scoped reset passed.');
})().catch(e=>{console.error(e);process.exitCode=1});
