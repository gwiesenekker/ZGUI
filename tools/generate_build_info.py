#!/usr/bin/env python3
"""Generate build identity and a manual RCDATA resource in the build directory."""
import pathlib
import subprocess
import sys


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True,
                                   stderr=subprocess.DEVNULL).strip()


def literal(text):
    return "'" + text.replace("'", "''") + "'"


def generate(root, output, resource_compiler="fpcres"):
    root = pathlib.Path(root).resolve()
    output = pathlib.Path(output).resolve()
    try:
        if pathlib.Path(git(root, 'rev-parse', '--show-toplevel')).resolve() != root:
            raise ValueError('Source folder is not the repository root')
        commit = git(root, 'rev-parse', '--verify', 'HEAD')
        revision = git(root, 'describe', '--tags', '--always')
        # Untracked local engines/configuration are not part of the executable.
        dirty = bool(git(root, 'status', '--porcelain', '--untracked-files=no'))
    except (OSError, ValueError, subprocess.CalledProcessError):
        commit, revision, dirty = 'unavailable (source archive)', 'source build', False
    manual = (root / 'MANUAL.md').read_text(encoding='utf-8')
    output.parent.mkdir(parents=True, exist_ok=True)
    resources = output.parent / 'resources'
    resources.mkdir(exist_ok=True)
    # Keep input resources separate from FPC's unit output: FPC copies .res
    # files there, and copying a resource onto itself would truncate it.
    # Compile the Markdown as data, not as thousands of Pascal string literals.
    # ASCII relative input names also avoid quoting paths inside the RC script.
    with (resources / 'gwdgui-manual.md').open('w', encoding='utf-8', newline='') as stream:
        stream.write(manual)
    (resources / 'gwdgui-manual.rc').write_text(
        'ZGUI_MANUAL RCDATA "gwdgui-manual.md"\n', encoding='ascii')
    subprocess.run([resource_compiler, '-of', 'res', 'gwdgui-manual.rc',
                    '-o', 'gwdgui-manual.res'], cwd=resources, check=True)
    lines = [
        '{$R ' + literal(str(resources / 'gwdgui-manual.res')) + '}',
        'const',
        '  BuildCommit = ' + literal(commit) + ';',
        '  BuildRevision = ' + literal(revision) + ';',
        '  BuildHasChanges = ' + str(dirty) + ';',
    ]
    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    generate(sys.argv[1], sys.argv[2])
