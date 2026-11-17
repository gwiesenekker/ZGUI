import os,pathlib,subprocess,sys,time,json,tempfile,shutil,select
root=pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='zgui-shutdown-measure-') as td:
 d=pathlib.Path(td);shutil.copy2(sys.argv[1],d/'zgui')
 shutil.copy2(pathlib.Path(sys.argv[2]) if len(sys.argv)>2 else root/'engine1/stockfish/stockfish-linux-x86-64-universal',d/'stockfish')
 shutil.copy2(root/'claude/probes-f875efe-shutdown/ballot80.fen',d/'ballot80.fen')
 defs=[dict(executable='stockfish',path=str(d)+'/',kind='uci',uci_id='SF '+name,arguments='',init='') for name in ['A','B']]
 (d/'engines.json').write_text(json.dumps(defs));err=open(d/'stderr.log','w+')
 p=subprocess.Popen([str(d/'zgui'),'--cli'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,env=dict(os.environ,XDG_CONFIG_HOME=str(d/'config')),cwd=d)
 def cmd(s):
  p.stdin.write((s+'\n').encode());p.stdin.flush()
  assert select.select([p.stdout],[],[],20)[0],s
  b=p.stdout.readline();assert b.startswith(b'OK '),b
  return json.loads(b[3:])
 def threads():return int(next(x.split()[1] for x in pathlib.Path(f'/proc/{p.pid}/status').read_text().splitlines() if x.startswith('Threads:')))
 def cpu():
  def ticks():
   a=pathlib.Path(f'/proc/{p.pid}/stat').read_text().split();return int(a[13])+int(a[14])
  a=ticks();time.sleep(2);return round((ticks()-a)/os.sysconf('SC_CLK_TCK')/2*100,2)
 try:
  cmd('list_engines');time.sleep(.3);baseline=threads();print('before threads=',baseline,'cpu=',cpu(),flush=True)
  started=cmd('run_tournament engine1_id=1 engine2_id=2 ballot="'+str(d/'ballot80.fen')+'" time=0.1 moves=0 increment=0 concurrent=2 allow_shared_executable=true')
  deadline=time.monotonic()+650;last=-1
  while True:
   q=cmd('query_tournament id='+str(started['tournament']))
   if q['games_completed']//40!=last:last=q['games_completed']//40;print('completed=',q['games_completed'],'state=',q['state'],flush=True)
   if q['state']=='completed':break
   assert time.monotonic()<deadline,q
   time.sleep(.5)
  time.sleep(.4);after=threads();print('after threads=',after,'cpu=',cpu(),flush=True)
  assert after<=baseline+1,(baseline,after)
  wid=subprocess.check_output(['xdotool','search','--onlyvisible','--pid',str(p.pid),'--name','^ZGUI -']).split()[0]
  subprocess.run(['xdotool','windowfocus',wid],check=True);subprocess.run(['xdotool','key','--window',wid,'ctrl+q'],check=True)
  begin=time.monotonic();last_click=begin
  while p.poll() is None and time.monotonic()-begin<12:
   windows=subprocess.run(['xdotool','search','--onlyvisible','--pid',str(p.pid),'--name','^Close '],capture_output=True).stdout.split()
   for w in windows:
    g=subprocess.run(['xdotool','getwindowgeometry','--shell',w],capture_output=True,text=True)
    if g.returncode:continue
    v=dict(line.split('=',1) for line in g.stdout.splitlines() if '=' in line)
    subprocess.run(['xdotool','mousemove','--window',w,str(int(v['WIDTH'])-150),str(int(v['HEIGHT'])-32),'click','1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    last_click=time.monotonic()
   time.sleep(.05)
  p.wait(timeout=1);err.flush();err.seek(0);text=err.read()
  print('close total_s=',round(time.monotonic()-begin,3),'after_final_discard_s=',round(time.monotonic()-last_click,3),'exit=',p.returncode,flush=True)
  assert p.returncode==0,text[-1500:]
  assert 'EAccessViolation' not in text and 'ExceptionOccurred' not in text,text[-1500:]
 finally:
  if p.poll() is None:p.kill();p.wait()
  p.stdin.close();p.stdout.close();err.close()
