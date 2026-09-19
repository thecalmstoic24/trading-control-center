"""Read-only Airtable view cache. No trading-agent calls or Airtable writes."""
import json
import re
import copy
import os
from pathlib import Path
import subprocess
import threading
import time
import urllib.parse
import urllib.request
import urllib.error

BASE='appzvICrv7LLlZdxm'
TABLE='tbl1u1mKMpVLmTqQP'
VIEW='viw6K3jRjU5PJpWM4'
URL=f'https://airtable.com/{BASE}/{TABLE}/{VIEW}'


def credential(path, token=None):
    # Windows DPAPI through PowerShell. Secrets travel over pipes, never command arguments.
    script=r'''$ErrorActionPreference='Stop';$r=[Console]::In.ReadToEnd()|ConvertFrom-Json
if($r.token){$s=ConvertTo-SecureString $r.token -AsPlainText -Force;$tmp=$r.path+'.tmp';$s|ConvertFrom-SecureString|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $r.path -Force}
else{$s=ConvertTo-SecureString ((Get-Content -LiteralPath $r.path -Raw).Trim());$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR($p))}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}'''
    result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],input=json.dumps({'path':str(path),'token':token}),capture_output=True,text=True,timeout=15,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if result.returncode: raise ValueError('Could not access the saved Airtable credential. Save a token in Planning setup.')
    return result.stdout.strip()


def get_json(url, token):
    request=urllib.request.Request(url,headers={'Authorization':'Bearer '+token},method='GET')
    try:
        with urllib.request.urlopen(request,timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as e:
        if e.code in (401,403): raise ValueError('Airtable access denied. Check token access to the Trading base and data.records:read permission.') from None
        if e.code==429: raise ValueError('Airtable rate limit reached. Planning will retry automatically.') from None
        raise ValueError('Airtable request failed (HTTP '+str(e.code)+').') from None


def fetch_view(token, getter=get_json, *, base=BASE, table_id=TABLE, view=VIEW):
    rows=[];offset=None;seen=set()
    for _ in range(1000):
        query={'view':view,'pageSize':100}
        if offset: query['offset']=offset
        page=getter(f'https://api.airtable.com/v0/{base}/{table_id}?'+urllib.parse.urlencode(query),token)
        rows.extend(page.get('records',[]))
        offset=page.get('offset')
        if not offset: break
        if offset in seen: raise ValueError('Airtable returned a repeated page; previous data retained.')
        seen.add(offset)
        time.sleep(.22)
    else: raise ValueError('View exceeds Planning page limit; previous data retained.')
    columns=[{'name':name,'type':'auto'} for name in dict.fromkeys(k for row in rows for k in row.get('fields',{}))]
    try:
        schema=getter(f'https://api.airtable.com/v0/meta/bases/{base}/tables',token)
        table=next(t for t in schema['tables'] if t['id']==table_id)
        columns=[{'name':f['name'],'type':f.get('type','auto')} for f in table['fields']]
    except Exception:
        pass # Schema permission is optional; populated fields still work.
    return {'rows':[{'id':r['id'],'fields':r.get('fields',{})} for r in rows], 'columns':columns}


def view_config(link, name=''):
    if not isinstance(link,str): raise ValueError('Enter an Airtable view link or view ID.')
    value=link.strip()
    if re.fullmatch(r'viw[A-Za-z0-9]{5,30}',value): base,table,view=BASE,TABLE,value
    else:
        parsed=urllib.parse.urlparse(value)
        if parsed.scheme!='https' or parsed.netloc!='airtable.com':
            raise ValueError('Use an https://airtable.com/base/table/view link or a viw view ID.')
        match=re.fullmatch(r'/(app[A-Za-z0-9]{5,30})/(tbl[A-Za-z0-9]{5,30})/(viw[A-Za-z0-9]{5,30})/?',parsed.path)
        if not match: raise ValueError('Use the Airtable view link containing app, tbl, and viw IDs.')
        base,table,view=match.groups()
    if not isinstance(name,str) or len(name)>100: raise ValueError('View name must be at most 100 characters.')
    return dict(key=f'{base}/{table}/{view}',base=base,table=table,view=view,name=name.strip() or view,url=f'https://airtable.com/{base}/{table}/{view}')


class Planning:
    def __init__(self, directory):
        self.path=Path(directory)/'planning-token.dat'
        self.views_path=Path(directory)/'planning-views.json'
        initial=view_config(URL,'Accounts')
        self.views=[initial]; self.active=initial['key']; self.caches={}
        if self.views_path.exists():
            saved=json.loads(self.views_path.read_text())
            self.views=[view_config(v['url'],v['name']) for v in saved['views']]
            if not self.views:self.views=[initial]
            self.active=saved.get('active',self.views[0]['key'])
            if self.active not in {v['key'] for v in self.views}:self.active=self.views[0]['key']
        self.lock=threading.Lock();self.wake=threading.Event();self.stop=threading.Event()
        self.data=self.empty_data(next(v for v in self.views if v['key']==self.active));self.caches[self.active]=self.data
        self.pending_token=None
        self.thread=threading.Thread(target=self.loop,daemon=True)
    @staticmethod
    def empty_data(view):
        return dict(rows=[],columns=[],updatedAt=None,error='',busy=False,configured=False,viewUrl=view['url'],viewKey=view['key'])
    def save_views(self):
        tmp=self.views_path.with_suffix('.tmp')
        tmp.write_text(json.dumps(dict(views=self.views,active=self.active)))
        os.replace(tmp,self.views_path)
    def select_view(self, key=None, link=None, name=''):
        candidate=view_config(link,name) if link is not None else None
        with self.lock:
            if candidate:
                existing=next((v for v in self.views if v['key']==candidate['key']),None)
                if not existing:self.views.append(candidate)
                elif name.strip():existing['name']=candidate['name']
                key=candidate['key']
            view=next((v for v in self.views if v['key']==key),None)
            if not view:raise ValueError('Choose a saved Airtable view.')
            self.active=key;self.data=self.caches.setdefault(key,self.empty_data(view));self.save_views()
        self.wake.set()
    def remove_view(self, key):
        with self.lock:
            if len(self.views)<=1:raise ValueError('Keep at least one saved view. Add another view first.')
            if not any(v['key']==key for v in self.views):raise ValueError('Choose a saved Airtable view.')
            self.views=[v for v in self.views if v['key']!=key]
            self.caches.pop(key,None)
            if self.active==key:
                view=self.views[0];self.active=view['key'];self.data=self.caches.setdefault(self.active,self.empty_data(view))
            self.save_views()
        self.wake.set()
    def start(self): self.thread.start();self.wake.set()
    def snapshot(self):
        with self.lock:return copy.deepcopy(dict(self.data,views=self.views))
    def refresh(self,token=None):
        if token is not None:
            if not isinstance(token,str) or not token.startswith('pat') or not 20<len(token)<1000:raise ValueError('Enter an Airtable personal access token.')
            with self.lock:self.pending_token=token
        self.wake.set()
    def loop(self):
        while not self.stop.is_set():
            self.wake.wait();self.wake.clear()
            if self.stop.is_set():return
            with self.lock:
                token=self.pending_token;self.pending_token=None
                view=next(v.copy() for v in self.views if v['key']==self.active)
                target=self.data;target['busy']=True
            try:
                is_new=token is not None
                if not token:
                    source=self.path if self.path.exists() else Path(os.environ.get('LOCALAPPDATA',''))/'NT-Airtable'/'token.dat'
                    if not source.exists():raise ValueError('Open Planning setup and save an Airtable token on this computer. VM credentials stay on their VMs.')
                    token=credential(source)
                result=fetch_view(token,base=view['base'],table_id=view['table'],view=view['view'])
                if is_new:credential(self.path,token)
                with self.lock:target.update(result,updatedAt=time.time(),error='',configured=True)
            except ValueError as e:
                with self.lock:target['error']=str(e)
            except Exception:
                with self.lock:target['error']='Planning refresh failed. Previous data retained; retry or check Planning setup.'
            finally:
                token=None
                with self.lock:target['busy']=False
    def close(self): self.stop.set();self.wake.set()
