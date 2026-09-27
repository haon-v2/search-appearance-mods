#!/usr/bin/env python3
"""Merge the latest stable Search release. Never guess through source conflicts."""
import json, os, re, subprocess, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def git(*args, check=True):
    return subprocess.run(['git', *args], cwd=ROOT, check=check, text=True, capture_output=True)

def version(value):
    if not re.fullmatch(r'v?\d+\.\d+\.\d+', value):
        raise ValueError('Not a stable semantic version: ' + value)
    return tuple(map(int, value.removeprefix('v').split('.')))

def integrate(tag):
    if version(tag) <= version((ROOT/'UPSTREAM_VERSION').read_text().strip()):
        return False
    if git('status', '--porcelain').stdout.strip():
        raise RuntimeError('Start from a clean checkout')
    git('fetch', '--no-tags', 'https://github.com/driceroland/Search.git', 'refs/tags/' + tag)
    commit = git('rev-parse', 'FETCH_HEAD^{commit}').stdout.strip()
    result = git('merge', '--no-commit', '--no-ff', commit, check=False)
    conflicts = git('diff', '--name-only', '--diff-filter=U').stdout.splitlines()
    # The fork's introductory README is the only intentional documentation override.
    # Never resolve code, workflow, licence or security changes automatically.
    if set(conflicts) - {'README.md'} or (result.returncode and not conflicts):
        git('merge', '--abort', check=False)
        raise RuntimeError('Search integration needs review; no release published. Conflicts: ' + ', '.join(conflicts) + '\n' + result.stderr)
    if 'README.md' in conflicts:
        (ROOT/'README.md').write_text(git('show', 'HEAD:README.md').stdout)
        git('add', 'README.md')
    (ROOT/'README-UPSTREAM.md').write_text(git('show', commit + ':README.md').stdout)
    # The merge may already exist through an earlier integration: still record its release.
    (ROOT/'UPSTREAM_VERSION').write_text(tag + '\n')
    (ROOT/'UPSTREAM_COMMIT').write_text(commit + '\n')
    major, minor, patch = version((ROOT/'LOADER_VERSION').read_text().strip())
    loader = f'{major}.{minor}.{patch+1}'
    (ROOT/'LOADER_VERSION').write_text(loader+'\n')
    (ROOT/'LOADER_BUILD').write_text(str(int((ROOT/'LOADER_BUILD').read_text())+1)+'\n')
    changelog = ROOT/'MOD-CHANGELOG.md'
    content = changelog.read_text()
    marker = content.index('\n## ')
    changelog.write_text(content[:marker] + f'\n## {loader}\n\n- Integrate Search {tag}. Published only after loader validation and native compatibility checks pass. See upstream CHANGELOG.md for browser changes.\n' + content[marker:])
    git('add', 'README-UPSTREAM.md', 'UPSTREAM_VERSION', 'UPSTREAM_COMMIT', 'LOADER_VERSION', 'LOADER_BUILD', 'MOD-CHANGELOG.md')
    git('commit', '-m', f'Integrate Search {tag} into appearance loader {loader}')
    return True

def release_metadata(path):
    headers = {'User-Agent':'Search-Appearance-Mod-Loader-Sync', 'Accept':'application/vnd.github+json'}
    # CI's read-only token avoids the shared runner's anonymous rate limit.
    # It is scoped to this step; browser users never need a token.
    if token := os.environ.get('GH_TOKEN'):
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request('https://api.github.com/repos/' + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

def main():
    release = release_metadata('driceroland/Search/releases/latest')
    if release.get('draft') or release.get('prerelease'):
        raise RuntimeError('Expected a stable published Search release')
    changed = integrate(release['tag_name'])
    # Retry interrupted publications on the next run, even if the integration
    # was already pushed. Only drafts/missing releases can be published.
    tag = 'appearance-mods-v' + (ROOT/'LOADER_VERSION').read_text().strip()
    try:
        own_release = release_metadata('haon-v2/search-appearance-mods/releases/tags/' + tag)
        publish = own_release['draft']
    except urllib.error.HTTPError as error:
        if error.code != 404: raise
        publish = True
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output,'a') as f:
            f.write('changed='+str(changed).lower()+'\n')
            f.write('publish='+str(publish).lower()+'\n')
    print('New Search release integrated; checks must pass before publishing.' if changed else 'Already based on the latest stable Search release.')

if __name__ == '__main__': main()
