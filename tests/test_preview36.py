"""Session metadata and lightweight transport must never change execution."""
import copy
import http.client
import json
import threading
from unittest.mock import patch
from test_pair_queue import QueueTests, PairQueue, Planning, module

class Preview36Tests(QueueTests):
    # Reuse the queue fixture, not its inherited suite.
    def test_session_is_durable_idempotent_and_preserves_existing_trades(self):
        identity=self.queue.add(self.body)
        self.queue.command('start',{})
        before=copy.deepcopy(self.queue.rows)
        running=self.queue.running
        result=self.queue.command('start-day',{'key':'a'*32})
        self.assertEqual(self.queue.rows,before)
        self.assertEqual(self.queue.running,running)
        self.assertEqual(self.queue.command('start-day',{'key':'a'*32}),result)
        self.assertEqual(len(self.queue.sessions),1)
        restored=PairQueue(self.fleet,Planning(),self.store)
        self.assertEqual(restored.active_session,'a'*32)
        self.assertEqual(restored.sessions,self.queue.sessions)
        self.assertFalse(restored.running)

    def test_new_dispatch_joins_session_existing_dispatch_does_not(self):
        self.queue.add(self.body)
        self.queue.command('start',{})
        self.queue.command('start-day',{'key':'b'*32})
        self.queue.add(self.body)
        self.queue.command('start',{})
        self.assertIsNone(self.queue.rows[0]['sessionId'])
        self.assertEqual(self.queue.rows[1]['sessionId'],'b'*32)
        self.assertTrue(self.queue.rows[1]['dispatchedAt'])

    def test_session_save_failure_rolls_back(self):
        with patch.object(self.queue,'save',side_effect=OSError('disk full')):
            with self.assertRaises(OSError):self.queue.command('start-day',{'key':'c'*32})
        self.assertEqual(self.queue.sessions,[])
        self.assertIsNone(self.queue.active_session)

    def test_compact_snapshot_drops_diagnostics_preserves_actions(self):
        self.queue.add(self.body)
        self.queue.rows[0]['draft']={'large':'x'*10000}
        self.queue.rows[0]['diagnostics']='x'*10000
        raw=self.queue.snapshot();compact=self.queue.snapshot(compact=True)
        self.assertEqual(compact['rows'][0]['spec'],raw['rows'][0]['spec'])
        self.assertTrue(compact['rows'][0]['draft'])
        self.assertLess(len(json.dumps(compact)),len(json.dumps(raw))/5)
        self.assertIsInstance(self.queue.rows[0]['draft'],dict)

    def test_dashboard_avoids_legacy_pair_snapshot(self):
        identity=self.fleet.create_pair('vm-left','vm-right')
        pair=self.fleet.get_pair(identity)
        with patch.object(pair,'state',side_effect=AssertionError('legacy snapshot')):
            state=self.fleet.state(dashboard=True)
        self.assertTrue(state['dashboard'])
        self.assertEqual(state['pairs'][0]['id'],identity)
        self.assertEqual(len(state['fleet']),2)

    def test_conditional_queue_response_sends_no_unchanged_body(self):
        server=module.ThreadingHTTPServer(('127.0.0.1',0),module.Handler)
        server.authority='127.0.0.1:'+str(server.server_port);server.token='a'*64;server.queue=self.queue
        threading.Thread(target=server.serve_forever,daemon=True).start()
        def get(etag=None):
            c=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
            headers={'X-Control-Token':server.token,'X-Control-View':'dashboard'}
            if etag:headers['If-None-Match']=etag
            try:
                c.request('GET','/api/queue',headers=headers);r=c.getresponse();return r.status,r.getheader('ETag'),r.read()
            finally:c.close()
        try:
            status,etag,body=get();self.assertEqual(status,200);self.assertTrue(body)
            self.assertEqual(get(etag),(304,etag,b''))
            self.queue.command('start-day',{'key':'d'*32})
            self.assertEqual(get(etag)[0],200)
        finally:server.shutdown();server.server_close()

# Do not rerun the inherited queue suite here.
for name in list(QueueTests.__dict__):
    if name.startswith('test_') and name not in Preview36Tests.__dict__:setattr(Preview36Tests,name,None)
