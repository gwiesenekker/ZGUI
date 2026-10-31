#!/usr/bin/env python3
"""Run Linux GUI checks on a hidden nested display, leaving desktop focus alone.

Usage: python3 tests/run_hidden_gui.py bash tests/run_gui_checks.sh
Requires Xephyr and an existing parent X display (DISPLAY, default :1).
The parent window is never mapped. There is intentionally no desktop fallback.
Test children and the nested server are retired even on failure/interruption.
"""
import ctypes, os, signal, shutil, subprocess, sys, time

if len(sys.argv) < 2:
    sys.exit(__doc__)
xephyr = shutil.which("Xephyr")
if not xephyr:
    sys.exit("Xephyr is required for hidden GUI checks; no desktop fallback")
parent_display = os.environ.get("DISPLAY", ":1")
x=ctypes.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes=[ctypes.c_char_p];x.XOpenDisplay.restype=ctypes.c_void_p
x.XDefaultRootWindow.argtypes=[ctypes.c_void_p];x.XDefaultRootWindow.restype=ctypes.c_ulong
x.XCreateSimpleWindow.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.c_int,ctypes.c_uint,ctypes.c_uint,ctypes.c_uint,ctypes.c_ulong,ctypes.c_ulong];x.XCreateSimpleWindow.restype=ctypes.c_ulong
x.XFlush.argtypes=[ctypes.c_void_p];x.XCloseDisplay.argtypes=[ctypes.c_void_p]
d=x.XOpenDisplay(parent_display.encode())
if not d: raise RuntimeError('Cannot open parent display')
w=x.XCreateSimpleWindow(d,x.XDefaultRootWindow(d),0,0,1800,1300,0,0,0);x.XFlush(d)
# The parent is never mapped: the nested server and its tests stay off the desktop.
number=next(n for n in range(90,120) if not os.path.exists('/tmp/.X11-unix/X%d'%n))
server=None;child=None
try:
    with open('/tmp/zgui-hidden-display-%d.log'%number,'w') as log:
        server=subprocess.Popen([xephyr,':%d'%number,'-parent',str(w),'-screen','1800x1300','-ac','-noreset','-nolisten','tcp'],env=dict(os.environ,DISPLAY=parent_display),stdout=log,stderr=log)
        for _ in range(60):
            probe=x.XOpenDisplay((':%d'%number).encode())
            if probe: x.XCloseDisplay(probe);break
            if server.poll() is not None: raise RuntimeError('Nested display failed')
            time.sleep(.1)
        else: raise RuntimeError('Nested display timed out')
        child=subprocess.Popen(sys.argv[1:],env=dict(os.environ,DISPLAY=':%d'%number),start_new_session=True)
        result=child.wait()
        sys.exit(result)
finally:
    if child:
        try: os.killpg(child.pid,signal.SIGKILL)
        except ProcessLookupError: pass
    if server:
        server.terminate()
        try: server.wait(timeout=3)
        except subprocess.TimeoutExpired: server.kill();server.wait()
    x.XCloseDisplay(d)
