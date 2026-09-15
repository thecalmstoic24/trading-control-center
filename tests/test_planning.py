import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import urlparse, parse_qs

spec=importlib.util.spec_from_file_location('planning',Path(__file__).parents[1]/'coordinator/planning.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class PlanningTests(unittest.TestCase):
    def test_all_pages_use_exact_view_and_schema_is_optional(self):
        urls=[]
        def get(url,token):
            urls.append(url)
            if '/meta/' in url:raise ValueError('no schema scope')
            query=parse_qs(urlparse(url).query)
            self.assertEqual(query['view'],[m.VIEW])
            if 'offset' in query:return {'records':[{'id':'b','fields':{'Balance':10}}]}
            return {'records':[{'id':'a','fields':{'id':'Account1'}}],'offset':'next page'}
        with patch.object(m.time,'sleep'):
            result=m.fetch_view('private',get)
        self.assertEqual([r['id'] for r in result['rows']],['a','b'])
        self.assertEqual([c['name'] for c in result['columns']],['id','Balance'])
        self.assertEqual(len(urls),3)
    def test_repeated_offset_fails_instead_of_partial_data(self):
        with patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(ValueError,'repeated page'):
                m.fetch_view('private',lambda *a:{'records':[],'offset':'same'})
    def test_get_only_and_auth_not_in_url(self):
        class Response:
            def __enter__(self):return self
            def __exit__(self,*a):pass
            def read(self):return b'{"records":[]}'
        with patch.object(m.urllib.request,'urlopen',return_value=Response()) as call:
            m.get_json('https://api.airtable.com/v0/test','private')
        request=call.call_args.args[0]
        self.assertEqual(request.get_method(),'GET')
        self.assertNotIn('private',request.full_url)
        self.assertEqual(request.get_header('Authorization'),'Bearer private')
    def test_worker_failure_preserves_last_success_without_blocking_snapshot(self):
        entered=threading.Event();proceed=threading.Event()
        def fetch(token,**kwargs):
            entered.set();proceed.wait(2);raise ValueError('Temporary failure')
        with tempfile.TemporaryDirectory() as directory:
            p=m.Planning(directory);p.data.update(rows=[{'id':'saved','fields':{}}],updatedAt=12)
            p.refresh('pat'+'x'*30)
            with patch.object(m,'fetch_view',side_effect=fetch):
                p.start();self.assertTrue(entered.wait(1))
                self.assertEqual(p.snapshot()['rows'][0]['id'],'saved')
                self.assertTrue(p.snapshot()['busy'])
                p.close();proceed.set();p.thread.join(2)
            self.assertEqual(p.snapshot()['updatedAt'],12)
            self.assertEqual(p.snapshot()['error'],'Temporary failure')
            self.assertFalse(p.path.exists(),'failed tokens must not replace stored credential')
    def test_view_links_and_ids_are_validated(self):
        view=m.view_config('viwDqzyeYiDPtrdHA','Funded')
        self.assertEqual(view['table'],m.TABLE)
        self.assertEqual(view['view'],'viwDqzyeYiDPtrdHA')
        self.assertEqual(view['name'],'Funded')
        full=m.view_config('https://airtable.com/appOther123/tblOther123/viwOther123?blocks=hide')
        self.assertEqual((full['base'],full['table'],full['view']),('appOther123','tblOther123','viwOther123'))
        for link in ['https://evil.example/appOther123/tblOther123/viwOther123','https://airtable.com.evil.example/a','http://airtable.com/appOther123/tblOther123/viwOther123','https://airtable.com/shr123456','viw1?view=other',None]:
            with self.assertRaises(ValueError):m.view_config(link)
    def test_custom_table_and_view_used_on_every_page_and_schema(self):
        urls=[]
        def get(url,token):
            urls.append(url)
            if '/meta/' in url:return {'tables':[{'id':'tblOther123','fields':[{'name':'Empty money','type':'currency'}]}]}
            self.assertIn('/appOther123/tblOther123?',url)
            self.assertEqual(parse_qs(urlparse(url).query)['view'],['viwOther123'])
            if len(urls)==1:return {'records':[],'offset':'next'}
            return {'records':[]}
        with patch.object(m.time,'sleep'):
            result=m.fetch_view('private',get,base='appOther123',table_id='tblOther123',view='viwOther123')
        self.assertEqual(result['columns'],[{'name':'Empty money','type':'currency'}])
        self.assertIn('/meta/bases/appOther123/tables',urls[-1])
    def test_saved_view_catalog_and_separate_caches(self):
        with tempfile.TemporaryDirectory() as directory:
            p=m.Planning(directory);default=p.active
            p.data.update(rows=[{'id':'old','fields':{}}],updatedAt=1)
            p.select_view(link='viwDqzyeYiDPtrdHA',name='Funded');new=p.active
            self.assertEqual(p.snapshot()['rows'],[])
            p.select_view(link='viwDqzyeYiDPtrdHA')
            self.assertEqual(len(p.views),2)
            self.assertEqual(p.views[-1]['name'],'Funded')
            restored=m.Planning(directory)
            self.assertEqual(restored.active,new);self.assertEqual(len(restored.views),2)
            p.select_view(key=default)
            self.assertEqual(p.snapshot()['rows'][0]['id'],'old')
            with self.assertRaises(ValueError):p.select_view(key='unknown')
            self.assertEqual(p.active,default)
    def test_late_response_does_not_replace_new_view_data(self):
        entered=threading.Event();proceed=threading.Event()
        def fetch(token,**kwargs):
            entered.set();proceed.wait(2)
            return {'rows':[{'id':'old-view-record','fields':{}}],'columns':[]}
        with tempfile.TemporaryDirectory() as directory:
            p=m.Planning(directory);p.refresh('pat'+'x'*30)
            with patch.object(m,'fetch_view',side_effect=fetch),patch.object(m,'credential'):
                p.start();self.assertTrue(entered.wait(1))
                p.select_view(link='viwDqzyeYiDPtrdHA');p.close();proceed.set();p.thread.join(2)
            self.assertEqual(p.snapshot()['rows'],[])
            self.assertTrue(p.snapshot()['viewKey'].endswith('viwDqzyeYiDPtrdHA'))

    def test_credential_secret_uses_stdin_not_arguments(self):
        class Result:returncode=0;stdout=''
        with patch.object(m.subprocess,'run',return_value=Result()) as call:
            m.credential(Path('private.dat'),'sensitive-value')
        self.assertNotIn('sensitive-value',str(call.call_args.args))
        self.assertEqual(json.loads(call.call_args.kwargs['input'])['token'],'sensitive-value')

if __name__=='__main__':unittest.main()
