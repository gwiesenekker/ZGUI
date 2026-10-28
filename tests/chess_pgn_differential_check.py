#!/usr/bin/env python3
"""Optional PGN oracle: python-chess (tested chess 1.11.2), no app dependency.
Usage: python3 tests/chess_pgn_differential_check.py /path/to/chess_pgn_oracle_probe
"""
import io
import pathlib
import random
import re
import subprocess
import sys
import tempfile
import chess
import chess.pgn

rng = random.Random(20261028)
nodes = 0

def prose(comment):
    return ' '.join(re.sub(r'\[%(?:eval|clk|emt)\s+[^\]]*\]', '', comment).split())

def compare(a, b):
    global nodes
    nodes += 1
    assert a.board().fen() == b.board().fen()
    assert a.nags == b.nags, (a.nags, b.nags)
    assert prose(a.comment) == prose(b.comment), (a.comment, b.comment)
    assert prose(a.starting_comment) == prose(b.starting_comment)
    assert a.eval() == b.eval(), (a.eval(), b.eval())
    assert a.clock() == b.clock()
    assert len(a.variations) == len(b.variations)
    for child_a, child_b in zip(a.variations, b.variations):
        assert child_a.move == child_b.move
        assert child_a.san() == child_b.san()
        compare(child_a, child_b)

with tempfile.TemporaryDirectory(prefix='zgui-pgn-oracle-') as scratch:
    root = pathlib.Path(scratch)
    source, target = root / 'input.pgn', root / 'output.pgn'
    for index in range(80):
        game = chess.pgn.Game()
        if index % 10 == 0:
            game.setup(chess.Board('4k3/8/8/8/8/8/8/R3K3 b - - 0 37'))
        game.headers['Event'] = f'Oracle {index}'
        game.headers['White'] = 'José'
        game.headers['Black'] = '棋手'
        game.headers['X_Unknown'] = 'preserve'
        game.comment = 'Root engine: literal score prose'
        node = game
        for ply in range(rng.randrange(10, 45)):
            board = node.board()
            moves = list(board.legal_moves)
            if not moves:
                break
            rng.shuffle(moves)
            main = node.add_variation(moves[0])
            main.comment = f'Ply {ply} (literal [text] ; punctuation)'
            main.nags.add(rng.randrange(256))
            if ply % 4 == 0:
                main.set_eval(chess.engine.PovScore(chess.engine.Cp(25), chess.WHITE))
                main.set_clock(180 - ply)
            if len(moves) > 1 and ply % 5 == 0:
                branch = node.add_variation(moves[1])
                branch.starting_comment = 'Variation begins'
                branch.comment = 'engine: literal branch'
                for _ in range(2):
                    alternatives = list(branch.board().legal_moves)
                    if not alternatives:
                        break
                    branch = branch.add_variation(rng.choice(alternatives))
            node = main
        game.headers['Result'] = node.board().result() if node.board().is_game_over() else '*'
        source.write_text(game.accept(chess.pgn.StringExporter(columns=80)), encoding='utf-8')
        subprocess.run([sys.argv[1], str(source), str(target)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result = chess.pgn.read_game(io.StringIO(target.read_text(encoding='utf-8')))
        assert result is not None and not result.errors
        assert dict(game.headers) == dict(result.headers)
        compare(game, result)
print(f'PGN oracle passed: 80 games, {nodes} nodes, headers/comments/NAGs/SAN/variations/evaluations/clocks')
