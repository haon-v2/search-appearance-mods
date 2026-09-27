#!/usr/bin/env python3
"""Exercise the shipping installer and helper with temporary keys/apps, never a user's app."""
import json, os, subprocess, tempfile, time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def run(*args, **kw): return subprocess.run(list(map(str,args)),check=True,**kw)
with tempfile.TemporaryDirectory(prefix='loader-install-tests-') as folder:
    folder=Path(folder)
    keygen=folder/'keygen.swift'
    keygen.write_text('import CryptoKit\nlet k=Curve25519.Signing.PrivateKey();print(k.rawRepresentation.base64EncodedString());print(k.publicKey.rawRepresentation.base64EncodedString())\n')
    private,public=subprocess.check_output(['swift',str(keygen)],text=True).splitlines()
    core=folder/'LoaderInstallCore.swift'
    core.write_text((root/'Sources/Search/LoaderInstallCore.swift').read_text().replace((root/'LOADER_UPDATE_PUBLIC_KEY').read_text().strip(),public).replace("process.standardError = FileHandle.nullDevice", "process.standardError = FileHandle.standardError"))
    main=folder/'main.swift';main.write_text((root/'Tests/loader-install-tests.swift').read_text())
    compiler=['swiftc','-module-cache-path',str(root/'.build/mod-test-cache'),str(root/'Sources/Search/LoaderRelease.swift'),str(core)]
    run(*compiler,main,'-o',folder/'tests')
    run(*compiler,'-parse-as-library',root/'Tools/LoaderInstallHelper.swift','-o',folder/'helper')
    env=dict(os.environ,TEST_LOADER_PRIVATE=private,TEST_LOADER_ROOT=str(folder),TEST_LOADER_HELPER=str(folder/'helper'))
    run(folder/'tests',env=env)
print('PASS: signed installer, rollback, old-process waiting and real helper relaunch')
