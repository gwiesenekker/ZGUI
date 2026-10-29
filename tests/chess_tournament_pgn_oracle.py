#!/usr/bin/env python3
"""Optional independent PGN check; feed chess_tournament_record_check's output.

Requires python-chess (import chess). No application code imports this package.
"""
import datetime
import io
import pathlib
import re
import sys

import chess.pgn

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
names = re.findall(r'^\[([A-Za-z0-9_]+)\s+"', text, re.M)
assert names[:7] == ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
assert len(names) == len(set(names))
stream = io.StringIO(text)
game = chess.pgn.read_game(stream)
assert game is not None and not game.errors
assert chess.pgn.read_game(stream) is None
assert game.headers["Date"] == "2026.10.29"
datetime.datetime.strptime(game.headers["Date"], "%Y.%m.%d")
assert game.headers["Result"] == "1/2-1/2"
assert game.headers["PlayedResult"] == "*"
assert game.headers["TournamentId"] == "id"
assert len(game.variations) == 2
assert len(list(game.mainline_moves())) == 2
assert "a comment" in game.variations[0].comment
assert game.variations[0].clock() == 60
print("python-chess tournament PGN roster/date/variation/clock checks passed")
