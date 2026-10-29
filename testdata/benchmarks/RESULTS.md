# Chess import measurements — 2026-10-29

Host: AMD Ryzen 9 5950X, Linux x86-64, FPC 3.2.2, -O2. One parser thread.
Corpus: the pinned December 2013 export and filter in CORPUS.json / README.md.
Generated input: 105,113,632 bytes, SHA-256
`4a63f4044099e778dfba704da37fa335f7e566ac7877a93f47e08075ceb2babb`.

| Phase | Games | Mainline plies | Keys | Wall time | Games/sec | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Scan + database parser output | 100,000 | 9,070,786 | 9,170,786 | 213.259 s | 468.91 | 2,848 KiB |
| Scanner only, ten passes | 1,000,000 | — | — | 43.545 s | 22,964.75 | 2,316 KiB |

The full parser run produced 110,508,804 canonical PGN bytes, with zero failures
or encoding warnings. All selected games were independently replayed and SAN
canonicalized by python-chess 1.11.2 during corpus preparation. The scanner
retains no collection entry list; its ten-pass run checks collection scaling.
The million-record result is scanner-only, not a million-game parser benchmark.

Raw CSV and /usr/bin/time output are in `parser-100k.csv`, `parser-100k.time`,
`scanner-1m.csv` and `scanner-1m.time`. The CSV source_bytes field is the sum of
last-record offsets, excluding two trailing whitespace bytes per pass;
total_file_bytes is the full source length. The timed program stops before game
hashing, compression, SQLite writes, continuation summaries and index creation.
These results are not database import throughput.

## F4 decision

Use the review's offered 250 games/sec end-to-end import gate on the Ryzen 9
5950X reference host and compiler settings listed above. This is a reproducible
reference-machine gate, not a minimum speed promised on other hardware. The current
parser ceiling leaves capacity for the remaining work; the original 500/sec
full-import target would exceed the measured parser throughput. A move-generator
rewrite is not needed to start the approved database seams. The full import result below demonstrates this target separately from the parser
measurement. Enabling gfDatabase also requires cross-format and recovery checks.


## Full database import

Same pinned input, host and optimized compiler settings as above. A fresh SQLite
schema-7 database, one importer thread, normal game/position storage, and no
replayed or fabricated games:

| Games | Imported | Duplicates | Errors | Mainline plies | Position rows | Wall time | Games/sec | Peak RSS |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100,000 | 100,000 | 0 | 0 | 9,070,786 | 9,170,786 | 319.091 s | 313.39 | 434,944 KiB (424.75 MiB) |

This includes scanning, the single-pass database parser mode, complete PGN hash
and packing, inserts, batch/final commits, continuation summary and final index
creation. Empty database creation and compiler time are outside the timer. The
250 games/sec and 512 MiB gates both pass. Raw output: `database-100k.csv` and
`database-100k.time`. A 10k prefix run is also recorded in `database-10k.*`.

The first full import measured 246.24 games/sec. Profiling identified repeated
implicit SQLDB preparation of the existing position INSERT. Explicitly preparing
that same query for chess, and releasing it before summary/index DDL and recovery,
produced the result above. There is no separate SQLite pipeline. Chess secondary
indexes are rebuilt through the existing import shell, and SQLite temporary
sorting uses files to bound memory; draughts settings remain unchanged.

Post-import verification checks 100,000 schema-7 games, all 9,170,786 position
rows, 100,000 terminal rows, zero orphan positions, a clean continuation summary,
9,070,786 summarized continuation occurrences and the expected metadata/indexes.
Duplicate imports, malformed games, hash-conflict continuation, direct/summary
agreement, rollback and cancellation are covered separately by regression tests.

Reproduce the full benchmark:

```sh
bash tests/run_chess_database_benchmark.sh testdata/benchmarks/lichess-2013-12-rapid-100k.pgn
```

To retain the database, supply a new database pathname as the second argument.
An optional third argument limits game count (0 means all). To measure a separate
duplicate pass, use the retained database and pass `0 existing`; the CSV counts
imports and duplicates separately and reports processed games/sec. This does not
replace the fresh-import acceptance measurement above. No duplicate-pass
throughput is claimed here. Generated PGNs and databases are not committed.


The existing opening catalogue is a separate functional fixture: all 3,865 games
imported without errors and populated all 500 ECO codes A00–E99. Its short lines
are not used for the full-game throughput gate.
