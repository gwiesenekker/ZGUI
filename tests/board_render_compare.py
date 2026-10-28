#!/usr/bin/env python3
"""Compare extracted draughts rendering with the original 42e0d54 control.
Needs Lazarus/GTK2 and a display (may be run under xvfb-run).
All reference code and output live in the caller-supplied temporary directory.
"""
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent.parent
out = pathlib.Path(sys.argv[1]).resolve()
for mode in ('baseline', 'current'):
    work = out / mode
    work.mkdir(parents=True, exist_ok=True)
    (work / 'MANUAL.md').write_bytes((root / 'MANUAL.md').read_bytes())
    (work / 'board_render_fixture.pas').write_bytes((root / 'tests/board_render_fixture.pas').read_bytes())
    if mode == 'baseline':
        text = subprocess.check_output(['git', 'show', '42e0d54:uDraughtsBoardControl.pas'], cwd=root)
        (work / 'uDraughtsBoardControl.pas').write_bytes(text)
    project = ET.parse(root / 'tests/help_menu_check.lpi')
    cfg = project.getroot()
    cfg.find('./ProjectOptions/Units/Unit0/Filename').set('Value', 'board_render_fixture.pas')
    cfg.find('./CompilerOptions/Other/CustomOptions').set('Value', '-Fu'+str(root))
    path = work / 'board_render_fixture.lpi'
    project.write(path)
    with (work / 'build.log').open('w') as log:
        subprocess.run([sys.executable, str(root / 'tests/build_lazarus_check.py'),
                        'gtk2', str(work / 'build'), str(path)], check=True, stdout=log, stderr=log)
    subprocess.run([str(work / 'build/board_render_fixture'), str(work / 'images')], check=True)
for i in range(8):
    a = (out / 'baseline/images' / f'{i}.bmp').read_bytes()
    b = (out / 'current/images' / f'{i}.bmp').read_bytes()
    assert len(set(a[54:])) > 16 and len(set(b[54:])) > 16, 'Blank saved bitmap'
    assert a == b, f'Rendering differs for fixture {i}; inspect {out}'
print('Draughts rendering matches 42e0d54 exactly (8 bitmap fixtures)')
