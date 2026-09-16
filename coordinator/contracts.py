"""Shared contract setting. Resolve root symbols once, when a pair is confirmed."""
import json
import re
import threading
from pathlib import Path

_lock = threading.RLock()

def validate_month(value):
    value = str(value).strip().upper()
    if not re.fullmatch(r'(MAR|JUN|SEP|DEC)[0-9]{2}', value):
        raise ValueError('Use a quarterly contract month such as DEC26 or MAR27.')
    return value

def settings(directory):
    with _lock:
        path = Path(directory) / 'contracts.json'
        try:
            month = validate_month(json.loads(path.read_text())['month']) if path.exists() else 'DEC26'
        except (KeyError, ValueError):
            raise ValueError('Saved contract setting is invalid. Save the contract month again.') from None
        return {'month': month, 'symbols': {root: root+' '+month for root in ('NQ','MNQ')}}

def save(directory, month):
    month = validate_month(month)
    with _lock:
        path = Path(directory) / 'contracts.json'
        tmp = path.with_suffix('.tmp')
        tmp.write_text(json.dumps({'month': month}))
        tmp.replace(path)
        return settings(directory)

def resolve(directory, ticker):
    ticker = str(ticker).strip().upper()
    return settings(directory)['symbols'][ticker] if ticker in ('NQ','MNQ') else ticker
