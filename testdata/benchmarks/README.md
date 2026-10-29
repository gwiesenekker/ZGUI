# Full-game chess import benchmarks

This directory contains the preparation tool and pinned provenance for the
100,000-game F3/F4 benchmark. Generated PGNs and working manifests are ignored;
the application does not depend on Python or these files.

Source: the December 2013 standard rated export from
https://database.lichess.org/standard/lichess_db_standard_rated_2013-12.pgn.zst

Lichess releases these exports under CC0 1.0:
https://database.lichess.org/ . The complete CC0 legal text is also included in
`../openings/COPYING.txt`.

Archive SHA-256:
`a77d132bdf7aece20f7f3b9b3aa69eae891f2a339e59bb148984c1577eba2de9`.
The preparation script rejects an archive whose bytes differ. `CORPUS.json`
records the generated PGN hash and counts.

Reproduce with Python 3.11+, python-chess (`chess==1.11.2`) and zstd installed:

```sh
curl --fail --location https://database.lichess.org/standard/lichess_db_standard_rated_2013-12.pgn.zst --output /tmp/lichess-2013-12.pgn.zst
python3 testdata/benchmarks/prepare_lichess.py /tmp/lichess-2013-12.pgn.zst testdata/benchmarks/lichess-2013-12-rapid-100k.pgn
bash tests/run_chess_pgn_database_benchmark.sh testdata/benchmarks/lichess-2013-12-rapid-100k.pgn
```

Select the first 100,000 games in source order that are rated Standard, have
`base seconds + 40 * increment seconds >= 480`, and have at least 60 mainline
plies. This is an explicit full-length-game filter, not a representative sample
of all Lichess speeds or all game lengths. Original headers and annotations are
retained. Old exports sometimes contain redundant SAN disambiguation (e.g.
`Rfe8` where canonical SAN is `Re8`). The preparation tool canonicalizes movetext
with python-chess, independently checking the selected games. This remains the original, separately pinned prepared corpus. Schema 8 also
accepts the reviewed legal SAN aliases, without changing that reference input. No game is fabricated or repeated in the corpus.

The benchmark measures scanner callbacks, the existing parser in database-output
mode, full variation validation, canonical token output and mainline UCI/key
extraction. It stops before hashing, compression, SQLite, summary and indexes.
It must not be reported as end-to-end database import throughput. The runner
builds with FPC -O2 and prints CSV plus `/usr/bin/time -v` resource measurements.
Optional arguments select a game limit, repeat count and `scan-only` mode.

A separate normal regression (`chess_pgn_database_check`) uses small fixtures,
including nested and repeated RAVs, comments/NAGs/typed metadata, malformed and
oversized entries, progress/cancellation and semantic GUI round trips. Neither
network access nor this large benchmark is required for normal regression.


For the complete SQLite import, including summary and index creation, run:

```sh
bash tests/run_chess_database_benchmark.sh testdata/benchmarks/lichess-2013-12-rapid-100k.pgn
```

See `RESULTS.md` for the separately measured parser and full-database results,
the accepted performance/memory gates and raw measurements. The database runner
uses a temporary database by default; pass a new pathname as the second argument
to retain it. Do not commit generated PGNs or databases.

For the separately pinned original movetext from the same selected games:

```sh
python3 testdata/benchmarks/prepare_lichess.py /tmp/lichess-2013-12.pgn.zst testdata/benchmarks/lichess-2013-12-rapid-100k-raw.pgn --raw
bash tests/run_chess_database_benchmark.sh testdata/benchmarks/lichess-2013-12-rapid-100k-raw.pgn /tmp/raw-v8.db 0 '' /tmp/raw-v8.log
```

`RAW_CORPUS.json` pins this independent raw representation. Selection and legal
replay checks are identical to the prepared corpus; `--raw` retains the source
movetext instead of formatting it. The optional fifth benchmark argument enables
normal import logging, allowing the one-per-game SAN warning count to be measured.
The application has no Python dependency.

Schema compatibility is checked independently using a schema-7 database generated
by the previous executable (git history is required):

```sh
python3 tests/chess_schema_compatibility_check.py
```
