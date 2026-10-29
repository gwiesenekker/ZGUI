#!/usr/bin/env python3
"""Compare reviewed shared rendering with a410a3d; all builds live under OUT.
Run on a GTK display. Requires git, Lazarus and Python; no source checkout edits.
"""
from collections import Counter
import io
import pathlib
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent.parent
out = pathlib.Path(sys.argv[1]).resolve()
fixtures = ['draughts-setup-0', 'draughts-setup-1', 'score-0', 'score-1']
fixtures += ['chess-' + str(i) for i in range(4)]
for mode in ('baseline', 'current'):
    work = out / mode
    work.mkdir(parents=True, exist_ok=True)
    if mode == 'baseline':
        archive = subprocess.check_output(['git', 'archive', 'a410a3d'], cwd=root)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(work, filter='data')
        source = work
    else:
        source = root
    (work / 'MANUAL.md').write_bytes((source / 'MANUAL.md').read_bytes())
    (work / 'setup_score_render_fixture.pas').write_bytes(
        (root / 'tests/setup_score_render_fixture.pas').read_bytes())
    project = ET.parse(root / 'tests/chess_board_check.lpi')
    cfg = project.getroot()
    cfg.find('./ProjectOptions/Units/Unit0/Filename').set('Value', 'setup_score_render_fixture.pas')
    cfg.find('./CompilerOptions/Other/CustomOptions').set('Value', '-Fu' + str(source))
    path = work / 'setup_score_render_fixture.lpi'
    project.write(path)
    with (work / 'build.log').open('w') as log:
        subprocess.run([sys.executable, str(root / 'tests/build_lazarus_check.py'),
                        'gtk2', str(work / 'build'), str(path)], check=True, stdout=log, stderr=log)
    subprocess.run([str(work / 'build/setup_score_render_fixture'), str(work / 'images')], check=True)
for name in fixtures:
    a = (out / 'baseline/images' / (name + '.bmp')).read_bytes()
    b = (out / 'current/images' / (name + '.bmp')).read_bytes()
    assert len(set(a[54:])) >= 12 and len(set(b[54:])) >= 12, 'Blank bitmap: ' + name
    if name.startswith('score-'):
        pixels = Counter(tuple(a[i:i+3][::-1]) for i in range(54, len(a), 3))
        expected = [(54,150,79), (190,64,64), (140,210,155), (230,145,145), (128,128,128)]
        expected += [(145,165,188)] if name == 'score-0' else [(28,74,132), (102,169,220)]
        assert all(pixels[c] > 0 for c in expected), 'Unexercised colour role: ' + name
    assert a == b, 'Rendering differs: ' + name + '; inspect ' + str(out)
print('Setup, score graphs and chess board rendering match a410a3d (8 bitmaps)')
