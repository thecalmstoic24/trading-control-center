"""Bulenox connection-label aliases. Preserve all other account identifiers."""
import re
from collections import Counter

def account_id(value):
    if not isinstance(value,str): return value
    match=re.fullmatch(r'(BX-?M?\d+)(?:[!|]Bulenox)+',value)
    return match.group(1) if match else value

def account_list(names):
    counts=Counter(account_id(n) for n in names)
    return [account_id(n) for n in names if counts[account_id(n)]==1]

def trading_name(account,names):
    if not re.fullmatch(r'BX-?M?\d+',account): return account
    matches=[n for n in names if account_id(n)==account]
    if len(matches)!=1: raise ValueError('Bulenox account is missing or ambiguous. Refresh this VM’s accounts.')
    return matches[0]
