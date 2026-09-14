import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'coordinator'))

spec=importlib.util.spec_from_file_location('center',Path(__file__).resolve().parents[1]/'coordinator'/'server.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Fake:
    def __init__(self):
        self.calls=[]
        self.fail=set()
        self.bindings={}
        self.states={slot:dict(id=slot,controlVersion=module.VERSION,ok=True,sampleAgeMs=0,
                             account='Sim101',quantity='1',position='Flat',ticker='MNQ',
                             prepared=False,prepareId='',scheduled=False,busy=False,
                             pairActive=False,pendingVerification=False) for slot in module.IDS}
    def __call__(self,config,command,body=None,**kwargs):
        slot=config['id']; body=body or {}; self.calls.append((slot,command,body))
        if (slot,command) in self.fail: raise TimeoutError('mock timeout')
        state=self.states[slot]
        if command=='status': return {'ok':True,'cacheAgeMs':0,'_rttMs':1,'state':state.copy()}
        if command=='bind_peer':self.bindings[slot]=body['peer']['id']
        if command in ('invalidate','unbind_peer'):state.update(prepared=False,prepareId='')
        if command=='unbind_peer':self.bindings.pop(slot,None);state['pairActive']=False
        if command=='prepare':state.update(prepared=True,prepareId=body['prepareId'],ticker=body['ticker'],account=body.get('account','Sim101'),quantity=str(body.get('quantity',1)),stopLoss=body['stopLoss'],profit=body['profit'])
        if command=='entry':
            self.states[slot].update(position='1 L',pairActive=True)
            self.states[self.bindings[slot]].update(position='1 S',pairActive=True)
        if command=='close':state.update(position='Flat',prepared=False,pairActive=False)
        return {'ok':True}


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.fake=Fake()
        self.center=module.Center(self.temp.name,self.fake,persist=False)
        self.center.config={slot:dict(id=slot,name=module.NAMES[slot],host='192.0.2.'+str(i+1),port=8789,pin=str(i+1)*64,token='b'*64) for i,slot in enumerate(module.IDS)}
    def tearDown(self):
        self.center.stop.set();self.center.pool.shutdown(wait=True);self.center.close_pool.shutdown(wait=True)
        for handler in self.center.logger.handlers:handler.close()
        self.temp.cleanup()
    def prepare(self):
        self.center.prepare(dict(ticker='MNQ',stopLoss=123,profit=456,noWorkingOrders=True),0)
    def test_mirrored_readback_and_only_one_paired_entry(self):
        self.prepare()
        self.assertTrue(self.center.state()['canEnter'])
        self.assertEqual(self.fake.states['vm-right']['stopLoss'],456)
        self.assertEqual(self.fake.states['vm-right']['profit'],123)
        self.center.entry('buy',0)
        calls=[c for c in self.fake.calls if c[1]=='entry']
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][0],'vm-left')
        with self.assertRaises(ValueError):self.center.entry('buy',0)
    def test_ratio_prepares_and_verifies_distinct_amounts(self):
        self.center.prepare(dict(ticker='MNQ SEP26',stopLoss=1000,profit=800,ratio='2:3',quantities={'vm-left':10,'vm-right':15}),0)
        self.assertTrue(self.center.state()['canEnter'])
        self.assertEqual(self.fake.states['vm-right']['stopLoss'],1200)
        self.assertEqual(self.fake.states['vm-right']['profit'],1500)
        self.assertEqual(self.fake.states['vm-right']['quantity'],'15')
    def test_ratio_quantity_mismatch_sends_no_prepare(self):
        with self.assertRaises(ValueError):
            self.center.prepare(dict(ticker='NQ SEP26',stopLoss=1000,profit=800,ratio='2:3',quantities={'vm-left':1,'vm-right':2}),0)
        self.assertFalse(any(c[1]=='prepare' for c in self.fake.calls))
    def test_stale_is_unknown_and_not_entry_ready(self):
        self.prepare()
        self.fake.states['vm-right']['sampleAgeMs']=4500
        self.center.observe('vm-right')
        self.assertEqual(self.center.state()['agents'][1]['position'],'Unknown')
        self.assertFalse(self.center.state()['canEnter'])
    def test_identity_mismatch_blocks(self):
        self.fake.states['vm-right']['id']='vm-left'
        self.center.refresh_both()
        self.assertFalse(self.center.state()['agents'][1]['online'])
    def test_prepare_without_manual_checkbox(self):
        self.center.prepare(dict(ticker='MNQ',stopLoss=1,profit=2),0)
        self.assertTrue(self.center.state()['canEnter'])
    def test_default_preparation_selects_sim_from_another_flat_account(self):
        self.fake.states['vm-left']['account']='LiveAccount'
        self.prepare()
        self.assertEqual(self.fake.states['vm-left']['account'],'Sim101')
    def test_configuration_change_blocks_entry(self):
        self.prepare();self.fake.states['vm-right']['prepareId']='changed'
        with self.assertRaises(ValueError):self.center.entry('sell',0)
        self.assertFalse(any(c[1]=='entry' for c in self.fake.calls))
    def test_duplicate_enrollment_rejected(self):
        code=lambda slot:base64.b64encode(json.dumps(dict(id=slot,host='example.com',port=8789,pin='a'*64,token='b'*64)).encode()).decode()
        self.center.config={}
        self.center.enroll('vm-left',code('vm-left'))
        with self.assertRaises(ValueError):self.center.enroll('vm-right',code('vm-right'))
    def test_close_independent_even_if_left_ack_lost(self):
        self.fake.fail.add(('vm-left','close'))
        self.center.close_both()
        self.assertTrue(any(c[0]=='vm-right' and c[1]=='close' for c in self.fake.calls))
        self.assertFalse(self.center.active)
    def test_lost_entry_ack_not_retried_and_requests_close(self):
        self.prepare();self.fake.fail.add(('vm-left','entry'))
        with self.assertRaises(ValueError):self.center.entry('buy',0)
        self.assertEqual(len([c for c in self.fake.calls if c[1]=='entry']),1)
        self.assertEqual({c[0] for c in self.fake.calls if c[1]=='close'},set(module.IDS))
    def test_restart_with_unresolved_entry_blocks_new_pair(self):
        Path(self.temp.name,'entry-unresolved.json').write_text('{}')
        other=module.Center(self.temp.name,self.fake,persist=False)
        self.assertTrue(other.active)
        other.pool.shutdown();other.close_pool.shutdown()
        for h in other.logger.handlers:h.close()
    def test_close_generation_cancels_prepare(self):
        self.center.generation=1
        with self.assertRaises(ValueError):self.prepare()
        self.assertIsNone(self.center.prepared)
    def test_invalid_numbers_rejected(self):
        for value in [float('nan'),float('inf'),-1,0,1.234,100001]:
            with self.assertRaises(ValueError):self.center.prepare(dict(ticker='MNQ',stopLoss=value,profit=1,noWorkingOrders=True),0)

    def add_vm(self, slot, name, index):
        code=base64.b64encode(json.dumps(dict(id=slot,name=name,host='192.0.2.'+str(index),port=8789,pin=format(index,'064x'),token='b'*64)).encode()).decode()
        self.center.enroll(None,code)
        self.fake.states[slot]=dict(self.fake.states['vm-left'],id=slot)
        self.center.observe(slot)
    def open_pair(self):
        self.prepare();self.center.entry('buy',self.center.generation);self.center.refresh_both()
    def flat_pair(self):
        for slot in self.center.pair:self.fake.states[slot].update(position='Flat',pairActive=False,prepared=False)
        self.center.refresh_both()
    def test_four_vm_selection_routes_only_selected_pair(self):
        self.center.refresh_both()
        self.add_vm('fnthu','FNThu',3);self.add_vm('fnsean','FNSean',4)
        self.center.select_pair('fnthu','fnsean')
        self.fake.calls.clear()
        generation=self.center.generation
        self.center.prepare(dict(ticker='MNQ',stopLoss=123,profit=456,noWorkingOrders=True),generation)
        self.center.entry('buy',generation)
        self.assertEqual({slot for slot,command,_ in self.fake.calls}, {'fnthu','fnsean'})
        self.assertEqual(self.fake.states['fnsean']['stopLoss'],456)
        self.assertEqual(self.fake.bindings,{'fnthu':'fnsean','fnsean':'fnthu'})
    def test_pair_selection_invalidates_old_readiness(self):
        self.prepare();self.center.select_pair('vm-right','vm-left')
        self.assertIsNone(self.center.prepared)
        self.assertTrue(all(not state['prepared'] for state in self.fake.states.values()))
        self.assertFalse(self.center.state()['canEnter'])
    def test_pair_change_blocked_during_active_trade(self):
        self.open_pair()
        with self.assertRaises(ValueError):self.center.select_pair('vm-right','vm-left')
    def test_natural_close_resets_once_preserves_settings_and_refreshes_accounts(self):
        self.open_pair();self.fake.calls.clear();self.flat_pair()
        state=self.center.state()
        self.assertFalse(state['active']);self.assertFalse(state['canEnter'])
        self.assertEqual(state['closedSequence'],1)
        self.assertEqual(state['settings']['stopLoss'],123)
        self.assertFalse(Path(self.temp.name,'entry-unresolved.json').exists())
        self.assertTrue(all(command in ('status','post_trade','accounts') for _,command,_ in self.fake.calls))
        self.center.refresh_both();self.assertEqual(self.center.state()['closedSequence'],1)
        for _ in range(100):
            if not self.center.sync_dispatch: break
            threading.Event().wait(.01)
        self.assertEqual(sorted(slot for slot,command,_ in self.fake.calls if command=='accounts'),sorted(self.center.pair))
        self.center.prepare(dict(ticker='MNQ',stopLoss=123,profit=456,noWorkingOrders=True),self.center.generation)
        self.assertTrue(self.center.state()['canEnter'])
    def test_auto_refresh_waits_for_export_and_never_enters_trade(self):
        self.open_pair()
        original=self.center.transport
        def transport(config,command,body=None,**kwargs):
            result=original(config,command,body,**kwargs)
            if command=='post_trade':self.fake.states[config['id']]['busy']=True
            return result
        self.center.transport=transport
        self.fake.calls.clear();self.flat_pair()
        for _ in range(100):
            if sum(c[1]=='post_trade' for c in self.fake.calls)==2:break
            threading.Event().wait(.01)
        self.assertFalse(any(c[1]=='accounts' for c in self.fake.calls))
        self.assertTrue(self.center.state()['busy'])
        with self.assertRaises(ValueError):self.center.submit('prepare',{})
        for state in self.fake.states.values():state['busy']=False
        for _ in range(200):
            if not self.center.sync_dispatch:break
            threading.Event().wait(.01)
        self.assertEqual(sum(c[1]=='accounts' for c in self.fake.calls),2)
        self.assertFalse(any(c[1] in ('prepare','entry') for c in self.fake.calls))
        self.assertFalse(self.center.state()['busy'])
        self.assertTrue(all(x=='Account refresh finished' for x in self.center.account_refresh.values()))
    def test_auto_refresh_stops_if_position_reopens(self):
        self.fake.states['vm-left']['position']='3 L'
        self.center.sync_dispatch=1
        self.center.post_trade('vm-left',None)
        self.assertFalse(any(c[1]=='accounts' for c in self.fake.calls))
        self.assertIn('automatic refresh stopped',self.center.account_refresh['vm-left'])
        self.assertEqual(self.center.sync_dispatch,0)
    def test_auto_refresh_failure_is_visible_and_unblocks_retry(self):
        self.fake.fail.add(('vm-left','accounts'))
        self.center.sync_dispatch=1
        self.center.post_trade('vm-left',None)
        self.assertIn('Refresh needs attention',self.center.account_refresh['vm-left'])
        self.assertEqual(self.center.sync_dispatch,0)
    def test_initial_flat_after_commit_is_not_a_completed_trade(self):
        self.prepare();self.center.entry('buy',0)
        self.flat_pair()
        self.assertTrue(self.center.active)
        self.assertEqual(self.center.closed_sequence,0)
    def test_stale_flat_cannot_reset(self):
        self.open_pair();self.fake.states['vm-right']['sampleAgeMs']=99999;self.flat_pair()
        self.assertTrue(self.center.active)
        self.fake.states['vm-right']['sampleAgeMs']=0;self.center.observe('vm-right')
        self.assertFalse(self.center.active)
    def test_pending_close_cannot_reset(self):
        self.open_pair();self.fake.states['vm-right']['closing']=True;self.flat_pair()
        self.assertTrue(self.center.active)
        self.fake.states['vm-right']['closing']=False;self.center.observe('vm-right')
        self.assertFalse(self.center.active)
    def test_peer_binding_failure_blocks_prepare_and_entry(self):
        self.fake.fail.add(('vm-right','bind_peer'))
        with self.assertRaises(ValueError):self.prepare()
        self.assertFalse(any(command in ('prepare','entry') for _,command,_ in self.fake.calls))
    def test_new_pair_requires_distinct_fresh_agents(self):
        self.center.refresh_both()
        with self.assertRaises(ValueError):self.center.select_pair('vm-left','vm-left')
        self.fake.states['vm-right']['sampleAgeMs']=99999;self.center.observe('vm-right')
        with self.assertRaises(ValueError):self.center.select_pair('vm-right','vm-left')
    def test_restart_keeps_selected_pair_and_unresolved_lock(self):
        self.center.refresh_both();self.center.select_pair('vm-right','vm-left')
        self.center.mark_active()
        other=module.Center(self.temp.name,self.fake,persist=False)
        self.assertEqual(other.pair,('vm-right','vm-left'));self.assertTrue(other.active)
        other.pool.shutdown();other.close_pool.shutdown()
        for handler in other.logger.handlers:handler.close()
    def test_fifty_vm_registration_limit(self):
        for i in range(3,51):self.add_vm('vm-'+str(i),'VM '+str(i),i)
        self.assertEqual(len(self.center.config),50)
        with self.assertRaises(ValueError):self.add_vm('vm-51','VM 51',51)


if __name__=='__main__': unittest.main()

class AccountSelectionTests(Tests):
    def test_independent_targets_and_quantities(self):
        self.center.prepare(dict(ticker='MNQ',stopLoss=10,profit=20,noWorkingOrders=True,
            accounts={'vm-left':'MFF-123','vm-right':'FN-456'},quantities={'vm-left':2,'vm-right':3}),0)
        self.assertTrue(self.center.state()['canEnter'])
        self.assertEqual(self.fake.states['vm-left']['account'],'MFF-123')
        self.assertEqual(self.fake.states['vm-right']['quantity'],'3')
        right_bind=next(body for slot,cmd,body in self.fake.calls if slot=='vm-right' and cmd=='bind_peer')
        self.assertEqual(right_bind['peerAccount'],'MFF-123')
        self.assertEqual(right_bind['peerQuantity'],2)
        self.fake.states['vm-right']['account']='WRONG'
        with self.assertRaises(ValueError): self.center.entry('buy',0)
        self.assertFalse(any(cmd=='entry' for _,cmd,_ in self.fake.calls))
    def test_quantity_validation(self):
        for qty in [0,-1,1.5,True,'2',1001]:
            with self.assertRaises(ValueError):
                self.center.prepare(dict(ticker='MNQ',stopLoss=10,profit=20,noWorkingOrders=True,quantities={'vm-left':qty}),0)
        self.assertFalse(any(cmd=='prepare' for _,cmd,_ in self.fake.calls))
