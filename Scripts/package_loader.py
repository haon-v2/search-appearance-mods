#!/usr/bin/env python3
"""Package the checked app and publishable manifest; never ship a mod."""
import hashlib, json, plistlib, shutil, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
version = (root/'LOADER_VERSION').read_text().strip()
build = int((root/'LOADER_BUILD').read_text())
tag = 'appearance-mods-v' + version
out = root/'build/releases'/tag
stage = out/'Search Appearance Mod Loader'
stage.mkdir(parents=True, exist_ok=True)
app = root/'build/Search Mod Preview.app'
with (app/'Contents/Info.plist').open('rb') as f: info = plistlib.load(f)
assert info['CFBundleIdentifier'] == 'local.noah.search.mod-preview'
assert info['CFBundleShortVersionString'] == version and int(info['CFBundleVersion']) == build
assert info['SearchUpstreamVersion'] == (root/'UPSTREAM_VERSION').read_text().strip()
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
# Packaging an app containing an accidentally bundled JSON mod is an error.
assert not list((app/'Contents/Resources').glob('*.json')), 'No mods may be bundled'
if (stage/app.name).exists(): shutil.rmtree(stage/app.name)
shutil.copytree(app, stage/app.name)
for name in ('LICENSE','CREDITS.md'): shutil.copy2(root/name, stage/name)
shutil.copy2(root/'docs/UPDATING.md', stage/'INSTALL.md')
archive = out/'Search-Appearance-Mod-Loader-macOS-arm64.zip'
if archive.exists(): archive.unlink()
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(stage),str(archive)], check=True)
source = out/'Search-Appearance-Mod-Loader-Source.tar.gz'
subprocess.run(['git','archive','--format=tar.gz','--prefix=search-appearance-mod-loader/','-o',str(source),'HEAD'],cwd=root,check=True)
url = 'https://github.com/haon-v2/search-appearance-mods/releases/'
manifest = dict(schemaVersion=1,version=version,build=build,upstreamVersion=(root/'UPSTREAM_VERSION').read_text().strip(),minimumSystemVersion='14.0',architecture='arm64',archive=url+'download/'+tag+'/'+archive.name,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),releaseURL=url+'tag/'+tag)
(out/'loader-update.json').write_text(json.dumps(manifest,indent=2)+'\n')
files = [archive,source,out/'loader-update.json']
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in files))
notes = root/'docs/releases'/f'{version}.md'
if notes.exists(): body = notes.read_text()
else:
    body = f'''# Appearance Mod Loader {version} Preview\n\nBased on Search {manifest['upstreamVersion']} by **Drice Roland / Office Commun and its contributors**. Appearance support by **Noah Helms (@haon-v2)**. Unofficial, not endorsed by Search.\n\nIntegrates the latest stable Search release. Build, schema and native UI compatibility checks passed before publication. See [Search's release](https://github.com/driceroland/Search/releases/tag/{manifest['upstreamVersion']}) for browser changes.\n\nNo mods bundled. [Curve Tabs](https://github.com/haon-v2/curve-tabs) remains a separate optional mod.\n\nQuit Search Mod Preview, unzip the download and replace **Search Mod Preview.app**. Existing preview data and mods stay in place. Leave official Search.app alone. Apple Silicon, macOS 14+, ad-hoc signed and not notarized.\n\nFirst switching from official Search requires signing into websites again. Drice / Office Commun would need to integrate and officially sign the loader to deliver a normal Search update retaining its sign-ins; no upstream commitment is implied.\n\nFuture compatibility is checked, not guaranteed. Source conflicts or failed tests stop automatic publication. Preview Settings → About checks compatible releases; installation is manual.\n'''
(out/'release-notes.md').write_text(body)
print(out)
