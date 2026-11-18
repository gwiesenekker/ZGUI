#!/usr/bin/env python3
"""Exercise the actual application's native resize path on the test display."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def xdo(*args):
    return subprocess.check_output(['xdotool', *map(str, args)], text=True, timeout=5)


def geometry(window):
    return dict(line.split('=', 1) for line in xdo('getwindowgeometry', '--shell', window).splitlines())


for game in ('chess', 'draughts'):
    with tempfile.TemporaryDirectory(prefix='zgui-resize-') as directory:
        folder = Path(directory)
        executable = folder / 'zgui'
        shutil.copy2(sys.argv[1], executable)
        (folder / 'prefs.json').write_text(json.dumps({'last_game': game}))
        with (folder / 'stderr.log').open('w') as log:
            process = subprocess.Popen([str(executable)], cwd=folder, stderr=log, stdout=log)
            try:
                deadline = time.monotonic() + 10
                window = None
                while time.monotonic() < deadline and process.poll() is None:
                    found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--pid', str(process.pid), '--name', '^ZGUI -'],
                                           capture_output=True, text=True, timeout=3)
                    if found.returncode == 0:
                        window = found.stdout.splitlines()[0]
                        break
                    time.sleep(.05)
                assert window, f'{game}: no visible main window; exit={process.poll()}'
                title = xdo('getwindowname', window)
                assert ('International draughts' if game == 'draughts' else 'Chess') in title, title
                screen_height = int(os.environ.get('ZGUI_TEST_SCREEN', '1800x1300').split('x')[1])
                assert int(geometry(window)['HEIGHT']) <= screen_height, f'{game}: startup exceeds screen height'
                xdo('windowmove', window, 0, 0)
                for step, (width, height) in enumerate(((1000, 500), (1300, 800), (1000, 500), (1366, 700),
                                      (1083, 600), (1300, 690), (1366, 700))):
                    xdo('windowsize', window, width, height)
                    time.sleep(.3)
                    assert process.poll() is None, f'{game}: exited {process.returncode} after {width}x{height}'
                    measured = geometry(window)
                    print(f'{game}: requested {width}x{height}, actual {measured["WIDTH"]}x{measured["HEIGHT"]}', flush=True)
                    if step in (0, 6):
                        def ticks():
                            fields = Path(f'/proc/{process.pid}/stat').read_text().split()
                            return int(fields[13]) + int(fields[14])
                        start_ticks, start_time = ticks(), time.monotonic()
                        time.sleep(.5)
                        cpu = (ticks() - start_ticks) / os.sysconf('SC_CLK_TCK') / (time.monotonic() - start_time)
                        print(f'{game}: settled CPU {cpu:.1%} of one core', flush=True)
                        assert cpu < .8, f'{game}: native resize leaves a busy event loop'
                    if height <= 700 and width >= 1083:
                        assert int(measured['HEIGHT']) <= 700, f'{game}: native laptop height exceeds 700'
                xdo('windowfocus', '--sync', window)
                xdo('key', 'ctrl+q')
                assert process.wait(timeout=6) == 0, f'{game}: normal close failed'
                assert not re.search(r'InvalidatePreferredSize loop|unhandled exception', (folder / 'stderr.log').read_text(), re.I)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                if process.returncode:
                    print((folder / 'stderr.log').read_text()[-4000:], file=sys.stderr)
print('Native application shrink/grow checks passed for both games.')
