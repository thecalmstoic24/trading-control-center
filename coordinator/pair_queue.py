"""Durable, explicitly started planning queue for independent VMs. No entry is retried.

Pair receipts come from the authenticated agent after its CSV values have been
confirmed by Airtable. Accounts browsing remains read-only in planning.py.
"""
import copy
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import threading
import time
import urllib.request
import urllib.parse
import urllib.error
import uuid

from planning import BASE, TABLE, credential
from ratios import pair_amounts, validate_quantities

PAIR_TABLE = 'tblHhpDgF7rYPQOaA'
PENDING = {'Queued', 'Waiting'}
TERMINAL = {'Complete', 'Cancelled', 'Removing'}


def slots(spec):
    return tuple(s for s in (spec.get("left"), spec.get("right")) if s)


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def money(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError('A numeric balance or Realized PnL is missing from the export.')
    return round(value, 2)


def trade_result(before, after):
    return round(money(after) - money(before), 2)


class PairStore:
    def __init__(self, planning):
        self.planning = planning

    def request(self, table, method='GET', body=None, query=None):
        path = self.planning.path
        if not path.exists():
            path = Path(os.environ.get('LOCALAPPDATA', '')) / 'NT-Airtable' / 'token.dat'
        if not path.exists():
            raise ValueError('Save an Airtable token in Planning setup with read and write access to the Trading base.')
        token = credential(path)
        url = f'https://api.airtable.com/v0/{BASE}/{table}'
        if query: url += '?' + urllib.parse.urlencode(query)
        req = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body, allow_nan=False).encode(),
                                     headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=20) as response: return json.load(response)
        except urllib.error.HTTPError as exc:
            raise ValueError(f'Airtable request failed (HTTP {exc.code}). Check Planning token read/write access; retry sync.') from None
        finally:
            token = None

    def records(self, table):
        result = []; offset = None; seen = set()
        while True:
            query = {'pageSize': 100}
            if offset: query['offset'] = offset
            page = self.request(table, query=query)
            result.extend(page['records']); offset = page.get('offset')
            if not offset: return result
            if offset in seen: raise ValueError('Repeated Airtable page.')
            seen.add(offset); time.sleep(.25)

    def push(self, row):
        # Lookup before every create; a lost write response must not create a second execution.
        records = self.records(PAIR_TABLE)
        matches = [r for r in records if r.get('fields', {}).get('Execution Key') == row['key']]
        if len(matches) > 1: raise ValueError('Duplicate Execution Key in Airtable; resolve before continuing.')
        collisions = [r for r in records if r.get('fields', {}).get('Pair ID') == row['id'] and r.get('fields', {}).get('Execution Key') != row['key']]
        if collisions: raise ValueError('Pair ID already exists on another coordinator. Use one coordinator for the queue.')
        fields = self.fields(row)
        # Upsert only by the internal UUID. Repeated saves preserve the same record.
        result = self.request(PAIR_TABLE, 'PATCH', {'performUpsert': {'fieldsToMergeOn': ['Execution Key']},
                                                   'records': [{'fields': fields}], 'typecast': False})
        saved = result.get('records', [])
        if len(saved) != 1 or saved[0].get('fields', {}).get('Execution Key') != row['key']:
            raise ValueError('Airtable did not confirm the pair record.')
        return saved[0]['id']

    def delete(self, row):
        matches = [r for r in self.records(PAIR_TABLE)
                   if r.get('fields', {}).get('Execution Key') == row['key']]
        for record in matches:
            record_id = record['id']
            if not re.fullmatch(r'rec[A-Za-z0-9]+', record_id):
                raise ValueError('Invalid Airtable pair record identity.')
            result = self.request(PAIR_TABLE, 'DELETE', query={'records[]': record_id})
            if not any(r.get('id') == record_id and r.get('deleted') is True for r in result.get('records', [])):
                raise ValueError('Airtable did not confirm pair deletion. Retry Remove.')

    @staticmethod
    def fields(row):
        spec = row['spec']; f = {'Pair ID': row['id'], 'Execution Key': row['key'], 'Status': row['status'],
            'Queue Order': row['order'], 'Instrument': spec['ticker'], 'Currency': 'USD',
            'Direction': 'Buy left / Sell right' if spec['direction'] == 'buy' else 'Sell left / Buy right',
            'Created At': row['created'], 'Activity / Error': row.get('message', '')}
        for side in ('left', 'right'):
            title = side.title(); slot = spec[side]
            if not slot: continue
            f.update({title + ' VM': spec['names'][slot], title + ' Account ID': spec['accounts'][slot],
                      title + ' Master Account': spec['masters'].get(slot, ''),
                      title + ' Quantity': spec['quantities'][slot],
                      title + ' Stop Loss': pair_amounts(spec)[0 if side == 'left' else 2],
                      title + ' Profit Target': pair_amounts(spec)[1 if side == 'left' else 3]})
            if slot in spec.get('balances', {}): f[title + ' Current Balance'] = spec['balances'][slot]
            record_id = spec.get('records', {}).get(slot)
            if record_id: f[title + ' Account'] = [record_id]
            for phase in ('before', 'after'):
                snap = row.get(phase, {}).get(slot)
                if snap:
                    f[title + ' Realized PnL ' + phase.title()] = snap['pnl']
                    f[title + ' Current Balance'] = snap['balance']
            if slot in row.get('results', {}): f[title + ' Trade P&L'] = row['results'][slot]
        if len(row.get('results',{})) == len(slots(spec)): f['Combined Result'] = round(sum(row['results'].values()), 2)
        for src, dst in [('started', 'Started At'), ('closed', 'Closed At'), ('synced', 'Results Synced At')]:
            if row.get(src): f[dst] = row[src]
        return f


class PairQueue:
    def __init__(self, fleet, planning, store=None):
        self.fleet = fleet; self.planning = planning; self.store = store or PairStore(planning)
        self.path = fleet.directory / 'planning-queue.json'
        self.lock = threading.RLock(); self.io = threading.Lock(); self.stop = threading.Event()
        self.running = False; self.message = 'Queue paused. Add pairs, then Start Queue.'
        self.rows = []; self.history = []; self.next_id = 1
        if self.path.exists():
            saved = json.loads(self.path.read_text()); self.rows = saved['rows']; self.next_id = saved['nextId']; self.history = saved.get('history', [])
            # A restart never resumes entry, even if a previous command response was lost.
            for row in self.rows:
                if row['status'] not in PENDING | TERMINAL:
                    row['status'] = 'Error'; row['message'] = 'Coordinator restarted. No entry will be retried. Review the pair in Trading.'
                    row['dirty'] = True
            self.message = 'Restored queue, paused. Review any interrupted pair before starting.'
        self.result_thread = threading.Thread(target=self.result_loop, daemon=True, name='queue-results')
        self.thread = threading.Thread(target=self.loop, daemon=True, name='planning-queue')

    def save(self):
        with self.lock:
            tmp = self.path.with_suffix('.tmp')
            tmp.write_text(json.dumps({'nextId': self.next_id, 'rows': self.rows, 'history': self.history}, allow_nan=False))
            os.replace(tmp, self.path)

    def snapshot(self):
        with self.lock: return copy.deepcopy({'running': self.running, 'message': self.message, 'rows': self.rows, 'history': self.history})

    def set_status(self, row, status, message):
        with self.lock:
            if (row['status'], row.get('message')) == (status, message): return
            row.update(status=status, message=message, dirty=True)
            if status in {'Complete','Cancelled'}: row.setdefault('completedUtc', now())
            self.save()

    def sync(self, row):
        # Queue mutation and background sync are serialized by io.
        if row.get('remoteDeleted') or row.get('localDraft'): return
        self.store.push(row)
        with self.lock: row['dirty'] = False; self.save()

    def add(self, body):
        with self.io:
            draft_key = body.get('draftKey')
            if draft_key is not None:
                if not isinstance(draft_key,str) or not re.fullmatch('[a-f0-9]{32}',draft_key):
                    raise ValueError('Invalid draft identity.')
                existing = next((r for r in self.rows + self.history if r['key']==draft_key),None)
                if existing: return existing['id']
            spec = self.validate(body)
            local = body.get('localDraft') is True
            remote = [] if local else self.store.records(PAIR_TABLE)
            maximum = max([int(r.get('fields', {}).get('Pair ID', '')[5:]) for r in remote
                           if re.fullmatch(r'PAIR-\d+', r.get('fields', {}).get('Pair ID', ''))] or [0])
            with self.lock:
                number = max(self.next_id, maximum + 1)
                if not local: self.next_id = number + 1
                row = dict(id=f'PAIR-{number:04d}', key=draft_key or uuid.uuid4().hex, spec=spec, status='Queued',
                           message='Waiting for Start Queue.', order=len(self.rows)+1, created=now(), dirty=True)
                if local: row.update(id='DRAFT-'+row['key'],localDraft=True,dirty=False,draft=copy.deepcopy(body.get('draft')))
                self.rows.append(row); self.save()
            try:
                if not local: self.sync(row)
            except Exception as exc:
                with self.lock: self.message = str(exc)
                # Retain the durable item; refresh shows the saved item and sync error.
            return row['id']

    def validate(self, body):
        left, right = body.get('left'), body.get('right')
        with self.fleet.lock:
            config = self.fleet.catalog.config
            members=slots(body)
            if not members or len(set(members))!=len(members) or any(s not in config for s in members): raise ValueError('Choose one registered VM or two different registered VMs.')
            if len(members)==1 and not self.fleet.view(members[0]).get('singlePair'): raise ValueError('Update the selected VM to Preview 23 for Single Pair.')
            names = {s: self.fleet.catalog.name(s) for s in members}
            available = {s: self.fleet.view(s)['accounts'] for s in members}
        ticker = str(body.get('ticker', '')).strip().upper()
        if not re.fullmatch(r'[A-Z0-9][A-Z0-9 .\-/]{0,29}', ticker): raise ValueError('Enter a valid instrument.')
        direction = body.get('direction')
        if direction not in ('buy', 'sell'): raise ValueError('Select the pair direction.')
        amounts = {k: body.get(k) for k in ('stopLoss', 'profit')}
        for v in amounts.values():
            if isinstance(v, bool) or not isinstance(v, (int,float)) or not math.isfinite(v) or not 0 < v <= 100000 or round(v,2) != v:
                raise ValueError('Enter positive Currency stop loss and profit target amounts, up to two decimals.')
        pair_amounts(body)
        accounts = {}; quantities = {}; masters = {}; records = {}; balances = {}; metrics = {}
        source = self.store.records(TABLE)
        for slot in members:
            a = body.get('accounts', {}).get(slot); q = body.get('quantities', {}).get(slot)
            if a not in available[slot]: raise ValueError('Account is not in this VM’s discovered NinjaTrader/Airtable list. Refresh accounts first.')
            if type(q) is not int or not 1 <= q <= 1000: raise ValueError('Quantity must be a whole number from 1 to 1000.')
            accounts[slot] = a; quantities[slot] = q
            if a == 'Sim101': masters[slot] = names[slot]; continue
            matches = [r for r in source if r.get('fields', {}).get('id') == a]
            if len(matches) != 1: raise ValueError('Account must have one exact Airtable match.')
            masters[slot] = str(matches[0]['fields'].get('Master Account', '')); records[slot] = matches[0]['id']
            balances[slot] = money(matches[0]['fields'].get('CurrentBalance'))
            metrics[slot]={k:matches[0]['fields'].get(k) for k in ('CurrentBalance','stop','Trailing max drawdown','tradingDays','largestProfitDay')}
        if len(members)==2 and all(accounts[s]!='Sim101' for s in members):
            funds=[]
            for slot in (left,right):
                name=masters[slot].strip().upper(); prefix=re.match(r'^(MFF|LCD|FN|BUL|APEX|TOPSTEP|OX)',name)
                funds.append(prefix.group(0) if prefix else re.split(r'[-_\s]+',name)[0])
            if funds[0] and funds[0]==funds[1]: raise ValueError('Same fund: choose accounts from different funds.')
        if len(members)==2 and accounts[left] == accounts[right] and accounts[left] != 'Sim101': raise ValueError('The same real account cannot be both sides of one pair.')
        if len(members)==2: validate_quantities(dict(body, quantities=quantities), left, right)
        return dict(**({'ratio':body['ratio']} if 'ratio' in body else {}),left=left,right=right,ticker=ticker,direction=direction,accounts=accounts,quantities=quantities,
                    names=names,masters=masters,records=records,balances=balances,metrics=metrics,**amounts)

    def command(self, action, body):
        if action == 'add': return {'id': self.add(body)}
        if action == 'duplicate':
            with self.lock:
                source=next((r for r in self.rows+self.history if r['id']==body.get('id') and r['status'] in {'Complete','Cancelled'}),None)
                if not source: raise ValueError('Only completed or canceled pairs can be duplicated.')
                spec=copy.deepcopy(source['spec'])
                source_key=source['key']
            spec['draftKey']=body.get('draftKey')
            if not isinstance(spec['draftKey'],str) or not re.fullmatch('[a-f0-9]{32}',spec['draftKey']):
                raise ValueError('Duplicate request identity is required.')
            with self.lock:
                existing=next((r for r in self.rows+self.history if r['key']==spec['draftKey']),None)
                if existing and existing.get('duplicateOf')!=source_key: raise ValueError('Duplicate request identity conflict.')
            identity=self.add(spec)
            with self.io,self.lock:
                row=next(r for r in self.rows if r['id']==identity)
                if row.get('duplicateOf') not in (None,source_key): raise ValueError('Duplicate request identity conflict.')
                if not row.get('duplicateOf'):
                    row['duplicateOf']=source_key
                    row['dirty']=True
                    row['message']='Copied from '+source['id']+'. Select Start when ready.'
                    self.rows.remove(row)
                    index=next((i+1 for i,r in enumerate(self.rows) if r['key']==source_key),len(self.rows))
                    self.rows.insert(index,row)
                    for i,r in enumerate(self.rows):r['order']=i+1
                    self.save()
            return {'id':identity}

        # Pause must not wait for an export/network request.
        if action == 'pause':
            with self.lock: self.running=False; self.message='Paused. Open trades continue to be monitored.'
            return {'ok':True}
        with self.io, self.lock:
            if action == 'edit-draft':
                row=next((r for r in self.rows if r['id']==body.get('id')),None)
                if not row or not row.get('localDraft') or row.get('dispatched'): raise ValueError('Only unstarted local drafts can be edited.')
                self.rows.remove(row);self.save()
                return {'draft':row}
            if action in ('start','resume'):
                # Failed rows retain their VM reservations, but do not stop unrelated rows.
                for row in self.rows:
                    if action=='start' and row['status'] in PENDING:
                        if row.get('localDraft'):
                            remote=self.store.records(PAIR_TABLE)
                            maximum=max([int(x['fields']['Pair ID'][5:]) for x in remote if re.fullmatch(r'PAIR-\d+',x.get('fields',{}).get('Pair ID',''))] or [0])
                            number=max(self.next_id,maximum+1);self.next_id=number+1
                            row.update(id=f'PAIR-{number:04d}',localDraft=False,dirty=True)
                            self.save()
                        row['dispatched']=True
                        row['fast22']=all(self.fleet.view(slot).get('backgroundExports') for slot in slots(row['spec']))
                self.running=True; self.message='Queue started. Follow this batch in Trading.'
            elif action == 'start-one':
                row=next((r for r in self.rows if r['id']==body.get('id')),None)
                if not row or row['status'] not in PENDING: raise ValueError('Select a waiting pair.')
                row['fast22']=all(self.fleet.view(slot).get('backgroundExports') for slot in slots(row['spec']));row['dispatched']=True;self.running=True;self.message='Pair started; waiting for available VMs.'
            elif action == 'refresh':
                self.refresh_remote()
            elif action == 'retry':
                for row in self.rows:
                    row['dirty']=row['status']!='Removing'
                    if row['status']=='Error' and row.get('closed') and row.get('afterId') and row.get('pairId') in self.fleet.pairs:
                        row.update(status='Awaiting results', deadline=time.time()+300, message='Retrying result verification only; no entry retry.')
                self.message='Saved pair records will be synced again. No trade entry is retried.'
            elif action == 'retry-prepare':
                row=next((r for r in self.rows if r['id']==body.get('id')),None)
                if not row or row['status']!='Error' or row.get('started'):
                    raise ValueError('Retry preparation is only available before any entry was requested.')
                identity=row.get('pairId')
                if identity in self.fleet.pairs:
                    pair=self.fleet.get_pair(identity)
                    if pair.active or pair.operation.locked() or pair.sync_dispatch or any(j['status']=='running' for j in pair.jobs):
                        raise ValueError('Wait for the existing operation and verify positions before retrying.')
                    self.fleet.release_pair(identity)
                for key in ('pairId','phase','job','before','beforeId','afterId','requested','deadline','refreshId'):
                    row.pop(key,None)
                row.update(status='Queued',dispatched=True,dirty=True,message='Preparation retry requested after calibration. Settings retained.')
                self.running=True
                self.message='Retrying preparation. No previous entry is retried.'
            elif action == 'skip-results':
                row=next((r for r in self.rows if r['id']==body.get('id')),None)
                if not row or not (row['status']=='Awaiting results' or (row['status']=='Error' and row.get('closed'))): raise ValueError('Select a closed pair awaiting results.')
                pair=self.fleet.get_pair(row['pairId'])
                pair.refresh_both()
                if not all(pair.view_agent(s).get('skipResults') for s in pair.pair): raise ValueError('Update participating agents to Preview 23 before skipping results.')
                for s in pair.pair: pair.call(s,'skip_results',{'tradeId':row['afterId']},15)
                pair.refresh_both()
                deadline=time.monotonic()+3
                while pair.sync_dispatch and time.monotonic()<deadline: time.sleep(.05)
                if pair.sync_dispatch: raise ValueError('Export stopped. Wait for the current refresh to finish, then click Skip Results again.')
                self.fleet.release_pair(row['pairId'])
                row.update(released22=True,fast22=True,resultsSkipped=True,completedUtc=now())
                self.set_status(row,'Complete','Results skipped; VMs released. Queued pairs continue.')
            elif action == 'resolve':
                row = next((r for r in self.rows if r['id']==body.get('id')), None)
                if not row or row['status'] != 'Error': raise ValueError('Select an interrupted pair.')
                identity = row.get('pairId')
                if identity in self.fleet.pairs:
                    pair = self.fleet.get_pair(identity)
                    pair.refresh_both()
                    if pair.sync_dispatch or not all(pair.safe_flat(pair.view_agent(s)) for s in pair.pair):
                        raise ValueError('Close the trade and verify both VMs fresh and Flat in Trading first.')
                    self.fleet.release_pair(identity)
                row.update(status='Cancelled', completedUtc=now(), released22=bool(row.get('fast22')), message='Reviewed and removed. Historical results retained; queued pairs continue.', dirty=True)
            elif action == 'remove-selected':
                ids=body.get('ids')
                if not isinstance(ids,list) or not ids or any(not isinstance(i,str) for i in ids):
                    raise ValueError('Select queued pairs to remove.')
                rows=[r for r in self.rows if r['id'] in set(ids)]
                if len(rows)!=len(set(ids)) or any(r['status'] not in PENDING | {'Removing'} for r in rows):
                    raise ValueError('Only waiting pairs can be removed. Refresh your selection.')
                for row in rows: row.update(status='Removing',message='Removing from Airtable.',dirty=False)
                self.save()
                try:
                    for row in rows: self.remove(row)
                except Exception:
                    self.running=False; self.message='Removal pending. Retry Remove to finish deleting from Airtable.'
                    raise
            elif action in ('move','cancel'):
                row = next((r for r in self.rows if r['id']==body.get('id')), None)
                if not row or row['status'] not in (PENDING | {'Removing'} if action == 'cancel' else PENDING): raise ValueError('Only waiting pairs can be moved or removed.')
                if action == 'cancel':
                    # Persist exclusion before network I/O; a lost delete response is retryable.
                    row.update(status='Removing',message='Removing from Airtable. Retry Remove if interrupted.',dirty=False)
                    self.save()
                    try: self.remove(row)
                    except Exception:
                        self.running=False
                        self.message='Pair removal pending. Retry Remove to finish deleting it from Airtable.'
                        raise
                else:
                    pending=[r for r in self.rows if r['status'] in PENDING]; i=pending.index(row); j=i+int(body.get('delta',0))
                    if not 0 <= j < len(pending): raise ValueError('Already at the end of the queue.')
                    a=self.rows.index(row); b=self.rows.index(pending[j]); self.rows[a],self.rows[b]=self.rows[b],self.rows[a]
                    for i,r in enumerate(self.rows): r['order']=i+1; r['dirty']=True
            else: raise ValueError('Unknown queue action.')
            self.save()
        return {'ok':True}

    def refresh_remote(self):
        # Called under io + lock. Never interpret a failed read as an empty table.
        remote = self.store.records(PAIR_TABLE)
        keys = {r.get('fields', {}).get('Execution Key') for r in remote}
        removed = 0
        for row in self.rows[:]:
            if row.get('localDraft') or row['key'] in keys or (row.get('dirty') and not row.get('remoteDeleted')):
                continue
            row.update(remoteDeleted=True, dirty=False)
            if row['status']=='Preparing': row['status']='Error'
            if row.get('pairId') in self.fleet.pairs:
                row['message']='Deleted in Airtable. Trade monitoring retained until the VMs are released.'
                continue
            self.rows.remove(row)
            removed += 1
        self.history = [r for r in self.history if r['key'] in keys]
        self.message=f'Trading refreshed from Airtable. {removed} deleted pair(s) removed.'
        self.save()

    def remove(self, row):
        if not row.get('localDraft'): self.store.delete(row)
        with self.lock:
            cancelled=copy.deepcopy(row)
            cancelled.update(status='Cancelled',message='Removed from queue and Airtable.',dirty=False,cancelled=now(),completedUtc=now())
            self.history.append(cancelled)
            self.rows.remove(row)
            self.message='Pair removed from the queue and Airtable.'
            self.save()

    def owned(self, identity):
        with self.lock:
            return any(r.get('pairId') == identity and r['status'] not in TERMINAL for r in self.rows)

    def fail(self, row, error):
        with self.lock: self.message='Pair failed; continuing with eligible queued pairs. '+str(error)
        self.set_status(row, 'Error', str(error))

    def receipt(self, pair, slot, identity):
        agent = pair.view_agent(slot)
        receipt = agent.get('syncReceipt') or {}
        if receipt.get('id') != identity: return None
        rows = [r for r in receipt.get('accounts', []) if r.get('Account') == pair.settings['accounts'][slot]]
        if len(rows) != 1: raise ValueError('Selected account is missing from its confirmed export receipt. Queue paused.')
        item = rows[0]
        return {'balance':money(item.get('CurrentBalance')), 'pnl':money(item.get('Realized PnL')), 'time':receipt['completedUtc']}

    def tick(self):
        with self.io:
            for row in self.rows[:]:
                if row.get('remoteDeleted') and row.get('pairId') not in self.fleet.pairs:
                    self.rows.remove(row); self.save(); continue
                if row['status']=='Removing':
                    self.remove(row)
                    continue
                if row.get('dirty') and not row.get('fast22'):
                    self.sync(row)
            # Advance every active pair, then reserve any eligible pending pairs.
            # Fleet ownership is checked under its lock before each reservation.
            active=[r for r in self.rows if r['status'] not in PENDING | TERMINAL | {'Error'}]
            for row in active:
                try: self.advance(row)
                except Exception as exc: self.fail(row, exc)
            if not self.running: return
            for row in self.rows[:]:
                if row['status'] not in PENDING or not row.get('dispatched'): continue
                try: self.advance(row)
                except Exception as exc: self.fail(row, exc)
            if not any(r['status'] not in TERMINAL | {'Error'} and r.get('dispatched') for r in self.rows):
                self.running=False; self.message='Queue finished. Review any failed pairs in Trading.'

    def advance(self, row):
        spec = row['spec']; members = slots(spec); status=row['status']
        if status in PENDING:
            if not self.running or not row.get('dispatched'): return
            with self.fleet.lock:
                if any(s in self.fleet.owners for s in members) or any(
                        a != 'Sim101' and a in p.settings.get('accounts', {}).values()
                        for a in spec['accounts'].values() for p in self.fleet.pairs.values()):
                    self.set_status(row,'Waiting','A VM or account is assigned to another pair. Release it in Trading when finished.'); return
            if not row.get('checked22'):
                for s in members: self.fleet.observe(s)
            with self.fleet.lock:
                agents=[self.fleet.view(s) for s in members]
                if any(a.get('calibrationRequired') for a in agents):
                    raise ValueError('Calibration required. Click Calibrate Chart 1 on the affected agent, then Retry preparation.')
                if not row.get('checked22') and not all(self.fleet.catalog.safe_flat(a) for a in agents):
                    self.set_status(row,'Waiting','Waiting for both VMs to report fresh, idle Flat.'); return
                if not all(a.get('queueReceipts') for a in agents):
                    raise ValueError('Update both selected VM agents to preview.7 for verified queue results.')
                if not all(a.get('queueAccountRefresh') for a in agents):
                    raise ValueError('Update both VM agents to Preview 18 for automatic verified account refresh.')
                if not self.running: return
                if row.get('fast22'): row['checked22']=True
                pair_id=self.fleet.create_pair(spec['left'],spec['right'])
                row['pairId']=pair_id
                pair=self.fleet.get_pair(pair_id)
                pair.settings.update({k:spec[k] for k in ('ticker','stopLoss','profit','accounts','quantities','ratio') if k in spec})
                if row.get('fast22'):
                    row['before']={}
                    for agent in agents:
                        receipt=agent.get('syncReceipt') or {}
                        matches=[a for a in receipt.get('accounts',[]) if a.get('Account')==spec['accounts'][agent['id']]]
                        if len(matches)==1:
                            try:
                                row['before'][agent['id']]={'pnl':money(matches[0].get('Realized PnL')),'balance':money(matches[0].get('CurrentBalance')),'time':receipt['completedUtc']}
                            except (ValueError,KeyError): pass
                    row['phase']='prepare';row['deadline']=time.time()+300
                    self.set_status(row,'Preparing','Using cached accounts. Preparing calibrated charts; no starting Airtable sync.')
                    row['job']=pair.submit('prepare',spec);self.save();return
                row['refreshId']=uuid.uuid4().hex; row['phase']='accounts'; row['requested']=[]; row['deadline']=time.time()+150
                self.set_status(row,'Preparing','Refreshing both agents’ account lists before preparation.'); return
        pair=self.fleet.get_pair(row['pairId'])
        if status=='Preparing' and row['phase']=='accounts':
            if not self.running: return
            if time.time()>row['deadline']:
                raise ValueError('Account refresh timed out. No trade entry sent. Check the agents’ account messages.')
            for slot in members:
                if slot not in row['requested']:
                    row['requested'].append(slot); self.save()
                    pair.call(slot,'accounts',{'refreshId':row['refreshId']},15)
                pair.observe(slot)
            agents=[pair.view_agent(s) for s in members]
            if not all(pair.safe_flat(a) and a.get('accountRefreshId')==row['refreshId'] for a in agents): return
            for a in agents:
                if spec['accounts'][a['id']] not in a['accounts']:
                    raise ValueError(a['name']+': Selected account is missing from the newly refreshed NinjaTrader/Airtable list. No entry sent.')
            row['beforeId']=uuid.uuid4().hex; row['phase']='before'; row['requested']=[]; row['deadline']=time.time()+300
            self.set_status(row,'Preparing','Accounts verified. Syncing starting balances and Realized PnL.'); return
        if status=='Preparing' and row['phase']=='before':
            if not self.running:
                self.message='Paused before entry. Start Queue to continue.'; return
            if time.time()>row['deadline']: raise ValueError('Starting export timed out. No entry sent.')
            for slot in members:
                if slot not in row['requested']:
                    row['requested'].append(slot); self.save() # before dispatch; no blind retry
                    pair.call(slot,'post_trade',{'tradeId':row['beforeId']},15)
                pair.observe(slot)
            snaps={s:self.receipt(pair,s,row['beforeId']) for s in members}
            if not all(snaps.values()) or not all(pair.safe_flat(pair.view_agent(s)) for s in members): return
            row['before']=snaps
            if not self.running: self.save(); return
            row['phase']='prepare'; row['job']=pair.submit('prepare',spec); self.save(); return
        if status=='Preparing' and row['phase']=='prepare':
            job=next(j for j in pair.jobs if j['id']==row['job'])
            if job['status']=='running': return
            if job['status']=='error': raise ValueError(job['message'])
            if not self.running: self.message='Paused before entry. Start Queue to continue.'; return
            if time.time() > row['deadline']: raise ValueError('Starting balance snapshot expired. No entry sent; add a new pair after review.')
            # Persist the one-way entry transition before sending anything to the agent.
            row['started']=now(); row['closedSequence']=pair.closed_sequence; row['afterId']=pair.binding_id
            self.set_status(row,'Trading','Entry requested; awaiting actual positions.')
            if not row.get('fast22'): self.sync(row)
            with self.lock:
                if not self.running:
                    row['phase']='prepare'; self.set_status(row,'Preparing','Paused before entry.'); return
                row['job']=pair.submit(('sell' if spec['direction']=='buy' else 'buy') if not spec.get('left') else spec['direction'],{}); self.save(); return
        if status=='Trading':
            pair.state()
            job=next((j for j in pair.jobs if j['id']==row.get('job')),None)
            if job and job['status']=='error': raise ValueError(job['message'])
            if pair.closed_sequence <= row['closedSequence']: return
            row['closed']=now(); row['deadline']=time.time()+(30 if row.get('fast22') else 300)
            self.set_status(row,'Awaiting results','Waiting for confirmed post-trade exports.'); return
        if status=='Awaiting results':
            if time.time()>row['deadline']:
                if row.get('fast22'):
                    self.set_status(row,'Awaiting results','CSV capture still pending. These VMs remain reserved until both snapshots are saved; other pairs continue.')
                else: raise ValueError('Post-trade result export timed out. Pair retained for review; no next entry.')
            for slot in members: pair.observe(slot)
            snaps={s:self.receipt(pair,s,row['afterId']) for s in members}
            if not all(snaps.values()) or pair.sync_dispatch: return
            if row.get('fast22'):
                row['after']=snaps;row['results']={}
                for slot,snap in snaps.items():
                    baseline=row.get('before',{}).get(slot)
                    if baseline and baseline['time'][:10]==snap['time'][:10]:
                        row['results'][slot]=trade_result(baseline['pnl'],snap['pnl'])
                # Freeze receipts locally before ownership changes; upload cannot block release.
                row['synced']=now();self.save()
                self.fleet.release_pair(row['pairId'])
                row['released22']=True
                self.set_status(row,'Complete','CSVs saved; VMs released. Airtable upload runs in background.' if len(row['results'])==2 else 'CSVs saved; VMs released. P&L unavailable where a same-day baseline is missing.')
                return
            # Midnight/session rollover can invalidate subtraction; never silently call it a loss.
            if any(row['before'][s]['time'][:10] != snaps[s]['time'][:10] for s in members):
                raise ValueError('Result crossed a UTC date boundary. Review PnL reset before recording a result.')
            row['after']=snaps; row['results']={s:trade_result(row['before'][s]['pnl'],snaps[s]['pnl']) for s in members}; row['synced']=now()
            # Save final results remotely while the pair is still reserved.
            row['completedUtc']=now(); row['status']='Complete'; row['message']='Results synced. Releasing VMs.'; row['dirty']=True; self.save(); self.sync(row)
            try: self.fleet.release_pair(row['pairId'])
            except Exception as exc:
                self.fail(row,'Results saved, but VM release failed: '+str(exc)); return
            self.planning.refresh(); self.message='Pair complete. Ready for the next queued pair.'

    def result_loop(self):
        # Airtable latency must never occupy the scheduler or a released VM.
        while not self.stop.is_set():
            with self.lock:
                pending=[copy.deepcopy(r) for r in self.rows if r.get('fast22') and r.get('released22') and r.get('dirty') and not r.get('remoteDeleted')]
            for snapshot in pending:
                try:
                    self.store.push(snapshot)
                    with self.lock:
                        row=next((r for r in self.rows if r['key']==snapshot['key']),None)
                        if row == snapshot:
                            row['dirty']=False;row['message']='Results saved to Airtable.';self.save()
                    self.planning.refresh()
                except Exception as exc:
                    with self.lock: self.message='Background result upload pending: '+str(exc)
            self.stop.wait(5)

    def loop(self):
        while not self.stop.is_set():
            try: self.tick()
            except Exception as exc:
                with self.lock: self.running=False; self.message=str(exc)
            self.stop.wait(.25 if any(r.get('fast22') and r['status'] not in TERMINAL | {'Error'} for r in self.rows) else 2)

    def start(self): self.result_thread.start(); self.thread.start()
    def close(self): self.running=False; self.stop.set()
