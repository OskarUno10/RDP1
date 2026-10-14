import contextlib, http.client, json, socket, socketserver, sys, tempfile, threading, time, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from relay_panel import Manager,Server,handler_for

def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0));return s.getsockname()[1]

class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        while True:
            data=self.request.recv(65536)
            if not data:return
            self.request.sendall(data)

class EchoServer(socketserver.ThreadingTCPServer):
    daemon_threads=True

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.m=Manager(Path(self.tmp.name)/'sessions.json',8787)
        self.echo=EchoServer(('127.0.0.1',0),Echo)
        threading.Thread(target=self.echo.serve_forever,daemon=True).start()
    def tearDown(self):
        self.m.close();self.echo.shutdown();self.echo.server_close();self.tmp.cleanup()
    def create(self,**extra):
        body=dict(name='Test',listen_port=port(),target_ip='127.0.0.1',target_port=self.echo.server_address[1],minutes=360)
        body.update(extra);return self.m.create(body)
    def test_actual_tcp_forwarding_and_stop(self):
        c=self.create();self.m.start(c['id'])
        with socket.create_connection(('127.0.0.1',c['listen_port']),timeout=2) as s:
            data=b'real relay data'*2000;s.sendall(data);received=b''
            while len(received)<len(data):received+=s.recv(65536)
            self.assertEqual(received,data)
            self.m.stop(c['id'])
            try:self.assertEqual(s.recv(1),b'')
            except ConnectionResetError:pass
        self.assertEqual(self.m.status()['sessions'][0]['status'],'stopped')
    def test_expiry_closes_active_connection(self):
        c=self.create();c['expires_at']=time.time()+1.2;self.m.start(c['id'])
        with socket.create_connection(('127.0.0.1',c['listen_port']),timeout=3) as s:
            s.sendall(b'hello');self.assertEqual(s.recv(5),b'hello')
            try:self.assertEqual(s.recv(1),b'')
            except ConnectionResetError:pass
        self.assertEqual(self.m.status()['sessions'][0]['status'],'expired')
        with self.assertRaises(ValueError):self.m.start(c['id'])
    def test_timer_persistence_and_no_extension(self):
        c=self.create();deadline=c['expires_at'];self.m.start(c['id']);self.m.stop(c['id'])
        reloaded=Manager(self.m.path,8787)
        self.assertEqual(reloaded.sessions[c['id']]['expires_at'],deadline)
        self.assertFalse(reloaded.running)
    def test_invalid_ports_targets_and_durations(self):
        for field,value in [('listen_port',5151),('listen_port',3389),('listen_port',8787),('target_port',8787),('target_ip','8.8.8.8'),('target_ip','169.254.169.254'),('minutes',361),('minutes',0),('minutes',float('nan')),('listen_port',True)]:
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):self.create(**{field:value})
    def test_duplicate_bind_does_not_claim_success(self):
        c=self.create();self.m.start(c['id']);d=self.create(listen_port=c['listen_port'])
        with self.assertRaises(OSError):self.m.start(d['id'])
        self.assertNotIn(d['id'],self.m.running)
    def test_api_auth_origin_and_rebinding_guards(self):
        p=port();self.m.panel_port=p
        server=Server(('127.0.0.1',p),handler_for(self.m,'test-secret',p,'<h1>Local panel</h1>'))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        def req(path='/',headers=None,method='GET',body=None):
            c=http.client.HTTPConnection('127.0.0.1',p,timeout=2);c.request(method,path,body,headers or {});r=c.getresponse();data=r.read();c.close();return r.status,data
        try:
            self.assertEqual(req()[0],200)
            self.assertEqual(req('/api/status')[0],403)
            self.assertEqual(req('/api/status',{'Authorization':'Bearer test-secret'})[0],200)
            self.assertEqual(req('/',{'Host':'attacker.example'})[0],403)
            self.assertEqual(req('/api/status',{'Authorization':'Bearer test-secret','Origin':'https://attacker.example'})[0],403)
            self.assertEqual(req('/api/create',{'Authorization':'Bearer test-secret','Content-Type':'application/json'},'POST','[]')[0],400)
        finally:server.shutdown();server.server_close()

if __name__=='__main__':unittest.main()
