# Parser-stage measurements — 2026-10-29

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

Use the review's offered 250 games/sec end-to-end import gate. The current
parser ceiling leaves capacity for the remaining work; the original 500/sec
full-import target would exceed the measured parser throughput. A move-generator
rewrite is not needed to start the approved database seams. The final import
still has to demonstrate 250/sec on this corpus and pass cross-format/recovery
checks before gfDatabase can be enabled. Optimize further if the final measured
pipeline needs it; do not infer that passing this parser benchmark passes that
acceptance gate.
