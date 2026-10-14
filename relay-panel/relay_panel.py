"""RdpFree Relay: local authenticated panel, bounded TCP sessions. Standard library only."""
import argparse, contextlib, hmac, ipaddress, json, math, os, secrets, select, socket, threading, time, uuid, webbrowser
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_SESSION = 21600
RESERVED = {3389, 5151}

class Relay:
    def __init__(self, config, log, on_expire):
        self.config, self.log, self.on_expire = config, log, on_expire
        self.stop_event = threading.Event()
        self.lock = threading.Lock()
        self.connections = set()
        self.worker_count = 0
        self.listener = None
        self.deadline = time.monotonic() + max(0, config['expires_at'] - time.time())

    def start(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                s.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            s.bind(('0.0.0.0', self.config['listen_port']))
            s.listen(32)
            s.settimeout(.5)
        except Exception:
            s.close()
            raise
        self.listener = s
        threading.Thread(target=self.accept, daemon=True).start()

    def expired(self):
        return time.monotonic() >= self.deadline or time.time() >= self.config['expires_at']

    def accept(self):
        try:
            while not self.stop_event.is_set() and not self.expired():
                try:
                    client, _ = self.listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                with self.lock:
                    if self.worker_count >= 32:
                        client.close()
                        continue
                    self.worker_count += 1
                    self.connections.add(client)
                threading.Thread(target=self.forward, args=(client,), daemon=True).start()
        finally:
            was_expired = self.expired()
            self.stop()
            if was_expired:
                self.on_expire(self.config['id'])

    def forward(self, client):
        upstream = None
        try:
            upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            upstream.settimeout(5)
            with self.lock:
                self.connections.add(upstream)
            if self.stop_event.is_set():
                return
            upstream.connect((self.config['target_ip'], self.config['target_port']))
            client.settimeout(2)
            upstream.settimeout(2)
            self.log('Target connected', self.config['id'])
            while not self.stop_event.is_set() and not self.expired():
                ready, _, _ = select.select([client, upstream], [], [], .5)
                for source in ready:
                    data = source.recv(65536)
                    if not data:
                        return
                    (upstream if source is client else client).sendall(data)
        except (OSError, ValueError):
            if not self.stop_event.is_set():
                self.log('Connection closed or target unreachable; check tunnel and target port', self.config['id'])
        finally:
            with self.lock:
                for s in (client, upstream):
                    if s is not None:
                        self.connections.discard(s)
                        with contextlib.suppress(OSError): s.close()
                self.worker_count -= 1

    def stop(self):
        self.stop_event.set()
        if self.listener:
            with contextlib.suppress(OSError): self.listener.close()
        with self.lock:
            for s in list(self.connections):
                with contextlib.suppress(OSError): s.shutdown(socket.SHUT_RDWR)
                with contextlib.suppress(OSError): s.close()

class Manager:
    def __init__(self, path, panel_port):
        self.path, self.panel_port = Path(path), panel_port
        self.lock = threading.RLock()
        self.running = {}
        self.events = deque(maxlen=200)
        self.sessions = {}
        if self.path.exists():
            data = json.loads(self.path.read_text(encoding='utf-8'))
            if not isinstance(data, list): raise ValueError('Invalid saved session file')
            for c in data:
                self.validate(c)
                if not isinstance(c.get('id'), str) or not c['id'].isalnum(): raise ValueError('Invalid session ID')
                if not all(isinstance(c.get(k),(int,float)) and math.isfinite(c[k]) for k in ('started_at','expires_at')) or not 0 < c['expires_at'] - c['started_at'] <= MAX_SESSION: raise ValueError('Invalid saved TTL')
                self.sessions[c['id']] = c
        self.log('Panel started. Saved sessions stay stopped; resume never extends expiry.')

    def validate(self, c):
        for key in ('listen_port', 'target_port'):
            if type(c.get(key)) is not int or not 1024 <= c[key] <= 65535:
                raise ValueError('Ports must be integers from 1024 to 65535')
        if c['listen_port'] in RESERVED | {self.panel_port}:
            raise ValueError('5151, 3389 and panel port are reserved; choose another port')
        ip = ipaddress.ip_address(c.get('target_ip', ''))
        allowed = [ipaddress.ip_network(n) for n in ('100.64.0.0/10','10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','127.0.0.0/8')]
        if ip.version != 4 or not any(ip in n for n in allowed):
            raise ValueError('Use a private IPv4 or Tailscale IPv4 target, not a public host')
        if c['target_port'] == self.panel_port:
            raise ValueError('The admin panel cannot be a relay target')
        if ip.is_loopback and c['target_port'] == c['listen_port']:
            raise ValueError('Relay cannot point to itself')
        if not isinstance(c.get('name'), str) or not 1 <= len(c['name'].strip()) <= 60:
            raise ValueError('Session name must contain 1–60 characters')

    def log(self, message, sid=''):
        with self.lock:
            self.events.append({'time':time.strftime('%H:%M:%S'), 'session':sid[:8], 'message':message})

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temp = self.path.with_suffix('.tmp')
        temp.write_text(json.dumps(list(self.sessions.values()), indent=2), encoding='utf-8')
        temp.replace(self.path)

    def create(self, body):
        c = {k:body.get(k) for k in ('name','listen_port','target_ip','target_port')}
        self.validate(c)
        minutes = body.get('minutes', 360)
        if type(minutes) is not int or not 1 <= minutes <= 360: raise ValueError('Duration is 1–360 minutes')
        with self.lock:
            if len(self.sessions) >= 100: raise ValueError('Delete old sessions first (maximum 100)')
            now = time.time()
            c.update(id=uuid.uuid4().hex, started_at=now, expires_at=now+minutes*60)
            self.sessions[c['id']] = c
            self.save()
            self.log('Session created; expiry clock started', c['id'])
            return c

    def expire(self, sid):
        with self.lock:
            self.running.pop(sid, None)
            self.log('Expired: listener and active connections closed', sid)

    def start(self, sid):
        with self.lock:
            c = self.sessions[sid]
            if time.time() >= c['expires_at']: raise ValueError('Session expired. Reconnect cannot reset its timer.')
            if sid in self.running: return
            if len(self.running) >= 8: raise ValueError('Maximum eight active listeners')
            r = Relay(c, self.log, self.expire)
            r.start()
            self.running[sid] = r
            self.log('Listening locally. PUBLIC REACHABILITY NOT VERIFIED.', sid)

    def stop(self, sid):
        with self.lock:
            r = self.running.pop(sid, None)
            if r: r.stop()
            self.log('Session stopped; expiry unchanged', sid)

    def delete(self, sid):
        with self.lock:
            self.stop(sid)
            del self.sessions[sid]
            self.save()

    def status(self):
        with self.lock:
            result=[]
            for c in self.sessions.values():
                r=self.running.get(c['id'])
                remaining=max(0,int(c['expires_at']-time.time()))
                result.append(dict(c,remaining=remaining,status='expired' if not remaining else ('listening' if r and not r.stop_event.is_set() else 'stopped'),connections=r.worker_count if r else 0))
            return {'sessions':result,'events':list(self.events),'public_reachability':'untested'}

    def close(self):
        with self.lock:
            for r in self.running.values(): r.stop()
            self.running.clear()

class Server(ThreadingHTTPServer):
    daemon_threads=True

def handler_for(manager, token, port, html):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def reply(self, code, data, content='application/json'):
            blob = data.encode('utf-8') if isinstance(data,str) else json.dumps(data).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type',content+'; charset=utf-8')
            self.send_header('Content-Length',str(len(blob)))
            self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('X-Frame-Options','DENY')
            self.send_header('Referrer-Policy','no-referrer')
            self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(blob)
        def allowed(self, auth=True):
            if self.headers.get('Host') not in (f'127.0.0.1:{port}',f'localhost:{port}'): return False
            origin=self.headers.get('Origin')
            if origin and origin not in (f'http://127.0.0.1:{port}',f'http://localhost:{port}'): return False
            return not auth or hmac.compare_digest(self.headers.get('Authorization',''), 'Bearer '+token)
        def do_GET(self):
            if not self.allowed(auth=self.path!='/'): return self.reply(403,{'error':'Unauthorized local request'})
            if self.path=='/': return self.reply(200,html,'text/html')
            if self.path=='/api/status': return self.reply(200,manager.status())
            self.reply(404,{'error':'Not found'})
        def do_POST(self):
            if not self.allowed(): return self.reply(403,{'error':'Unauthorized local request'})
            try:
                if self.headers.get('Content-Type','').split(';')[0]!='application/json': raise ValueError('JSON required')
                length=int(self.headers.get('Content-Length','0'))
                if not 0<length<=8192: raise ValueError('Invalid body size')
                body=json.loads(self.rfile.read(length))
                if not isinstance(body,dict): raise ValueError('JSON object required')
                if self.path=='/api/create': result=manager.create(body)
                elif self.path in ('/api/start','/api/stop','/api/delete'):
                    getattr(manager,self.path.rsplit('/',1)[1])(body['id']); result={'ok':True}
                else: return self.reply(404,{'error':'Not found'})
                self.reply(200,result)
            except (ValueError,KeyError,TypeError,OSError) as e:
                self.reply(400,{'error':str(e)})
    return Handler

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=8787)
    parser.add_argument('--no-browser',action='store_true')
    parser.add_argument('--data',default=str(Path(os.environ.get('LOCALAPPDATA',str(Path.home()))) / 'RdpFreeRelay' / 'sessions.json'))
    args=parser.parse_args()
    if args.port in RESERVED or not 1024<=args.port<=65535: parser.error('Invalid local panel port')
    manager=Manager(args.data,args.port)
    token=secrets.token_urlsafe(32)
    html=Path(__file__).with_name('panel.html').read_text(encoding='utf-8')
    server=Server(('127.0.0.1',args.port),handler_for(manager,token,args.port,html))
    url=f'http://127.0.0.1:{args.port}/#{token}'
    print('RdpFree Relay — LOCAL administrator panel only. Do not forward port '+str(args.port)+'.')
    print('No public NAT mapping is created. Close this console / Ctrl+C to stop all relays.')
    if not args.no_browser: webbrowser.open(url)
    else: print('Local access URL (private, do not share): '+url)
    try: server.serve_forever(poll_interval=.3)
    except KeyboardInterrupt: pass
    finally: manager.close();server.server_close()

if __name__=='__main__': main()
