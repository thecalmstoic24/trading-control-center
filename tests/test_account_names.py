import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'coordinator'))
import unittest
from account_names import account_id,account_list,trading_name
class AccountNames(unittest.TestCase):
 def test_narrow_suffix_rule(self):
  for suffix in ['!Bulenox','!Bulenox!Bulenox']:
   self.assertEqual(account_id('BX-M123456'+suffix),'BX-M123456')
  for name in ['MFF123!Bulenox','BX-M123!Other','BX-M123!Bulenox!Other','Sim101','BX-M123','BX-M123!bulenox']:
   self.assertEqual(account_id(name),name)
 def test_collision_is_not_selectable(self):
  self.assertEqual(account_list(['BX-M123','BX-M123!Bulenox','Sim101']),['Sim101'])

class PipeSuffixTests(unittest.TestCase):
    def test_reported_labels(self):
        for raw in ['BX-M7526703186112|Bulenox','BX-M7526707176126|Bulenox','BX-M7526703186112|Bulenox!Bulenox']:
            clean=raw.split('|')[0]
            self.assertEqual(account_id(raw),clean)
            self.assertEqual(trading_name(clean,[raw,'Sim101']),raw)
