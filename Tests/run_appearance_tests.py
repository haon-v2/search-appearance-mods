from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='search-mod-tests-') as tmp:
    tmp=Path(tmp)
    (tmp/'main.swift').write_text((root/'Tests/appearance-tests.swift').read_text())
    subprocess.run(['swiftc','-swift-version','5','-module-cache-path',str(root/'.build/mod-test-cache'),str(root/'Sources/Search/AppearanceModStore.swift'),str(tmp/'main.swift'),'-o',str(tmp/'tests')],check=True)
    subprocess.run([str(tmp/'tests'),str(root/'Tests/fixtures/edge-rail.json')],env=dict(os.environ,MOD_TEST_ROOT=str(tmp)),check=True)
