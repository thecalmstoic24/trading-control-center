import base64
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from test_center import module, Fake

class CapacityTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.fake=Fake()
        self.fleet=module.Fleet(self.temp.name,self.fake,persist=False)
        self.ids=[]
        prototype=self.fake.states['vm-left'].copy()
        for i in range(50):
            slot=f'vm-{i:02d}';self.ids.append(slot)
            self.fake.states[slot]=dict(prototype,id=slot)
            code=self.code(i)
            self.fleet.enroll(slot,code)
            self.fleet.observe(slot)
    def code(self,i):
        return base64.b64encode(json.dumps(dict(id=f'vm-{i:02d}',name=f'VM {i}',host=f'100.70.0.{i+1}',port=8789,pin=format(i+1,'064x'),token='b'*64)).encode()).decode()
    def tearDown(self):
        self.fleet.shutdown()
        for center in [self.fleet.catalog,*self.fleet.pairs.values(),*self.fleet.retired]:
            center.pool.shutdown(wait=True);center.close_pool.shutdown(wait=True)
            for handler in center.logger.handlers:handler.close()
        self.temp.cleanup()
    def pairs(self):
        self.fleet.catalog.refresh_both()
        return [self.fleet.create_pair(self.ids[i],self.ids[i+1]) for i in range(0,40,2)]
    def wait_jobs(self,jobs):
        deadline=time.monotonic()+12
        while time.monotonic()<deadline:
            found=[next(j for j in self.fleet.pairs[pair].jobs if j['id']==job) for pair,job in jobs.items()]
            if all(j['status']!='running' for j in found):
                self.assertTrue(all(j['status']=='done' for j in found),found)
                return
            time.sleep(.01)
        self.fail('Scale test jobs did not finish')
    def test_capacity_boundaries_and_idempotent_pair_selection(self):
        self.assertEqual(len(self.fleet.state()['fleet']),50)
        with self.assertRaisesRegex(ValueError,'50'):self.fleet.enroll('vm-50',self.code(50))
        pairs=self.pairs()
        self.assertEqual(self.fleet.create_pair(*self.ids[:2]),pairs[0])
        with self.assertRaisesRegex(ValueError,'20 pairs'):self.fleet.create_pair(*self.ids[40:42])
        self.assertEqual(self.fleet.state()['limits'],dict(vms=50,pairs=20))
    def test_twenty_concurrent_pairs_and_close_all(self):
        pairs=self.pairs()
        prepared={pid:self.fleet.submit('prepare',dict(pairId=pid,ticker='MNQ',stopLoss=100,profit=200,noWorkingOrders=True)) for pid in pairs}
        self.wait_jobs(prepared)
        barrier=threading.Barrier(20)
        def transport(config,command,body=None,**kwargs):
            if command=='entry':barrier.wait(timeout=10)
            return self.fake(config,command,body,**kwargs)
        for pair in self.fleet.pairs.values():pair.transport=transport
        entries={pid:self.fleet.submit('buy',dict(pairId=pid)) for pid in pairs}
        self.wait_jobs(entries)
        with ThreadPoolExecutor(max_workers=20) as pool:
            list(pool.map(lambda p:self.fleet.pairs[p].refresh_both(),pairs))
        self.assertEqual(sum(p['active'] for p in self.fleet.state()['pairs']),20)
        self.assertEqual(sum(self.fake.states[s]['position']!='Flat' for s in self.ids),40)
        self.assertEqual(len([c for c in self.fake.calls if c[1]=='entry']),20)
        self.assertTrue(all(self.fake.states[s]['position']=='Flat' for s in self.ids[40:]))
        result=self.fleet.close_all()
        self.wait_jobs({pid:value['job'] for pid,value in result['pairs'].items()})
        self.assertTrue(all(self.fake.states[s]['position']=='Flat' for s in self.ids))
        self.assertFalse(any(p['active'] for p in self.fleet.state()['pairs']))
        self.assertEqual({s for s,cmd,_ in self.fake.calls if cmd=='close'},set(self.ids[:40]))
