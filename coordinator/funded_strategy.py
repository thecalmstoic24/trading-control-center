"""Eligibility for the explicit New Non-consistency planning strategy."""
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP, ROUND_CEILING

STRATEGY = 'new-non-consistency'


def scalar(value):
    if isinstance(value, list) and len(value) == 1:
        return scalar(value[0])
    return value.get('name') if isinstance(value, dict) else value


def number(value, name):
    value = scalar(value)
    try:
        if isinstance(value, bool) or value is None:
            raise ValueError()
        result = Decimal(str(value))
        if not result.is_finite():
            raise ValueError()
        return result
    except (InvalidOperation, ValueError):
        raise ValueError('Missing or invalid ' + name + '.') from None


def account(fields):
    if str(scalar(fields.get('RealStage')) or '').strip().lower() != 'funded':
        raise ValueError('New Non-consistency requires RealStage Funded.')
    if number(fields.get('NoConsistency'), 'NoConsistency') != 1:
        raise ValueError('New Non-consistency requires NoConsistency = 1.')
    if not 48700 <= number(fields.get('RealCurrentBalance'), 'RealCurrentBalance') <= 50300:
        raise ValueError('RealCurrentBalance must be between $48,700 and $50,300.')
    firms = [scalar(v) for k, v in fields.items() if k.strip().lower() == 'firm']
    if len(firms) != 1 or not isinstance(firms[0], str) or not firms[0].strip():
        raise ValueError('Missing or ambiguous firm.')
    dd = number(fields.get('RealDrawdown'), 'RealDrawdown')
    if not 0 < dd <= 100000:
        raise ValueError('RealDrawdown must be positive and at most $100,000.')
    cents = (dd * 100).quantize(Decimal('1'), rounding=ROUND_HALF_UP)
    cap = (cents / 1000).quantize(Decimal('1'), rounding=ROUND_CEILING) * 10
    if cap <= 0:
        raise ValueError('RealDrawdown must be at least one cent.')
    return ' '.join(firms[0].upper().split()), cap


def validate(fields_left, fields_right, amounts):
    left_firm, left_cap = account(fields_left)
    right_firm, right_cap = account(fields_right)
    if left_firm == right_firm:
        raise ValueError('Same fund: choose accounts from different funds.')
    stop, profit, right_stop, right_profit = amounts
    for value, cap in ((stop, left_cap), (profit, right_cap), (right_stop, right_cap), (right_profit, left_cap)):
        if not 0 < number(value, 'Currency amount') <= cap:
            raise ValueError('New Non-consistency amounts exceed the rounded drawdown preset. Edit or regenerate this pair.')
