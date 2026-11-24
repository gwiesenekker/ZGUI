#!/usr/bin/env python3
"""SCU-style identity fallback, archive substitution, and display-free --version."""
import importlib.util
import io
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from unittest import mock
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import generate_build_info as info

def run(args, **kwargs):
    return subprocess.check_output(list(map(str, args)), stderr=subprocess.STDOUT, **kwargs)

with tempfile.TemporaryDirectory(prefix='zgui-version-') as tmp:
    base = pathlib.Path(tmp)
    run(['fpc', '-B', '-FU'+tmp, '-FE'+tmp, ROOT/'tools/generate_build_info.pas'])
    helper = base/'generate_build_info'
    source = base/'source';source.mkdir();(source/'MANUAL.md').write_text('# Manual\n')
    output = base/'output';output.mkdir()
    metadata = source/'.git';metadata.mkdir()
    a, b = 'a'*40, 'b'*64
    def check(expected):
        env = dict(os.environ, PATH=str(base/'missing'))
        run([helper, source, output/'native.inc', shutil.which('fpcres')], env=env)
        with mock.patch.object(info, 'git', side_effect=OSError('Git unavailable')):
            info.generate(source, output/'python.inc', resource_compiler=shutil.which('fpcres'))
        assert (output/'native.inc').read_bytes() == (output/'python.inc').read_bytes()
        text = (output/'native.inc').read_text()
        assert "BuildCommit = '"+expected+"'" in text
        assert 'BuildChangesKnown = False;' in text
    (metadata/'HEAD').write_text(a+'\n');check(a)
    (metadata/'HEAD').write_text('ref: refs/heads/main\n')
    (metadata/'refs/heads').mkdir(parents=True);(metadata/'refs/heads/main').write_text(b+'\n');check(b)
    (metadata/'refs/heads/main').unlink();(metadata/'packed-refs').write_text('# pack-refs with: peeled\n'+a+' refs/heads/main\n');check(a)
    (metadata/'HEAD').write_text('ref: refs/../outside\n');check('unavailable (source archive)')
    # A linked worktree uses its private HEAD and its common refs directory.
    shutil.rmtree(metadata);common=base/'common';(common/'refs/heads').mkdir(parents=True)
    (common/'refs/heads/main').write_text(a+'\n');private=common/'worktrees/test';private.mkdir(parents=True)
    (private/'HEAD').write_text('ref: refs/heads/main\n');(private/'commondir').write_text('../..\n')
    metadata.write_text('gitdir: '+str(private)+'\n');check(a)
    metadata.unlink();check('unavailable (source archive)')
    # git archive embeds identity even without a .git directory or Git executable.
    repo=base/'repo';(repo/'tools').mkdir(parents=True)
    for name in ['generate_build_info.py','generate_build_info.pas']:
        shutil.copy2(ROOT/'tools'/name,repo/'tools'/name)
    shutil.copy2(ROOT/'.gitattributes',repo/'.gitattributes');shutil.copy2(source/'MANUAL.md',repo/'MANUAL.md')
    run(['git','init',repo]);run(['git','-C',repo,'add','.'])
    run(['git','-C',repo,'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-m','Fixture'])
    commit=run(['git','-C',repo,'rev-parse','HEAD']).decode().strip()
    archive=base/'archive';archive.mkdir()
    with tarfile.open(fileobj=io.BytesIO(run(['git','-C',repo,'archive','HEAD']))) as tar:
        # Extract only our four known fixture files; keep Python 3.8+ support.
        for name in ('.gitattributes', 'MANUAL.md', 'tools/generate_build_info.py',
                     'tools/generate_build_info.pas'):
            target = archive / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(name) as stream:
                target.write_bytes(stream.read())
    run(['fpc','-B','-FU'+tmp,'-FE'+tmp,'-o'+str(base/'archive-generator'),archive/'tools/generate_build_info.pas'])
    run([base/'archive-generator',archive,output/'archive.inc',shutil.which('fpcres')],env=dict(os.environ,PATH=str(base/'missing')))
    assert "BuildCommit = '"+commit+"'" in (output/'archive.inc').read_text()
    spec=importlib.util.spec_from_file_location('archive_info',archive/'tools/generate_build_info.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with mock.patch.object(module,'git',side_effect=OSError()):
        module.generate(archive,output/'archive-python.inc',resource_compiler=shutil.which('fpcres'))
    assert (output/'archive.inc').read_bytes()==(output/'archive-python.inc').read_bytes()
if len(sys.argv)>1:
    env=os.environ.copy();env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
    result=subprocess.run([sys.argv[1],'--version'],env=env,capture_output=True,timeout=5)
    assert result.returncode==0,(result.returncode,result.stderr)
    assert re.fullmatch(rb'1\.2-[0-9a-f]{7}\r?\n',result.stdout),result.stdout
    assert not result.stderr,result.stderr
print('Version reporting checks passed (metadata, archives and optional display-free executable)')
