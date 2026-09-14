"""Read-only Airtable view cache. No trading-agent calls or Airtable writes."""
import json
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


def fetch_view(token, getter=get_json):
    rows=[];offset=None;seen=set()
    for _ in range(1000):
        query={'view':VIEW,'pageSize':100}
        if offset: query['offset']=offset
        page=getter(f'https://api.airtable.com/v0/{BASE}/{TABLE}?'+urllib.parse.urlencode(query),token)
        rows.extend(page.get('records',[]))
        offset=page.get('offset')
        if not offset: break
        if offset in seen: raise ValueError('Airtable returned a repeated page; previous data retained.')
        seen.add(offset)
        time.sleep(.22)
    else: raise ValueError('View exceeds Planning page limit; previous data retained.')
    columns=[{'name':name,'type':'auto'} for name in dict.fromkeys(k for row in rows for k in row.get('fields',{}))]
    try:
        schema=getter(f'https://api.airtable.com/v0/meta/bases/{BASE}/tables',token)
        table=next(t for t in schema['tables'] if t['id']==TABLE)
        columns=[{'name':f['name'],'type':f.get('type','auto')} for f in table['fields']]
    except Exception:
        pass # Schema permission is optional; populated fields still work.
    return {'rows':[{'id':r['id'],'fields':r.get('fields',{})} for r in rows], 'columns':columns}


class Planning:
    def __init__(self, directory):
        self.path=Path(directory)/'planning-token.dat'
        self.lock=threading.Lock();self.wake=threading.Event();self.stop=threading.Event()
        self.data={'rows':[],'columns':[],'updatedAt':None,'error':'','busy':False,'configured':False,'viewUrl':URL}
        self.pending_token=None
        self.thread=threading.Thread(target=self.loop,daemon=True)
    def start(self): self.thread.start();self.wake.set()
    def snapshot(self):
        with self.lock:return dict(self.data)
    def refresh(self,token=None):
        if token is not None:
            if not isinstance(token,str) or not token.startswith('pat') or not 20<len(token)<1000:raise ValueError('Enter an Airtable personal access token.')
            with self.lock:self.pending_token=token
        self.wake.set()
    def loop(self):
        while not self.stop.is_set():
            self.wake.wait(30);self.wake.clear()
            if self.stop.is_set():return
            with self.lock:
                token=self.pending_token;self.pending_token=None;self.data['busy']=True
            try:
                is_new=token is not None
                if not token:
                    source=self.path if self.path.exists() else Path(os.environ.get('LOCALAPPDATA',''))/'NT-Airtable'/'token.dat'
                    if not source.exists():raise ValueError('Open Planning setup and save an Airtable token on this computer. VM credentials stay on their VMs.')
                    token=credential(source)
                result=fetch_view(token)
                if is_new:credential(self.path,token)
                with self.lock:self.data.update(result,updatedAt=time.time(),error='',configured=True)
            except ValueError as e:
                with self.lock:self.data['error']=str(e)
            except Exception:
                with self.lock:self.data['error']='Planning refresh failed. Previous data retained; retry or check Planning setup.'
            finally:
                token=None
                with self.lock:self.data['busy']=False
    def close(self): self.stop.set();self.wake.set()
