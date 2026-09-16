const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
function load(saved){const styles={},attrs={},storage={},host={style:{setProperty(k,v){styles[k]=v;}},getBoundingClientRect(){return {left:0,width:1010};}},divider={setAttribute(k,v){attrs[k]=v;},setPointerCapture(){}};
vm.runInNewContext(fs.readFileSync('coordinator/static/trading-layout.js','utf8'),{document:{getElementById:id=>id==='trading-split'?host:divider},localStorage:{getItem(){return saved??null;},setItem(k,v){storage[k]=v;}}});return {styles,attrs,storage,divider};}
let x=load();assert.equal(x.styles['--pair-share'],'75fr');assert.equal(x.styles['--activity-share'],'25fr');
x.divider.onpointerdown({button:0,clientX:755,pointerId:1,preventDefault(){}});x.divider.onpointermove({clientX:655});x.divider.onpointerup();assert.equal(x.storage['trading-pair-share'],'65');
x=load(x.storage['trading-pair-share']);assert.equal(x.attrs['aria-valuenow'],'65');x.divider.onkeydown({key:'ArrowRight',preventDefault(){}});assert.equal(x.storage['trading-pair-share'],'67');
x.divider.onkeydown({key:'End',preventDefault(){}});assert.equal(x.styles['--pair-share'],'85fr');assert.equal(load('invalid').styles['--pair-share'],'75fr');
const html=fs.readFileSync('coordinator/static/index.html','utf8');assert.equal((html.match(/id="queue-activity"/g)||[]).length,1);assert.ok(html.indexOf('id="trading-split"')<html.indexOf('id="trading-divider"'));assert.ok(html.indexOf('id="trading-divider"')<html.indexOf('id="queue-activity"'));
console.log('PASS: 75/25 default, drag persistence, reload, keyboard resizing, bounds and activity placement.');
