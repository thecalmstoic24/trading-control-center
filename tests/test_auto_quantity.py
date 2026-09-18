import copy
import datetime as dt
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'coordinator'))
import auto_quantity as aq
from ratios import pair_amounts
from pair_queue import import_pending,PairStore

class AutoQuantityTests(unittest.TestCase):
    def setUp(self):
        self.clock=dt.datetime(2026,9,18,15,0,tzinfo=dt.timezone.utc)
        self.config=dict(enabled=True,vm='source',bars=3,multiplier=1)
        self.spec=dict(ticker='NQ DEC26',profit=600,ratio='2:3',left='a',right='b')
        self.view=dict(fresh=True,candles=dict(periodMinutes=1,instrument='NQ 12-26',publishedUtc=self.clock.isoformat(),bars=[dict(time=(self.clock-dt.timedelta(minutes=i)).isoformat(),high=1010,low=1000) for i in (2,1,0)]))
    def test_exact_whole_nq_and_ratio(self):
        result=aq.size(self.spec,self.config,self.view,self.clock)
        self.assertEqual((result['ticker'],result['leftQuantity'],result['rightQuantity']),('MNQ DEC26',30,45))
        self.spec['ratio']='1:1'
        result=aq.size(self.spec,self.config,self.view,self.clock)
        self.assertEqual((result['ticker'],result['leftQuantity']),('NQ DEC26',3))
    def test_never_rounds_up_quantity_and_preserves_ratios(self):
        for ratio in ('1:1','2:3','3:2','3:5','5:4'):
            self.spec.update(profit=533,ratio=ratio)
            out=aq.size(self.spec,self.config,self.view,self.clock)
            a,b=map(int,ratio.split(':'))
            self.assertEqual(out['leftQuantity']*b,out['rightQuantity']*a)
            self.assertLessEqual(out['estimatedLeftProfit'],533)
    def test_wicks_average_tick_rounding(self):
        self.view['candles']['bars'][0].update(high=1010.1)
        out=aq.size(self.spec,self.config,self.view,self.clock)
        self.assertAlmostEqual(out['averageRange'],10.0333333333333)
        self.assertEqual(out['distance'],10.25)
    def test_fail_closed(self):
        changes=[lambda v:v.update(fresh=False),lambda v:v.pop('candles'),lambda v:v['candles'].update(instrument='NQ 09-26'),lambda v:v['candles'].update(bars=[]),lambda v:v['candles'].update(periodMinutes=5),lambda v:v['candles'].update(publishedUtc=(self.clock-dt.timedelta(seconds=91)).isoformat()),lambda v:v['candles']['bars'][-1].update(time=(self.clock-dt.timedelta(days=1)).isoformat()),lambda v:v['candles']['bars'][-1].update(high=float('nan'))]
        for change in changes:
            view=copy.deepcopy(self.view);change(view)
            with self.assertRaises(ValueError):aq.size(self.spec,self.config,view,self.clock)
    def test_tiny_budget_blocks_instead_of_increasing_risk(self):
        self.spec['profit']=1
        with self.assertRaises(ValueError):aq.size(self.spec,self.config,self.view,self.clock)
    def test_whole_dollar_amounts(self):
        self.assertEqual(pair_amounts(dict(ratio='3:2',stopLoss=800,profit=533.33)),(800,534,356,534))
    def test_remote_edit_atomic_and_priority(self):
        row=dict(spec=dict(left='a',right='b',ratio='2:3',quantities={'a':2,'b':3}),priority=4)
        import_pending(row,{'Priority':'2','Left Quantity':4,'Right Quantity':6})
        self.assertEqual(row['priority'],2);self.assertEqual(row['spec']['quantities'],{'a':4,'b':6})
        original=copy.deepcopy(row)
        with self.assertRaises(ValueError):import_pending(row,{'Priority':'1','Left Quantity':5,'Right Quantity':6})
        self.assertEqual(row,original)
        import_pending(row,{});self.assertEqual(row['priority'],4)

if __name__=='__main__':unittest.main()
