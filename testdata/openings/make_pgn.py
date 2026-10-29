"""Rebuild the PGN from the accompanying pinned Lichess opening tables."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def quote(text):
    return text.replace('\\', '\\\\').replace('"', '\\"')


def main():
    count = 0
    with (ROOT / 'lichess-openings.pgn').open('w', encoding='utf-8', newline='\n') as out:
        for letter in 'abcde':
            with (ROOT / f'{letter}.tsv').open(encoding='utf-8', newline='') as source:
                for row in csv.DictReader(source, delimiter='\t'):
                    count += 1
                    tags = [
                        ('Event', 'Lichess opening catalogue'),
                        ('Site', 'https://github.com/lichess-org/chess-openings'),
                        ('Date', '????.??.??'), ('Round', str(count)),
                        ('White', 'Opening line'), ('Black', 'Opening line'),
                        ('Result', '*'), ('ECO', row['eco']), ('Opening', row['name']),
                    ]
                    out.write('\n'.join(f'[{key} "{quote(value)}"]' for key, value in tags))
                    out.write('\n\n' + row['pgn'] + ' *\n\n')
    print(f'Wrote {count} openings to {ROOT / "lichess-openings.pgn"}')


if __name__ == '__main__':
    main()
