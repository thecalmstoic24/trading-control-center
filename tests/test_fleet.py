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
    def test_startup_refresh_once_per_agent_process_and_old_agents_unchanged(self):
        slot='vm-left'
        with patch.object(self.fleet,'refresh_vm') as refresh:
            self.fleet.refresh_on_startup(slot);refresh.assert_not_called()
            self.fake.states[slot]['agentSession']='a'*32;self.fleet.observe(slot)
            self.fleet.refresh_on_startup(slot);refresh.assert_called_once_with(slot)
            self.fleet.vm_refresh[slot]={'status':'complete'}
            for _ in range(3):self.fleet.refresh_on_startup(slot)
            self.assertEqual(refresh.call_count,1)
            self.fake.states[slot]['agentSession']='b'*32;self.fleet.observe(slot)
            self.fleet.refresh_on_startup(slot);self.assertEqual(refresh.call_count,2)

    def test_startup_refresh_defers_active_busy_and_calibrating_vm(self):
        slot='vm-left';self.fake.states[slot]['agentSession']='a'*32
        pair=self.fleet.get_pair(self.a)
        with patch.object(self.fleet,'refresh_vm') as refresh:
            for field in ('busy','scheduled','calibrationRequired'):
                self.fake.states[slot][field]=True;self.fleet.observe(slot)
                self.fleet.refresh_on_startup(slot);refresh.assert_not_called()
                self.fake.states[slot][field]=False
            self.fleet.observe(slot);pair.active=True
            self.fleet.refresh_on_startup(slot);refresh.assert_not_called()
            pair.active=False;pair.prepared='prepared'
            self.fleet.refresh_on_startup(slot);refresh.assert_not_called()
            pair.prepared=None
            self.fleet.refresh_on_startup(slot);refresh.assert_called_once_with(slot)

    def test_startup_refresh_failure_backoff_and_inflight_dedup(self):
        slot='vm-left';self.fake.states[slot]['agentSession']='a'*32;self.fleet.observe(slot)
        with patch.object(self.fleet,'refresh_vm') as refresh:
            self.fleet.refresh_on_startup(slot)
            self.fleet.vm_refresh[slot]={'status':'running'}
            for _ in range(3):self.fleet.refresh_on_startup(slot)
            self.assertEqual(refresh.call_count,1)
            self.fleet.vm_refresh[slot]={'status':'error'}
            self.fleet.refresh_on_startup(slot);self.fleet.refresh_on_startup(slot)
            self.assertEqual(refresh.call_count,1)
            self.fleet.startup_refresh[slot]['retryAt']=0
            self.fleet.refresh_on_startup(slot);self.assertEqual(refresh.call_count,2)

    def test_vm_sync_targets_only_selected_agent_and_preserves_blank_account(self):
        self.fake.states['vm-left'].update(manualSync=True,account='')
        self.fake.calls.clear();reply=self.fleet.sync_vm('vm-left')
        self.assertTrue(reply['ok'])
        self.assertEqual([(slot,cmd) for slot,cmd,_ in self.fake.calls if cmd!='status'],[('vm-left','manual_sync')])
        self.assertEqual(self.fake.states['vm-left']['account'],'')
        self.assertTrue(any('Sync Airtable requested' in event['message'] for event in self.fleet.vm_events))
        self.assertFalse(self.fleet.vm_sync_requests)

    def test_vm_sync_can_request_deferral_on_busy_agent(self):
        self.fake.states['vm-left'].update(manualSync=True,busy=True,pairActive=True)
        self.fleet.get_pair(self.a).active=True
        self.fleet.sync_vm('vm-left')
        self.assertEqual(sum(command=='manual_sync' for _,command,_ in self.fake.calls),1)
        self.assertTrue(self.fleet.get_pair(self.a).active)
        self.assertFalse(any(command in ('prepare','entry','close') for _,command,_ in self.fake.calls))

    def test_vm_sync_unsupported_disconnected_and_duplicate_requests(self):
        with self.assertRaisesRegex(ValueError,'Update this VM'):self.fleet.sync_vm('vm-left')
        self.fake.states['vm-left']['manualSync']=True
        self.fake.fail.add(('vm-left','status'))
        with self.assertRaisesRegex(ValueError,'disconnected'):self.fleet.sync_vm('vm-left')
        self.fake.fail.clear();self.fleet.vm_sync_requests.add('vm-left')
        self.assertIn('already',self.fleet.sync_vm('vm-left')['message'])
        self.fleet.vm_sync_requests.clear();self.fake.states['vm-left']['manualSyncPending']=True
        self.assertIn('already',self.fleet.sync_vm('vm-left')['message'])
        self.assertFalse(any(command=='manual_sync' for _,command,_ in self.fake.calls))

    def test_vm_sync_timeout_never_resends(self):
        self.fake.states['vm-left']['manualSync']=True
        original=self.fleet.get_pair(self.a).transport;attempts=[]
        def transport(config,command,body=None,**kwargs):
            if command=='manual_sync':attempts.append(command);raise TimeoutError('Lost reply')
            return original(config,command,body,**kwargs)
        self.fleet.get_pair(self.a).transport=transport
        with self.assertRaises(TimeoutError):self.fleet.sync_vm('vm-left')
        self.assertEqual(attempts,['manual_sync']);self.assertFalse(self.fleet.vm_sync_requests)

    def test_vm_refresh_updates_owned_shared_account_list(self):
        self.fake.states['vm-left']['accounts']=['Sim101','MFF-NEW']
        self.fleet.refresh_vm('vm-left')
        deadline=time.time()+4
        while self.fleet.vm_refresh['vm-left']['status']=='running' and time.time()<deadline: time.sleep(.02)
        self.assertEqual(self.fleet.vm_refresh['vm-left']['status'],'complete')
        self.assertIn('MFF-NEW',self.fleet.view('vm-left')['accounts'])
        self.assertIn('MFF-NEW',self.fleet.get_pair(self.a).view_agent('vm-left')['accounts'])
    def test_vm_refresh_does_not_touch_active_pair(self):
        self.fleet.get_pair(self.a).active=True
        with self.assertRaises(ValueError): self.fleet.refresh_vm('vm-left')
        self.assertFalse(any(c[1]=='accounts' for c in self.fake.calls))
    def wait_vm_refresh(self, slot):
        deadline=time.monotonic()+4
        while self.fleet.vm_refresh[slot]['status']=='running' and time.monotonic()<deadline:
            time.sleep(.01)
        return self.fleet.vm_refresh[slot]
    def test_blank_chart_account_refresh_completes_without_selecting_or_trading(self):
        slot='vm-left'
        self.fake.states[slot].update(account='',accounts=['Sim101','BX-M123'],accountMessage='2 matched accounts')
        self.fleet.vm_refresh[slot]={'status':'error','message':'Previous refresh failure'}
        self.fake.calls.clear()
        self.fleet.refresh_vm(slot)
        result=self.wait_vm_refresh(slot)
        self.assertEqual(result['status'],'complete',result)
        self.assertIn('BX-M123',self.fleet.view(slot)['accounts'])
        self.assertEqual(self.fake.states[slot]['account'],'')
        self.assertEqual([command for _,command,_ in self.fake.calls if command!='status'],['accounts'])
    def test_blank_chart_refresh_rejects_stale_nonflat_or_busy_state(self):
        slot='vm-left'
        baseline=dict(self.fake.states[slot],account='')
        for changes in ({'ok':False},{'sampleAgeMs':999999},{'position':'1 L'},
                        {'position':'Unknown'},{'busy':True},{'scheduled':True},
                        {'pendingVerification':True},{'closing':True},{'pairActive':True}):
            with self.subTest(changes=changes):
                # Each case is independent; observing a position above marks the pair active.
                self.fleet.get_pair(self.a).active=False
                self.fleet.get_pair(self.a).opened_ids.clear()
                self.fake.states[slot]=dict(baseline,**changes)
                self.fake.calls.clear()
                self.fleet.refresh_vm(slot)
                result=self.wait_vm_refresh(slot)
                self.assertEqual(result['status'],'error',result)
                self.assertFalse(any(command=='accounts' for _,command,_ in self.fake.calls))
    def test_blank_account_discovery_does_not_weaken_trade_or_close_checks(self):
        slot='vm-left';center=self.fleet.get_pair(self.a)
        self.fake.states[slot]['account']=''
        center.observe(slot)
        view=center.view_agent(slot)
        self.assertTrue(center.account_discovery_idle(view))
        self.assertFalse(center.safe_flat(view))
        center.wait_refresh_idle(slot,timeout=.1,allow_unselected_account=True)
        with self.assertRaisesRegex(ValueError,'could not verify an idle VM'):
            center.wait_refresh_idle(slot,timeout=.01)
        self.fake.calls.clear()
        with self.assertRaisesRegex(ValueError,'fresh Flat'):
            center.prepare(dict(ticker='NQ DEC26',stopLoss=100,profit=200),center.generation)
        self.assertFalse(any(command in ('prepare','bind_peer','entry') for _,command,_ in self.fake.calls))
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
