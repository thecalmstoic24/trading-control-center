import copy
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'coordinator'))
from pair_queue import PairQueue, PairStore, PAIR_TABLE, TABLE, trade_result
from test_center import Fake, module

class Store:
    def __init__(self): self.rows={}; self.fail=False; self.maximum=0
    def records(self,table):
        if table==PAIR_TABLE:
            return [{'fields':{'Pair ID':f'PAIR-{self.maximum:04d}'}}] if self.maximum else []
        return []
    def push(self,row):
        if self.fail: raise ValueError('Airtable unavailable')
        self.rows[row['key']]=copy.deepcopy(row)

class Planning:
    def refresh(self): pass

class Agent(Fake):
    def __init__(self):
        super().__init__(); self.pnls={s:0 for s in module.IDS}; self.skip_receipt=False
        for s in self.states.values(): s.update(queueReceipts=True,accounts=['Sim101'])
    def __call__(self,config,command,body=None,**kw):
        reply=super().__call__(config,command,body,**kw)
        if command=='post_trade' and not self.skip_receipt:
            s=config['id']; self.states[s]['syncReceipt']={'id':body['tradeId'],'completedUtc':'2026-09-14T12:00:00Z',
                'accounts':[{'Account':'Sim101','CurrentBalance':100000+self.pnls[s],'Realized PnL':self.pnls[s]}]}
        return reply

class QueueTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.agent=Agent(); self.fleet=module.Fleet(self.tmp.name,self.agent,persist=False)
        self.fleet.catalog.config={s:dict(id=s,name=s,host='100.64.0.'+str(i+1),port=8789,pin=str(i+1)*64,token='b'*64) for i,s in enumerate(module.IDS)}
        for s in module.IDS:
            self.fleet.catalog.poll_locks[s]=threading.Lock(); self.fleet.observe(s)
        self.store=Store(); self.queue=PairQueue(self.fleet,Planning(),self.store)
        self.body=dict(left='vm-left',right='vm-right',ticker='NQ SEP26',direction='buy',stopLoss=100,profit=200,
            accounts={s:'Sim101' for s in module.IDS},quantities={s:3 for s in module.IDS})
    def tearDown(self):
        self.fleet.shutdown()
        for c in [self.fleet.catalog,*self.fleet.pairs.values(),*self.fleet.retired]:
            c.pool.shutdown(wait=True);c.close_pool.shutdown(wait=True)
            for h in c.logger.handlers:h.close()
        self.tmp.cleanup()
    def test_ratio_survives_queue_and_reaches_agents(self):
        self.body.update(ratio='2:3',quantities={'vm-left':10,'vm-right':15},stopLoss=1000,profit=800,ticker='MNQ SEP26')
        self.queue.add(self.body)
        self.queue.command('start',{})
        self.tick_until('Trading')
        self.assertEqual(self.agent.states['vm-right']['profit'],1500)
        self.assertEqual(self.agent.states['vm-right']['stopLoss'],1200)
        self.assertEqual(self.agent.states['vm-right']['quantity'],'15')
    def tick_until(self,status,limit=200):
        for _ in range(limit):
            self.queue.tick()
            if self.queue.rows[0]['status']==status:return
            time.sleep(.01)
        self.fail(str(self.queue.snapshot()))
    def add_start(self): self.queue.add(self.body); self.queue.command('start',{})
    def entered(self):
        self.add_start();self.tick_until('Trading')
        pair=self.fleet.get_pair(self.queue.rows[0]['pairId'])
        for _ in range(100):
            pair.refresh_both()
            if len(pair.opened_ids)==2 and not pair.operation.locked():break
            time.sleep(.01)
        return pair
    def flat(self,pair):
        for s in module.IDS:self.agent.states[s].update(position='Flat',pairActive=False,prepared=False)
        pair.refresh_both()
    def test_repeated_draft_confirmation_creates_one_pair(self):
        body={**self.body,'draftKey':'a'*32}
        first=self.queue.add(body)
        self.assertEqual(self.queue.add(body),first)
        self.assertEqual(len(self.queue.rows),1)
        self.assertEqual(len(self.store.rows),1)
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))

    def test_invalid_draft_identity_rejected(self):
        with self.assertRaises(ValueError): self.queue.add({**self.body,'draftKey':'invalid'})
        self.assertEqual(self.queue.rows,[])

    def test_no_entry_until_start_and_four_digit_ids(self):
        self.assertEqual(self.queue.add(self.body),'PAIR-0001');self.queue.tick()
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
    def test_ids_continue_past_four_digits_without_reuse(self):
        self.store.maximum=9999;self.assertEqual(self.queue.add(self.body),'PAIR-10000')
    def test_simulated_lifecycle_results_release_before_next(self):
        pair=self.entered();self.queue.add(self.body)
        self.agent.pnls.update({'vm-left':900,'vm-right':-900});self.flat(pair)
        self.tick_until('Complete')
        row=self.queue.rows[0]
        self.assertEqual(row['results'],{'vm-left':900,'vm-right':-900});self.assertEqual(len(self.fleet.pairs),0)
        self.assertEqual(self.store.rows[row['key']]['status'],'Complete')
        self.assertEqual(len([c for c in self.agent.calls if c[1]=='entry']),1)
    def test_nonflat_waits_without_entry(self):
        self.agent.states['vm-left']['position']='3 L';self.add_start();self.queue.tick()
        self.assertEqual(self.queue.rows[0]['status'],'Waiting');self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
    def test_unknown_waits_without_entry(self):
        self.agent.fail.add(('vm-right','status'));self.add_start();self.queue.tick()
        self.assertEqual(self.queue.rows[0]['status'],'Waiting')
    def test_old_agent_blocked_before_any_export_or_entry(self):
        self.agent.states['vm-left']['queueReceipts']=False;self.add_start();self.queue.tick()
        self.assertEqual(self.queue.rows[0]['status'],'Error');self.assertFalse(any(c[1] in ('entry','post_trade') for c in self.agent.calls))
    def test_pause_before_entry(self):
        self.add_start();self.queue.tick();self.queue.command('pause',{});self.queue.tick()
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
    def test_pause_still_finishes_results(self):
        pair=self.entered();self.queue.command('pause',{});self.flat(pair);self.tick_until('Complete')
        self.assertFalse(self.queue.running)
    def test_restart_never_replays_entry(self):
        self.entered();other=PairQueue(self.fleet,Planning(),self.store);other.tick()
        self.assertFalse(other.running);self.assertEqual(other.rows[0]['status'],'Error')
        self.assertEqual(len([c for c in self.agent.calls if c[1]=='entry']),1)
    def test_missing_receipt_does_not_prepare_or_enter(self):
        self.agent.skip_receipt=True;self.add_start()
        for _ in range(3):self.queue.tick()
        self.assertFalse(any(c[1] in ('prepare','entry') for c in self.agent.calls))
    def test_lost_entry_response_never_retried(self):
        self.agent.fail.add(('vm-left','entry'));self.add_start();self.tick_until('Error')
        for _ in range(3):self.queue.tick()
        self.assertEqual(len([c for c in self.agent.calls if c[1]=='entry']),1)
    def test_sync_retry_preserves_execution_key(self):
        self.queue.add(self.body);key=self.queue.rows[0]['key'];self.queue.command('retry',{});self.queue.tick()
        self.assertEqual(list(self.store.rows),[key]);self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
    def test_sort_cancel_only_waiting(self):
        self.queue.add(self.body);self.queue.add(self.body);self.queue.command('move',{'id':'PAIR-0002','delta':-1})
        self.assertEqual(self.queue.rows[0]['id'],'PAIR-0002');self.queue.command('cancel',{'id':'PAIR-0001'})
        self.assertEqual(self.queue.rows[1]['status'],'Cancelled')
    def test_invalid_amounts_accounts_and_quantities(self):
        for values in ({'stopLoss':0},{'profit':float('nan')},{'quantities':{'vm-left':0}},{'accounts':{'vm-left':'random'}}):
            with self.assertRaises(ValueError):self.queue.add({**self.body,**values})
    def test_pause_during_pre_entry_airtable_write_sends_no_entry(self):
        original=self.store.push
        def pause(row):
            original(row)
            if row['status']=='Trading': self.queue.command('pause',{})
        self.store.push=pause
        self.add_start()
        for _ in range(10):self.queue.tick();time.sleep(.01)
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))

    def test_wrong_receipt_id_cannot_authorize_entry(self):
        self.agent.skip_receipt=True
        for state in self.agent.states.values():state['syncReceipt']={'id':'old','accounts':[]}
        self.add_start()
        for _ in range(5):self.queue.tick()
        self.assertFalse(any(c[1] in ('prepare','entry') for c in self.agent.calls))

    def test_airtable_failure_prevents_entry(self):
        self.queue.add(self.body);self.queue.command('start',{});self.queue.rows[0]['dirty']=True;self.store.fail=True
        with self.assertRaises(ValueError):self.queue.tick()
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))

    def test_currency_delta_and_field_layout(self):
        self.assertEqual(trade_result(1200,300),-900)
        with self.assertRaises(ValueError):trade_result(None,100)
        self.queue.add(self.body);fields=PairStore.fields(self.queue.rows[0]);self.assertEqual(fields['Left Quantity'],3)
        self.assertEqual(fields['Right Stop Loss'],200);self.assertNotIn('Left Trade P&L',fields)

if __name__=='__main__':unittest.main()
