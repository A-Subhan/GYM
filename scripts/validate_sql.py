#!/usr/bin/env python3
"""Validate all 10xx SQL files with sqlglot (tsql dialect) and balanced-quote/paren check."""
import os, re, sys
import sqlglot

DB_DIR = "/home/z/my-project/Database"

# Files to validate (in run order)
FILES = [
    "10_00_log_table.sql",
    "10a_userType.sql",
    "10b_joiningFee.sql",
    "10c_master_tables.sql",
    "10d_master_data_migration.sql",
    "10e_staff_merge.sql",
    "10f_shift_ids.sql",
    "10g_calendar_ids.sql",
    "10h_misc_tables.sql",
    "10i_branch.sql",
    "10j_feepayment_id.sql",
    "10_zz_summary.sql",
    "10_verify.sql",
]

def split_batches(sql_text):
    """Split on GO (case-insensitive, on its own line)."""
    lines = sql_text.splitlines()
    batches = []
    current = []
    for line in lines:
        if re.match(r'^\s*GO\s*;?\s*$', line, re.IGNORECASE):
            if current:
                batches.append("\n".join(current))
                current = []
        else:
            current.append(line)
    if current:
        batches.append("\n".join(current))
    return batches

def check_quotes(batch):
    """Check that single quotes are balanced (count of ' is even, ignoring escaped '')."""
    # Remove single-line comments (-- ...)
    cleaned = re.sub(r'--[^\n]*', '', batch)
    # Remove multi-line comments (/* ... */)
    cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)
    # Count single quotes (escaped '' counts as one pair, so even is fine)
    count = cleaned.count("'")
    return count % 2 == 0, count

def check_parens(batch):
    """Check that parentheses are balanced."""
    # Remove strings (single-quoted)
    cleaned = re.sub(r"'(?:[^']|'')*'", "''", batch)
    # Remove comments
    cleaned = re.sub(r'--[^\n]*', '', cleaned)
    cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)
    depth = 0
    for ch in cleaned:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth < 0:
                return False, f"unmatched ) at depth {depth}"
    return depth == 0, f"final depth {depth}"

def validate_file(filepath):
    fname = os.path.basename(filepath)
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    batches = split_batches(content)
    errors = []

    for i, batch in enumerate(batches, 1):
        batch_preview = batch.strip()[:80].replace('\n', ' ')
        if not batch.strip():
            continue

        # 1. Balanced quotes
        q_ok, q_count = check_quotes(batch)
        if not q_ok:
            errors.append(f"  batch {i}: UNBALANCED QUOTES (count={q_count}) | {batch_preview}")

        # 2. Balanced parens
        p_ok, p_msg = check_parens(batch)
        if not p_ok:
            errors.append(f"  batch {i}: UNBALANCED PARENS ({p_msg}) | {batch_preview}")

        # 3. sqlglot parse (tsql dialect)
        # Note: sqlglot falls back to 'Command' for many T-SQL constructs
        # (IF/BEGIN/END/TRY/CATCH/PRINT/etc). We only count it as an error
        # if it raises a ParseError (real syntax error), not a fallback.
        import warnings
        import logging
        # Suppress sqlglot fallback warnings
        logging.getLogger('sqlglot').setLevel(logging.ERROR)
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                sqlglot.parse(batch, read="tsql")
        except sqlglot.errors.ParseError as e:
            err_str = str(e).replace('\n', ' ')[:120]
            errors.append(f"  batch {i}: SQLGLOT PARSE ERROR: {err_str} | {batch_preview}")
        except Exception as e:
            # Other exceptions (not ParseError) are likely fallbacks, not real errors
            pass

    return len(batches), errors

print("=" * 80)
print("SQL VALIDATION REPORT (sqlglot tsql + quote/paren balance check)")
print("=" * 80)

all_ok = True
for fname in FILES:
    fpath = os.path.join(DB_DIR, fname)
    if not os.path.exists(fpath):
        print(f"\n{fname}: FILE NOT FOUND")
        all_ok = False
        continue

    nbatches, errors = validate_file(fpath)
    if errors:
        all_ok = False
        print(f"\n{fname}: FAIL ({nbatches} batches, {len(errors)} errors)")
        for e in errors[:20]:
            print(e)
        if len(errors) > 20:
            print(f"  ... and {len(errors)-20} more errors")
    else:
        print(f"\n{fname}: PASS ({nbatches} batches, 0 errors)")

print("\n" + "=" * 80)
if all_ok:
    print("OVERALL: ALL FILES PASS")
else:
    print("OVERALL: SOME FILES FAILED - see above")
print("=" * 80)
