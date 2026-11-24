#!/usr/bin/env python3
"""Generate build identity and a manual RCDATA resource in the build directory."""
import pathlib
import re
import subprocess
import sys


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True,
                                   stderr=subprocess.DEVNULL).strip()


ARCHIVE_COMMIT = '$Format:%H$'


def checkout_commit(root):
    """Read only this checkout's HEAD, including linked worktrees, without Git."""
    try:
        directory = root / '.git'
        if directory.is_file():
            marker = directory.read_text(encoding='utf-8').strip()
            if not marker.startswith('gitdir: '):
                return ''
            directory = (root / marker[8:]).resolve()
        head = (directory / 'HEAD').read_text(encoding='ascii').strip()
        if head.startswith('ref: '):
            ref = head[5:]
            if not ref.startswith('refs/') or any(p in ('', '.', '..') for p in ref.split('/')) or any(c in ref for c in '\\:'):
                return ''
            common = directory
            if (directory / 'commondir').is_file():
                common = (directory / (directory / 'commondir').read_text().strip()).resolve()
            try:
                head = (common / ref).read_text(encoding='ascii').strip()
            except FileNotFoundError:
                head = next((line.split(' ', 1)[0] for line in
                             (common / 'packed-refs').read_text(encoding='ascii').splitlines()
                             if line.endswith(' ' + ref)), '')
        return head.lower() if re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}', head) else ''
    except (OSError, UnicodeError):
        return ''


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
        changes_known = True
    except (OSError, ValueError, subprocess.CalledProcessError):
        commit = checkout_commit(root)
        if not commit and re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', ARCHIVE_COMMIT):
            commit = ARCHIVE_COMMIT
        commit = commit or 'unavailable (source archive)'
        revision, dirty, changes_known = 'source build', False, False
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
        '  BuildChangesKnown = ' + str(changes_known) + ';',
    ]
    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    generate(sys.argv[1], sys.argv[2])
