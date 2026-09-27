#!/usr/bin/env python3
import importlib.util, subprocess, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='loader-feed-test-') as d:
    d=Path(d);(d/'main.swift').write_text((root/'Tests/loader-update-tests.swift').read_text())
    subprocess.run(['swiftc','-module-cache-path',str(root/'.build/mod-test-cache'),str(root/'Sources/Search/LoaderRelease.swift'),str(d/'main.swift'),'-o',str(d/'test')],check=True)
    subprocess.run([str(d/'test')],check=True)
spec=importlib.util.spec_from_file_location('sync',root/'Scripts/sync_upstream.py')
sync=importlib.util.module_from_spec(spec);spec.loader.exec_module(sync)

def run(repo,*args):
    return subprocess.run(['git',*args],cwd=repo,text=True,capture_output=True,check=True).stdout.strip()

class IntegrationTests(unittest.TestCase):
    def test_versions(self):
        self.assertGreater(sync.version('v1.0.10'),sync.version('v1.0.9'))
        for invalid in ('v1.0.4-beta','../main','main','1.2'):
            with self.assertRaises(ValueError):sync.version(invalid)

    def integration(self, conflict):
        with tempfile.TemporaryDirectory(prefix='search-sync-test-') as folder:
            folder=Path(folder);upstream=folder/'upstream';upstream.mkdir()
            run(upstream,'init','-b','main');run(upstream,'config','user.name','Test');run(upstream,'config','user.email','test@example.invalid')
            (upstream/'README.md').write_text('Original README\n');(upstream/'code.swift').write_text('original\n')
            run(upstream,'add','.');run(upstream,'commit','-m','base');run(upstream,'tag','v1.0.0')
            fork=folder/'fork';run(folder,'clone',str(upstream),str(fork));run(fork,'config','user.name','Test');run(fork,'config','user.email','test@example.invalid')
            for name,value in {'UPSTREAM_VERSION':'v1.0.0\n','UPSTREAM_COMMIT':'base\n','LOADER_VERSION':'0.2.0\n','LOADER_BUILD':'3\n','MOD-CHANGELOG.md':'# Loader\n\n## 0.2.0\n\nInitial\n','README.md':'Our loader README\n'}.items(): (fork/name).write_text(value)
            if conflict:(fork/'code.swift').write_text('fork changed same line\n')
            run(fork,'add','.');run(fork,'commit','-m','loader')
            before=run(fork,'rev-parse','HEAD')
            (upstream/'README.md').write_text('New upstream README\n');(upstream/'code.swift').write_text('new upstream\n')
            run(upstream,'add','.');run(upstream,'commit','-m','upstream update');run(upstream,'tag','v1.0.1')
            original=sync.git
            def local_git(*args,**kwargs):
                args=tuple(str(upstream) if a=='https://github.com/driceroland/Search.git' else a for a in args)
                return original(*args,**kwargs)
            with patch.object(sync,'ROOT',fork),patch.object(sync,'git',local_git):
                if conflict:
                    with self.assertRaisesRegex(RuntimeError,'needs review'):sync.integrate('v1.0.1')
                    self.assertEqual(run(fork,'rev-parse','HEAD'),before)
                    self.assertEqual(run(fork,'status','--porcelain'),'')
                    self.assertEqual((fork/'LOADER_BUILD').read_text(),'3\n')
                else:
                    self.assertTrue(sync.integrate('v1.0.1'))
                    self.assertEqual((fork/'README.md').read_text(),'Our loader README\n')
                    self.assertEqual((fork/'README-UPSTREAM.md').read_text(),'New upstream README\n')
                    self.assertEqual((fork/'code.swift').read_text(),'new upstream\n')
                    self.assertEqual((fork/'LOADER_BUILD').read_text(),'4\n')
                    self.assertEqual((fork/'LOADER_VERSION').read_text(),'0.2.1\n')
                    self.assertFalse(sync.integrate('v1.0.1'))
                    self.assertFalse(sync.integrate('v1.0.0'))
                    self.assertEqual(run(fork,'status','--porcelain'),'')
    def test_clean_merge(self):self.integration(False)
    def test_code_conflict_stops(self):self.integration(True)

unittest.main()
