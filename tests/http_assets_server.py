"""Production static HTTP routes for browser tests; API responses remain mocked."""
from test_center import module

server = module.ThreadingHTTPServer(('127.0.0.1', 8788), module.Handler)
server.authority = '127.0.0.1:8788'
server.token = 'a' * 64
print('ready', flush=True)
try:
    server.serve_forever()
finally:
    server.server_close()
