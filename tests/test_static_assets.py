"""Exercise the production HTTP handler, rather than a browser file fixture."""
import http.client
from html.parser import HTMLParser
import threading
import unittest
from test_center import module


class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sources = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'script' and attrs.get('src'):
            self.sources.append(attrs['src'])


class StaticAssetsTests(unittest.TestCase):
    def test_dashboard_scripts_are_served_by_production_handler(self):
        server = module.ThreadingHTTPServer(('127.0.0.1', 0), module.Handler)
        server.authority = '127.0.0.1:' + str(server.server_port)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def get(path):
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
            try:
                connection.request('GET', path)
                response = connection.getresponse()
                return response.status, response.getheader('Content-Type'), response.read()
            finally:
                connection.close()

        try:
            status, _, html = get('/')
            self.assertEqual(status, 200)
            scripts = Scripts()
            scripts.feed(html.decode())
            self.assertIn('/suggestions.js', scripts.sources)
            self.assertLess(scripts.sources.index('/suggestions.js'), scripts.sources.index('/drafts.js'))
            for src in scripts.sources:
                with self.subTest(src=src):
                    status, kind, body = get(src)
                    self.assertEqual(status, 200)
                    self.assertTrue(kind.startswith('text/javascript'))
                    self.assertEqual(body, (module.ROOT / 'static' / src.lstrip('/')).read_bytes())
            self.assertEqual(get('/../server.py')[0], 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
