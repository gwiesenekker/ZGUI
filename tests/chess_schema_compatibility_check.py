#!/usr/bin/env python3
"""Pin v7 identities using the last v7 executable, then exercise v7/v8 together.
Optional integration check: requires git history, FPC and SQLite; no checked-in DB.
"""
import io
import pathlib
import sqlite3
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = '6edae32'


def compile_probe(source, output):
    output.mkdir()
    with (output / 'build.log').open('w') as log:
        subprocess.run(['fpc', '-B', '-O2', '-Fu' + str(source),
                        '-FU' + str(output), '-FE' + str(output),
                        str(ROOT / 'tests/chess_database_benchmark.pas')],
                       cwd=output, check=True, stdout=log, stderr=log)
    return output / 'chess_database_benchmark'


def run(exe, pgn, db, existing=False, reject=False):
    before = db.read_bytes() if reject else None
    result = subprocess.run([str(exe), str(pgn), str(db), '0',
                             'existing' if existing else ''],
                            capture_output=True, text=True)
    if reject:
        assert result.returncode, result.stdout
        assert db.read_bytes() == before, 'Rejected file changed'
        return
    assert result.returncode == 0, result.stderr
    return tuple(map(int, result.stdout.splitlines()[-1].split(',')[:3]))


def snapshot(db):
    with sqlite3.connect(db) as c:
        names = [r[0] for r in c.execute(
            "select name from sqlite_master where type='table' order by name")]
        return (c.execute('pragma user_version').fetchone(),
                {name: c.execute('select * from "' + name + '" order by rowid').fetchall()
                 for name in names})


def version(db, expected):
    with sqlite3.connect(db) as c:
        assert c.execute('pragma user_version').fetchone()[0] == expected
        assert c.execute('select distinct hash_version from games').fetchall() == [(expected,)]
        identity = c.execute("select value from database_metadata where name='game_identity_format'").fetchone()[0]
        assert identity == {7: 'complete-lossless-pgn-token-v1',
                            8: 'canonical-legal-pgn-token-v2'}[expected]
        assert c.execute('pragma integrity_check').fetchone()[0] == 'ok'


with tempfile.TemporaryDirectory(prefix='zgui-schema-compat-') as tmp:
    work = pathlib.Path(tmp)
    old_source = work / 'old-source'
    old_source.mkdir()
    paths = subprocess.check_output(['git', 'ls-tree', '--name-only', BASELINE],
                                    cwd=ROOT, text=True).splitlines()
    paths = [p for p in paths if p.endswith('.pas')]
    archive = subprocess.check_output(['git', 'archive', BASELINE, '--', *paths], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(old_source, filter='data')
    old = compile_probe(old_source, work / 'old-build')
    new = compile_probe(ROOT, work / 'new-build')
    pgn = work / 'games.pgn'
    body = '1.e4 {literal note} (1.d4 $1 d5 (1...Nf6)) e5 2.Nf3 Nc6 3.Bc4 Nf6 4.{castle} *'
    games = ['[Event "Spelling"]\n' + body.replace('{castle}', x)
             for x in ('0-0', 'O-O')]
    # A custom starting FEN complements the NAGs and nested RAVs above.
    games += ['[Event "Custom"]\n[SetUp "1"]\n[FEN "4k3/8/8/8/8/8/8/R3K3 b - - 0 37"]\n37...Kf7 *']
    pgn.write_text('\n\n'.join(games), encoding='utf-8')
    legacy, modern = work / 'legacy.db', work / 'modern.db'
    assert run(old, pgn, legacy) == (3, 0, 0)
    version(legacy, 7)
    before = snapshot(legacy)
    assert run(new, pgn, legacy, existing=True) == (0, 3, 0)
    assert snapshot(legacy) == before, 'Legacy rows, hashes, metadata or summary changed'
    assert run(old, pgn, legacy, existing=True) == (0, 3, 0)
    assert snapshot(legacy) == before
    assert run(new, pgn, modern) == (2, 1, 0), 'v8 canonical spellings must deduplicate'
    version(modern, 8)
    assert run(new, pgn, modern, existing=True) == (0, 3, 0)
    run(old, pgn, modern, existing=True, reject=True)
    # Writing a new game to v7 still uses its old writer and hash domain.
    pgn.write_text('[Event "New legacy"]\n' + games[0].split('\n', 1)[1], encoding='utf-8')
    assert run(new, pgn, legacy, existing=True) == (1, 0, 0)
    assert run(old, pgn, legacy, existing=True) == (0, 1, 0)
    version(legacy, 7)
    # v8 keeps changes to tags, comments, NAGs and branches distinct.
    pgn.write_text('\n\n'.join([
        games[0].replace('Spelling', 'Tag changed'),
        games[0].replace('literal note', 'changed note'),
        games[0].replace('$1', '$2'),
        games[0].replace('(1...Nf6)', '(1...e6)')]), encoding='utf-8')
    assert run(new, pgn, modern, existing=True) == (4, 0, 0)
    for sql in ["pragma user_version=9",
                "update database_metadata set value='wrong' where name='game_identity_format'",
                "update games set hash_version=7 where id=1"]:
        bad = work / 'bad.db'
        bad.write_bytes(modern.read_bytes())
        with sqlite3.connect(bad) as c:
            c.execute(sql)
        run(new, pgn, bad, existing=True, reject=True)
print('Schema compatibility passed: real v7 rows/hashes/text/keys/metadata unchanged; v7 writes readable by old build; v8 canonical dedup and annotation identity; incompatible versions rejected unchanged')
