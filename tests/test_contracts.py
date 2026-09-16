import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'coordinator'))
import contracts

class ContractTests(unittest.TestCase):
    def test_validation_persistence_and_explicit_symbols(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(contracts.resolve(d,'NQ'),'NQ DEC26')
            contracts.save(d,' mar27 ')
            self.assertEqual(contracts.settings(d)['month'],'MAR27')
            self.assertEqual(contracts.resolve(d,'mnq'),'MNQ MAR27')
            self.assertEqual(contracts.resolve(d,'NQ SEP26'),'NQ SEP26')
            for value in ('','NQ DEC26','JAN27','DEC2026','DEC26;bad',None):
                with self.assertRaises(ValueError):contracts.save(d,value)
            self.assertEqual(contracts.settings(d)['month'],'MAR27')
            Path(d,'contracts.json').write_text('{}')
            with self.assertRaises(ValueError):contracts.resolve(d,'NQ')
            self.assertEqual(contracts.resolve(d,'NQ DEC26'),'NQ DEC26')
            contracts.save(d,'JUN27')
            self.assertEqual(contracts.resolve(d,'NQ'),'NQ JUN27')
