# Chess opening test collection

`lichess-openings.pgn` contains 3,865 named opening lines covering all 500 ECO
codes, A00–E99. Each line is a separate unfinished PGN game (`Result "*"`),
with its ECO code and full opening name in tags. These are opening positions,
not completed games; their results must not count as wins, draws or losses.
This is a catalogue of named openings, not every possible opening continuation.

Source: https://github.com/lichess-org/chess-openings

Downloaded 2026-10-29, pinned to commit
`e76b8b4ec5c8aeeba41dac6caf4a60b938f652db` (2026-10-28).
Original tables and their CC0 1.0 licence (`COPYING.txt`) are included unchanged.
Upstream documentation:
https://github.com/lichess-org/chess-openings/blob/e76b8b4ec5c8aeeba41dac6caf4a60b938f652db/README.md

| Source | Lines |
| --- | ---: |
| a.tsv | 823 |
| b.tsv | 781 |
| c.tsv | 1,250 |
| d.tsv | 644 |
| e.tsv | 367 |

To reproduce the PGN locally, run `python3 testdata/openings/make_pgn.py` from
the project root. The script requires only Python's standard library and reads
the included tables without downloading anything. `SHA256SUMS` records checksums
for the original tables, licence and generated PGN.

Validation: all 3,865 records contain legal mainlines (37,700 total plies),
independently checked with python-chess 1.11.2. The ECO tags cover A00–E99.

For database testing, expect repeated positions and transpositions across lines.
Position searches count occurrences; those counts can exceed distinct game
counts. This short-opening collection is not a representative throughput
benchmark for full-length games and does not exercise comments or variations.
