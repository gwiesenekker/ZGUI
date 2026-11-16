#!/usr/bin/env python3
"""Integrated stdin/stdout + GUI checks. Run only on tests/run_hidden_gui.py's display."""
import ctypes,json,os,pathlib,select,shutil,subprocess,sys,tempfile,time
helper=str(pathlib.Path(sys.argv[1]).resolve()); actual=str(pathlib.Path(sys.argv[2]).resolve()) if len(sys.argv)>2 else None
checks=0
def check(b,label):
 global checks
 checks+=1
 if not b: raise AssertionError(label)
class Client:
 def __init__(self,exe,args,folder):
  self.log=open(folder/'stderr.log','wb'); self.buffer=b''
  self.p=subprocess.Popen([exe,*args],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.log,
       env=dict(os.environ,XDG_CONFIG_HOME=str(folder/'config')),start_new_session=(os.name=='posix'))
 def command(self,line,expected='OK',timeout=6):
  self.p.stdin.write((line+'\n').encode());self.p.stdin.flush()
  end=time.monotonic()+timeout
  while b'\n' not in self.buffer:
   if time.monotonic()>end: raise AssertionError('No response for '+line)
   if select.select([self.p.stdout],[],[],.1)[0]:
    data=os.read(self.p.stdout.fileno(),65536)
    if not data: raise AssertionError('Unexpected stdout EOF for '+line)
    self.buffer+=data
  raw,self.buffer=self.buffer.split(b'\n',1)
  prefix,payload=raw.split(b' ',1);check(prefix.decode()==expected,'response prefix for '+line+': '+raw.decode(errors='replace'))
  return json.loads(payload)
 def check_tail(self):
  tail=self.buffer;end=time.monotonic()+3;closed=False
  while time.monotonic()<end:
   if select.select([self.p.stdout],[],[],.1)[0]:
    data=os.read(self.p.stdout.fileno(),65536)
    if not data:closed=True;break
    tail+=data
  check(closed,'protocol stdout closes with the GUI')
  check(not tail,'no unsolicited or partial stdout bytes at shutdown: '+repr(tail[:300]))
 def cleanup(self):
  if self.p.poll() is None:
   self.p.terminate()
   try:self.p.wait(timeout=3)
   except subprocess.TimeoutExpired:self.p.kill();self.p.wait()
  for f in [self.p.stdin,self.p.stdout]:
   if f and not f.closed:f.close()
  self.log.close()
def report(path,predicate,timeout=7):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:
   data=json.loads(path.read_text())
   if predicate(data):return data
  except (OSError,json.JSONDecodeError):pass
  time.sleep(.05)
 raise AssertionError('GUI state did not reach expected condition: '+str(path))
with tempfile.TemporaryDirectory(prefix='zgui-cli-application-') as tmp:
 root=pathlib.Path(tmp)
 live=root/'live';live.mkdir();state=live/'state.json';c=Client(helper,['--session',str(state)],live)
 try:
  data=c.command('list_engines');check(len(data['engines'])==4,'session sees test registrations')
  a=c.command('run_tournament engine1_id=1 engine2_id=2 name="Chess Ö" time=120 increment=0 allow_shared_executable=true')
  b=c.command('run_tournament engine1_id=3 engine2_id=4 name="Draughts" time=120 increment=0')
  check(a['tournament']!=b['tournament'],'distinct tournament handles')
  r=report(state,lambda x:x['chess_plies']>0 and x['draughts_plies']>0 and x['chess_viewed'] and x['draughts_viewed'])
  check(r['main_visible'] and r['host_visible'] and r['games']==2,'GUI stays live and rows select both running boards')
  for match in [a,b]:
   q=c.command('query_tournament id='+str(match['tournament']));check(q['games_total']==2,'query actual ordinary match')
  pathlib.Path(str(state)+'.modal').touch()
  end=time.monotonic()+4
  while not pathlib.Path(str(state)+'.modal.ready').exists() and time.monotonic()<end:time.sleep(.05)
  check(pathlib.Path(str(state)+'.modal.ready').exists(),'real modal dialog opened')
  busy=c.command('list_engines','ERROR');check(busy['code']=='BUSY','pipe request refuses nested modal loop')
  busy=c.command('query_tournament id='+str(a['tournament']),'ERROR');check(busy['code']=='BUSY','pipe query refuses open modal')
  pathlib.Path(str(state)+'.modal.done').touch();end=time.monotonic()+4
  while not pathlib.Path(str(state)+'.modal.closed').exists() and time.monotonic()<end:time.sleep(.05)
  check(pathlib.Path(str(state)+'.modal.closed').exists(),'modal dialog closed normally')
  c.command('list_engines')
  for i in range(3):
   extra=c.command(f'run_tournament engine1_id=1 engine2_id=2 name="Extra {i}" time=120 allow_shared_executable=true')
   check(extra['games_total']==2,'additional tournament uses normal pairing')
  report(state,lambda x:x['tabs']==5)
  pathlib.Path(str(state)+'.engine-problem').touch()
  report(state,lambda x:x['engine_notices'])
  c.command('list_engines')
  q=c.command('query_tournament id='+str(a['tournament']))
  check(q['games_total']==2,'queued engine notices do not block read-only CLI')
  state.with_suffix('.json.stop').touch()
  for match in [a,b]:
   end=time.monotonic()+6
   while True:
    q=c.command('query_tournament id='+str(match['tournament']))
    if q['state'] in ['attention','stopped','completed','error']:break
    if time.monotonic()>end:raise AssertionError('GUI Stop not reflected by query')
    time.sleep(.1)
   check(q['games_active']==0,'GUI Stop stops CLI-started games')
  c.p.stdin.close();before=report(state,lambda x:True)['ticks'];time.sleep(.2)
  after=report(state,lambda x:x['ticks']>before)
  check(c.p.poll() is None and after['main_visible'],'input EOF leaves GUI and tournament window open')
  state.with_suffix('.json.close').touch();c.p.wait(timeout=5);check(c.p.returncode==0,'GUI close shuts down integrated session')
  c.check_tail();check(b'diagnostic-probe' in (live/'stderr.log').read_bytes(),'buffered diagnostics go to stderr')
 finally:c.cleanup()
 for blocked in [False,True]:
  folder=root/('blocked' if blocked else 'idle');folder.mkdir();state=folder/'state.json';c=Client(helper,['--session',str(state)],folder)
  try:
   r=report(state,lambda x:x['main_visible'])
   if blocked:
    c.p.stdin.write(b'list_engines\n'*200);c.p.stdin.flush();time.sleep(.25)
   state.with_suffix('.json.close').touch();c.p.wait(timeout=5)
   check(c.p.returncode==0,'GUI shutdown cancels '+('blocked output' if blocked else 'idle input'))
  finally:c.cleanup()
 if actual and os.name=='posix':
  # Run the identical release binary in a private directory, never the user's configs.
  folder=root/'actual';folder.mkdir();exe=folder/'zgui';shutil.copy2(actual,exe)
  shutil.copy2(pathlib.Path(helper).parent/'engines.json',folder/'engines.json')
  c=Client(str(exe),['--cli'],folder)
  try:
   data=c.command('list_engines');check(len(data['engines'])==4,'actual zgui --cli reaches the GUI dispatcher')
   for i in range(5):
    match=c.command(f'run_tournament engine1_id=1 engine2_id=2 name="Real {i}" time=120 allow_shared_executable=true')
    q=c.command('query_tournament id='+str(match['tournament']))
    check(q['games_total']==2,'real binary creates and queries five tournaments')
   c.command('query_tournament id=999','ERROR')
   c.p.stdin.close();time.sleep(.2);check(c.p.poll() is None,'actual executable keeps GUI alive at EOF')
   windows=[];end=time.monotonic()+3
   while not windows and time.monotonic()<end:
    found=subprocess.run(['xdotool','search','--all','--onlyvisible','--pid',str(c.p.pid),'--name','^ZGUI -'],capture_output=True,text=True)
    windows=found.stdout.split();time.sleep(.05)
   check(bool(windows),'actual GUI main window is visible on the isolated display')
   x=ctypes.CDLL('libX11.so.6');x.XOpenDisplay.argtypes=[ctypes.c_char_p];x.XOpenDisplay.restype=ctypes.c_void_p
   x.XInternAtom.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_int];x.XInternAtom.restype=ctypes.c_ulong
   class Data(ctypes.Union):_fields_=[('b',ctypes.c_char*20),('l',ctypes.c_long*5)]
   class Message(ctypes.Structure):_fields_=[('type',ctypes.c_int),('serial',ctypes.c_ulong),('send',ctypes.c_int),('display',ctypes.c_void_p),('window',ctypes.c_ulong),('message_type',ctypes.c_ulong),('format',ctypes.c_int),('data',Data)]
   class Event(ctypes.Union):_fields_=[('message',Message),('pad',ctypes.c_long*24)]
   x.XSendEvent.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.c_long,ctypes.POINTER(Event)]
   x.XFlush.argtypes=[ctypes.c_void_p];x.XCloseDisplay.argtypes=[ctypes.c_void_p]
   d=x.XOpenDisplay(None)
   try:
    e=Event();e.message.type=33;e.message.send=1;e.message.display=d;e.message.window=int(windows[0]);e.message.format=32
    e.message.message_type=x.XInternAtom(d,b'WM_PROTOCOLS',0);e.message.data.l[0]=x.XInternAtom(d,b'WM_DELETE_WINDOW',0)
    x.XSendEvent(d,e.message.window,0,0,ctypes.byref(e));x.XFlush(d)
   finally:x.XCloseDisplay(d)
   # Preserve the ordinary standalone Save/No/Cancel flow, if fresh boards
   # carry initial header data. This is UI automation on the hidden display.
   end=time.monotonic()+12
   while c.p.poll() is None and time.monotonic()<end:
    found=subprocess.run(['xdotool','search','--all','--onlyvisible','--pid',str(c.p.pid),'--name','^Close '],capture_output=True,text=True)
    if found.stdout.split():
     dialog=found.stdout.split()[0]
     geometry=subprocess.run(['xdotool','getwindowgeometry','--shell',dialog],capture_output=True,text=True)
     if geometry.returncode==0:
      values=dict(line.split('=',1) for line in geometry.stdout.splitlines() if '=' in line)
      # A dialog can disappear between discovery and clicking.
      title=subprocess.run(['xdotool','getwindowname',dialog],capture_output=True,text=True).stdout.strip()
      if title=='Close tournament':
       # These dialogs default to Cancel; the preceding tab stop is Discard.
       subprocess.run(['xdotool','windowfocus','--sync',dialog,'key','--clearmodifiers','shift+Tab','Return'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
      else:
       subprocess.run(['xdotool','mousemove','--window',dialog,str(int(values['WIDTH'])-150),str(int(values['HEIGHT'])-32),'click','1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    time.sleep(.1)
   if c.p.poll() is None:
    remaining=subprocess.run(['xdotool','search','--all','--onlyvisible','--pid',str(c.p.pid)],capture_output=True,text=True)
    for window in remaining.stdout.split():
     title=subprocess.run(['xdotool','getwindowname',window],capture_output=True,text=True)
     print('Still visible during close:',window,title.stdout.strip(),flush=True)
   c.p.wait(timeout=1);check(c.p.returncode==0,'actual GUI close cancels terminal session normally')
   c.check_tail()
  finally:c.cleanup()
print(f'Integrated CLI application checks passed: {checks}')
