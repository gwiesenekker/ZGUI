#!/usr/bin/env python3
"""Compare reviewed shared rendering with 1d137d8; all builds live under OUT.
Run on a GTK display. Requires git, Lazarus and Python; no source checkout edits.
"""
import io
import pathlib
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent.parent
out = pathlib.Path(sys.argv[1]).resolve()
fixtures = ['0','1']
for mode in ('baseline', 'current'):
    work = out / mode
    work.mkdir(parents=True, exist_ok=True)
    if mode == 'baseline':
        archive = subprocess.check_output(['git', 'archive', '1d137d8'], cwd=root)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(work, filter='data')
        source = work
    else:
        source = root
    (work / 'MANUAL.md').write_bytes((source / 'MANUAL.md').read_bytes())
    (work / 'database_render_fixture.pas').write_bytes(
        (root / 'tests/database_render_fixture.pas').read_bytes())
    project = ET.parse(root / 'tests/chess_board_check.lpi')
    cfg = project.getroot()
    cfg.find('./ProjectOptions/Units/Unit0/Filename').set('Value', 'database_render_fixture.pas')
    cfg.find('./CompilerOptions/Other/CustomOptions').set('Value', '-Fu' + str(source))
    path = work / 'database_render_fixture.lpi'
    project.write(path)
    with (work / 'build.log').open('w') as log:
        subprocess.run([sys.executable, str(root / 'tests/build_lazarus_check.py'),
                        'gtk2', str(work / 'build'), str(path)], check=True, stdout=log, stderr=log)
    subprocess.run([str(work / 'build/database_render_fixture'), str(work / 'images')], check=True)
for name in fixtures:
    a = (out / 'baseline/images' / (name + '.bmp')).read_bytes()
    b = (out / 'current/images' / (name + '.bmp')).read_bytes()
    assert len(set(a[54:])) >= 12 and len(set(b[54:])) >= 12, 'Blank bitmap: ' + name
    assert a == b, 'Rendering differs: ' + name + '; inspect ' + str(out)
print('Draughts database dialog matches 1d137d8 at default/minimum sizes')
