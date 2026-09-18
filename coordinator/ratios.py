"""Shared currency-ratio validation for planning and agent preparation."""
from decimal import Decimal, ROUND_CEILING
import math

RATIOS = ('1:1','2:1','1:2','2:3','3:2','3:4','4:3','2:5','5:2','3:5','5:3','4:5','5:4')

def pair_amounts(body):
    ratio = body.get('ratio', '1:1')
    if ratio not in RATIOS:
        raise ValueError('Select a supported pair ratio.')
    a, b = map(int, ratio.split(':'))
    stop, profit = body.get('stopLoss', 0), body.get('profit', 0)
    for value in (stop, profit):
        if isinstance(value, bool): raise ValueError('Enter positive currency amounts.')
        try: v = float(value)
        except (TypeError, ValueError): raise ValueError('Enter positive currency amounts.')
        if not math.isfinite(v) or not 0 < v <= 100000 or round(v, 2) != v:
            raise ValueError('Enter positive currency amounts up to 100000 with at most two decimals.')
    stop,profit=math.ceil(float(stop)),math.ceil(float(profit))
    def scale(value):
        result = float((Decimal(str(value))*b/a).quantize(Decimal('1'), rounding=ROUND_CEILING))
        if not 0 < result <= 100000: raise ValueError('Ratio produces a currency amount outside the supported range.')
        return result
    return float(math.ceil(float(stop))), float(math.ceil(float(profit))), scale(profit), scale(stop)

def validate_quantities(body, left, right):
    if 'ratio' not in body: return # Existing manual pairs keep independent quantities.
    a, b = map(int, body['ratio'].split(':'))
    q = body['quantities']
    if q[left]*b != q[right]*a:
        raise ValueError('Quantities must be whole contracts matching the selected ratio. Adjust quantity or ratio.')
