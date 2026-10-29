#!/usr/bin/env python3
"""Prepare the pinned 100k benchmark from an official Lichess monthly export.

This is a fixture preparation tool for the export's [Event ...] record layout,
not a PGN importer. The application parser validates all emitted games.
Usage: python3 prepare_lichess.py SOURCE.pgn.zst OUTPUT.pgn [--raw]
Requires zstd and python-chess (chess==1.11.2); no network access.
"""
import collections
import io
import chess
import chess.pgn
import hashlib
import json
import pathlib
import re
import subprocess
import sys

SOURCE_URL = 'https://database.lichess.org/standard/lichess_db_standard_rated_2013-12.pgn.zst'
SOURCE_SHA256 = 'a77d132bdf7aece20f7f3b9b3aa69eae891f2a339e59bb148984c1577eba2de9'


def records(stream):
    chunks = []
    for line in stream:
        if line.startswith('[Event ') and chunks:
            yield ''.join(chunks)
            chunks = []
        chunks.append(line)
    if chunks:
        yield ''.join(chunks)


def main():
    raw = '--raw' in sys.argv[1:]
    source, target = map(pathlib.Path, [s for s in sys.argv[1:] if s != '--raw'])
    digest = hashlib.file_digest(source.open('rb'), 'sha256').hexdigest()
    if digest != SOURCE_SHA256:
        raise SystemExit('Source checksum differs from the pinned archive')
    count = plies = annotated = examined = 0
    lengths = collections.Counter()
    process = subprocess.Popen(['zstdcat', str(source)], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    try:
        with target.open('w', encoding='utf-8', newline='\n') as out:
            for text in records(process.stdout):
                examined += 1
                header, body = text.split('\n\n', 1)
                tags = dict(re.findall(r'^\[(\w+) "(.*)"\]$', header, re.M))
                if not tags.get('Event', '').startswith('Rated '):
                    continue
                if tags.get('Variant', 'Standard') != 'Standard':
                    continue
                tc = re.fullmatch(r'(\d+)\+(\d+)', tags.get('TimeControl', ''))
                if not tc or int(tc[1]) + 40 * int(tc[2]) < 480:
                    continue
                # Official monthly exports have no RAV. Keep comments in output,
                # remove them only for the documented length-selection filter.
                moves = re.sub(r'\{[^}]*\}', ' ', body, flags=re.S)
                if '(' in moves or ')' in moves:
                    continue
                moves = re.sub(r'\d+\.+|\$\d+|[!?]', ' ', moves)
                tokens = [t for t in moves.split() if t not in ('1-0', '0-1', '1/2-1/2', '*')]
                if len(tokens) < 60:
                    continue
                game = chess.pgn.read_game(io.StringIO(text))
                if game is None or game.errors:
                    raise RuntimeError('Invalid selected source game')
                # Old exports contain redundant SAN disambiguation (Rfe8 when
                # only one rook can reach e8). Canonicalize with an independent
                # rules oracle; keep the source header verbatim and annotations.
                canonical_body = game.accept(chess.pgn.StringExporter(
                    headers=False, variations=True, comments=True, columns=80))
                out.write(text if raw else header + '\n\n' + canonical_body.rstrip() + '\n\n')
                count += 1
                plies += len(tokens)
                annotated += '{' in body
                lengths[(len(tokens) // 40) * 40] += 1
                if count % 10000 == 0:
                    print(f'Prepared {count} games', file=sys.stderr, flush=True)
                if count == 100000:
                    break
    finally:
        process.stdout.close()
        process.terminate()
        process.wait()
    if count != 100000 or plies / count < 80:
        raise SystemExit(f'Insufficient corpus: {count} games, {plies} plies')
    manifest = dict(representation='raw-source' if raw else 'canonical-san', canonical_san_oracle='python-chess '+chess.__version__, source_url=SOURCE_URL, source_sha256=digest, licence='CC0-1.0',
                    output_sha256=hashlib.file_digest(target.open('rb'), 'sha256').hexdigest(),
                    games=count, plies=plies, mean_plies=plies/count, annotated_games=annotated,
                    source_records_examined=examined, length_histogram_40_plies=dict(lengths),
                    filter='First 100k rated Standard; base+40*increment>=480; >=60 mainline plies; source order')
    target.with_suffix('.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
