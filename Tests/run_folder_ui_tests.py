"""Folder integration against the real, isolated Search app; no personal profile."""
import json, os, socket, sys, time, http.server, threading
from pathlib import Path
root = Path(__file__).resolve().parents[1]
world = os.environ['APPEARANCE_TEST_WORLD']
sock = str(Path.home()/f'Library/Application Support/Search Mod Preview ({world})/bench.sock')
def ask(error=False, **request):
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(40); s.connect(sock); s.sendall(json.dumps(request).encode()+b'\n'); data=b''
        while b'\n' not in data: data += s.recv(1<<20)
    answer=json.loads(data.split(b'\n')[0])
    assert ('error' in answer) == error, answer
    return answer
def state(**kw): return ask(do='tabFolders',**kw)
if '--restored' in sys.argv:
    s=state()
    assert s['enabled'] and any(f['name']=='Research' for f in s['folders']), s
    research=next(f['id'] for f in s['folders'] if f['name']=='Research')
    assert sum(t['folder']==research for t in s['tabs']) >= 2, s
    assert ask(do='appearance')['enabled']=='test.rail'
    print('PASS: folders, tab membership and both enabled mods survive a real app restart',flush=True)
    sys.exit()
class Page(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers()
        self.wfile.write(b'<title>Research notebook</title><style>body{background:#faf9f6;color:#333;font:22px system-ui;padding:60px}</style><h1>A place for every thought.</h1><p>Sidebar folders keep your research together.</p>')
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Page)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    ask(do='ui',sidebar=True,welcome=False,settings=False,folded=False)
    ask(do='appearance',sidebarWidth=280,enable='test.rail')
    ask(do='appearance',install=str(root/'Tests/fixtures/tab-folders.json'))
    ask(do='appearance',enable='curve.tab-folders')
    assert ask(do='appearance')['enabled']=='test.rail'
    research=state(create='Research')['folders'][-1]['id']
    reading=state(create='Reading')['folders'][-1]['id']
    assert state()['savedFolders']==2
    before=ask(do='appearance')['views']
    payload=json.dumps([{'name':'Research','tabs':[{'title':f'Notebook {i}','url':f'http://127.0.0.1:{server.server_port}/notes/{i}'} for i in range(3)]+[{'title':'bad','url':'javascript:alert(1)'}]}])
    s=state(importJSON=payload)
    imported=[t for t in s['tabs'] if t['folder']==research]
    assert len(imported)==3 and all(not t['built'] for t in imported)
    assert ask(do='appearance')['views']==before, 'Import constructed extra WebViews'
    assert len([t for t in state(importJSON=payload)['tabs'] if t['folder']==research])==3
    first,second,third=[t['id'] for t in imported]
    # The exact validated payload consumed by the native drag/drop delegate.
    s=state(drop=s['nonce']+':'+first,folder=reading)
    assert next(t for t in s['tabs'] if t['id']==first)['folder']==reading
    state(error=True,drop='other-window:'+first,folder=research)
    state(error=True,move=first,folder='00000000-0000-0000-0000-000000000001')
    state(folder=reading,rename='Reading list')
    assert next(f for f in state()['folders'] if f['id']==reading)['name']=='Reading list'
    state(folder=research,collapsed=True)
    assert next(f for f in state()['folders'] if f['id']==research)['collapsed']
    ask(do='select',id=second);ask(do='wait',id=second)
    s=state()
    assert not next(f for f in s['folders'] if f['id']==research)['collapsed']
    assert set(s['railTabs'])=={second,third}
    # Native rail reordering must map its filtered positions to the full tab array.
    time.sleep(.3)
    ask(do='appearance',offset=0,dragFrom=80,dragTo=300)
    assert state()['railTabs']==[third,second],state()
    state(newTab=True)
    s=state();blank=next(t for t in s['tabs'] if t['folder']==research and not t['url'])
    state(close=blank['id'])
    ask(do='select',id=second);state(duplicate=True)
    s=state();duplicate=next(t for t in reversed(s['tabs']) if t['folder']==research and t['id'] not in (second,third))
    state(close=duplicate['id']);state(reopen=True)
    assert len([t for t in state()['tabs'] if t['folder']==research])==3
    s=state(privateTab=True);private=next(t for t in s['tabs'] if t['private'])
    state(error=True,move=private['id'],folder=research)
    state(close=private['id'])
    assert all(t['folder'] for t in state()['savedTabs'])
    # Disabling only changes presentation, never tab identity or allocated pages.
    before=state()['tabs'];views=ask(do='appearance')['views']
    ask(do='appearance',disable='curve.tab-folders')
    assert not state()['enabled'] and state()['tabs']==before
    assert ask(do='appearance')['views']==views
    ask(do='appearance',enable='curve.tab-folders')
    state(folder=reading,delete=True)
    assert next(t for t in state()['tabs'] if t['id']==first)['folder']==''
    exported=json.loads(state()['exportJSON'])
    assert len(exported)==1 and exported[0]['name']=='Research'
    # Folder definitions and tab membership cannot cross spaces.
    ask(do='ui',spaces=True)
    ask(do='space',action='new',name='Separate test space')
    assert not state()['folders']
    state(error=True,folder=research,move=first)
    ask(do='space',action='go',index=1)
    assert any(f['id']==research for f in state()['folders'])
    # Screenshot includes actual native sidebar and the coexisting curved rail.
    ask(do='select',id=second);ask(do='resize',width=1180,height=780,steps=1)
    time.sleep(.5);ask(do='picture',path='/tmp/search-tab-folders.png',page=False)
    ask(do='appearance',settingsPage='Appearance');ask(do='ui',settings=True)
    time.sleep(.5);ask(do='picture',path='/tmp/search-tab-folders-settings.png',page=False)
    ask(do='ui',settings=False)
    state()
    print('PASS: lazy import, deduplication, safe drag/drop, CRUD, private tabs, scoped rail, new/duplicate/reopen, disabling, export and workspace isolation',flush=True)
finally:
    server.shutdown()
