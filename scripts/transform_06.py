#!/usr/bin/env python3
"""Transform Database/06_master_data.sql to use the new business-id formats.

Replaces cuid-style PKs for the in-scope tables (Defaults, Role, Permission,
User, TaxHead, AccountMapping, FinanceDefaults) with their new formats
(CMP-001, ROL-001, PRM-0001, USR-0001, TAX-001, ACM-001, FDF-001) and
updates every FK reference throughout the file.

Also fixes extraction artifacts ([m stripped from column names) and adds a
company-wide FinanceDefaults row (FDF-001, branchId NULL).
"""
import re
import sys

# --- Config ---
IN_SCOPE = {
    'Defaults':        ('CMP-', 3),
    'Role':            ('ROL-', 3),
    'Permission':      ('PRM-', 4),
    'User':            ('USR-', 4),
    'TaxHead':         ('TAX-', 3),
    'AccountMapping':  ('ACM-', 3),
    'FinanceDefaults': ('FDF-', 3),
}

def main(path: str) -> None:
    src = open(path, 'r', encoding='utf-8').read()

    # --- 1. Artifact fix is NOT needed — the file already has [module],
    #        [mustChangePassword], [membershipPlanId]. The previous version
    #        of this script corrupted [module] into [m[module] by replacing
    #        the 'odule]' substring INSIDE [module]. Do NOT do that. ---

    # --- 2. Build mapping old_cuid -> new_id ---
    # Find each INSERT INTO [Table] ([id], ... VALUES ('cuid', ...)
    # The id is the first quoted value after VALUES (.
    mapping = {}      # old_id -> new_id
    counters = {t: 0 for t in IN_SCOPE}

    # Match: INSERT INTO [Table] ([id], ... ) VALUES ('cuid',
    # Non-greedy [^\n]*? to find the FIRST ) (column list closing paren),
    # not the final ); at the end of the VALUES clause.
    insert_re = re.compile(
        r'INSERT INTO \[(\w+)\] \(\[id\][^\n]*?\)\s*VALUES\s*\(\'([a-z0-9-]+)\'',
        re.MULTILINE
    )

    for m in insert_re.finditer(src):
        table = m.group(1)
        old_id = m.group(2)
        if table not in IN_SCOPE:
            continue
        # Skip if the id is already in the new format (re-run safety)
        prefix, width = IN_SCOPE[table]
        if old_id.startswith(prefix):
            continue
        # Skip 'findef-001' style ids for FinanceDefaults — handle separately below
        if table == 'FinanceDefaults' and old_id.startswith('findef-'):
            continue
        # Must be a cuid to migrate (cuid format: c + 24 lowercase alphanumeric)
        if not re.match(r'^c[a-z0-9]{24}$', old_id):
            continue
        counters[table] += 1
        seq = counters[table]
        new_id = f"{prefix}{str(seq).zfill(width)}"
        mapping[old_id] = new_id

    # --- 3. Handle FinanceDefaults 'findef-001' / 'findef-002' ---
    # Map them to FDF-002 and FDF-003 (FDF-001 reserved for company-wide)
    findef_re = re.compile(
        r"(INSERT INTO \[FinanceDefaults\] \(\[id\][^\n]*\)\s*VALUES\s*\(')(findef-\d+)",
    )
    findef_counter = 1  # FDF-001 is company-wide; branch rows start at FDF-002
    for m in findef_re.finditer(src):
        old_id = m.group(2)
        findef_counter += 1
        new_id = f"FDF-{str(findef_counter).zfill(3)}"
        mapping[old_id] = new_id

    # --- 4. Replace all old ids with new ids ---
    for old_id, new_id in mapping.items():
        src = src.replace(f"'{old_id}'", f"'{new_id}'")

    # --- 5. Add a company-wide FinanceDefaults row (FDF-001, branchId NULL) ---
    # Find the first FinanceDefaults INSERT and prepend the company-wide row.
    company_wide_insert = (
        "INSERT INTO [FinanceDefaults] ([id], [branchId], [defaultCashAccountId], "
        "[defaultBankAccountId], [defaultTaxHeadId], [financialYearId], [createdAt], "
        "[updatedAt]) VALUES ('FDF-001', NULL, '01001', '01002', 'TAX-001', 'fy-2026', "
        "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');\n"
    )
    # Find the first FinanceDefaults INSERT line
    fd_marker = 'INSERT INTO [FinanceDefaults]'
    fd_pos = src.find(fd_marker)
    if fd_pos >= 0:
        # Find the start of the line
        line_start = src.rfind('\n', 0, fd_pos) + 1
        src = src[:line_start] + company_wide_insert + src[line_start:]

    # --- 6. Write ---
    open(path, 'w', encoding='utf-8').write(src)
    print(f"Replaced {len(mapping)} ids:")
    for t in IN_SCOPE:
        prefix, width = IN_SCOPE[t]
        n = counters[t]
        if t == 'FinanceDefaults':
            n = findef_counter - 1
        print(f"  {t}: {n} rows -> {prefix}{'1'.zfill(width)}..{prefix}{str(n).zfill(width)}")
    print("Added company-wide FinanceDefaults row (FDF-001, branchId NULL)")

if __name__ == '__main__':
    main(sys.argv[1])
