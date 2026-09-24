"""Exercise the isolated preview through Search's test-only native interface."""
import http.server,json,socket,threading,time,os
from pathlib import Path
root=Path(__file__).resolve().parents[1]
world=os.environ.get('APPEARANCE_TEST_WORLD','appearance')
path=str(Path.home()/f'Library/Application Support/Search Mod Preview ({world})/bench.sock')
def ask(**request):
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(40);s.connect(path);s.sendall(json.dumps(request).encode()+b'\n');data=b''
        while b'\n' not in data:
            part=s.recv(1<<20)
            if not part:break
            data+=part
        answer=json.loads(data.split(b'\n')[0])
        assert 'error' not in answer,answer
        return answer
class Page(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers()
        self.wfile.write(f'''<!doctype html><meta charset="utf-8"><title>Research notes {self.path}</title><style>body{{margin:0;padding:60px;font:20px system-ui;background:#f7f5ef;color:#263127}}h1{{font-size:54px;max-width:600px}}button{{padding:12px;border:1px solid #ccc;border-radius:12px;background:white}}p{{max-width:560px;line-height:1.8}}</style><h1>A little room to explore.</h1><p>This is a local test page. The mod’s tabs follow the edge while Search handles the website.</p><button id="click" onclick="this.textContent='Clicked'">Check page interaction</button>'''.encode())
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Page);threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    ask(do='close',id='all')
    package=Path(os.environ.get('APPEARANCE_TEST_MOD',str(root/'Tests/fixtures/edge-rail.json')))
    mod_id=json.loads(package.read_text())['id']
    state=ask(do='appearance')
    if mod_id in state['installed']:ask(do='appearance',remove=mod_id)
    ask(do='appearance',install=str(package))
    ask(do='appearance',enable=mod_id);ask(do='ui',sidebar=False,welcome=False,settings=False)
    time.sleep(.4)
    assert ask(do='appearance')['rail']
    ids=[]
    for n in range(1,10): ids.append(ask(do='open',url=f'http://127.0.0.1:{server.server_port}/note-{n}')['id'])
    ask(do='wait',id=ids[0]);ask(do='select',id=ids[0]);time.sleep(.5)
    before=ask(do='tabs')['tabs']
    views=ask(do='appearance')['views']
    ask(do='appearance',enable='');time.sleep(.4)
    assert not ask(do='appearance')['rail']
    ask(do='appearance',enable=mod_id);time.sleep(.4)
    after=ask(do='tabs')['tabs']
    assert [t['id'] for t in before]==[t['id'] for t in after]
    assert views==ask(do='appearance')['views'], 'Appearance switch rebuilt a webpage'
    ask(do='tap',id=ids[0],selector='#click')
    for _ in range(40):
        label=ask(do='eval',id=ids[0],js="document.querySelector('#click').textContent")['value']
        if label=='Clicked':break
        time.sleep(.05)
    assert label=='Clicked', label
    print('PASS: import/enable, standard-layout fallback, tab preservation, and actual page clicks',flush=True)
    state=ask(do='appearance',offset=0)
    target=state['tabs'][2]['id']
    ask(do='appearance',click=2*222+100);time.sleep(.2)
    assert next(t['id'] for t in ask(do='tabs')['tabs'] if t['active'])==target
    state=ask(do='appearance',offset=0);original=state['tabs'][1]['id']
    ask(do='appearance',dragFrom=222+90,dragTo=3*222+90);time.sleep(.2)
    assert ask(do='tabs')['tabs'][3]['id']==original
    state=ask(do='appearance',offset=0);closing=state['tabs'][4]['id']
    ask(do='appearance',click=4*222+190);time.sleep(.2)
    assert closing not in [t['id'] for t in ask(do='tabs')['tabs']]
    state=ask(do='appearance',offset=1e8)
    assert state['maximum']>0 and state['offset']==state['maximum']
    print('PASS: selecting, dragging through the bend, closing a vertical tab, and bounded overflow scrolling',flush=True)
    for width,height in [(640,480),(1440,900),(1180,780)]:
        ask(do='resize',width=width,height=height,steps=1);time.sleep(.2)
        state=ask(do='appearance');assert state['width']==width and 0<=state['offset']<=state['maximum']
    first=next(t['id'] for t in ask(do='tabs')['tabs'] if t['bench'])
    ask(do='select',id=first);ask(do='appearance',offset=0)
    for look in ['light','dark']:
        ask(do='ui',look=look);time.sleep(.3)
        ask(do='picture',path=f'/tmp/search-mod-{look}.png',page=False)
    ask(do='appearance',settingsPage='appearance')
    ask(do='ui',settings=True);time.sleep(.3)
    ask(do='picture',path='/tmp/search-mod-settings.png',page=False)
    ask(do='ui',settings=False,folded=True,peek=True);time.sleep(.5)
    assert ask(do='appearance')['rail']
    ask(do='ui',folded=False,peek=False)
    print('PASS: narrow/wide resize, light/dark rendering and folded rail reveal',flush=True)
finally:server.shutdown()
