#!/usr/bin/env python3
"""Optional independent check; needs python-chess and the compiled test probe.

Usage: python3 tests/chess_differential_check.py /path/to/chess_oracle_probe
Reference: https://github.com/niklasf/python-chess (tested with chess 1.11.2).
The application and normal regression suite do not depend on Python chess.
"""
import random
import subprocess
import sys
import chess

rng = random.Random(20261028)
positions = moves = 0
probe = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, text=True, bufsize=1)


def check(board):
    global positions, moves
    fen = board.fen(en_passant="fen")
    probe.stdin.write(fen + "\n")
    probe.stdin.flush()
    header = probe.stdout.readline().rstrip("\n").split("\t")
    key = board.fen(en_passant="legal").rsplit(" ", 2)[0]
    expected = [fen, key, str(int(board.is_check())),
                str(int(board.has_insufficient_material(chess.WHITE))),
                str(int(board.has_insufficient_material(chess.BLACK)))]
    assert header == expected, (fen, header, expected)
    actual = {}
    while True:
        line = probe.stdout.readline().rstrip("\n")
        assert line, ("probe terminated", fen)
        if line == ".":
            break
        move, san, child_fen = line.split("\t")
        assert move not in actual, ("duplicate move", fen, move)
        actual[move] = (san, child_fen)
    expected = {}
    for move in board.legal_moves:
        san = board.san(move)
        child = board.copy(stack=False)
        child.push(move)
        expected[move.uci()] = (san, child.fen(en_passant="fen"))
    assert actual == expected, (fen, actual, expected)
    positions += 1
    moves += len(expected)


try:
    # Include rare move types independently of the random opening walks.
    for fen in [
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
        "8/8/8/r4pPK/8/8/8/k7 w - f6 0 2",
        "4k3/8/8/3pP3/4K3/8/8/8 w - d6 0 2",
        "4k3/P7/8/8/8/8/7p/4K3 w - - 0 1",
        "4k3/8/8/8/8/1N6/8/1N2KN2 w - - 0 1",
        "4k1n1/8/8/8/8/8/8/3QK3 w - - 0 1",
        "4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1",
    ]:
        board = chess.Board(fen)
        assert board.is_valid(), fen
        check(board)
    # Deterministic walks reach quiet positions, checks, captures and endgames.
    for game in range(40):
        board = chess.Board()
        for ply in range(160):
            check(board)
            legal = list(board.legal_moves)
            if not legal:
                break
            board.push(rng.choice(legal))
    print(f"Differential checks passed: {positions} positions, {moves} legal moves/SAN/child FENs")
finally:
    probe.stdin.close()
    probe.stdout.close()
    code = probe.wait(timeout=10)
    if sys.exc_info()[0] is None:
        assert code == 0, code
