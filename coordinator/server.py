"""Local Windows control center. Standard library only; verifies explicit account and quantity selections."""
from __future__ import annotations
import argparse
import base64
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
import hmac
import ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
from logging.handlers import RotatingFileHandler
import math
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
import threading
import time
import uuid
import webbrowser

# Embedded Windows Python omits the script directory, including at import time.
import sys
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from ratios import pair_amounts, validate_quantities
from account_names import account_id, account_list, trading_name

VERSION = '16.0-preview.21'
AGENT_VERSIONS = {'16.0-preview.20','16.0-preview.19','16.0-preview.18','16.0-preview.17','16.0-preview.16',VERSION, '16.0-preview.15', '16.0-preview.14', '16.0-preview.13', '16.0-preview.12', '16.0-preview.11', '16.0-preview.10', '16.0-preview.9', '16.0-preview.8', '16.0-preview.7', '16.0-preview.6', '16.0-preview.5', '16.0-preview.4', '16.0-preview.3', '16.0-preview.2', '15.0-preview.1', '15.0-preview.2', '15.0-preview.3', '15.0-preview.4', '15.0-preview.5', '16.0-preview.1'}
IDS = ('vm-left', 'vm-right')
NAMES = dict(zip(IDS, ('MFFLocDao', 'LCDLocDao')))
MAX_VMS = 50
MAX_PAIRS = 20
MAX_AGE_MS = 4000


def protect(data: bytes, decrypt=False) -> bytes:
    """DPAPI CurrentUser: credentials never persist as plaintext."""
    if os.name != 'nt':
        raise RuntimeError('Credential persistence requires Windows DPAPI.')
    from ctypes import wintypes
    class Blob(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_byte))]
    buf = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte)))
    target = Blob()
    crypt32 = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    kernel32.LocalFree.restype = ctypes.c_void_p
    fn = crypt32.CryptUnprotectData if decrypt else crypt32.CryptProtectData
    fn.argtypes = [ctypes.POINTER(Blob), ctypes.c_void_p, ctypes.c_void_p,
                   ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
    fn.restype = wintypes.BOOL
    if not fn(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(target)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(target.data, target.size)
    finally:
        kernel32.LocalFree(ctypes.cast(target.data, ctypes.c_void_p))


def atomic_write(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_bytes(value)
    os.replace(temp, path)


def parse_enrollment(code, slot=None):
    try:
        value = json.loads(base64.b64decode(code.strip(), validate=True))
    except Exception as exc:
        raise ValueError('Paste the complete connection code from this VM.') from exc
    identity = str(value.get('id', ''))
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,47}', identity):
        raise ValueError('Invalid VM identity.')
    if slot is not None and identity != slot:
        raise ValueError('Connection code belongs to another VM.')
    slot = identity
    name = str(value.get('name') or NAMES.get(slot, slot)).strip()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 _.\-]{0,39}', name):
        raise ValueError('VM name must be 1–40 letters, numbers, spaces, dots, hyphens or underscores.')
    host = str(value.get('host', '')).strip()
    if not re.fullmatch(r'[A-Za-z0-9.:-]{1,253}', host):
        raise ValueError('Invalid VM address.')
    pin = str(value.get('pin', '')).lower()
    token = str(value.get('token', ''))
    if not re.fullmatch(r'[0-9a-f]{64}', pin) or not re.fullmatch(r'[0-9a-f]{64}', token):
        raise ValueError('Connection code has an invalid certificate or credential.')
    port = int(value.get('port', 0))
    if port < 1024 or port > 65535:
        raise ValueError('Invalid VM port.')
    return dict(id=slot, name=name, host=host, port=port, pin=pin, token=token)


def agent_call(config, command, body=None, timeout=5, request_id=None):
    """Pin the TLS certificate BEFORE transmitting any authentication material."""
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE  # Explicit certificate pin below replaces CA verification.
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    start = time.monotonic()
    with socket.create_connection((config['host'], config['port']), timeout=4) as raw:
        with context.wrap_socket(raw, server_hostname=config['host']) as conn:
            actual = hashlib.sha256(conn.getpeercert(binary_form=True)).hexdigest()
            if not hmac.compare_digest(actual, config['pin']):
                raise ValueError('VM certificate changed. Re-import its connection code locally.')
            conn.settimeout(timeout)
            envelope = '\n'.join((config['token'], request_id or uuid.uuid4().hex,
                                  command, json.dumps(body or {}, separators=(',', ':'), allow_nan=False))) + '\n'
            conn.sendall(envelope.encode('utf-8'))
            with conn.makefile('rb') as reader:
                line = reader.readline(65537)
            if not line.endswith(b'\n') or len(line) > 65536:
                raise ValueError('Invalid VM reply.')
            result = json.loads(line)
            if not isinstance(result, dict):
                raise ValueError('Invalid VM reply.')
    result['_rttMs'] = round((time.monotonic() - start) * 1000)
    return result


class Center:
    def __init__(self, directory, transport=agent_call, persist=True):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.transport, self.persist = transport, persist
        self.lock = threading.RLock()
        self.operation = threading.Lock()
        self.pool = ThreadPoolExecutor(max_workers=6, thread_name_prefix='vm')
        self.close_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix='close')
        self.poll_locks = {slot:threading.Lock() for slot in IDS}
        self.stop = threading.Event()
        self.config = {}
        self.pair = IDS
        self.poll_threads = {}
        self.closed_sequence = 0
        self.sync_dispatch = 0
        self.account_refresh = {}
        self.opened_ids = set()
        self.binding_id = None
        self.observations = {}
        self.last_good = {}
        self.discovery_until = 0
        self.events = deque(maxlen=150)
        self.jobs = deque(maxlen=50)
        self.prepared = None
        self.active = False
        self.generation = 0
        self.settings = dict(ticker='NQ SEP26', stopLoss=0, profit=0, accounts={}, quantities={})
        self.last_positions = {}
        self.logger = logging.getLogger('center-' + uuid.uuid4().hex)
        self.logger.setLevel(logging.INFO)
        handler = RotatingFileHandler(self.directory / 'activity.log', maxBytes=1_000_000, backupCount=3, encoding='utf8')
        handler.setFormatter(logging.Formatter('%(asctime)sZ %(message)s'))
        handler.formatter.converter = time.gmtime
        self.logger.addHandler(handler)
        path = self.directory / 'connections.dpapi'
        if persist and path.exists():
            self.config = json.loads(protect(path.read_bytes(), decrypt=True))
        fleet_path = self.directory / 'fleet.json'
        if fleet_path.exists():
            saved = json.loads(fleet_path.read_text())
            self.pair = tuple(saved.get('pair', IDS))
            self.settings.update(saved.get('settings', {}))
        for slot, config in self.config.items():
            config.setdefault('name', NAMES.get(slot, slot))
            self.poll_locks.setdefault(slot, threading.Lock())
        self.active = (self.directory / 'entry-unresolved.json').exists()
        if self.active:
            marker = json.loads((self.directory / 'entry-unresolved.json').read_text())
            self.pair = tuple(marker.get('pair', self.pair))
        self.event('Coordinator started. Prepare is required before entry.')

    def name(self, slot):
        return self.config.get(slot, {}).get('name', NAMES.get(slot, slot))

    def save_fleet(self):
        atomic_write(self.directory / 'fleet.json', json.dumps({'pair':self.pair, 'settings':self.settings}).encode())

    def mark_active(self):
        atomic_write(self.directory / 'entry-unresolved.json', json.dumps({'pair':self.pair, 'requested':time.time()}).encode())

    def reset_closed(self, message):
        self.active = False
        self.prepared = None
        export_id = self.binding_id if self.opened_ids else None
        self.opened_ids.clear()
        self.closed_sequence += 1
        self.sync_dispatch += len(self.pair)
        self.discovery_until = time.monotonic() + 280
        for slot in self.pair:
            self.account_refresh[slot] = 'Waiting for post-trade sync' if export_id else 'Refreshing accounts'
            self.pool.submit(self.post_trade, slot, export_id)
        (self.directory / 'entry-unresolved.json').unlink(missing_ok=True)
        self.event(message)

    def wait_refresh_idle(self, slot, timeout=130):
        deadline = time.monotonic() + timeout
        while not self.stop.is_set() and time.monotonic() < deadline:
            self.observe(slot)
            with self.lock:
                agent = self.view_agent(slot)
                if self.active:
                    raise ValueError('Pair activity changed; automatic refresh stopped.')
                if self.safe_flat(agent):
                    return
                if agent['fresh'] and agent['position'] != 'Flat':
                    raise ValueError('Position is no longer Flat; automatic refresh stopped.')
            self.stop.wait(.5)
        raise ValueError('Account refresh could not verify an idle VM. Use Refresh accounts to retry.')

    def post_trade(self, slot, trade_id):
        try:
            if trade_id:
                try:
                    self.call(slot, 'post_trade', {'tradeId':trade_id}, 15)
                    self.event(f'{self.name(slot)} post-trade export queued.')
                except Exception:
                    self.event(f'{self.name(slot)} export could not start. Refresh sync on that VM.')
            self.wait_refresh_idle(slot)
            with self.lock:
                self.account_refresh[slot] = 'Refreshing accounts'
            self.call(slot, 'accounts', {}, 15)
            self.wait_refresh_idle(slot)
            with self.lock:
                self.account_refresh[slot] = 'Account refresh finished'
            self.event(f'{self.name(slot)} account refresh finished. Select accounts and Prepare & Verify.')
        except Exception as exc:
            with self.lock:
                self.account_refresh[slot] = 'Refresh needs attention: ' + str(exc)[:200]
            self.event(f'{self.name(slot)} automatic account refresh needs attention. Use Refresh accounts to retry.')
        finally:
            with self.lock: self.sync_dispatch -= 1

    def reconcile_closed(self):
        if (not self.active or self.operation.locked() or not set(self.pair).issubset(self.opened_ids)
                or any(j['command']=='close' and j['status']=='running' for j in self.jobs)):
            return
        if all(self.safe_flat(self.view_agent(slot)) for slot in self.pair):
            self.reset_closed('Both positions verified Flat. Dashboard reset; check working orders and Prepare for the next trade.')

    def select_pair(self, left, right):
        if not self.operation.acquire(blocking=False):
            raise ValueError('Wait for the current operation.')
        try:
            with self.lock:
                if self.active:
                    raise ValueError('Close and verify the current pair before changing VMs.')
                if left == right or left not in self.config or right not in self.config:
                    raise ValueError('Choose two different registered VMs.')
                if not all(self.safe_flat(self.view_agent(slot)) for slot in (left, right)):
                    raise ValueError('Both selected VMs must be fresh, Flat, and idle.')
                if not all(self.safe_flat(self.view_agent(slot)) for slot in self.pair if slot in self.config):
                    raise ValueError('Verify the previous pair is fresh, flat and idle before changing VMs.')
                outgoing = tuple(slot for slot in self.pair if slot in self.config)
                generation = self.generation
                self.prepared = None
            # Do not block status publication while the outgoing agents acknowledge.
            invalidations = [self.pool.submit(self.call, slot, 'invalidate', {}, 10) for slot in outgoing]
            for future in invalidations:
                future.result()
            with self.lock:
                self.assert_generation(generation)
                if self.active or not all(self.safe_flat(self.view_agent(slot)) for slot in (left, right)):
                    raise ValueError('Pair readiness changed. Check both selected VMs and retry selection.')
                self.pair = (left, right)
                self.prepared = None
                self.binding_id = None
                self.opened_ids.clear()
                self.generation += 1
                self.save_fleet()
                self.event(f'Pair selected: {self.name(left)} / {self.name(right)}. Prepare is required.')
        finally:
            self.operation.release()

    def event(self, text):
        # Callers supply bounded messages; do not log request bodies or enrollment codes.
        text = str(text)[:700]
        with self.lock:
            self.events.appendleft(dict(time=time.strftime('%H:%M:%S', time.gmtime()), message=text))
        self.logger.info(text)

    def observe(self, slot):
        with self.poll_locks[slot]:
            self._observe(slot)

    def _observe(self, slot):
        with self.lock:
            config = self.config.get(slot)
        if not config:
            return
        try:
            response = self.transport(config, 'status')
            state = response.get('state', {})
            total_age = float(response.get('cacheAgeMs', 999999)) + float(state.get('sampleAgeMs', 999999)) + response.get('_rttMs', 0)
            valid = response.get('ok') and state.get('id') == slot and state.get('controlVersion') in AGENT_VERSIONS
            fresh = bool(valid and state.get('ok') and math.isfinite(total_age) and 0 <= total_age < MAX_AGE_MS)
            observation = dict(online=bool(valid), fresh=fresh, received=time.monotonic(),
                               ageMs=total_age if math.isfinite(total_age) else 999999,
                               rttMs=response.get('_rttMs'), state=state if valid else {},
                               error='' if valid else 'Agent identity/version mismatch; install V15 on this VM before using multiple pairs.')
        except Exception as exc:
            observation = dict(online=False, fresh=False, received=time.monotonic(), ageMs=999999,
                               state={}, rttMs=None, error=f'Connection unavailable ({type(exc).__name__}).')
        with self.lock:
            if self.config.get(slot) == config:
                self.observations[slot] = observation
                if observation['fresh']:
                    self.last_good[slot] = dict(observation['state'])
                    position = observation['state'].get('position')
                    if self.last_positions.get(slot) != position:
                        self.last_positions[slot] = position
                        self.event(f'{self.name(slot)} position observed: {position}.')
                    if position and position not in ('Flat', 'Unknown') and slot in self.pair:
                        self.active = True
                        self.opened_ids.add(slot)
                        marker = self.directory / 'entry-unresolved.json'
                        if not marker.exists():
                            self.mark_active()
                self.reconcile_closed()
                if slot in self.pair and not observation['fresh'] and not self.active:
                    self.prepared = None

    def loop(self, slot):
        while not self.stop.is_set():
            self.observe(slot)
            self.stop.wait(1)

    def start(self):
        with self.lock:
            for slot in self.config:
                self.poll_locks.setdefault(slot, threading.Lock())
                if slot not in self.poll_threads:
                    thread = threading.Thread(target=self.loop, args=(slot,), daemon=True)
                    self.poll_threads[slot] = thread
                    thread.start()

    def view_agent(self, slot):
        o = self.observations.get(slot, {})
        age = o.get('ageMs', 999999) + (time.monotonic() - o.get('received', time.monotonic())) * 1000
        fresh = bool(o.get('fresh') and age < MAX_AGE_MS)
        s = o.get('state', {})
        cached = self.last_good.get(slot, {}).copy()
        raw_accounts=s.get('accounts') or cached.get('accounts', ['Sim101'])
        if cached:
            cached['account']=account_id(cached.get('account'))
            cached['accounts']=account_list(cached.get('accounts', ['Sim101']))
        return dict(id=slot, name=self.name(slot), configured=slot in self.config,
                    online=bool(o.get('online') and time.monotonic() - o.get('received', 0) < 7), fresh=fresh,
                    ageMs=round(age), rttMs=o.get('rttMs'), position=s.get('position') if fresh else 'Unknown',
                    account=account_id(s.get('account')) if fresh else None, quantity=s.get('quantity') if fresh else None,
                    ticker=s.get('ticker') if fresh else None, prepared=bool(fresh and s.get('prepared')),
                    prepareId=s.get('prepareId') if fresh else None,
                    scheduled=bool(s.get('scheduled')), busy=bool(s.get('busy')),
                    pairActive=bool(s.get('pairActive')), pending=bool(s.get('pendingVerification')), closing=bool(s.get('closing')),
                    stopLoss=s.get('stopLoss'), profit=s.get('profit'),
                    message=o.get('error') or s.get('message', ''),
                    execution=s.get('execution', ''), sampleUtc=s.get('sampleUtc'),
                    snapshotHeld=bool(cached and not self.active and not self.prepared), lastKnown=cached, accounts=account_list(raw_accounts), rawAccounts=raw_accounts, accountMessage=s.get('accountMessage', ''), sync=s.get('sync', ''),
                    calibrationRequired=bool(s.get('calibrationRequired')), accountRefreshId=s.get('accountRefreshId'), queueAccountRefresh=bool(s.get('queueAccountRefresh')), syncReceipt=s.get('syncReceipt'), queueReceipts=bool(s.get('queueReceipts')),
                    selectedAccount=account_id(s.get('selectedAccount', 'Sim101')), selectedQuantity=s.get('selectedQuantity', 1))

    def safe_flat(self, agent):
        return (agent['fresh'] and bool(agent['account'])
                and agent['position'] == 'Flat' and not agent['scheduled'] and not agent['busy']
                and not agent['pairActive'] and not agent['pending'] and not agent.get('closing'))

    def release_flat(self, agent):
        # A retained pairActive flag is cleared by an authenticated unbind after local Flat readback.
        return (agent['fresh'] and agent['position'] == 'Flat'
                and not any(agent.get(k) for k in ('scheduled','busy','pending','closing')))

    def target_matches(self, agent):
        return (agent['account'] == self.settings.get('accounts', {}).get(agent['id'], 'Sim101')
                and str(agent['quantity']) == str(self.settings.get('quantities', {}).get(agent['id'], 1)))

    def state(self):
        with self.lock:
            self.reconcile_closed()
            agents = [self.view_agent(slot) for slot in self.pair]
            ready = bool(self.prepared and not self.active and not self.operation.locked()
                         and all(self.safe_flat(a) and self.target_matches(a) and a['prepared'] and a['prepareId'] == self.prepared for a in agents))
            return dict(version=VERSION, agents=agents, settings=self.settings.copy(), canEnter=ready,
                        prepared=bool(self.prepared), active=self.active, busy=self.operation.locked() or self.sync_dispatch > 0,
                        events=list(self.events), jobs=list(self.jobs), serverTime=time.time(),
                        fleet=[self.view_agent(slot) for slot in self.config], pair=list(self.pair), closedSequence=self.closed_sequence, accountRefresh=self.account_refresh.copy())

    def enroll(self, slot, code):
        value = parse_enrollment(code, slot)
        slot = value['id']
        if not self.operation.acquire(blocking=False):
            raise ValueError('Wait for the current operation to finish.')
        try:
            with self.lock:
                if self.active:
                    raise ValueError('Verify the current pair is flat before changing connections.')
                if slot not in self.config and len(self.config) >= MAX_VMS:
                    raise ValueError(f'This release supports up to {MAX_VMS} registered VMs.')
                others = [x for k, x in self.config.items() if k != slot]
                if any(x.get('name', '').casefold() == value['name'].casefold() for x in others):
                    raise ValueError('Choose a unique VM name.')
                if any(x['pin'] == value['pin'] or (x['host'], x['port']) == (value['host'], value['port']) for x in others):
                    raise ValueError('Each registration must represent a different VM agent.')
                self.config[slot] = value
                self.poll_locks.setdefault(slot, threading.Lock())
                self.prepared = None
                self.observations.pop(slot, None)
                if self.persist:
                    atomic_write(self.directory / 'connections.dpapi', protect(json.dumps(self.config).encode()))
            self.event(f'{self.name(slot)} connection saved. Checking agent identity.')
            if self.persist:
                self.start()
        finally:
            self.operation.release()

    def call(self, slot, command, body=None, timeout=75):
        with self.lock:
            config = self.config.get(slot)
        if not config:
            raise ValueError(f'{self.name(slot)} is not connected.')
        response = self.transport(config, command, body or {}, timeout=timeout)
        if not response.get('ok'):
            # Agent-authenticated messages contain UI errors, never credentials.
            raise ValueError(f"{self.name(slot)}: {str(response.get('message', 'Command rejected'))[:400]}")
        return response

    def refresh_both(self):
        futures = [self.pool.submit(self.observe, slot) for slot in self.pair]
        for f in futures:
            f.result()

    def submit(self, command, body):
        if self.sync_dispatch and command != 'close':
            raise ValueError('Post-trade sync and account refresh are running. Wait for their status.')
        if command not in ('prepare', 'buy', 'sell', 'close', 'ack_flat', 'accounts'):
            raise ValueError('Unknown action.')
        if command != 'close' and not self.operation.acquire(blocking=False):
            raise ValueError('An operation is already running.')
        with self.lock:
            if command == 'close':
                if any(j['command'] == 'close' and j['status'] == 'running' for j in self.jobs):
                    raise ValueError('Close verification is already running; see each VM result.')
                self.generation += 1
                self.prepared = None
                self.active = True
                self.mark_active()
            job = dict(id=uuid.uuid4().hex, command=command, status='running', message='Requested')
            self.jobs.appendleft(job)
            generation = self.generation
        threading.Thread(target=self.run_job, args=(job, command, body, generation), daemon=True).start()
        return job['id']

    def run_job(self, job, command, body, generation):
        try:
            self.event(f'{command.upper()} requested.')
            if command == 'accounts':
                with self.lock: self.account_refresh.clear()
                self.discovery_until = time.monotonic() + 130
                self.prepared = None
                if self.active: raise ValueError('Close and verify this pair before refreshing accounts.')
                requests = {slot:self.pool.submit(self.call, slot, 'accounts', {}, 15) for slot in self.pair}
                errors = []
                for slot, future in requests.items():
                    try: future.result()
                    except Exception as exc: errors.append(f'{self.name(slot)}: {exc}')
                if errors: raise ValueError('; '.join(errors))
                self.event('Account refresh started on both VMs. Lists update when discovery finishes.')
            elif command == 'prepare':
                self.prepare(body, generation)
            elif command in ('buy', 'sell'):
                self.entry(command, generation)
            elif command == 'close':
                self.close_both()
            else:
                self.refresh_both()
                if not all(self.safe_flat(a) for a in self.state()['agents']):
                    raise ValueError('Both agents must report fresh Flat with no trading or sync operation in progress.')
                with self.lock:
                    self.reset_closed('Both positions verified Flat; dashboard reset for the next preparation.')
            with self.lock:
                job.update(status='done', message='Completed; see observations and activity log.')
        except Exception as exc:
            with self.lock:
                self.prepared = None
                job.update(status='error', message=str(exc)[:500])
            self.event(str(exc))
        finally:
            if command != 'close':
                self.operation.release()

    def assert_generation(self, generation):
        with self.lock:
            if generation != self.generation:
                raise ValueError('Operation cancelled by Close Both; prepare again.')

    def prepare(self, body, generation):
        ticker = str(body.get('ticker', '')).strip().upper()
        if not re.fullmatch(r'[A-Z0-9][A-Z0-9 .\-/]{0,29}', ticker):
            raise ValueError('Enter the NinjaTrader instrument, for example MNQ 09-26.')
        stop, profit, right_stop, right_profit = pair_amounts(body)
        accounts, quantities = {}, {}
        for slot in self.pair:
            account = body.get('accounts', {}).get(slot, 'Sim101')
            quantity = body.get('quantities', {}).get(slot, 1)
            if not isinstance(account, str) or not account or len(account) > 120:
                raise ValueError('Select an available account for each VM.')
            if type(quantity) is not int or not 1 <= quantity <= 1000:
                raise ValueError('Quantity must be a whole number from 1 to 1000.')
            accounts[slot], quantities[slot] = account, quantity
        validate_quantities(dict(body, quantities=quantities), *self.pair)
        with self.lock:
            if self.active:
                raise ValueError('Verify Both Flat before preparing another pair.')
            self.prepared = None
            self.settings = dict(ticker=ticker, stopLoss=stop, profit=profit, ratio=body.get('ratio', '1:1'), accounts=accounts, quantities=quantities)
        self.refresh_both()
        if not all(self.safe_flat(a) for a in self.state()['agents']):
            raise ValueError('Both VMs must report fresh Flat, with no pending action.')
        self.assert_generation(generation)
        raw_accounts={slot:trading_name(accounts[slot],self.view_agent(slot)['rawAccounts']) for slot in self.pair}
        binding = uuid.uuid4().hex
        bindings = []
        for slot, peer in (self.pair, self.pair[::-1]):
            peer_config = self.config[peer].copy()
            peer_config['name'] = self.name(peer)
            bindings.append(self.pool.submit(self.call, slot, 'bind_peer', {'peer':peer_config,'bindingId':binding, 'peerAccount':raw_accounts[peer], 'peerQuantity':quantities[peer]}))
        errors = []
        for future in bindings:
            try: future.result()
            except Exception as exc: errors.append(str(exc))
        if errors: raise ValueError('; '.join(errors))
        self.assert_generation(generation)
        self.binding_id = binding
        self.save_fleet()
        prepare_id = uuid.uuid4().hex
        def one(slot, sl, pt):
            return self.call(slot, 'prepare', dict(ticker=ticker, stopLoss=sl, profit=pt, prepareId=prepare_id, account=raw_accounts[slot], quantity=quantities[slot]))
        results = [self.pool.submit(one, self.pair[0], stop, profit), self.pool.submit(one, self.pair[1], right_stop, right_profit)]
        errors = []
        for slot, result in zip(self.pair, results):
            try:
                result.result()
                self.event(f'{self.name(slot)} preparation acknowledged; verifying observations.')
            except Exception as exc:
                errors.append(str(exc))
        self.assert_generation(generation)
        if errors:
            raise ValueError('; '.join(errors))
        # Obtain observations after the agent's next cache publication.
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            self.assert_generation(generation)
            self.refresh_both()
            agents = self.state()['agents']
            if all(self.safe_flat(a) and self.target_matches(a) and a['prepared'] and a['prepareId'] == prepare_id for a in agents):
                if [(float(a['stopLoss']), float(a['profit'])) for a in agents] != [(stop, profit), (right_stop, right_profit)]:
                    raise ValueError('Mirrored stop-loss/profit readback does not match.')
                with self.lock:
                    self.assert_generation(generation)
                    self.prepared = prepare_id
                self.event('Both VMs prepared. Mirrored currency amounts verified. Entry is available.')
                return
            self.stop.wait(.5)
        raise ValueError('Preparation acknowledgement received, but fresh readiness was not verified.')

    def entry(self, side, generation):
        with self.lock:
            prepared = self.prepared
            if not prepared or self.active:
                raise ValueError('Prepare and verify both VMs before entry.')
        # Read-only authenticated checks in both directions, before marking entry active.
        checks={slot:self.pool.submit(self.call,slot,'peer_check',{'prepareId':prepared},35) for slot in self.pair}
        errors=[]
        for slot,future in checks.items():
            try: future.result()
            except Exception as exc: errors.append(self.name(slot)+': '+str(exc))
        if errors:
            raise ValueError('Peer connection check failed; no entry sent. Update both agents to Preview 19 and verify their direct connection. '+'; '.join(errors))
        self.event('Direct peer connection verified in both directions. Rechecking readiness before entry.')
        self.refresh_both()
        if not all(self.safe_flat(a) and self.target_matches(a) and a['prepared'] and a['prepareId'] == prepared for a in self.state()['agents']):
            raise ValueError('Readiness changed. Prepare both VMs again.')
        self.assert_generation(generation)
        with self.lock:
            self.assert_generation(generation)
            self.active = True
            self.prepared = None
            self.opened_ids.clear()
            self.mark_active()
        try:
            # ONE paired entry request to the selected left VM: retain the V10.4 arm/commit and peer monitoring.
            # Never retry an entry following a lost response.
            self.call(self.pair[0], 'entry', dict(side=side.upper(), prepareId=prepared), timeout=30)
            self.assert_generation(generation)
            self.event(f'Pair entry accepted by {self.name(self.pair[0])}. Waiting for actual position observations; acceptance is not a fill.')
        except Exception as exc:
            self.event('Entry outcome uncertain. Requesting recovery close on both VMs.')
            with self.lock:
                self.generation += 1
            self.close_both()
            raise ValueError(f'Entry did not complete normally: {exc}') from exc

    def close_both(self):
        # Independent requests: a failed VM must not prevent the other request.
        futures = {slot:self.close_pool.submit(self.call, slot, 'close', {}, 30) for slot in self.pair}
        for slot, future in futures.items():
            try:
                future.result()
                self.event(f'{self.name(slot)} close acknowledged. Awaiting Flat observation.')
            except Exception as exc:
                self.event(f'{self.name(slot)} close outcome unknown: {exc}')
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            self.refresh_both()
            agents = self.state()['agents']
            if all(self.safe_flat(a) for a in agents):
                with self.lock:
                    self.reset_closed('Both positions independently verified Flat. Dashboard reset; prepare again before entry.')
                return
            self.stop.wait(.6)
        raise ValueError('Close not verified on both VMs. Check both NinjaTrader windows manually.')


class Fleet:
    """One coordinator registry; each immutable pair owns an independent Center.

    Fleet lock orders before any Center lock. Pair jobs never acquire fleet lock.
    Poll locks are shared by VM, and only one background poller exists per VM.
    """
    def __init__(self, directory, transport=agent_call, persist=True):
        self.directory = Path(directory)
        self.catalog = Center(directory, transport, persist)
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.pairs = {}
        self.owners = {}
        self.threads = {}
        self.retired = []
        self.releasing = set()
        self.vm_refresh = {}
        self.persist = persist
        self.transport = transport
        self.started = False
        self.global_events = deque(maxlen=50)
        self.index_path = self.directory / 'pairs-v13.json'
        if self.index_path.exists():
            records = json.loads(self.index_path.read_text())
            for record in records:
                self._load_pair(record['id'], tuple(record['members']))
        else:
            # Migrate the former single pair, preserving any unresolved-entry lock.
            members = self.catalog.pair
            if len(members) == 2 and (self.catalog.active or all(slot in self.catalog.config for slot in members)):
                pair = self._load_pair(uuid.uuid4().hex, members)
                pair.settings = self.catalog.settings.copy()
                pair.active = self.catalog.active
                if pair.active:
                    pair.mark_active()
                pair.save_fleet()
            self.save_index()
        # A retained root marker protects a V12 rollback; V15 uses per-pair markers.
        self.catalog.pair = ()
        self.catalog.active = False

    def _load_pair(self, identity, members):
        if not re.fullmatch('[a-f0-9]{32}', identity) or len(members) != 2 or members[0] == members[1]:
            raise ValueError('Invalid saved pair. Restore the coordinator configuration backup.')
        if any(slot in self.owners for slot in members):
            raise ValueError('Saved pairs share a VM. Restore the coordinator configuration backup.')
        pair = Center(self.directory / 'pairs' / identity, self.transport, persist=False)
        if pair.active and pair.pair != members:
            raise ValueError('Unresolved pair membership differs from its saved reservation.')
        pair.pair = members
        pair.config = self.catalog.config
        pair.poll_locks = self.catalog.poll_locks
        for slot in members:
            pair.poll_locks.setdefault(slot, threading.Lock())
            if slot in self.catalog.observations:
                pair.observations[slot] = self.catalog.observations[slot]
                pair.last_good[slot] = self.catalog.last_good.get(slot, {})
        self.pairs[identity] = pair
        for slot in members:
            self.owners[slot] = identity
        return pair

    def save_index(self):
        atomic_write(self.index_path, json.dumps([{'id':key,'members':pair.pair} for key,pair in self.pairs.items()]).encode())

    def get_pair(self, identity):
        if identity not in self.pairs:
            raise ValueError('Select an existing pair first.')
        return self.pairs[identity]

    def view(self, slot):
        owner = self.owners.get(slot)
        center = self.pairs[owner] if owner else self.catalog
        with center.lock:
            result = center.view_agent(slot)
        result['pairId'] = owner
        result['refresh'] = self.vm_refresh.get(slot, {}).copy()
        return result

    def create_pair(self, left, right):
        # Network I/O stays outside the fleet lock so other pairs keep monitoring.
        with self.lock:
            if any(self.vm_refresh.get(s,{}).get('status')=='running' for s in (left,right)):
                raise ValueError('VM account refresh is running. Wait for it to finish.')
            if left == right or left not in self.catalog.config or right not in self.catalog.config:
                raise ValueError('Choose two different registered VMs.')
            for identity, pair in self.pairs.items():
                if pair.pair == (left, right):
                    return identity
            if left in self.owners or right in self.owners:
                raise ValueError('A selected VM belongs to another pair. Release that pair first.')
        requests = [self.catalog.pool.submit(self.catalog.observe, slot) for slot in (left, right)]
        for request in requests:
            request.result()
        # Recheck reservations after the requests: another browser may have paired a VM.
        with self.lock:
            if any(self.vm_refresh.get(s,{}).get('status')=='running' for s in (left,right)):
                raise ValueError('VM account refresh is running. Wait for it to finish.')
            if left == right or left not in self.catalog.config or right not in self.catalog.config:
                raise ValueError('Choose two different registered VMs.')
            for identity,pair in self.pairs.items():
                if pair.pair == (left, right):
                    return identity
            if len(self.pairs) >= MAX_PAIRS:
                raise ValueError(f'Up to {MAX_PAIRS} pairs can be assigned simultaneously. Release an idle pair to create another.')
            if left in self.owners or right in self.owners:
                raise ValueError('A selected VM belongs to another pair. Close, verify and release that pair first.')
            if not all(self.catalog.safe_flat(self.view(slot)) for slot in (left, right)):
                raise ValueError('New pair requires two fresh, idle Flat agents.')
            identity = uuid.uuid4().hex
            pair = self._load_pair(identity, (left, right))
            try:
                pair.save_fleet()
                self.save_index()
            except Exception:
                del self.pairs[identity]
                for slot in (left, right):
                    del self.owners[slot]
                self.retired.append(pair)
                raise
            pair.event('Pair created. Prepare & Verify is required before entry.')
            return identity

    def release_pair(self, identity):
        with self.lock:
            pair = self.get_pair(identity)
            if identity in self.releasing or not pair.operation.acquire(blocking=False):
                raise ValueError('Wait for this pair operation to finish.')
            self.releasing.add(identity)
            generation = pair.generation
        try:
            with pair.lock:
                if pair.sync_dispatch or any(j['status']=='running' for j in pair.jobs):
                    raise ValueError('Wait for the current pair operation to finish, then release.')
            pair.refresh_both()
            agents = pair.state()['agents']
            def releasable(items):
                return (any(pair.release_flat(a) for a in items)
                        and all(pair.release_flat(a) or (not a['fresh'] and not any(a[k] for k in ('busy','scheduled','pending','closing'))) for a in items))
            if not releasable(agents):
                raise ValueError('Release requires idle Flat / Flat or Flat / Unknown status.')
            verified_slots = [a['id'] for a in agents if pair.release_flat(a)]
            futures = [pair.pool.submit(pair.call, slot, 'unbind_peer', {}, 10) for slot in verified_slots]
            for future in futures:
                future.result()
            pair.refresh_both()
            with self.lock, pair.lock:
                pair.prepared = None
                pair.assert_generation(generation)
                if not releasable(pair.state()['agents']):
                    raise ValueError('Pair readiness changed; release blocked.')
                if len(verified_slots) != 2:
                    pair.event('Pair assignment released with an Unknown VM. Its remote position and binding were not verified or closed.')
                pair.active = False
                (pair.directory / 'entry-unresolved.json').unlink(missing_ok=True)
                pair.generation += 1
                del self.pairs[identity]
                try:
                    self.save_index()
                except Exception:
                    self.pairs[identity] = pair
                    raise
                for slot in pair.pair:
                    self.catalog.observations[slot] = pair.observations.get(slot, {})
                    self.catalog.last_good[slot] = pair.last_good.get(slot, {})
                    self.owners.pop(slot, None)
                self.retired.append(pair)
                pair.pool.shutdown(wait=False)
                pair.close_pool.shutdown(wait=False)
        finally:
            with self.lock:
                self.releasing.discard(identity)
                pair.operation.release()

    def enroll(self, slot, code):
        value = parse_enrollment(code, slot)
        with self.lock:
            owner = self.owners.get(value['id'])
            if owner:
                # V15 network migration may update only the address of the same idle, authenticated VM.
                pair = self.get_pair(owner)
                old = self.catalog.config.get(value['id'], {})
                same_identity = all(old.get(k) == value.get(k) for k in ('id','name','pin','token','port'))
                try: private = ipaddress.ip_address(value['host']) in ipaddress.ip_network('100.64.0.0/10')
                except ValueError: private = False
                if not same_identity or not private or not pair.operation.acquire(blocking=False):
                    raise ValueError('Release this VM from its pair before changing its identity. Network migration requires the same VM credentials.')
                try:
                    with pair.lock:
                        if pair.sync_dispatch or any(j['status']=='running' for j in pair.jobs):
                            raise ValueError('Wait for the current pair operation before updating its network registration.')
                    response = self.transport(value, 'status', timeout=5)
                    state = response.get('state', {})
                    age = float(response.get('cacheAgeMs',999999)) + float(state.get('sampleAgeMs',999999)) + float(response.get('_rttMs',0))
                    if not (response.get('ok') and state.get('ok') and state.get('id') == value['id']
                            and state.get('controlVersion') in AGENT_VERSIONS and 0 <= age < MAX_AGE_MS
                            and state.get('position') == 'Flat' and state.get('account')
                            and not any(state.get(k) for k in ('busy','scheduled','pairActive','pendingVerification','closing'))):
                        raise ValueError('The new private endpoint must report fresh, idle Flat status before registration changes.')
                    with pair.lock:
                        # Restore reachability without clearing an unresolved trade or releasing ownership.
                        # The authenticated new endpoint has reported fresh, idle Flat above.
                        updated = dict(self.catalog.config);updated[value['id']] = value
                        if self.persist:
                            atomic_write(self.directory / 'connections.dpapi', protect(json.dumps(updated).encode()))
                        self.catalog.config[value['id']] = value
                        pair.config[value['id']] = value
                        pair.prepared = None;pair.generation += 1
                        pair.observations.pop(value['id'], None)
                        self.catalog.observations.pop(value['id'], None)
                        pair.event('Private network address updated for '+value['name']+'. Prepare again before entry.')
                    return
                finally:
                    pair.operation.release()
            # Center.enroll persists credentials. Fleet supplies its own pollers.
            old_persist = self.catalog.persist
            self.catalog.persist = False
            try:
                old = self.catalog.config.get(value['id'])
                self.catalog.enroll(slot, code)
                if self.persist:
                    try:
                        atomic_write(self.directory / 'connections.dpapi', protect(json.dumps(self.catalog.config).encode()))
                    except Exception:
                        if old is None: self.catalog.config.pop(value['id'], None)
                        else: self.catalog.config[value['id']] = old
                        raise
            finally:
                self.catalog.persist = old_persist
            if self.started:
                self.start()

    def invalidate(self, identity):
        with self.lock:
            pair = self.get_pair(identity)
            with pair.lock:
                pair.prepared = None
                pair.generation += 1

    def submit(self, command, body):
        with self.lock:
            pair = self.get_pair(body.get('pairId'))
            return pair.submit(command, body)

    def close_all(self):
        results = {}
        with self.lock:
            # Submission starts independent threads; do not wait for any close reply.
            for identity,pair in self.pairs.items():
                try:
                    results[identity] = {'job':pair.submit('close', {})}
                except ValueError as exc:
                    results[identity] = {'error':str(exc)}
            self.global_events.appendleft({'time':time.strftime('%H:%M:%S', time.gmtime()),
                'message':f'Close All Pairs requested for {len(results)} pairs. Verify each result separately.'})
        return {'ok':True, 'pairs':results}

    def state(self):
        with self.lock:
            states = []
            for identity,pair in self.pairs.items():
                state = pair.state()
                state['id'] = identity
                state['name'] = ' / '.join(pair.name(slot) for slot in pair.pair)
                states.append(state)
            return {'version':VERSION, 'pairs':states, 'limits':{'vms':MAX_VMS,'pairs':MAX_PAIRS},
                    'fleet':[self.view(slot) for slot in self.catalog.config],
                    'events':list(self.global_events), 'serverTime':time.time()}

    def observe(self, slot):
        with self.lock:
            owner = self.owners.get(slot)
            center = self.pairs[owner] if owner else self.catalog
        center.observe(slot)

    def refresh_vm(self, slot):
        with self.lock:
            if slot not in self.catalog.config: raise ValueError('Choose a registered VM.')
            if self.vm_refresh.get(slot,{}).get('status')=='running': return
            owner=self.owners.get(slot)
            center=self.pairs[owner] if owner else self.catalog
            locked=False
            if owner:
                if not center.operation.acquire(blocking=False): raise ValueError('A pair operation is running. Try refresh after it finishes.')
                locked=True
                if center.active or center.prepared or center.sync_dispatch:
                    center.operation.release()
                    raise ValueError('This pair is prepared, trading or syncing. Finish it before refreshing accounts.')
            self.vm_refresh[slot]={'status':'running','message':'Checking connection and refreshing accounts…'}
        def work():
            try:
                center.observe(slot)
                with center.lock:
                    if not center.safe_flat(center.view_agent(slot)):
                        raise ValueError('VM must report fresh, idle Flat before account discovery.')
                    center.discovery_until=time.monotonic()+130
                center.call(slot,'accounts',{},15)
                # The worker publishes its account list asynchronously.
                center.stop.wait(1)
                center.wait_refresh_idle(slot)
                with center.lock:
                    view=center.view_agent(slot)
                    if not view.get('accounts'): raise ValueError('No account list returned. Check Airtable setup on this VM.')
                    message=view.get('accountMessage','')
                    if any(word in message.lower() for word in ('error','failed','unable')):
                        raise ValueError(message)
                with self.lock: self.vm_refresh[slot]={'status':'complete','message':'Accounts refreshed. '+message,'time':time.time()}
            except Exception as exc:
                with self.lock: self.vm_refresh[slot]={'status':'error','message':str(exc)[:350]}
            finally:
                if locked: center.operation.release()
        threading.Thread(target=work,daemon=True).start()

    def idle_snapshot_held(self, slot):
        with self.lock:
            owner = self.owners.get(slot)
            center = self.pairs.get(owner)
            if center is None:
                return False
            with center.lock:
                cached = center.last_good.get(slot, {})
                return (not center.active and not center.prepared and not center.sync_dispatch
                        and time.monotonic() >= center.discovery_until
                        and not any(j['status'] == 'running' for j in center.jobs)
                        and cached.get('position') == 'Flat'
                        and not any(cached.get(k) for k in ('busy','scheduled','pendingVerification','closing','pairActive')))

    def loop(self, slot):
        while not self.stop.is_set():
            if not self.idle_snapshot_held(slot):
                self.observe(slot)
            self.stop.wait(1)

    def start(self):
        with self.lock:
            self.started = True
            for slot in self.catalog.config:
                if slot not in self.threads:
                    thread = threading.Thread(target=self.loop, args=(slot,), daemon=True)
                    self.threads[slot] = thread
                    thread.start()

    def shutdown(self):
        self.stop.set()
        for center in [self.catalog, *self.pairs.values(), *self.retired]:
            center.stop.set()
            center.pool.shutdown(wait=False)
            center.close_pool.shutdown(wait=False)


class Handler(BaseHTTPRequestHandler):
    server_version = 'TradingControlCenter'
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, *_):
        pass

    def reply(self, status, value, kind='application/json; charset=utf-8'):
        data = json.dumps(value, allow_nan=False).encode() if isinstance(value, (dict, list)) else value
        self.send_response(status)
        for key, val in {'Content-Type':kind, 'Content-Length':str(len(data)), 'Cache-Control':'no-store',
                         'X-Content-Type-Options':'nosniff', 'Referrer-Policy':'no-referrer',
                         'X-Frame-Options':'DENY',
                         'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"}.items():
            self.send_header(key, val)
        self.end_headers()
        self.wfile.write(data)

    def allowed(self, auth=False, post=False):
        if self.headers.get('Host') != self.server.authority:
            self.reply(403, {'error':'Invalid host.'})
            return False
        if auth and not hmac.compare_digest(self.headers.get('X-Control-Token', ''), self.server.token):
            self.reply(401, {'error':'Open the dashboard using its desktop shortcut.'})
            return False
        if post and (self.headers.get('Origin') != 'http://' + self.server.authority or
                     self.headers.get('Content-Type', '').split(';')[0] != 'application/json'):
            self.reply(403, {'error':'Invalid request origin or content type.'})
            return False
        return True

    def do_GET(self):
        if not self.allowed(auth=self.path.startswith('/api/')):
            return
        if self.path == '/api/queue':
            self.reply(200, self.server.queue.snapshot())
            return
        if self.path == '/api/planning':
            self.reply(200, self.server.planning.snapshot())
            return
        if self.path == '/api/state':
            self.reply(200, self.server.center.state())
            return
        files = {'/':'index.html', '/app.js':'app.js', '/planning.js':'planning.js', '/queue.js':'queue.js', '/vms.js':'vms.js', '/ratio.js': 'ratio.js', '/drafts.js':'drafts.js', '/style.css':'style.css', '/favicon.svg':'favicon.svg'}
        kinds = {'.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8',
                 '.css':'text/css; charset=utf-8', '.svg':'image/svg+xml'}
        if self.path not in files:
            self.reply(404, {'error':'Not found.'})
            return
        path = ROOT / 'static' / files[self.path]
        self.reply(200, path.read_bytes(), kinds[path.suffix])

    def queue_guard(self, identity):
        queue = getattr(self.server, 'queue', None)
        if queue and queue.owned(identity):
            raise ValueError('This pair belongs to the Planning queue. Pause the queue to stop new entries; Close Pair remains available.')

    def do_POST(self):
        if not self.allowed(auth=True, post=True):
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 16384 or self.headers.get('Transfer-Encoding'):
                raise ValueError('Invalid request size.')
            body = json.loads(self.rfile.read(size))
            if not isinstance(body, dict):
                raise ValueError('Invalid request body.')
            if self.path.startswith('/api/queue/'):
                self.reply(200, self.server.queue.command(self.path.rsplit('/',1)[1], body))
            elif self.path == '/api/planning/view':
                self.server.planning.select_view(body.get('key'),body.get('link'),body.get('name',''))
                self.reply(200, {'ok':True})
            elif self.path == '/api/planning/refresh':
                self.server.planning.refresh(body.get('token'))
                self.reply(202, {'ok':True})
            elif self.path == '/api/vm-refresh':
                self.server.center.refresh_vm(body.get('id'))
                self.reply(202, {'ok':True})
            elif self.path == '/api/enroll':
                slot = body.get('id')
                self.server.center.enroll(slot, body.get('code', ''))
                self.reply(200, {'ok':True, 'id':parse_enrollment(body.get('code', ''), slot)['id']})
            elif self.path == '/api/pair':
                pair_id = self.server.center.create_pair(body.get('left'), body.get('right'))
                self.reply(200, {'ok':True, 'pairId':pair_id})
            elif self.path == '/api/invalidate':
                self.queue_guard(body.get('pairId'))
                self.server.center.invalidate(body.get('pairId'))
                self.reply(200, {'ok':True})
            elif self.path == '/api/release-pair':
                self.queue_guard(body.get('pairId'))
                self.server.center.release_pair(body.get('pairId'))
                self.reply(200, {'ok':True})
            elif self.path == '/api/close-all':
                if getattr(self.server, 'queue', None): self.server.queue.command('pause', {})
                self.reply(202, self.server.center.close_all())
            elif self.path == '/api/action':
                if body.get('command') != 'close': self.queue_guard(body.get('pairId'))
                elif getattr(self.server, 'queue', None) and self.server.queue.owned(body.get('pairId')): self.server.queue.command('pause', {})
                job = self.server.center.submit(body.get('command'), body)
                self.reply(202, {'ok':True, 'job':job})
            else:
                self.reply(404, {'error':'Not found.'})
        except (ValueError, TypeError, KeyError) as exc:
            self.reply(400, {'error':str(exc)[:500]})
        except Exception:
            self.reply(500, {'error':'Coordinator error. See the local activity log.'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    from planning import Planning
    from pair_queue import PairQueue
    center = Fleet(args.data_dir)
    server = ThreadingHTTPServer(('127.0.0.1', 8788), Handler)
    server.daemon_threads = True
    server.authority = '127.0.0.1:8788'
    server.center = center
    server.planning = Planning(args.data_dir)
    server.planning.start()
    server.queue = PairQueue(center, server.planning)
    server.queue.start()
    server.token = secrets.token_hex(32)
    url = 'http://' + server.authority + '/#' + server.token
    atomic_write(args.data_dir / 'launch.json', json.dumps({'pid':os.getpid(), 'url':url}).encode())
    center.start()
    print('Trading Control Center is running. Keep this window open. Closing the browser is OK.', flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever(poll_interval=.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.queue.close()
        server.planning.close()
        center.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
