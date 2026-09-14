"""Durable, explicitly started sequential planning queue. No entry is retried.

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
TERMINAL = {'Complete', 'Cancelled'}


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

    @staticmethod
    def fields(row):
        spec = row['spec']; f = {'Pair ID': row['id'], 'Execution Key': row['key'], 'Status': row['status'],
            'Queue Order': row['order'], 'Instrument': spec['ticker'], 'Currency': 'USD',
            'Direction': 'Buy left / Sell right' if spec['direction'] == 'buy' else 'Sell left / Buy right',
            'Created At': row['created'], 'Activity / Error': row.get('message', '')}
        for side in ('left', 'right'):
            title = side.title(); slot = spec[side]
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
        if row.get('results'): f['Combined Result'] = round(sum(row['results'].values()), 2)
        for src, dst in [('started', 'Started At'), ('closed', 'Closed At'), ('synced', 'Results Synced At')]:
            if row.get(src): f[dst] = row[src]
        return f


class PairQueue:
    def __init__(self, fleet, planning, store=None):
        self.fleet = fleet; self.planning = planning; self.store = store or PairStore(planning)
        self.path = fleet.directory / 'planning-queue.json'
        self.lock = threading.RLock(); self.io = threading.Lock(); self.stop = threading.Event()
        self.running = False; self.message = 'Queue paused. Add pairs, then Start Queue.'
        self.rows = []; self.next_id = 1
        if self.path.exists():
            saved = json.loads(self.path.read_text()); self.rows = saved['rows']; self.next_id = saved['nextId']
            # A restart never resumes entry, even if a previous command response was lost.
            for row in self.rows:
                if row['status'] not in PENDING | TERMINAL:
                    row['status'] = 'Error'; row['message'] = 'Coordinator restarted. No entry will be retried. Review the pair in Trading.'
                    row['dirty'] = True
            self.message = 'Restored queue, paused. Review any interrupted pair before starting.'
        self.thread = threading.Thread(target=self.loop, daemon=True, name='planning-queue')

    def save(self):
        tmp = self.path.with_suffix('.tmp')
        tmp.write_text(json.dumps({'nextId': self.next_id, 'rows': self.rows}, allow_nan=False))
        os.replace(tmp, self.path)

    def snapshot(self):
        with self.lock: return copy.deepcopy({'running': self.running, 'message': self.message, 'rows': self.rows})

    def set_status(self, row, status, message):
        with self.lock:
            if (row['status'], row.get('message')) == (status, message): return
            row.update(status=status, message=message, dirty=True); self.save()

    def sync(self, row):
        # Queue mutation and background sync are serialized by io.
        self.store.push(row)
        with self.lock: row['dirty'] = False; self.save()

    def add(self, body):
        with self.io:
            draft_key = body.get('draftKey')
            if draft_key is not None:
                if not isinstance(draft_key,str) or not re.fullmatch('[a-f0-9]{32}',draft_key):
                    raise ValueError('Invalid draft identity.')
                existing = next((r for r in self.rows if r['key']==draft_key),None)
                if existing: return existing['id']
            spec = self.validate(body)
            remote = self.store.records(PAIR_TABLE)
            maximum = max([int(r.get('fields', {}).get('Pair ID', '')[5:]) for r in remote
                           if re.fullmatch(r'PAIR-\d+', r.get('fields', {}).get('Pair ID', ''))] or [0])
            with self.lock:
                number = max(self.next_id, maximum + 1); self.next_id = number + 1
                row = dict(id=f'PAIR-{number:04d}', key=draft_key or uuid.uuid4().hex, spec=spec, status='Queued',
                           message='Waiting for Start Queue.', order=len(self.rows)+1, created=now(), dirty=True)
                self.rows.append(row); self.save()
            try: self.sync(row)
            except Exception as exc:
                with self.lock: self.message = str(exc)
                # Retain the durable item; refresh shows the saved item and sync error.
            return row['id']

    def validate(self, body):
        left, right = body.get('left'), body.get('right')
        with self.fleet.lock:
            config = self.fleet.catalog.config
            if left == right or left not in config or right not in config: raise ValueError('Choose two different registered VMs.')
            names = {s: self.fleet.catalog.name(s) for s in (left, right)}
            available = {s: self.fleet.view(s)['accounts'] for s in (left, right)}
        ticker = str(body.get('ticker', '')).strip().upper()
        if not re.fullmatch(r'[A-Z0-9][A-Z0-9 .\-/]{0,29}', ticker): raise ValueError('Enter a valid instrument.')
        direction = body.get('direction')
        if direction not in ('buy', 'sell'): raise ValueError('Select the pair direction.')
        amounts = {k: body.get(k) for k in ('stopLoss', 'profit')}
        for v in amounts.values():
            if isinstance(v, bool) or not isinstance(v, (int,float)) or not math.isfinite(v) or not 0 < v <= 100000 or round(v,2) != v:
                raise ValueError('Enter positive Currency stop loss and profit target amounts, up to two decimals.')
        pair_amounts(body)
        accounts = {}; quantities = {}; masters = {}; records = {}; balances = {}
        source = self.store.records(TABLE)
        for slot in (left, right):
            a = body.get('accounts', {}).get(slot); q = body.get('quantities', {}).get(slot)
            if a not in available[slot]: raise ValueError('Account is not in this VM’s discovered NinjaTrader/Airtable list. Refresh accounts first.')
            if type(q) is not int or not 1 <= q <= 1000: raise ValueError('Quantity must be a whole number from 1 to 1000.')
            accounts[slot] = a; quantities[slot] = q
            if a == 'Sim101': masters[slot] = names[slot]; continue
            matches = [r for r in source if r.get('fields', {}).get('id') == a]
            if len(matches) != 1: raise ValueError('Account must have one exact Airtable match.')
            masters[slot] = str(matches[0]['fields'].get('Master Account', '')); records[slot] = matches[0]['id']
            balances[slot] = money(matches[0]['fields'].get('CurrentBalance'))
        if all(accounts[s]!='Sim101' for s in (left,right)):
            funds=[]
            for slot in (left,right):
                name=masters[slot].strip().upper(); prefix=re.match(r'^(MFF|LCD|FN|BUL|APEX|TOPSTEP|OX)',name)
                funds.append(prefix.group(0) if prefix else re.split(r'[-_\s]+',name)[0])
            if funds[0] and funds[0]==funds[1]: raise ValueError('Same fund: choose accounts from different funds.')
        if accounts[left] == accounts[right] and accounts[left] != 'Sim101': raise ValueError('The same real account cannot be both sides of one pair.')
        validate_quantities(dict(body, quantities=quantities), left, right)
        return dict(**({'ratio':body['ratio']} if 'ratio' in body else {}),left=left,right=right,ticker=ticker,direction=direction,accounts=accounts,quantities=quantities,
                    names=names,masters=masters,records=records,balances=balances,**amounts)

    def command(self, action, body):
        if action == 'add': return {'id': self.add(body)}
        # Pause must not wait for an export/network request.
        if action == 'pause':
            with self.lock: self.running=False; self.message='Paused. Open trades continue to be monitored.'
            return {'ok':True}
        with self.io, self.lock:
            if action == 'start':
                if any(r['status'] == 'Error' for r in self.rows): raise ValueError('Review the queue error before starting. Entry is never retried automatically.')
                self.running=True; self.message='Queue started. Waiting for the first available pair.'
            elif action == 'retry':
                for row in self.rows:
                    row['dirty']=True
                    if row['status']=='Error' and row.get('closed') and row.get('afterId') and row.get('pairId') in self.fleet.pairs:
                        row.update(status='Awaiting results', deadline=time.time()+300, message='Retrying result verification only; no entry retry.')
                self.message='Saved pair records will be synced again. No trade entry is retried.'
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
                self.running=False
                row.update(status='Cancelled', message='Reviewed and removed. No entry retry; historical results retained if available.', dirty=True)
            elif action in ('move','cancel'):
                row = next((r for r in self.rows if r['id']==body.get('id')), None)
                if not row or row['status'] not in PENDING: raise ValueError('Only waiting pairs can be moved or removed.')
                if action == 'cancel': row.update(status='Cancelled',message='Removed from queue.',dirty=True)
                else:
                    pending=[r for r in self.rows if r['status'] in PENDING]; i=pending.index(row); j=i+int(body.get('delta',0))
                    if not 0 <= j < len(pending): raise ValueError('Already at the end of the queue.')
                    a=self.rows.index(row); b=self.rows.index(pending[j]); self.rows[a],self.rows[b]=self.rows[b],self.rows[a]
                    for i,r in enumerate(self.rows): r['order']=i+1; r['dirty']=True
            else: raise ValueError('Unknown queue action.')
            self.save()
        return {'ok':True}

    def owned(self, identity):
        with self.lock:
            return any(r.get('pairId') == identity and r['status'] not in TERMINAL for r in self.rows)

    def fail(self, row, error):
        with self.lock: self.running=False; self.message=str(error)
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
            for row in self.rows:
                if row.get('dirty'):
                    self.sync(row)
            current = next((r for r in self.rows if r['status'] not in PENDING | TERMINAL), None)
            if current and current['status']=='Error': return
            row = current
            if row is None:
                if not self.running: return
                row = next((r for r in self.rows if r['status'] in PENDING), None)
                if row is None:
                    self.running=False; self.message='Queue complete.'; return
            try: self.advance(row)
            except Exception as exc: self.fail(row, exc)

    def advance(self, row):
        spec = row['spec']; slots = (spec['left'],spec['right']); status=row['status']
        if status in PENDING:
            if not self.running: return
            with self.fleet.lock:
                if any(s in self.fleet.owners for s in slots) or any(
                        a != 'Sim101' and a in p.settings.get('accounts', {}).values()
                        for a in spec['accounts'].values() for p in self.fleet.pairs.values()):
                    self.set_status(row,'Waiting','A VM or account is assigned to another pair. Release it in Trading when finished.'); return
            for s in slots: self.fleet.observe(s)
            with self.fleet.lock:
                agents=[self.fleet.view(s) for s in slots]
                if not all(self.fleet.catalog.safe_flat(a) for a in agents):
                    self.set_status(row,'Waiting','Waiting for both VMs to report fresh, idle Flat.'); return
                if not all(a.get('queueReceipts') for a in agents):
                    raise ValueError('Update both selected VM agents to preview.7 for verified queue results.')
                if not all(spec['accounts'][a['id']] in a['accounts'] for a in agents):
                    raise ValueError('Selected account is no longer available. Refresh accounts and add a corrected pair.')
                if not self.running: return
                pair_id=self.fleet.create_pair(*slots)
                row['pairId']=pair_id
                pair=self.fleet.get_pair(pair_id)
                pair.settings.update({k:spec[k] for k in ('ticker','stopLoss','profit','accounts','quantities','ratio') if k in spec})
                row['beforeId']=uuid.uuid4().hex; row['phase']='before'; row['requested']=[]; row['deadline']=time.time()+300
                self.set_status(row,'Preparing','Syncing starting balances and Realized PnL.'); return
        pair=self.fleet.get_pair(row['pairId'])
        if status=='Preparing' and row['phase']=='before':
            if not self.running:
                self.message='Paused before entry. Start Queue to continue.'; return
            if time.time()>row['deadline']: raise ValueError('Starting export timed out. No entry sent.')
            for slot in slots:
                if slot not in row['requested']:
                    row['requested'].append(slot); self.save() # before dispatch; no blind retry
                    pair.call(slot,'post_trade',{'tradeId':row['beforeId']},15)
                pair.observe(slot)
            snaps={s:self.receipt(pair,s,row['beforeId']) for s in slots}
            if not all(snaps.values()) or not all(pair.safe_flat(pair.view_agent(s)) for s in slots): return
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
            self.set_status(row,'Trading','Entry requested; awaiting actual positions.'); self.sync(row)
            with self.lock:
                if not self.running:
                    row['phase']='prepare'; self.set_status(row,'Preparing','Paused before entry.'); return
                row['job']=pair.submit(spec['direction'],{}); self.save(); return
        if status=='Trading':
            pair.state()
            job=next((j for j in pair.jobs if j['id']==row.get('job')),None)
            if job and job['status']=='error': raise ValueError(job['message'])
            if pair.closed_sequence <= row['closedSequence']: return
            row['closed']=now(); row['deadline']=time.time()+300
            self.set_status(row,'Awaiting results','Waiting for confirmed post-trade exports.'); return
        if status=='Awaiting results':
            if time.time()>row['deadline']: raise ValueError('Post-trade result export timed out. Pair retained for review; no next entry.')
            for slot in slots: pair.observe(slot)
            snaps={s:self.receipt(pair,s,row['afterId']) for s in slots}
            if not all(snaps.values()) or pair.sync_dispatch: return
            # Midnight/session rollover can invalidate subtraction; never silently call it a loss.
            if any(row['before'][s]['time'][:10] != snaps[s]['time'][:10] for s in slots):
                raise ValueError('Result crossed a UTC date boundary. Review PnL reset before recording a result.')
            row['after']=snaps; row['results']={s:trade_result(row['before'][s]['pnl'],snaps[s]['pnl']) for s in slots}; row['synced']=now()
            # Save final results remotely while the pair is still reserved.
            row['status']='Complete'; row['message']='Results synced. Releasing VMs.'; row['dirty']=True; self.save(); self.sync(row)
            try: self.fleet.release_pair(row['pairId'])
            except Exception as exc:
                self.fail(row,'Results saved, but VM release failed: '+str(exc)); return
            self.planning.refresh(); self.message='Pair complete. Ready for the next queued pair.'

    def loop(self):
        while not self.stop.is_set():
            try: self.tick()
            except Exception as exc:
                with self.lock: self.running=False; self.message=str(exc)
            self.stop.wait(2)

    def start(self): self.thread.start()
    def close(self): self.running=False; self.stop.set()
