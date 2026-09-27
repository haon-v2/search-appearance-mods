"""Regressions for the 1.0.4 window/session and sidebar changes."""
import json,os,socket,sys,time
from pathlib import Path
world=os.environ['APPEARANCE_TEST_WORLD']
sock=str(Path.home()/f'Library/Application Support/Search Mod Preview ({world})/bench.sock')
def ask(**request):
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(40);s.connect(sock);s.sendall(json.dumps(request).encode()+b'\n');data=b''
        while b'\n' not in data:
            part=s.recv(1<<20)
            assert part,'Lost test connection'
            data+=part
    answer=json.loads(data.split(b'\n')[0]);assert 'error' not in answer,answer
    return answer
def state(window=1,**kw):return ask(do='tabFolders',window=window,**kw)
if '--restored' in sys.argv:
    windows=ask(do='windows')['windows']
    assert len(windows)==2,windows
    assert any(t['url']=='https://example.invalid/window-two' and t['folder'] for t in state(2)['tabs'])
    assert ask(do='group',window=1)['groups'][0]['name']=='Native group'
    print('PASS: multiple windows restore folder membership and native group data',flush=True)
    sys.exit()
ask(do='ui',settings=False,sidebar=True,folded=False,peek=False,side='right')
for width in (176,300,440):
    ask(do='appearance',sidebarWidth=width);time.sleep(.35)
    rail=ask(do='appearance');assert rail['rail'] and abs(rail['railX'])<2,rail
    assert abs(rail['width']-(1180-width))<3,rail
ask(do='picture',path='/tmp/search104-right-sidebar.png',page=False)
ask(do='ui',side='left');ask(do='appearance',sidebarWidth=280)
s=state();research=next(f['id'] for f in s['folders'] if f['name']=='Research')
# The definition store is shared; each window retains only its own tabs.
ask(do='windows',action='new');assert len(ask(do='windows')['windows'])==2
assert state(2)['folders']==state(1)['folders']
state(2,folder=research,rename='Shared Research')
assert next(f['name'] for f in state(1)['folders'] if f['id']==research)=='Shared Research'
state(1,folder=research,rename='Research')
first=next(t['id'] for t in state(1)['tabs'] if t['folder']==research)
ask(do='towindow',window=1,id=first,to=2)
assert next(t['folder'] for t in state(2)['tabs'] if t['id']==first)==research
assert first not in [t['id'] for t in state(1)['tabs']]
ask(do='towindow',window=2,id=first,to=1)
# Removing a folder in either window cannot leave dangling memberships elsewhere.
temp=state(1,create='Remove across windows')['folders'][-1]['id']
state(1,move=first,folder=temp)
state(2,folder=temp,delete=True)
assert next(t['folder'] for t in state(1)['tabs'] if t['id']==first)==''
state(1,move=first,folder=research)
state(2,importJSON=json.dumps([{'name':'Research','tabs':[{'title':'Second window','url':'https://example.invalid/window-two'}]}]))
assert any(t['folder']==research for t in state(2)['tabs'])
# Both group formats survive session encoding and module toggles.
ask(do='ui',window=1,tabGroups=True)
ask(do='group',window=1,id=first[:8].lower(),new=True,name='Native group')
assert ask(do='group',window=1)['groups'][0]['name']=='Native group'
ask(do='appearance',window=1,disable='curve.tab-folders',enable='')
assert ask(do='group',window=1)['groups'][0]['name']=='Native group'
assert next(t['folder'] for t in state(1)['tabs'] if t['id']==first)==research
ask(do='appearance',window=1,enable='test.rail');ask(do='appearance',window=1,enable='curve.tab-folders')
state(1);state(2)
ask(do='windows',action='front',n=1)
print('PASS: right sidebar sizes, shared folder definitions, cross-window moves/deletion, independent sessions and native groups',flush=True)
