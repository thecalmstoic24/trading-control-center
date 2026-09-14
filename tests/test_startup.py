"""Isolated Python models Windows embedded runtime import-path behavior."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class StartupTests(unittest.TestCase):
    def test_coordinator_starts_without_script_directory_on_search_path(self):
        server=Path(__file__).resolve().parents[1]/'coordinator'/'server.py'
        with tempfile.TemporaryDirectory() as cwd:
            result=subprocess.run([sys.executable,'-I',str(server),'--help'],cwd=cwd,capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('--data-dir',result.stdout)
