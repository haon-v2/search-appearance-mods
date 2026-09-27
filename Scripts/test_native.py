#!/usr/bin/env python3
"""Run the real app in a disposable test world, never a person's profile."""
import os, subprocess, time, uuid
from pathlib import Path
root = Path(__file__).resolve().parents[1]
world = 'loader-ci-' + uuid.uuid4().hex[:8]
identity = 'local.noah.search.mod-preview.test.' + world
for key in ('bench', 'welcomed'):
    subprocess.run(['defaults', 'write', identity, key, '-bool', 'true'], check=True)
env = dict(os.environ, SEARCH_PROBE=world, APPEARANCE_TEST_WORLD=world)
log = Path('/tmp') / (world + '.log')
with log.open('w') as output:
    app = subprocess.Popen([str(root/'build/Search Mod Preview.app/Contents/MacOS/SearchModPreview')], cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
    try:
        sock = Path.home()/f'Library/Application Support/Search Mod Preview ({world})/bench.sock'
        for _ in range(120):
            if app.poll() is not None: raise RuntimeError('Preview exited: ' + log.read_text())
            if sock.exists(): break
            time.sleep(.25)
        else: raise RuntimeError('Test interface did not start: ' + log.read_text())
        subprocess.run(['python3', 'Tests/run_appearance_ui_tests.py'], cwd=root, env=env, check=True, timeout=180)
        subprocess.run(['python3', 'Tests/run_folder_ui_tests.py'], cwd=root, env=env, check=True, timeout=180)
        subprocess.run(['python3', 'Tests/run_search104_ui_tests.py'], cwd=root, env=env, check=True, timeout=180)
        app.terminate(); app.wait(timeout=10)
        if sock.exists(): sock.unlink()
        app = subprocess.Popen([str(root/'build/Search Mod Preview.app/Contents/MacOS/SearchModPreview')], cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
        for _ in range(120):
            if app.poll() is not None: raise RuntimeError('Preview exited on restart')
            if sock.exists(): break
            time.sleep(.25)
        else: raise RuntimeError('Test interface did not restart')
        subprocess.run(['python3', 'Tests/run_folder_ui_tests.py', '--restored'], cwd=root, env=env, check=True, timeout=60)
        subprocess.run(['python3', 'Tests/run_search104_ui_tests.py', '--restored'], cwd=root, env=env, check=True, timeout=60)
    finally:
        app.terminate()
        try: app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill(); app.wait()
        # Only our newly created, uniquely named test settings.
        subprocess.run(['defaults', 'delete', identity], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print('PASS: isolated native app checks')
