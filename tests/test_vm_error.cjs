// Exercise the production VM renderer and event handlers without a browser runtime.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
class Element{
 constructor(tag){this.tag=tag;this.children=[];this.dataset={};this.className='';this.textContent='';this.scrollTop=0;this.isConnected=true;}
 append(...children){this.children.push(...children);}
 replaceChildren(...children){this.children=children;}
 setAttribute(){}
}
const elements=new Map(),listeners=new Map();
const context={document:{getElementById(id){if(!elements.has(id))elements.set(id,new Element('div'));return elements.get(id);},createElement(tag){return new Element(tag);}},
 localStorage:{getItem(){return null;},setItem(){}},window:{addEventListener(name,fn){listeners.set(name,fn);}},api(){throw new Error('Unexpected API call');}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../coordinator/static/vms.js'),'utf8'),context);
const fleet=['left','right','other'].map(id=>({id,name:id,online:true,fresh:true,position:'Flat',account:'Sim101',accounts:['Sim101'],pairId:id==='other'?null:'binding-77',refresh:{status:'complete',message:'Accounts refreshed successfully.'}}));
let queue={rows:[{id:'PAIR-0077',pairId:'binding-77',status:'Error',message:'ATM Edit dialog did not open.'}],history:[]};
function emit(name,detail){listeners.get(name)({detail});}
function row(id){return elements.get('vms-list').children.find(r=>r.dataset.vm===id);}
function badge(id){return row(id).children[0].children.find(n=>n.className.startsWith('vm-availability'));}
function message(id){return row(id).children[0].children.find(n=>n.className==='vm-refresh-summary').title;}
emit('fleet-updated',{fleet});assert.equal(badge('left').textContent,'Paired');
emit('queue-updated',queue);
for(const id of ['left','right']){
 assert.equal(badge(id).textContent,'Error');assert.ok(badge(id).className.includes('vm-error'));
 assert.match(message(id),/PAIR-0077.*ATM Edit dialog/);
}
assert.equal(badge('other').textContent,'Ready · Available');
function release(id){return row(id).children[0].children.find(n=>n.className==='vm-row-actions').children.find(n=>n.textContent==='Release VMs');}
assert.equal(release('other').disabled,true);assert.match(release('other').title,/No pair reservation/);
assert.equal(release('left').disabled,false);
assert.equal(row('left').children[0].children.length,8);
assert.equal(row('left').children[1].hidden,true);
row('left').children[0].children.find(n=>n.className==='vm-account-toggle quiet').onclick();
assert.equal(row('left').children[1].hidden,false);
assert.equal(fleet[0].pairId,'binding-77');
fleet[0].refresh.status='running';emit('fleet-updated',{fleet});
assert.equal(badge('left').textContent,'Error');
fleet[0].online=false;emit('fleet-updated',{fleet});
assert.equal(badge('left').textContent,'Error');
fleet[0].online=true;fleet[0].refresh.status='complete';queue.rows[0].status='Preparing';emit('queue-updated',queue);
assert.equal(badge('right').textContent,'Paired');assert.ok(badge('right').className.includes('vm-paired'));
queue.history=queue.rows.map(r=>({...r,status:'Error'}));queue.rows=[];
for(const item of fleet)item.pairId=null;
emit('queue-updated',queue);emit('fleet-updated',{fleet});
assert.equal(badge('left').textContent,'Ready · Available');
assert.equal(message('left'),'Accounts refreshed successfully.');
fleet[0].pairId='binding-new';queue.rows=[{id:'PAIR-0077',pairId:'binding-77',status:'Error'}];
emit('queue-updated',queue);emit('fleet-updated',{fleet});
assert.equal(badge('left').textContent,'Paired');
// Current Single Pair errors are handled by the same ownership rule.
queue.rows=[{id:'PAIR-0078',pairId:'binding-new',status:'Error'}];emit('queue-updated',queue);
assert.equal(badge('left').textContent,'Error');assert.equal(badge('right').textContent,'Ready · Available');
assert.match(message('left'),/Pair failed/);
console.log('PASS: single-line VM cells, expandable accounts, persistent disabled/enabled release action, Error precedence and ownership guards.');
