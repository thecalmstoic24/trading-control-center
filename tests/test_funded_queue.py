import unittest
import test_pair_queue as fixture


class FundedQueueTests(unittest.TestCase):
    setUp = fixture.QueueTests.setUp
    tearDown = fixture.QueueTests.tearDown
    deferred_body = fixture.QueueTests.deferred_body
    match_deferred = fixture.QueueTests.match_deferred

    def funded_body(self):
        body=self.deferred_body()
        body['draft']['suggestion']={'strategy':'new-non-consistency','revision':37}
        for side,firm in [('left','MFF'),('right','FN')]:
            body['draft'][side]['metrics']=dict(firm=firm,RealStage='Funded',NoConsistency=1,RealCurrentBalance=50000,RealDrawdown=1500)
        self.records=self.store.records(fixture.TABLE)
        for rec in self.records:
            rec['fields'].update(body['draft']['left' if rec['fields']['id']=='MFF-A' else 'right']['metrics'])
        self.store.records=lambda table:self.records if table==fixture.TABLE else []
        return body

    def test_preserves_strategy_and_rechecks_current_airtable_before_prepare(self):
        self.queue.add(self.funded_body());self.queue.command('start',{});self.match_deferred()
        row=self.queue.rows[0]
        self.assertEqual(row['spec']['strategy'],'new-non-consistency')
        self.records[0]['fields']['RealCurrentBalance']=50301
        self.agent.calls.clear();self.queue.tick()
        self.assertEqual(row['status'],'Waiting')
        self.assertIn('RealCurrentBalance',row['message'])
        self.assertFalse(self.fleet.pairs)
        self.assertFalse(any(cmd in ('prepare','entry') for _,cmd,_ in self.agent.calls))
        self.records[0]['fields']['RealCurrentBalance']=50000;row['vmMatchRetryAt']=0
        self.queue.tick()
        self.assertEqual(row['status'],'Preparing',row['message'])
        self.assertEqual(row['spec']['strategy'],'new-non-consistency')

    def test_cannot_confirm_invalid_eligibility(self):
        body=self.funded_body();body['draft']['left']['metrics']['NoConsistency']=0
        with self.assertRaisesRegex(ValueError,'NoConsistency'):self.queue.add(body)
        self.assertEqual(self.queue.rows,[])
