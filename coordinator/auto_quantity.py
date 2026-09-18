"""Deterministic sizing from authenticated VM completed-candle telemetry."""
import datetime as dt
import json
import math
import os
from fractions import Fraction

def configuration(directory):
    path=directory/'auto-quantity.json'
    return json.loads(path.read_text()) if path.exists() else dict(enabled=False,vm='',bars=10,multiplier=1)

def validate_config(value):
    if not isinstance(value,dict) or type(value.get('enabled')) is not bool: raise ValueError('Invalid Auto Quantity settings.')
    bars=value.get('bars'); multiplier=value.get('multiplier'); vm=value.get('vm')
    if type(bars) is not int or not 1<=bars<=100: raise ValueError('Select 1–100 completed candles.')
    if isinstance(multiplier,bool) or not isinstance(multiplier,(int,float)) or not math.isfinite(multiplier) or not .1<=multiplier<=20: raise ValueError('Distance multiplier must be 0.1–20.')
    if not isinstance(vm,str) or len(vm)>100 or (value['enabled'] and not vm): raise ValueError('Select a candle source VM.')
    return dict(enabled=value['enabled'],vm=vm,bars=bars,multiplier=multiplier)

def save(directory,value):
    value=validate_config(value);path=directory/'auto-quantity.json';temp=path.with_suffix('.tmp');temp.write_text(json.dumps(value));os.replace(temp,path);return value

def size(spec,config,view,clock=None):
    config=validate_config(config)
    if not view.get('fresh'): raise ValueError('Candle source VM is disconnected or stale.')
    feed=view.get('candles')
    if not isinstance(feed,dict) or feed.get('periodMinutes')!=1: raise ValueError('Enable TccTelemetry on a 1-minute NQ/MNQ chart on the source VM.')
    clock=clock or dt.datetime.now(dt.timezone.utc)
    try: stamp=dt.datetime.fromisoformat(feed['publishedUtc'].replace('Z','+00:00'))
    except (KeyError,TypeError,ValueError): raise ValueError('Candle timestamp is missing or invalid.')
    if stamp.tzinfo is None or not -5<=(clock-stamp).total_seconds()<=90: raise ValueError('Completed candle data is stale. Auto Quantity has not been applied.')
    expected=spec['ticker'].split(' ',1)
    actual=str(feed.get('instrument','')).split(' ',1)
    if len(actual)==2 and len(actual[1])==5 and actual[1][2]=='-':
        months={'03':'MAR','06':'JUN','09':'SEP','12':'DEC'}
        actual[1]=months.get(actual[1][:2],'?')+actual[1][3:]
    if expected[0] not in ('NQ','MNQ') or actual[0] not in ('NQ','MNQ') or expected[1:]!=actual[1:]: raise ValueError('Candle contract does not match the pair contract.')
    bars=feed.get('bars',[])
    if not isinstance(bars,list) or len(bars)<config['bars']: raise ValueError('Not enough completed candles for the selected bar count.')
    bars=bars[-config['bars']:];ranges=[];times=[]
    for bar in bars:
        if not isinstance(bar,dict): raise ValueError('Invalid candle data.')
        high,low=bar.get('high'),bar.get('low')
        if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in (high,low)) or high<low: raise ValueError('Invalid candle range.')
        stamp=str(bar.get('time',''))
        if not stamp or (times and stamp<=times[-1]): raise ValueError('Candles must be unique and chronological.')
        try: closed=dt.datetime.fromisoformat(stamp.replace('Z','+00:00'))
        except ValueError: raise ValueError('Invalid completed candle timestamp.')
        if closed.tzinfo is None or (closed-clock).total_seconds()>5: raise ValueError('Candle time must be UTC and completed.')
        times.append(stamp);ranges.append(high-low)
    if (clock-closed).total_seconds()>150: raise ValueError('Most recent completed candle is stale.')
    average=sum(ranges)/len(ranges);distance=average*config['multiplier']
    if distance<=0: raise ValueError('Average candle distance must be positive.')
    distance=math.ceil(distance*4-1e-9)/4
    from ratios import RATIOS
    if spec.get('ratio','1:1') not in RATIOS: raise ValueError('Select a supported pair ratio.')
    ratio=Fraction(spec.get('ratio','1:1').replace(':','/'));a,b=ratio.numerator,ratio.denominator
    budget=float(spec['profit'])
    if not math.isfinite(budget) or not 0<budget<=100000: raise ValueError('Enter a positive left profit target, up to 100000.')
    max_micro=math.floor(budget/(distance*2)+1e-9)
    units=max_micro//a;left=units*a;right=units*b
    if left<1 or right<1: raise ValueError('Profit target is too small for one ratio-preserving MNQ lot at this distance.')
    root='MNQ'
    if left%10==0 and right%10==0: root='NQ';left//=10;right//=10
    if max(left,right)>1000: raise ValueError('Auto Quantity exceeds the 1,000-contract limit.')
    return dict(ticker=root+' '+expected[1] if len(expected)>1 else root,leftQuantity=left,rightQuantity=right,averageRange=average,distance=distance,bars=config['bars'],source=config['vm'],publishedUtc=feed['publishedUtc'],estimatedLeftProfit=left*distance*(20 if root=='NQ' else 2))

def apply(spec,config,view):
    result=size(spec,config,view)
    spec['ticker']=result['ticker'];spec['quantities']={spec['left']:result['leftQuantity'],spec['right']:result['rightQuantity']};spec['autoSizing']=result
    return result
