"""Local Windows control center. Standard library only; never sends live-account orders."""
from __future__ import annotations
import argparse
import base64
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
import hmac
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

VERSION = '11.0-preview.1'
IDS = ('vm-left', 'vm-right')
NAMES = dict(zip(IDS, ('VM left', 'VM right')))
ROOT = Path(__file__).resolve().parent
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


def parse_enrollment(code, slot):
    try:
        value = json.loads(base64.b64decode(code.strip(), validate=True))
    except Exception as exc:
        raise ValueError('Paste the complete connection code from this VM.') from exc
    if value.get('id') != slot:
        raise ValueError(f'This connection code is not for {NAMES[slot]}.')
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
    return dict(id=slot, host=host, port=port, pin=pin, token=token)


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
        self.observations = {}
        self.events = deque(maxlen=150)
        self.jobs = deque(maxlen=50)
        self.prepared = None
        self.active = False
        self.generation = 0
        self.settings = dict(ticker='MNQ', stopLoss=100, profit=200)
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
        self.active = (self.directory / 'entry-unresolved.json').exists()
        self.event('Coordinator started. Prepare is required before entry.')

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
            valid = response.get('ok') and state.get('id') == slot and state.get('controlVersion') == VERSION
            fresh = bool(valid and state.get('ok') and math.isfinite(total_age) and 0 <= total_age < MAX_AGE_MS)
            observation = dict(online=bool(valid), fresh=fresh, received=time.monotonic(),
                               ageMs=total_age if math.isfinite(total_age) else 999999,
                               rttMs=response.get('_rttMs'), state=state if valid else {},
                               error='' if valid else 'Agent identity/version mismatch; install both v11 preview agents.')
        except Exception as exc:
            observation = dict(online=False, fresh=False, received=time.monotonic(), ageMs=999999,
                               state={}, rttMs=None, error=f'Connection unavailable ({type(exc).__name__}).')
        with self.lock:
            if self.config.get(slot) == config:
                self.observations[slot] = observation
                if observation['fresh']:
                    position = observation['state'].get('position')
                    if self.last_positions.get(slot) != position:
                        self.last_positions[slot] = position
                        self.event(f'{NAMES[slot]} position observed: {position}.')
                    if position != 'Flat':
                        self.active = True
                        marker = self.directory / 'entry-unresolved.json'
                        if not marker.exists():
                            atomic_write(marker, json.dumps({'observed':time.time()}).encode())
                if not observation['fresh'] and not self.active:
                    self.prepared = None

    def loop(self, slot):
        while not self.stop.is_set():
            self.observe(slot)
            self.stop.wait(1)

    def start(self):
        for slot in IDS:
            threading.Thread(target=self.loop, args=(slot,), daemon=True).start()

    def view_agent(self, slot):
        o = self.observations.get(slot, {})
        age = o.get('ageMs', 999999) + (time.monotonic() - o.get('received', time.monotonic())) * 1000
        fresh = bool(o.get('fresh') and age < MAX_AGE_MS)
        s = o.get('state', {})
        return dict(id=slot, name=NAMES[slot], configured=slot in self.config,
                    online=bool(o.get('online') and time.monotonic() - o.get('received', 0) < 7), fresh=fresh,
                    ageMs=round(age), rttMs=o.get('rttMs'), position=s.get('position') if fresh else 'Unknown',
                    account=s.get('account') if fresh else None, quantity=s.get('quantity') if fresh else None,
                    ticker=s.get('ticker') if fresh else None, prepared=bool(fresh and s.get('prepared')),
                    prepareId=s.get('prepareId') if fresh else None,
                    scheduled=bool(s.get('scheduled')), busy=bool(s.get('busy')),
                    pairActive=bool(s.get('pairActive')), pending=bool(s.get('pendingVerification')),
                    stopLoss=s.get('stopLoss'), profit=s.get('profit'),
                    message=o.get('error') or s.get('message', ''),
                    execution=s.get('execution', ''), sampleUtc=s.get('sampleUtc'))

    def safe_flat(self, agent):
        return (agent['fresh'] and agent['account'] == 'Sim101' and str(agent['quantity']) == '1'
                and agent['position'] == 'Flat' and not agent['scheduled'] and not agent['busy']
                and not agent['pairActive'] and not agent['pending'])

    def state(self):
        with self.lock:
            agents = [self.view_agent(slot) for slot in IDS]
            ready = bool(self.prepared and not self.active and not self.operation.locked()
                         and all(self.safe_flat(a) and a['prepared'] and a['prepareId'] == self.prepared for a in agents))
            return dict(version=VERSION, agents=agents, settings=self.settings.copy(), canEnter=ready,
                        prepared=bool(self.prepared), active=self.active, busy=self.operation.locked(),
                        events=list(self.events), jobs=list(self.jobs), serverTime=time.time())

    def enroll(self, slot, code):
        value = parse_enrollment(code, slot)
        if not self.operation.acquire(blocking=False):
            raise ValueError('Wait for the current operation to finish.')
        try:
            with self.lock:
                if self.active:
                    raise ValueError('Verify the current pair is flat before changing connections.')
                others = [x for k, x in self.config.items() if k != slot]
                if any(x['pin'] == value['pin'] or (x['host'], x['port']) == (value['host'], value['port']) for x in others):
                    raise ValueError('VM left and VM right must be different agents.')
                self.config[slot] = value
                self.prepared = None
                self.observations.pop(slot, None)
                if self.persist:
                    atomic_write(self.directory / 'connections.dpapi', protect(json.dumps(self.config).encode()))
            self.event(f'{NAMES[slot]} connection saved. Checking agent identity.')
        finally:
            self.operation.release()

    def call(self, slot, command, body=None, timeout=75):
        with self.lock:
            config = self.config.get(slot)
        if not config:
            raise ValueError(f'{NAMES[slot]} is not connected.')
        response = self.transport(config, command, body or {}, timeout=timeout)
        if not response.get('ok'):
            # Agent-authenticated messages contain UI errors, never credentials.
            raise ValueError(f"{NAMES[slot]}: {str(response.get('message', 'Command rejected'))[:400]}")
        return response

    def refresh_both(self):
        futures = [self.pool.submit(self.observe, slot) for slot in IDS]
        for f in futures:
            f.result()

    def submit(self, command, body):
        if command not in ('prepare', 'buy', 'sell', 'close', 'ack_flat'):
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
            job = dict(id=uuid.uuid4().hex, command=command, status='running', message='Requested')
            self.jobs.appendleft(job)
            generation = self.generation
        threading.Thread(target=self.run_job, args=(job, command, body, generation), daemon=True).start()
        return job['id']

    def run_job(self, job, command, body, generation):
        try:
            self.event(f'{command.upper()} requested.')
            if command == 'prepare':
                self.prepare(body, generation)
            elif command in ('buy', 'sell'):
                self.entry(command, generation)
            elif command == 'close':
                self.close_both()
            else:
                if body.get('noWorkingOrders') is not True:
                    raise ValueError('Check both VMs for working orders first.')
                self.refresh_both()
                if not all(self.safe_flat(a) for a in self.state()['agents']):
                    raise ValueError('Fresh Flat status has not been verified on both agents.')
                with self.lock:
                    self.active = False
                    self.prepared = None
                    (self.directory / 'entry-unresolved.json').unlink(missing_ok=True)
                self.event('Both positions verified Flat; working-order check confirmed by operator.')
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
        if body.get('noWorkingOrders') is not True:
            raise ValueError('Check both Sim101 accounts have no working orders before preparing.')
        ticker = str(body.get('ticker', '')).strip().upper()
        if not re.fullmatch(r'[A-Z0-9][A-Z0-9 .\-/]{0,29}', ticker):
            raise ValueError('Enter the NinjaTrader instrument, for example MNQ 09-26.')
        stop, profit = float(body.get('stopLoss', 0)), float(body.get('profit', 0))
        if not all(math.isfinite(v) and 0 < v <= 100000 and round(v, 2) == v for v in (stop, profit)):
            raise ValueError('Stop loss and profit must be positive currency amounts with at most two decimals.')
        with self.lock:
            if self.active:
                raise ValueError('Verify Both Flat before preparing another pair.')
            self.prepared = None
            self.settings = dict(ticker=ticker, stopLoss=stop, profit=profit)
        self.refresh_both()
        if not all(self.safe_flat(a) for a in self.state()['agents']):
            raise ValueError('Both VMs must report fresh Sim101 / Qty 1 / Flat, with no pending action.')
        prepare_id = uuid.uuid4().hex
        def one(slot, sl, pt):
            return self.call(slot, 'prepare', dict(ticker=ticker, stopLoss=sl, profit=pt, prepareId=prepare_id))
        results = [self.pool.submit(one, IDS[0], stop, profit), self.pool.submit(one, IDS[1], profit, stop)]
        errors = []
        for slot, result in zip(IDS, results):
            try:
                result.result()
                self.event(f'{NAMES[slot]} preparation acknowledged; verifying observations.')
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
            if all(self.safe_flat(a) and a['prepared'] and a['prepareId'] == prepare_id for a in agents):
                if [(float(a['stopLoss']), float(a['profit'])) for a in agents] != [(stop, profit), (profit, stop)]:
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
        self.refresh_both()
        if not all(self.safe_flat(a) and a['prepared'] and a['prepareId'] == prepared for a in self.state()['agents']):
            raise ValueError('Readiness changed. Prepare both VMs again.')
        self.assert_generation(generation)
        with self.lock:
            self.assert_generation(generation)
            self.active = True
            self.prepared = None
            atomic_write(self.directory / 'entry-unresolved.json', json.dumps({'requested':time.time()}).encode())
        try:
            # ONE paired entry request to VM left: retain the V10.4 arm/commit and peer monitoring.
            # Never retry an entry following a lost response.
            self.call('vm-left', 'entry', dict(side=side.upper(), prepareId=prepared), timeout=30)
            self.assert_generation(generation)
            self.event('Pair entry accepted by VM left. Waiting for actual position observations; acceptance is not a fill.')
        except Exception as exc:
            self.event('Entry outcome uncertain. Requesting recovery close on both VMs.')
            with self.lock:
                self.generation += 1
            self.close_both()
            raise ValueError(f'Entry did not complete normally: {exc}') from exc

    def close_both(self):
        # Independent requests: a failed VM must not prevent the other request.
        futures = {slot:self.close_pool.submit(self.call, slot, 'close', {}, 30) for slot in IDS}
        for slot, future in futures.items():
            try:
                future.result()
                self.event(f'{NAMES[slot]} close acknowledged. Awaiting Flat observation.')
            except Exception as exc:
                self.event(f'{NAMES[slot]} close outcome unknown: {exc}')
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            self.refresh_both()
            agents = self.state()['agents']
            if all(self.safe_flat(a) for a in agents):
                with self.lock:
                    self.active = False
                    self.prepared = None
                    (self.directory / 'entry-unresolved.json').unlink(missing_ok=True)
                self.event('Both positions independently verified Flat. Check working orders before preparing again.')
                return
            self.stop.wait(.6)
        raise ValueError('Close not verified on both VMs. Check both NinjaTrader windows manually.')


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
        if self.path == '/api/state':
            self.reply(200, self.server.center.state())
            return
        files = {'/':'index.html', '/app.js':'app.js', '/style.css':'style.css', '/favicon.svg':'favicon.svg'}
        kinds = {'.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8',
                 '.css':'text/css; charset=utf-8', '.svg':'image/svg+xml'}
        if self.path not in files:
            self.reply(404, {'error':'Not found.'})
            return
        path = ROOT / 'static' / files[self.path]
        self.reply(200, path.read_bytes(), kinds[path.suffix])

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
            if self.path == '/api/enroll':
                slot = body.get('id')
                if slot not in IDS:
                    raise ValueError('Choose VM left or VM right.')
                self.server.center.enroll(slot, body.get('code', ''))
                self.reply(200, {'ok':True})
            elif self.path == '/api/invalidate':
                with self.server.center.lock:
                    self.server.center.prepared = None
                    self.server.center.generation += 1
                self.reply(200, {'ok':True})
            elif self.path == '/api/action':
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
    center = Center(args.data_dir)
    server = ThreadingHTTPServer(('127.0.0.1', 8788), Handler)
    server.daemon_threads = True
    server.authority = '127.0.0.1:8788'
    server.center = center
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
        center.stop.set()
        server.server_close()


if __name__ == '__main__':
    main()
