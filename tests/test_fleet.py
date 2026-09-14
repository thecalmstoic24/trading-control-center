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
        for _ in range(100):
            if not self.fleet.pairs[self.a].sync_dispatch: break
            threading.Event().wait(.01)
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
    def test_one_flat_one_unknown_can_release(self):
        self.fake.states['vm-right']['sampleAgeMs']=99999
        self.fleet.release_pair(self.a)
        self.assertNotIn(self.a,self.fleet.pairs)
        self.assertNotIn('vm-right',self.fleet.owners)
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

class MigrationTests(FleetTests):
    def private_code(self, slot):
        import base64, json
        value=self.fleet.catalog.config[slot].copy()
        value['host']='100.77.1.2'
        return base64.b64encode(json.dumps(value).encode()).decode()
    def test_idle_same_identity_migrates_without_releasing_pair(self):
        slot=self.ids[0]
        self.fleet.enroll(slot,self.private_code(slot))
        self.assertEqual(self.fleet.catalog.config[slot]['host'],'100.77.1.2')
        self.assertEqual(self.fleet.pairs[self.a].config[slot]['host'],'100.77.1.2')
        self.assertEqual(self.fleet.owners[slot],self.a)
        self.assertFalse(any(command=='entry' for _,command,_ in self.fake.calls))
    def test_active_pair_cannot_migrate(self):
        self.prepare(self.a);self.enter(self.a)
        with self.assertRaises(ValueError):self.fleet.enroll(self.ids[0],self.private_code(self.ids[0]))
    def test_stale_new_endpoint_cannot_migrate(self):
        self.fake.states[self.ids[0]]['sampleAgeMs']=99999
        with self.assertRaises(ValueError):self.fleet.enroll(self.ids[0],self.private_code(self.ids[0]))

    def test_unresolved_flat_pair_can_restore_address_without_clearing_recovery(self):
        pair=self.fleet.pairs[self.a]
        pair.active=True
        pair.prepared='old-preparation'
        generation=pair.generation
        slot=self.ids[0]
        self.fleet.enroll(slot,self.private_code(slot))
        self.assertEqual(pair.config[slot]['host'],'100.77.1.2')
        self.assertTrue(pair.active)
        self.assertIsNone(pair.prepared)
        self.assertGreater(pair.generation,generation)
        self.assertEqual(self.fleet.owners[slot],self.a)
        self.assertFalse(any(command!='status' for _,command,_ in self.fake.calls))

    def test_unresolved_busy_endpoint_cannot_restore_address(self):
        self.fleet.pairs[self.a].active=True
        self.fake.states[self.ids[0]]['busy']=True
        with self.assertRaises(ValueError):
            self.fleet.enroll(self.ids[0],self.private_code(self.ids[0]))
        self.assertTrue(self.fleet.pairs[self.a].active)

    def test_flat_unresolved_pair_releases_despite_account_quantity_changes(self):
        pair=self.fleet.pairs[self.a]
        pair.active=True;pair.mark_active()
        for slot in self.ids[:2]:
            self.fake.states[slot].update(account='Different-'+slot,quantity=7,pairActive=True)
        self.fleet.release_pair(self.a)
        self.assertNotIn(self.a,self.fleet.pairs)
        self.assertTrue(all(slot not in self.fleet.owners for slot in self.ids[:2]))
        self.assertFalse((pair.directory/'entry-unresolved.json').exists())
        self.assertFalse(any(c[1] in ('entry','close','prepare') for c in self.fake.calls))

    def test_release_keeps_reservations_on_unbind_failure(self):
        self.fleet.pairs[self.a].active=True
        self.fake.fail.add((self.ids[1],'unbind_peer'))
        with self.assertRaises(Exception): self.fleet.release_pair(self.a)
        self.assertTrue(all(self.fleet.owners[slot]==self.a for slot in self.ids[:2]))

    def test_idle_polling_pauses_but_active_and_prepared_continue(self):
        pair=self.fleet.pairs[self.a]
        pair.refresh_both()
        self.assertTrue(self.fleet.idle_snapshot_held(self.ids[0]))
        pair.active=True
        self.assertFalse(self.fleet.idle_snapshot_held(self.ids[0]))
        pair.active=False;pair.prepared={'test':True}
        self.assertFalse(self.fleet.idle_snapshot_held(self.ids[0]))

    def test_cached_accounts_do_not_make_failed_status_fresh(self):
        pair=self.fleet.pairs[self.a]
        slot=self.ids[0]
        self.fake.states[slot]['accounts']=['Sim101','MatchedAccount']
        pair.refresh_both()
        pair.observations[slot]={'fresh':False,'state':{},'received':time.monotonic()}
        view=pair.view_agent(slot)
        self.assertEqual(view['accounts'],['Sim101','MatchedAccount'])
        self.assertEqual(view['lastKnown']['position'],'Flat')
        self.assertFalse(view['fresh'])
        self.assertEqual(view['position'],'Unknown')

    def test_two_unknown_vms_cannot_release(self):
        for slot in self.ids[:2]:self.fake.states[slot]['sampleAgeMs']=99999
        with self.assertRaises(ValueError):self.fleet.release_pair(self.a)
        self.assertIn(self.a,self.fleet.pairs)

    def test_create_pair_refreshes_stale_snapshot(self):
        self.fleet.release_pair(self.a)
        for slot in self.ids[:2]:
            self.fleet.catalog.observations[slot]['received']=time.monotonic()-60
        self.fake.calls.clear()
        identity=self.fleet.create_pair(*self.ids[:2])
        self.assertIn(identity,self.fleet.pairs)
        self.assertEqual({slot for slot,cmd,_ in self.fake.calls if cmd=='status'},set(self.ids[:2]))

    def test_create_pair_rejects_newly_open_position(self):
        self.fleet.release_pair(self.a)
        self.fake.states[self.ids[0]]['position']='1 L'
        with self.assertRaises(ValueError):self.fleet.create_pair(*self.ids[:2])
        self.assertNotIn(self.ids[0],self.fleet.owners)
