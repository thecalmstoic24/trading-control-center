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
 def test_mt_discovery_and_full_trading_label(self):
  clean='BX-MT123456'
  for suffix in ['', '!Bulenox', '!Bulenox!Bulenox', '|Bulenox', '|Bulenox|Bulenox', '|Bulenox!Bulenox']:
   with self.subTest(suffix=suffix):
    raw=clean+suffix
    self.assertEqual(account_id(raw),clean)
    self.assertEqual(account_list(['Sim101',raw]),['Sim101',clean])
    self.assertEqual(trading_name(clean,['Sim101',raw]),raw)
 def test_mt_duplicates_missing_and_distinct_m_account(self):
  mt='BX-MT123456';m='BX-M123456'
  names=[mt+'|Bulenox',m+'|Bulenox']
  self.assertEqual(account_list(names),[mt,m])
  self.assertEqual(trading_name(mt,names),names[0])
  self.assertEqual(trading_name(m,names),names[1])
  self.assertEqual(account_list([mt,mt+'!Bulenox','Sim101']),['Sim101'])
  for names in [[m+'|Bulenox'],[mt,mt+'|Bulenox']]:
   with self.assertRaises(ValueError):trading_name(mt,names)
 def test_mt_unrelated_suffixes_unchanged(self):
  for name in ['BX-MT123!Other','BX-MT123!bulenox','BX-MT123!Bulenox!Other','BX-MTX123!Bulenox']:
   self.assertEqual(account_id(name),name)

class PipeSuffixTests(unittest.TestCase):
    def test_reported_labels(self):
        for raw in ['BX-M7526703186112|Bulenox','BX-M7526707176126|Bulenox','BX-M7526703186112|Bulenox!Bulenox']:
            clean=raw.split('|')[0]
            self.assertEqual(account_id(raw),clean)
            self.assertEqual(trading_name(clean,[raw,'Sim101']),raw)
