// Exercise the actual dashboard render path with a small DOM fixture.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Element {
  constructor(){this.value='';this.checked=false;this.disabled=false;this.textContent='';this.children=[];this.parts={};this.classList={add(){},remove(){},toggle(){}};}
  addEventListener(){} showModal(){} replaceChildren(){this.children=[];} append(...children){this.children.push(...children);}
  querySelector(key){return this.parts[key]??=(new Element());}
}
const elements={},get=id=>elements[id]??=(new Element());
const context=vm.createContext({document:{getElementById:get,createElement:()=>new Element()},location:{hash:''},sessionStorage:{getItem:()=>'',setItem(){}},history:{replaceState(){}},setInterval(){},fetch:()=>new Promise(()=>{}),console});
vm.runInContext(fs.readFileSync('coordinator/static/app.js','utf8'),context);
function render(s){context.fixture=s;vm.runInContext('render(fixture)',context);}
const agent=(id,name)=>({id,name,configured:true,online:true,fresh:true,position:'Flat',account:'Sim101',quantity:1,ticker:'MNQ',ageMs:1});
const a=agent('vm-left','MFFLocDao'),b=agent('vm-right','LCDLocDao'),c=agent('fnthu','FNThu'),d=agent('fnsean','FNSean');
const s={settings:{ticker:'MNQ',stopLoss:123,profit:456},fleet:[a,b,c,d],agents:[a,b],pair:[a.id,b.id],closedSequence:0,canEnter:false,active:false,busy:false,events:[],jobs:[]};
render(s);assert.equal(get('vm-left').querySelector('h2').textContent,'MFFLocDao');
get('pair-left').value='fnthu';render(s);assert.equal(get('pair-left').value,'fnthu','polling must preserve a pending selection');
s.pair=['fnthu','fnsean'];s.agents=[c,d];render(s);
assert.equal(get('vm-left').querySelector('h2').textContent,'FNThu');assert.match(get('buy').textContent,/Buy FNThu \/ Sell FNSean/);
s.active=true;get('orders-checked').checked=true;render(s);assert.equal(get('orders-checked').disabled,false,'manual recovery confirmation remains available');
s.active=false;s.closedSequence=1;render(s);
assert.equal(get('orders-checked').checked,false);assert.equal(get('left-stop').value,123);assert.equal(get('buy').disabled,true);assert.equal(get('prepare').disabled,false);assert.match(get('alert').textContent,/Both positions verified Flat/);
console.log('Dashboard: named pair routing, selection persistence, recovery checkbox and post-close reset passed.');
