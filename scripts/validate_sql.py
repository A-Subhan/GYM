#!/usr/bin/env python3
"""Parse a T-SQL script batch-by-batch with sqlglot. Reports parse errors
per batch so we can fix them. Uses IGNORE error_level so unsupported
procedural blocks fall back to "Command" parsing (not treated as errors).
"""
import sys
import sqlglot
from sqlglot.errors import ErrorLevel

sys.setrecursionlimit(10000)

def main(path: str) -> int:
    src = open(path, 'r', encoding='utf-8').read()
    batches = []
    cur = []
    for line in src.splitlines():
        if line.strip() == 'GO':
            batches.append('\n'.join(cur))
            cur = []
        else:
            cur.append(line)
    if cur:
        batches.append('\n'.join(cur))

    print(f'{len(batches)} batches in {path}')
    errors = 0
    for i, b in enumerate(batches):
        if not b.strip():
            continue
        try:
            sqlglot.parse(b, read='tsql', error_level=ErrorLevel.IGNORE)
        except Exception as e:
            errors += 1
            print(f'--- BATCH {i} ERROR ---')
            print(f'  {e}')
            print(f'--- batch {i} first 5 lines ---')
            for ln in b.splitlines()[:5]:
                print(f'  | {ln}')
            print()
    if errors == 0:
        print('PASS — no parse errors')
        return 0
    print(f'FAIL — {errors} parse error(s)')
    return 1

if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
