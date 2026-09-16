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
    def delete(self,row):
        if self.fail: raise ValueError('Airtable unavailable')
        self.rows.pop(row['key'],None)
    def push(self,row):
        if self.fail: raise ValueError('Airtable unavailable')
        self.rows[row['key']]=copy.deepcopy(row)

class Planning:
    def refresh(self): pass

class Agent(Fake):
    def __init__(self):
        super().__init__(); self.pnls={s:0 for s in module.IDS}; self.skip_receipt=False
        for s in self.states.values(): s.update(queueReceipts=True,queueAccountRefresh=True,accounts=['Sim101'])
    def __call__(self,config,command,body=None,**kw):
        reply=super().__call__(config,command,body,**kw)
        if command=='accounts': self.states[config['id']]['accountRefreshId']=body.get('refreshId')
        if command=='post_trade' and not self.skip_receipt:
            s=config['id']; self.states[s]['syncReceipt']={'id':body['tradeId'],'completedUtc':'2026-09-14T12:00:00Z',
                'accounts':[{'Account':getattr(self,'receipt_accounts',{}).get(s,'Sim101'),'CurrentBalance':100000+self.pnls[s],'Realized PnL':self.pnls[s]}]}
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
        for pair in list(self.fleet.pairs.values()):
            deadline=time.monotonic()+3
            while pair.operation.locked() and time.monotonic()<deadline:time.sleep(.01)
        self.fleet.shutdown()
        for c in [self.fleet.catalog,*self.fleet.pairs.values(),*self.fleet.retired]:
            c.pool.shutdown(wait=True);c.close_pool.shutdown(wait=True)
            for h in c.logger.handlers:h.close()
        self.tmp.cleanup()
    def test_contract_month_pins_confirmed_pair_and_survives_reload(self):
        import contracts
        self.queue.add(dict(self.body,ticker='NQ',localDraft=True,draft={'key':'a'*32,'ticker':'NQ'}))
        first=self.queue.rows[0]
        self.assertEqual(first['spec']['ticker'],'NQ DEC26')
        self.assertEqual(first['draft']['ticker'],'NQ DEC26')
        contracts.save(self.fleet.directory,'MAR27')
        restored=PairQueue(self.fleet,Planning(),self.store)
        self.assertEqual(restored.rows[0]['spec']['ticker'],'NQ DEC26')
        self.queue.add(dict(self.body,ticker='MNQ',localDraft=True))
        self.assertEqual(self.queue.rows[1]['spec']['ticker'],'MNQ MAR27')
        self.queue.command('start',{})
        self.assertEqual(first['spec']['ticker'],'NQ DEC26')
        self.queue.tick()
        pair=self.fleet.get_pair(first['pairId'])
        deadline=time.monotonic()+3
        while pair.operation.locked() and time.monotonic()<deadline:time.sleep(.01)
        self.assertEqual(pair.settings['ticker'],'NQ DEC26')
        self.assertTrue(all(c[2]['ticker']=='NQ DEC26' for c in self.agent.calls if c[1]=='prepare'))

    def test_manual_pair_resolves_from_shared_contract_setting(self):
        import contracts
        contracts.save(self.fleet.directory,'JUN27')
        identity=self.fleet.create_pair('vm-left','vm-right')
        pair=self.fleet.get_pair(identity)
        pair.prepare(dict(self.body,ticker='MNQ'),pair.generation)
        self.assertEqual(pair.settings['ticker'],'MNQ JUN27')

    def enable_fast22(self):
        for slot,state in self.agent.states.items():
            state.update(backgroundExports=True,syncReceipt={'id':'baseline','completedUtc':'2026-09-14T11:00:00Z',
                'accounts':[{'Account':'Sim101','CurrentBalance':100000,'Realized PnL':0}]})
            self.fleet.observe(slot)

    def test_local_draft_gets_id_only_at_start(self):
        key='a'*32
        identity=self.queue.add(dict(self.body,localDraft=True,draftKey=key,draft={'key':key}))
        self.assertTrue(identity.startswith('DRAFT-'));self.assertEqual(self.store.rows,{})
        self.queue.tick();self.assertEqual(self.store.rows,{})
        self.queue.command('start',{})
        row=self.queue.rows[0];self.assertEqual(row['id'],'PAIR-0001');self.assertEqual(row['key'],key)
        self.queue.command('start',{});self.assertEqual(row['id'],'PAIR-0001')

    def test_local_draft_can_return_for_edit_without_remote_delete(self):
        identity=self.queue.add(dict(self.body,localDraft=True,draft={'key':'a'*32}))
        self.store.fail=True
        result=self.queue.command('edit-draft',{'id':identity})
        self.assertEqual(result['draft']['draft']['key'],'a'*32);self.assertEqual(self.queue.rows,[])

    def test_resolve_error_releases_vm_and_continues_queue(self):
        self.enable_fast22();self.add_start();self.queue.tick()
        first=self.queue.rows[0];pair=self.fleet.get_pair(first['pairId'])
        while pair.operation.locked():time.sleep(.01)
        self.queue.fail(first,'test preparation error')
        self.queue.add(self.body);self.queue.command('start',{});self.queue.tick()
        self.assertEqual(self.queue.rows[1]['status'],'Preparing')
        self.assertTrue(first['errorReleased']);self.assertEqual(first['status'],'Error')
        self.queue.command('resolve',{'id':first['id']})
        self.assertTrue(self.queue.running);self.assertIn('completedUtc',first)
        self.queue.tick();self.assertEqual(self.queue.rows[1]['status'],'Preparing')

    def failed_reserved_pair(self):
        self.enable_fast22();self.add_start();self.queue.tick()
        row=self.queue.rows[-1];pair=self.fleet.get_pair(row['pairId'])
        while pair.operation.locked():time.sleep(.01)
        self.queue.fail(row,'Preparation failed')
        return row,pair

    def test_error_auto_release_blocks_stale_busy_scheduled_or_open_vm(self):
        for field,value in [('scheduled',True),('busy',True),('pendingVerification',True),('pairActive',True)]:
            with self.subTest(field=field):
                row,pair=self.failed_reserved_pair()
                self.agent.states['vm-right'][field]=value
                self.queue.release_error(row)
                self.assertIn(row['pairId'],self.fleet.pairs)
                self.assertFalse(row.get('errorReleased'))
                self.agent.states['vm-right'][field]='Flat' if field=='position' else False
                row['releaseCheckAt']=0;self.queue.release_error(row)
                self.assertTrue(row['errorReleased'])
        row,pair=self.failed_reserved_pair();self.agent.fail.add(('vm-right','status'))
        self.queue.release_error(row);self.assertIn(row['pairId'],self.fleet.pairs)

    def test_error_auto_release_retains_observed_position_even_after_flat(self):
        row,pair=self.failed_reserved_pair();self.agent.states['vm-right']['position']='Long'
        self.queue.release_error(row);self.assertFalse(row.get('errorReleased'))
        self.agent.states['vm-right']['position']='Flat';row['releaseCheckAt']=0
        self.queue.release_error(row);self.assertFalse(row.get('errorReleased'))

    def test_error_auto_release_never_clears_uncertain_entry_even_if_flat(self):
        row,pair=self.failed_reserved_pair();row['started']='2026-09-16T12:00:00Z'
        self.queue.release_error(row)
        self.assertIn(row['pairId'],self.fleet.pairs);self.assertFalse(row.get('errorReleased'))
        row['entryNotSent']=True;pair.opened_ids.add('vm-left')
        self.queue.release_error(row);self.assertFalse(row.get('errorReleased'))

    def test_error_release_rechecks_after_unbind(self):
        row,pair=self.failed_reserved_pair();original=pair.transport
        def changed(config,command,body=None,**kwargs):
            result=original(config,command,body,**kwargs)
            if command=='unbind_peer':self.agent.states[config['id']]['scheduled']=True
            return result
        pair.transport=changed;self.queue.release_error(row)
        self.assertIn(row['pairId'],self.fleet.pairs);self.assertFalse(row.get('errorReleased'))

    def test_retry_released_error_waits_for_new_owner(self):
        row,pair=self.failed_reserved_pair();row.update(started='2026-09-16T12:00:00Z',entryNotSent=True)
        self.queue.release_error(row);self.assertTrue(row['errorReleased'])
        self.queue.add(self.body);self.queue.command('start',{});self.queue.tick()
        next_row=self.queue.rows[1];self.assertEqual(next_row['status'],'Preparing')
        next_owner=next_row['pairId']
        self.queue.command('retry-prepare',{'id':row['id']});self.queue.tick()
        self.assertEqual(row['status'],'Waiting');self.assertIn(next_owner,self.fleet.pairs)

    def test_vm_activity_is_bounded_deduplicated_and_identifies_vm(self):
        self.fleet.state();count=len(self.fleet.vm_events);self.fleet.state()
        self.assertEqual(len(self.fleet.vm_events),count)
        self.agent.states['vm-left']['message']='Sync completed'
        self.fleet.observe('vm-left')
        event=self.fleet.state()['vmEvents'][0]
        self.assertEqual(event['vm'],'vm-left');self.assertEqual(event['message'],'Sync completed')
        self.assertIn('utc',event)
        for n in range(250):self.fleet.vm_event('vm-left',str(n))
        self.assertEqual(len(self.fleet.vm_events),200)

    def test_skip_results_releases_and_keeps_queue_running(self):
        self.enable_fast22()
        for s in self.agent.states.values():s['skipResults']=True
        pair=self.entered();self.agent.skip_receipt=True;self.flat(pair);self.tick_until('Awaiting results')
        while pair.sync_dispatch:time.sleep(.01)
        row=self.queue.rows[0]
        self.queue.add(self.body);self.queue.command('start',{})
        self.queue.command('skip-results',{'id':row['id']})
        self.assertEqual(row['status'],'Complete');self.assertTrue(row['resultsSkipped']);self.assertIn('completedUtc',row)
        self.assertEqual(len([c for c in self.agent.calls if c[1]=='skip_results']),2)
        self.queue.tick();self.assertEqual(self.queue.rows[1]['status'],'Preparing')

    def test_skip_rejection_keeps_reservation(self):
        self.enable_fast22()
        for s in self.agent.states.values():s['skipResults']=True
        pair=self.entered();self.agent.skip_receipt=True;self.flat(pair);self.tick_until('Awaiting results')
        while pair.sync_dispatch:time.sleep(.01)
        row=self.queue.rows[0];self.agent.fail.add(('vm-right','skip_results'))
        with self.assertRaises(TimeoutError):self.queue.command('skip-results',{'id':row['id']})
        self.assertIn(row['pairId'],self.fleet.pairs);self.assertEqual(row['status'],'Awaiting results')

    def test_single_pair_left_and_right_use_only_selected_agent(self):
        for side in ('left','right'):
            with self.subTest(side=side):
                self.enable_fast22()
                selected='vm-'+side;other='right' if side=='left' else 'left'
                self.agent.states[selected]['singlePair']=True;self.fleet.observe(selected)
                original=self.fleet.transport
                def transport(config,command,body=None,**kw):
                    if command=='single_entry':
                        self.agent.calls.append((config['id'],command,body))
                        self.agent.states[config['id']].update(position='1 L' if body['side']=='BUY' else '1 S')
                        return {'ok':True}
                    return original(config,command,body,**kw)
                self.fleet.transport=transport
                body=dict(self.body);body[other]=None
                body['accounts']={selected:'Sim101'};body['quantities']={selected:3}
                self.queue.rows=[];self.queue.add(body);self.queue.command('start',{})
                self.agent.calls=[];self.tick_until('Trading');row=self.queue.rows[0]
                pair=self.fleet.get_pair(row['pairId'])
                for _ in range(100):
                    pair.refresh_both()
                    if pair.opened_ids and not pair.operation.locked():break
                    time.sleep(.01)
                self.assertEqual(pair.pair,(selected,))
                entries=[c for c in self.agent.calls if c[1]=='single_entry']
                self.assertEqual(len(entries),1);self.assertEqual(entries[0][2]['side'],'BUY' if side=='left' else 'SELL')
                self.assertFalse(any(c[0]!=selected for c in self.agent.calls))
                self.assertFalse(any(c[1] in ('bind_peer','peer_check','entry') for c in self.agent.calls))
                self.flat(pair);self.tick_until('Complete');self.assertNotIn(selected,self.fleet.owners)
                self.fleet.transport=original

    def test_fast_start_has_no_account_or_export_requests(self):
        self.enable_fast22();self.entered()
        self.assertTrue(self.queue.rows[0]['fast22'])
        self.assertFalse(any(c[1] in ('accounts','post_trade') for c in self.agent.calls))

    def test_fast_release_starts_next_pair_while_airtable_offline(self):
        self.enable_fast22();pair=self.entered()
        self.queue.add(self.body);self.queue.command('start',{})
        self.store.fail=True
        self.agent.pnls.update({'vm-left':125,'vm-right':-90});self.flat(pair)
        self.tick_until('Complete')
        row=self.queue.rows[0]
        self.assertTrue(row['released22']);self.assertTrue(row['dirty'])
        self.assertEqual(row['results'],{'vm-left':125,'vm-right':-90})
        self.assertEqual(self.queue.rows[1]['status'],'Preparing')
        self.assertFalse(any(c[1]=='accounts' for c in self.agent.calls))
        self.agent.pnls['vm-left']=999
        self.assertEqual(row['after']['vm-left']['pnl'],125)

    def test_background_upload_does_not_lock_scheduler(self):
        self.enable_fast22();pair=self.entered();self.flat(pair);self.tick_until('Complete')
        started=threading.Event();finish=threading.Event()
        def slow_upload(row): started.set();finish.wait(3)
        self.store.push=slow_upload
        self.queue.result_thread.start()
        try:
            self.assertTrue(started.wait(1))
            start=time.monotonic();self.queue.tick()
            self.assertLess(time.monotonic()-start,.5)
        finally:
            self.queue.close();finish.set();self.queue.result_thread.join(2)

    def test_fast_missing_csv_after_30_seconds_retains_vms(self):
        self.enable_fast22();pair=self.entered();self.agent.skip_receipt=True
        self.flat(pair);self.tick_until('Awaiting results')
        row=self.queue.rows[0];row['deadline']=time.time()-1;self.queue.tick()
        self.assertEqual(row['status'],'Awaiting results')
        self.assertIn(row['pairId'],self.fleet.pairs)
        self.assertIn('CSV capture still pending',row['message'])

    def test_duplicate_canceled_history_has_new_identity_and_no_entry(self):
        self.queue.add(self.body);source=copy.deepcopy(self.queue.rows[0])
        self.queue.command('cancel',{'id':source['id']})
        identity=self.queue.command('duplicate',{'id':source['id'],'draftKey':'e'*32})['id']
        row=self.queue.rows[0]
        self.assertNotEqual(identity,source['id']);self.assertEqual(row['spec'],source['spec'])
        self.assertFalse(row.get('dispatched'));self.assertNotIn('results',row)
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))

    def test_refresh_removes_deleted_history_without_recreating(self):
        self.queue.add(self.body)
        row=self.queue.rows[0]
        row.update(status='Complete',dispatched=True)
        self.queue.command('refresh',{})
        self.assertEqual(self.queue.rows,[])
        self.queue.tick()
        self.assertEqual(len(self.store.rows),1) # no push/delete as a result of reading

    def test_refresh_read_failure_preserves_rows(self):
        self.queue.add(self.body)
        def broken(table): raise ValueError('offline')
        self.store.records=broken
        with self.assertRaisesRegex(ValueError,'offline'):self.queue.command('refresh',{})
        self.assertEqual(len(self.queue.rows),1)

    def test_deleted_active_record_keeps_monitor_and_never_upserts(self):
        self.add_start();self.queue.tick()
        row=self.queue.rows[0];self.queue.sync(row)
        identity=row['pairId']
        self.queue.command('refresh',{})
        self.assertIn(identity,self.fleet.pairs)
        self.assertTrue(row['remoteDeleted'])
        self.store.fail=True
        self.queue.sync(row) # suppressed even if worker would fail

    def test_failed_row_does_not_block_next_unreserved_pair(self):
        self.queue.add(self.body);self.queue.add(self.body)
        first,second=self.queue.rows
        self.queue.fail(first,'Selected account missing')
        self.queue.command('start',{})
        self.queue.tick()
        self.assertEqual(first['status'],'Error')
        self.assertEqual(second['status'],'Preparing')

    def test_waiting_row_does_not_block_later_eligible_row(self):
        self.queue.add(self.body);self.queue.add(self.body)
        self.queue.command('start',{})
        first,second=self.queue.rows
        seen=[]
        def advance(row):
            seen.append(row['id'])
            row['status']='Waiting' if row is first else 'Preparing'
        self.queue.advance=advance
        self.queue.tick()
        self.assertEqual(seen,[first['id'],second['id']])

    def test_accounts_refresh_completes_before_export_and_prepare(self):
        self.add_start();self.tick_until('Trading')
        for slot in module.IDS:
            commands=[c[1] for c in self.agent.calls if c[0]==slot]
            self.assertLess(commands.index('accounts'),commands.index('post_trade'))
            self.assertLess(commands.index('accounts'),commands.index('prepare'))

    def test_old_refresh_id_cannot_start_export(self):
        self.add_start();self.queue.tick();self.queue.tick()
        row=self.queue.rows[0]
        # Return to waiting for this request, with stale cached completion IDs.
        row['phase']='accounts'
        row['requested']=list(module.IDS)
        for state in self.agent.states.values():state['accountRefreshId']='old'
        self.queue.tick()
        self.assertEqual(row['phase'],'accounts')
        self.assertFalse(any(c[1] in ('post_trade','prepare','entry') for c in self.agent.calls))

    def test_newly_refreshed_missing_account_stops_before_export(self):
        self.add_start();self.queue.tick()
        self.queue.rows[0]['spec']['accounts']['vm-left']='missing'
        self.queue.tick()
        self.assertEqual(self.queue.rows[0]['status'],'Error')
        self.assertIn('newly refreshed',self.queue.rows[0]['message'])
        self.assertFalse(any(c[1] in ('post_trade','prepare','entry') for c in self.agent.calls))

    def test_failed_account_refresh_never_enters(self):
        self.add_start();self.queue.tick()
        self.agent.fail.add(('vm-right','accounts'))
        self.queue.tick()
        self.assertEqual(self.queue.rows[0]['status'],'Error')
        self.assertFalse(any(c[1] in ('post_trade','prepare','entry') for c in self.agent.calls))

    def test_independent_pairs_trade_concurrently_shared_vm_waits(self):
        for i,slot in enumerate(['vm-c','vm-d']):
            self.fleet.catalog.config[slot]=dict(id=slot,name=slot,host='100.64.0.'+str(i+10),port=8789,pin='c'*64,token='b'*64)
            self.fleet.catalog.poll_locks[slot]=threading.Lock()
            self.agent.states[slot]=dict(self.agent.states['vm-left'],id=slot)
            self.agent.pnls[slot]=0
            self.fleet.observe(slot)
        self.queue.add(self.body)
        shared=dict(self.body,right='vm-c',accounts={'vm-left':'Sim101','vm-c':'Sim101'},quantities={'vm-left':3,'vm-c':3})
        free=dict(self.body,left='vm-c',right='vm-d',accounts={'vm-c':'Sim101','vm-d':'Sim101'},quantities={'vm-c':3,'vm-d':3})
        self.queue.add(shared);self.queue.add(free);self.queue.command('start',{})
        for _ in range(200):
            self.queue.tick()
            if self.queue.rows[0]['status']==self.queue.rows[2]['status']=='Trading':break
            time.sleep(.01)
        self.assertEqual([r['status'] for r in self.queue.rows],['Trading','Waiting','Trading'])
        self.assertEqual(len(self.fleet.pairs),2)
        self.assertEqual(len(self.fleet.owners),4)
        self.queue.command('pause',{})
        self.queue.tick()
        self.assertFalse(self.queue.running)
        self.assertEqual(self.queue.rows[1]['status'],'Waiting')
        self.assertEqual(len(self.fleet.pairs),2)

    def test_retry_preparation_keeps_identity_settings_and_releases_old_reservation(self):
        self.add_start();self.queue.tick()
        row=self.queue.rows[0];key=row['key'];spec=copy.deepcopy(row['spec'])
        self.queue.fail(row,'Calibration required')
        self.queue.command('retry-prepare',{'id':row['id']})
        self.assertEqual(row['key'],key);self.assertEqual(row['spec'],spec)
        self.assertEqual(row['status'],'Queued');self.assertNotIn('pairId',row)
        self.assertEqual(len(self.fleet.pairs),0)
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
        self.tick_until('Trading')

    def test_before_arm_readiness_retry_requires_proof_and_rechecks_the_pair(self):
        self.enable_fast22();original=self.fleet.transport
        def transport(config,command,body=None,**kwargs):
            if command=='entry':
                self.agent.calls.append((config['id'],command,body))
                pair=next(p for p in self.fleet.pairs.values() if config['id'] in p.pair)
                return dict(ok=False,message='Entry stage readiness check: Timing unstable',errorCode='READINESS_BEFORE_ARM',entryNotSent=True,prepareId=body['prepareId'],bindingId=pair.binding_id)
            return original(config,command,body,**kwargs)
        self.fleet.transport=transport
        self.add_start();self.queue.rows[0]['releaseCheckAt']=time.time()+3600
        self.tick_until('Error');row=self.queue.rows[0]
        self.assertTrue(row['started']);self.assertTrue(row['entryNotSent'])
        self.assertTrue(self.queue.snapshot()['rows'][0]['canRetryReadiness'])
        count=sum(c[1]=='entry' for c in self.agent.calls)
        for _ in range(4):self.queue.tick()
        self.assertEqual(sum(c[1]=='entry' for c in self.agent.calls),count)
        # Account mismatch and a scheduled action both prevent retry, even with proof.
        self.agent.states['vm-right']['account']='Different'
        with self.assertRaisesRegex(ValueError,'freshly verified Flat'):self.queue.command('retry-prepare',{'id':row['id']})
        self.agent.states['vm-right']['account']='Sim101';self.agent.states['vm-right']['scheduled']=True
        with self.assertRaisesRegex(ValueError,'freshly verified Flat'):self.queue.command('retry-prepare',{'id':row['id']})
        self.agent.states['vm-right']['scheduled']=False
        self.fleet.transport=original
        self.queue.command('retry-prepare',{'id':row['id']})
        self.assertNotIn('started',row);self.assertEqual(row['status'],'Queued');self.assertEqual(len(row['attempts']),1)
        self.tick_until('Trading')
        pair=self.fleet.get_pair(row['pairId'])
        deadline=time.monotonic()+3
        while pair.operation.locked() and time.monotonic()<deadline:time.sleep(.01)
        self.assertEqual(sum(c[1]=='entry' for c in self.agent.calls),count+1)

    def test_legacy_clock_error_is_classified_but_generic_uncertainty_is_not(self):
        from pair_queue import retryable_entry
        message='Entry did not complete normally: FN-THUH: Entry stage readiness check: Estimated VM clock difference exceeds 500 ms. Synchronize Windows time.'
        self.assertTrue(retryable_entry({'message':message}))
        self.assertFalse(retryable_entry({'message':'Entry timeout: clock difference exceeds 500 ms'}))
        self.assertFalse(retryable_entry({'message':message+' Command outcome unknown.'}))

    def test_retry_preparation_rejects_any_prior_entry(self):
        self.add_start();row=self.queue.rows[0]
        row.update(status='Error',started='2026-09-15T01:00:00Z')
        with self.assertRaisesRegex(ValueError,'before any entry'):
            self.queue.command('retry-prepare',{'id':row['id']})
        self.assertEqual(row['status'],'Error')

    def test_calibration_required_has_actionable_error_before_reservation(self):
        self.add_start();self.agent.states['vm-left']['calibrationRequired']=True
        self.queue.tick()
        self.assertEqual(self.queue.rows[0]['status'],'Error')
        self.assertIn('Calibrate Chart 1',self.queue.rows[0]['message'])
        self.assertEqual(len(self.fleet.pairs),0)

    def test_duplicate_completed_pair_new_identity_same_configuration_no_entry(self):
        self.queue.add(self.body);source=self.queue.rows[0]
        source.update(status='Complete',results={'vm-left':900,'vm-right':-850},started='old')
        result=self.queue.command('duplicate',{'id':source['id'],'draftKey':'d'*32})
        row=self.queue.rows[1]
        self.assertEqual(row['id'],result['id']);self.assertNotEqual(row['id'],source['id'])
        self.assertEqual(row['spec'],source['spec']);self.assertEqual(row['status'],'Queued')
        self.assertNotIn('results',row);self.assertNotIn('started',row)
        self.assertFalse(row.get('dispatched'));self.queue.tick()
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
        again=self.queue.command('duplicate',{'id':source['id'],'draftKey':'d'*32})
        self.assertEqual(again,result);self.assertEqual(len(self.queue.rows),2)
        self.assertIn(row['key'],self.store.rows)

    def test_duplicate_rejects_running_source_and_identity_collision(self):
        self.queue.add(self.body);source=self.queue.rows[0]
        with self.assertRaisesRegex(ValueError,'completed'):
            self.queue.command('duplicate',{'id':source['id'],'draftKey':'d'*32})
        source['status']='Complete'
        with self.assertRaisesRegex(ValueError,'identity conflict'):
            self.queue.command('duplicate',{'id':source['id'],'draftKey':source['key']})
        self.assertEqual(len(self.queue.rows),1)

    def test_ratio_survives_queue_and_reaches_agents(self):
        self.body.update(ratio='2:3',quantities={'vm-left':10,'vm-right':15},stopLoss=1000,profit=800,ticker='MNQ SEP26')
        self.queue.add(self.body)
        self.queue.command('start',{})
        self.tick_until('Trading')
        self.assertEqual(self.agent.states['vm-right']['profit'],1500)
        self.assertEqual(self.agent.states['vm-right']['stopLoss'],1200)
        self.assertEqual(self.agent.states['vm-right']['quantity'],'15')
    def test_same_fund_rejected_on_server(self):
        for slot,account in [('vm-left','A'),('vm-right','B')]:
            self.agent.states[slot]['accounts']=[account]
            self.fleet.observe(slot)
            self.body['accounts'][slot]=account
        self.store.records=lambda table:[{'id':'rec'+a,'fields':{'id':a,'Master Account':m,'CurrentBalance':50000}} for a,m in [('A','MFF-A'),('B','MFF-B')]]
        with self.assertRaisesRegex(ValueError,'Same fund'): self.queue.add(self.body)
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

    def test_bulenox_queue_uses_canonical_receipts_and_airtable_results(self):
        raw='BX-M7526703186112!Bulenox!Bulenox';clean='BX-M7526703186112'
        self.agent.states['vm-left']['accounts']=['Sim101',raw]
        self.agent.receipt_accounts={'vm-left':clean}
        self.fleet.observe('vm-left');self.body['accounts']['vm-left']=clean
        original=self.store.records
        self.store.records=lambda table:[{'id':'recBUL','fields':{'id':clean,'Master Account':'BUL-THAO','CurrentBalance':50000}}] if table==TABLE else original(table)
        pair=self.entered()
        self.assertEqual(self.agent.states['vm-left']['account'],raw)
        self.agent.pnls.update({'vm-left':900,'vm-right':-900});self.flat(pair);self.tick_until('Complete')
        row=self.queue.rows[0];fields=PairStore.fields(row)
        self.assertEqual(fields['Left Account ID'],clean)
        self.assertEqual(fields['Left Account'],['recBUL'])
        self.assertEqual(fields['Left Trade P&L'],900)
        self.assertEqual(len([c for c in self.agent.calls if c[1]=='entry']),1)

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
        self.assertEqual([r['id'] for r in self.queue.rows],['PAIR-0002'])
        self.assertEqual(len(self.store.rows),1)
    def test_delete_failure_survives_restart_without_entry_or_recreation(self):
        self.queue.add(self.body); row=self.queue.rows[0]; self.store.fail=True
        with self.assertRaisesRegex(ValueError,'unavailable'):
            self.queue.command('cancel',{'id':row['id']})
        self.assertEqual(row['status'],'Removing')
        restored=PairQueue(self.fleet,Planning(),self.store)
        self.assertEqual(restored.rows[0]['status'],'Removing')
        self.store.fail=False; restored.tick()
        self.assertEqual(restored.rows,[]); self.assertEqual(self.store.rows,{})
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
    def test_cannot_remove_preparing_or_trading_pair(self):
        self.queue.add(self.body); row=self.queue.rows[0]
        for status in ['Preparing','Trading','Awaiting results','Complete','Error']:
            row['status']=status
            with self.assertRaisesRegex(ValueError,'Only waiting'):
                self.queue.command('cancel',{'id':row['id']})
        self.assertEqual(len(self.store.rows),1)
    def test_remote_delete_targets_execution_key_only_and_is_idempotent(self):
        store=PairStore(Planning()); calls=[]; records=[
            {'id':'recOwn','fields':{'Execution Key':'own'}},
            {'id':'recOther','fields':{'Execution Key':'other'}}]
        store.records=lambda table: records[:]
        def request(table,method,query):
            calls.append((table,method,query))
            records[:]=[r for r in records if r['id']!=query['records[]']]
            return {'records':[{'id':query['records[]'],'deleted':True}]}
        store.request=request
        store.delete({'key':'own'}); store.delete({'key':'own'})
        self.assertEqual(calls,[(PAIR_TABLE,'DELETE',{'records[]':'recOwn'})])
        self.assertEqual(records[0]['id'],'recOther')

    def test_start_count_excludes_already_dispatched_pairs(self):
        self.queue.add(self.body);self.queue.add(self.body)
        self.assertEqual(self.queue.command('start',{})['startedCount'],2)
        self.assertEqual(self.queue.command('start',{})['startedCount'],0)
        self.queue.add(self.body)
        self.assertEqual(self.queue.command('start',{})['startedCount'],1)

    def test_start_dispatches_batch_new_plans_wait_for_next_start(self):
        self.queue.add(self.body);self.queue.add(self.body)
        self.queue.command('start',{})
        self.assertTrue(all(r['dispatched'] for r in self.queue.rows))
        self.queue.add(self.body)
        self.assertFalse(self.queue.rows[-1].get('dispatched',False))
        self.queue.command('pause',{});self.queue.command('resume',{})
        self.assertFalse(self.queue.rows[-1].get('dispatched',False))
        for row in self.queue.rows[:2]:row['status']='Complete'
        self.queue.tick()
        self.assertFalse(self.queue.running)
        self.assertFalse(any(c[1]=='entry' for c in self.agent.calls))
        self.queue.command('start',{})
        self.assertTrue(self.queue.rows[-1]['dispatched'])
    def test_bulk_remove_keeps_local_cancel_history_without_recreating_airtable(self):
        ids=[self.queue.add(self.body),self.queue.add(self.body)]
        self.queue.command('remove-selected',{'ids':ids})
        self.assertEqual(self.queue.rows,[]);self.assertEqual(self.store.rows,{})
        restored=PairQueue(self.fleet,Planning(),self.store)
        self.assertEqual(len(restored.snapshot()['history']),2)
        self.assertTrue(all(r['status']=='Cancelled' for r in restored.history))
        restored.command('retry',{});restored.tick()
        self.assertEqual(self.store.rows,{})
    def test_bulk_remove_rejects_entire_selection_if_one_started(self):
        ids=[self.queue.add(self.body),self.queue.add(self.body)]
        self.queue.rows[1]['status']='Trading'
        with self.assertRaisesRegex(ValueError,'Only waiting'):
            self.queue.command('remove-selected',{'ids':ids})
        self.assertEqual(len(self.queue.rows),2);self.assertEqual(len(self.store.rows),2)

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
