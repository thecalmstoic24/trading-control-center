import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'coordinator'))
from funded_strategy import account, validate


class FundedStrategyTests(unittest.TestCase):
    def fields(self, firm='A', **changes):
        return dict(firm=firm, RealStage='Funded', NoConsistency=1,
                    RealCurrentBalance=50000, RealDrawdown=1501.23, **changes)

    def test_exact_fields_and_boundaries(self):
        for balance in (48700, 50300):
            fields=self.fields();fields['RealCurrentBalance']=balance
            self.assertEqual(account(fields)[1],1510)
        for name, bad in [('RealStage','Evaluation'),('NoConsistency',0),('RealCurrentBalance',48699.99),('RealCurrentBalance',50300.01),('RealDrawdown',0)]:
            fields=self.fields();fields[name]=bad
            with self.assertRaises(ValueError):account(fields)
        fields=self.fields();del fields['RealCurrentBalance'];fields['CurrentBalance']=50000
        with self.assertRaises(ValueError):account(fields)

    def test_currency_caps_and_fund(self):
        validate(self.fields('A'),self.fields('B'),(1510,1510,1510,1510))
        with self.assertRaises(ValueError):validate(self.fields('A'),self.fields('A'),(1510,1510,1510,1510))
        with self.assertRaises(ValueError):validate(self.fields('A'),self.fields('B'),(1510,1510,1510,1510.01))

    def test_missing_and_nonfinite(self):
        for bad in (None,False,'','NaN','Infinity',[]):
            fields=self.fields();fields['RealDrawdown']=bad
            with self.assertRaises(ValueError):account(fields)


if __name__ == '__main__':unittest.main()
