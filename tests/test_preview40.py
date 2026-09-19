import copy
import tempfile
import unittest
from unittest.mock import patch
import test_pair_queue as fixture
from test_planning import m

class UploadTests(unittest.TestCase):
    setUp=fixture.QueueTests.setUp
    tearDown=fixture.QueueTests.tearDown
    def test_missing_record_is_terminal_upload_only_and_receipts_survive(self):
        self.queue.add(self.body)
        row=self.queue.rows[0];row.update(status='Complete',after={'vm-left':{'balance':123}},results={'vm-left':23})
        receipts=copy.deepcopy(row['after']);self.queue.message='Background result upload pending: old'
        with patch.object(self.store,'push',side_effect=ValueError('HTTP 422 ROW_DOES_NOT_EXIST rec123')) as push:
            self.queue.sync(row);self.queue.sync(row)
            self.assertEqual(push.call_count,1)
        self.assertTrue(row['uploadSkipped']);self.assertFalse(row['dirty'])
        self.assertEqual(row['after'],receipts);self.assertEqual(row['results'],{'vm-left':23})
        self.assertEqual(self.queue.message,'')
    def test_network_and_pending_pair_errors_are_not_discarded(self):
        self.queue.add(self.body);row=self.queue.rows[0]
        for status,error in [('Complete','HTTP 503 unavailable'),('Queued','HTTP 422 ROW_DOES_NOT_EXIST')]:
            row.update(status=status,dirty=True)
            with patch.object(self.store,'push',side_effect=ValueError(error)):
                with self.assertRaises(ValueError):self.queue.sync(row)
            self.assertTrue(row['dirty']);self.assertFalse(row.get('uploadSkipped'))

class ViewTests(unittest.TestCase):
    def test_remove_saved_view_persists_without_remote_delete(self):
        with tempfile.TemporaryDirectory() as directory:
            planning=m.Planning(directory);old=planning.active
            planning.select_view(link='viw12345678901234',name='Second')
            removed=planning.active
            planning.remove_view(removed)
            self.assertEqual(planning.active,old)
            restored=m.Planning(directory)
            self.assertEqual(restored.active,old);self.assertEqual(len(restored.views),1)
            with self.assertRaises(ValueError):restored.remove_view(old)
