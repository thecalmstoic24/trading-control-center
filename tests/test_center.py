import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest

spec=importlib.util.spec_from_file_location('center',Path(__file__).resolve().parents[1]/'coordinator'/'server.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Fake:
    def __init__(self):
        self.calls=[]
        self.fail=set()
        self.states={slot:dict(id=slot,controlVersion=module.VERSION,ok=True,sampleAgeMs=0,
                             account='Sim101',quantity='1',position='Flat',ticker='MNQ',
                             prepared=False,prepareId='',scheduled=False,busy=False,
                             pairActive=False,pendingVerification=False) for slot in module.IDS}
    def __call__(self,config,command,body=None,**kwargs):
        slot=config['id']; body=body or {}; self.calls.append((slot,command,body))
        if (slot,command) in self.fail: raise TimeoutError('mock timeout')
        state=self.states[slot]
        if command=='status': return {'ok':True,'cacheAgeMs':0,'_rttMs':1,'state':state.copy()}
        if command=='prepare':state.update(prepared=True,prepareId=body['prepareId'],ticker=body['ticker'],stopLoss=body['stopLoss'],profit=body['profit'])
        if command=='entry':
            self.states['vm-left'].update(position='1 L',pairActive=True)
            self.states['vm-right'].update(position='1 S',pairActive=True)
        if command=='close':state.update(position='Flat',prepared=False,pairActive=False)
        return {'ok':True}


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.fake=Fake()
        self.center=module.Center(self.temp.name,self.fake,persist=False)
        self.center.config={slot:{'id':slot} for slot in module.IDS}
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
    def test_manual_working_order_confirmation_required(self):
        with self.assertRaises(ValueError):self.center.prepare(dict(ticker='MNQ',stopLoss=1,profit=2),0)
        self.assertFalse(any(c[1]=='prepare' for c in self.fake.calls))
    def test_non_sim_account_blocks_preparation(self):
        self.fake.states['vm-left']['account']='LiveAccount'
        with self.assertRaises(ValueError):self.prepare()
        self.assertFalse(any(c[1]=='prepare' for c in self.fake.calls))
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


if __name__=='__main__': unittest.main()
