#!/usr/bin/env python3
"""Cross-platform pipe checks for cli_terminal_check; no GUI or engine needed."""
import json, subprocess, sys, time, os
exe=sys.argv[1]
checks=0
def check(value, label):
 global checks
 checks+=1
 if not value: raise AssertionError(label)
def responses(data):
 lines=data.splitlines()
 for line in lines:
  check(line.startswith((b'OK ',b'ERROR ')), 'stdout contains only response lines')
 return [(line.split(b' ',1)[0].decode(),json.loads(line.split(b' ',1)[1])) for line in lines]
payload='ping\r\nKampioen Ö ♞\nfinal line'.encode()
p=subprocess.run([exe],input=payload,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5)
r=responses(p.stdout)
check(p.returncode==0 and [v['echo'] for _,v in r]==['ping','Kampioen Ö ♞','final line'],'UTF-8, CRLF and EOF final line')
check(b'zgui>' not in p.stderr,'no pipe prompt')
p=subprocess.run([exe],input=b'bad\x00line\n\xff\n'+b'x'*65537+b'\nrecovered\n',stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5)
r=responses(p.stdout)
check([x[0] for x in r]==['ERROR','ERROR','ERROR','OK'],'one error per invalid or overlong line, then recover')
check(r[-1][1]['echo']=='recovered','line draining')
p=subprocess.Popen([exe,'--close-after-ms','300'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
 p.wait(timeout=3);check(p.returncode==0,'idle input cancellation')
finally:
 if p.poll() is None:p.kill()
 p.stdin.close();p.stdout.close();p.stderr.close()
p=subprocess.Popen([exe,'--close-after-ms','300'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
 p.stdin.write(b'large\n');p.stdin.flush();p.wait(timeout=3)
 check(p.returncode==0,'blocked response cancellation')
finally:
 if p.poll() is None:p.kill()
 p.stdin.close();p.stdout.close();p.stderr.close()
p=subprocess.Popen([exe],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
 p.stdout.close();p.stdin.write(b'ping\n');p.stdin.flush();p.wait(timeout=3)
 check(p.returncode==0,'broken output detaches without SIGPIPE termination')
finally:
 if p.poll() is None:p.kill()
 p.stdin.close();p.stderr.close()
if os.name=='posix':
 import pty, signal, select, termios, fcntl
 master,slave=pty.openpty()
 def setup():
  os.setsid()
  import fcntl
  fcntl.ioctl(0,termios.TIOCSCTTY,0)
 original_flags=fcntl.fcntl(slave,fcntl.F_GETFL)
 p=subprocess.Popen([exe,'--close-after-ms','1800'],stdin=slave,stdout=slave,stderr=slave,preexec_fn=setup)
 try:
  select.select([master],[],[],2);initial=os.read(master,4096)
  check(b'zgui>' in initial,'terminal prompt')
  check(fcntl.fcntl(slave,fcntl.F_GETFL)==original_flags,'terminal does not change the launching shell tty flags')
  os.write(master,b'engine\n');started=b'';deadline=time.monotonic()+1
  while time.monotonic()<deadline and b'engine_started' not in started:
   if select.select([master],[],[],.1)[0]: started+=os.read(master,4096)
  check(b'engine_started' in started,'start two real platform-process peers')
  os.write(master,b'partial');os.killpg(p.pid,signal.SIGINT);time.sleep(.1);os.write(master,b'ping_engine\n')
  seen=b'';deadline=time.monotonic()+1.2
  while time.monotonic()<deadline:
   if select.select([master],[],[],.1)[0]:
    try:seen+=os.read(master,4096)
    except OSError:break
   if b'engines_alive' in seen:break
  check(b'"engines_alive" : true' in seen and b'partialping' not in seen,'Ctrl+C cancels input while both engine peers continue')
  p.wait(timeout=3);check(p.returncode==0,'terminal cancellation stops promptly')
 finally:
  if p.poll() is None:p.kill()
  os.close(master);os.close(slave)
 # Controller owns the foreground tty; the helper is a background job.
 master,slave=pty.openpty()
 code="import subprocess,os,sys;p=subprocess.Popen([sys.argv[1],'--close-after-ms','300'],preexec_fn=os.setpgrp);sys.exit(p.wait())"
 p=subprocess.Popen([sys.executable,'-c',code,exe],stdin=slave,stdout=slave,stderr=slave,preexec_fn=setup)
 os.close(slave)
 try:
  p.wait(timeout=3);check(p.returncode==0,'background terminal job stays responsive without SIGTTIN stop')
 finally:
  if p.poll() is None:p.kill()
  os.close(master)
# Stop is called explicitly twice by the helper and again by its destructor.
# Repeat process teardown to exercise the intermittent double-join regression.
for i in range(20):
 p=subprocess.run([exe],input=b'ping\n',stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5)
 check(p.returncode==0, 'repeated terminal Stop/destruction exits cleanly '+str(i))
 check(b'EAccessViolation' not in p.stderr and b'Exception' not in p.stderr, 'no shutdown exception '+str(i))
print(f'CLI terminal transport checks passed: {checks}')
