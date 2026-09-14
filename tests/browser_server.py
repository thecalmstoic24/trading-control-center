"""Local test fixture only. Never included in the installer."""
import tempfile
from test_center import Fake, module

temp=tempfile.TemporaryDirectory()
center=module.Center(temp.name,Fake(),persist=False)
center.config={slot:{'id':slot} for slot in module.IDS}
center.start()
server=module.ThreadingHTTPServer(('127.0.0.1',8788),module.Handler)
server.center=center
server.authority='127.0.0.1:8788'
server.token='a'*64
try:server.serve_forever()
finally:server.server_close();center.stop.set();temp.cleanup()
