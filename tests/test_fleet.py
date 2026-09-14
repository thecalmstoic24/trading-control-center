import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from test_center import module, Fake

class FleetTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.fake=Fake()
        self.fleet=module.Fleet(self.temp.name,self.fake,persist=False)
        self.ids=['vm-left','vm-right','fnthu','fnsean']
        for i,slot in enumerate(self.ids):
            self.fake.states[slot]=dict(self.fake.states['vm-left'],id=slot)
            self.fleet.catalog.config[slot]=dict(id=slot,name=slot,host='192.0.2.'+str(i+1),port=8789,pin=format(i+1,'064x'),token='b'*64)
            self.fleet.catalog.poll_locks[slot]=threading.Lock()
            self.fleet.observe(slot)
        self.a=self.fleet.create_pair(*self.ids[:2])
        self.b=self.fleet.create_pair(*self.ids[2:])
    def tearDown(self):
        self.fleet.shutdown()
        for center in [self.fleet.catalog,*self.fleet.pairs.values(),*self.fleet.retired]:
            center.pool.shutdown(wait=True);center.close_pool.shutdown(wait=True)
            for handler in center.logger.handlers:handler.close()
        self.temp.cleanup()
    def wait_job(self,identity,job):
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            found=next(j for j in self.fleet.pairs[identity].jobs if j['id']==job)
            if found['status']!='running':
                self.assertEqual(found['status'],'done',found['message']);return
            time.sleep(.01)
        self.fail('Job did not complete')
    def prepare(self,identity,sl=123,profit=456):
        job=self.fleet.submit('prepare',dict(pairId=identity,ticker='MNQ',stopLoss=sl,profit=profit,noWorkingOrders=True))
        self.wait_job(identity,job)
    def enter(self,identity):
        job=self.fleet.submit('buy',dict(pairId=identity));self.wait_job(identity,job)
        self.fleet.pairs[identity].refresh_both()
    def test_independent_concurrent_entry_and_mirrored_settings(self):
        self.prepare(self.a,111,222);self.prepare(self.b,333,444)
        barrier=threading.Barrier(2)
        def transport(config,command,body=None,**kwargs):
            if command=='entry':barrier.wait(timeout=2)
            return self.fake(config,command,body,**kwargs)
        for pair in self.fleet.pairs.values():pair.transport=transport
        jobs=[self.fleet.submit('buy',dict(pairId=p)) for p in [self.a,self.b]]
        for p,j in zip([self.a,self.b],jobs):self.wait_job(p,j);self.fleet.pairs[p].refresh_both()
        self.assertTrue(all(p.active for p in self.fleet.pairs.values()))
        self.assertEqual(self.fake.states['vm-right']['stopLoss'],222)
        self.assertEqual(self.fake.states['fnsean']['stopLoss'],444)
        self.assertEqual({c[0] for c in self.fake.calls if c[1]=='entry'},{'vm-left','fnthu'})
    def test_close_one_pair_does_not_change_other(self):
        self.prepare(self.a);self.prepare(self.b);self.enter(self.a);self.enter(self.b)
        self.fake.calls.clear()
        job=self.fleet.submit('close',dict(pairId=self.a));self.wait_job(self.a,job)
        self.assertFalse(self.fleet.pairs[self.a].active)
        self.assertTrue(self.fleet.pairs[self.b].active)
        self.assertEqual({c[0] for c in self.fake.calls if c[1]=='close'},set(self.ids[:2]))
    def test_natural_reset_is_scoped_to_one_pair(self):
        self.prepare(self.a);self.prepare(self.b);self.enter(self.a);self.enter(self.b)
        for slot in self.ids[:2]:self.fake.states[slot].update(position='Flat',pairActive=False,prepared=False)
        self.fleet.pairs[self.a].refresh_both()
        self.assertEqual(self.fleet.pairs[self.a].closed_sequence,1)
        self.assertEqual(self.fleet.pairs[self.b].closed_sequence,0)
        self.assertTrue(self.fleet.pairs[self.b].active)
        self.prepare(self.a)
        self.assertTrue(self.fleet.pairs[self.a].state()['canEnter'])
    def test_shared_vm_reservation_is_rejected(self):
        with self.assertRaises(ValueError):self.fleet.create_pair('vm-left','fnsean')
        self.assertEqual(len(self.fleet.pairs),2)
    def test_active_pair_cannot_release(self):
        self.prepare(self.a);self.enter(self.a)
        with self.assertRaises(ValueError):self.fleet.release_pair(self.a)
        self.assertEqual(self.fleet.owners['vm-left'],self.a)
    def test_released_vms_can_be_repaired_and_old_id_cannot_execute(self):
        self.prepare(self.a);self.prepare(self.b)
        self.fleet.release_pair(self.a);self.fleet.release_pair(self.b)
        new=self.fleet.create_pair('vm-left','fnsean')
        with self.assertRaises(ValueError):self.fleet.submit('buy',dict(pairId=self.a))
        self.prepare(new)
        self.assertEqual(self.fake.bindings['vm-left'],'fnsean')
        self.assertTrue(all(not self.fake.states[slot]['prepared'] for slot in ['vm-right','fnthu']))
    def test_stale_flat_pair_cannot_release(self):
        self.fake.states['vm-right']['sampleAgeMs']=99999
        with self.assertRaises(ValueError):self.fleet.release_pair(self.a)
    def test_actions_require_explicit_pair_id(self):
        with self.assertRaises(ValueError):self.fleet.submit('buy',{})
    def test_close_all_dispatches_despite_a_blocked_vm(self):
        self.prepare(self.a);self.prepare(self.b);self.enter(self.a);self.enter(self.b)
        blocked=threading.Event();resume=threading.Event()
        def transport(config,command,body=None,**kwargs):
            if command=='close' and config['id']=='vm-left':
                blocked.set();resume.wait(3)
            return self.fake(config,command,body,**kwargs)
        self.fleet.pairs[self.a].transport=transport
        try:
            result=self.fleet.close_all()
            self.assertTrue(blocked.wait(1))
            self.wait_job(self.b,result['pairs'][self.b]['job'])
            self.assertFalse(self.fleet.pairs[self.b].active)
            self.assertTrue(self.fleet.pairs[self.a].active)
        finally:resume.set()
        self.wait_job(self.a,result['pairs'][self.a]['job'])
    def test_restart_preserves_both_pair_locks(self):
        self.prepare(self.a);self.prepare(self.b);self.enter(self.a);self.enter(self.b)
        other=module.Fleet(self.temp.name,self.fake,persist=False)
        try:
            self.assertEqual(set(other.pairs),{self.a,self.b})
            self.assertTrue(all(p.active for p in other.pairs.values()))
            self.assertEqual(other.owners,self.fleet.owners)
        finally:other.shutdown()
    def test_http_actions_require_a_pair_and_preserve_other_pairs(self):
        import http.client
        server=module.ThreadingHTTPServer(('127.0.0.1',0),module.Handler)
        server.authority='127.0.0.1:'+str(server.server_port)
        server.token='test-session';server.center=self.fleet
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        def request(path,body=None,token='test-session'):
            connection=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
            headers={'X-Control-Token':token,'Origin':'http://'+server.authority,'Content-Type':'application/json'}
            connection.request('POST' if body is not None else 'GET',path,json.dumps(body) if body is not None else None,headers)
            response=connection.getresponse();result=json.loads(response.read());status=response.status;connection.close()
            return status,result
        try:
            status,state=request('/api/state');self.assertEqual(status,200);self.assertEqual(len(state['pairs']),2)
            self.assertEqual(request('/api/state',token='bad')[0],401)
            self.assertEqual(request('/api/action',{'command':'buy'})[0],400)
            status,result=request('/api/action',dict(command='prepare',pairId=self.b,ticker='MNQ',stopLoss=100,profit=200,noWorkingOrders=True))
            self.assertEqual(status,202);self.wait_job(self.b,result['job'])
            self.assertIsNone(self.fleet.pairs[self.a].prepared)
            self.assertIsNotNone(self.fleet.pairs[self.b].prepared)
        finally:server.shutdown();server.server_close();thread.join()
    def test_v12_agent_is_blocked_for_pair_isolation(self):
        self.fake.states['vm-left']['controlVersion']='12.0-preview.1'
        self.fleet.observe('vm-left')
        self.assertFalse(self.fleet.view('vm-left')['fresh'])
    def test_v12_unresolved_migration_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory,'connections.dpapi').write_bytes(json.dumps(self.fleet.catalog.config).encode())
            Path(directory,'entry-unresolved.json').write_text('{}')
            with patch.object(module,'protect',lambda data,decrypt=False:data):
                migrated=module.Fleet(directory,self.fake,persist=True)
            try:
                self.assertEqual(len(migrated.pairs),1)
                self.assertTrue(next(iter(migrated.pairs.values())).active)
            finally:migrated.shutdown()

if __name__=='__main__':unittest.main()
