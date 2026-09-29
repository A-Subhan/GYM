# Database/_archive - NOT part of the fresh install

Everything in this folder is **archived and inert**. Do **not** run any of it on
a fresh database.

## What is in here

| Item | What it was | Why archived |
|------|-------------|--------------|
| `_additions_master_data.sql`, `_extracted_master_data.sql`, `_header_master_data.sql` | Scratch files used while `06_master_data.sql` was being assembled | Superseded by `06_master_data.sql` (nothing references them; running them would duplicate master rows) |
| `_generated_tables.sql` | Machine-generated table dump used as a cross-check while `02_schema_tables.sql` was written | Superseded by `02_schema_tables.sql` |
| `_columns_reference.txt` | Column inventory scratch note | Superseded by `Backend/prisma/schema.prisma` (the design authority) |
| `migrations/00_preflight_check.sql` ... `12_views_procedures_rebuild.sql`, `migrations/README.md`, `migrations/99_rollback_notes.md` | One-off upgrade path for a PRE-EXISTING old database (Account→charts rename, book tables, legacy voucher migration, PK rebuild, id regeneration, module removal) | Only ever meant for upgrading the old DB. A fresh install must NOT run them - the fresh-install scripts 02-06 already create the final shape. |

## How history was preserved

The files were moved here with `git mv` (rename commits), so the full history
of every archived file stays available via `git log --follow`.

## The only exception

Nothing in this folder is referenced by backend code. (Comments in
`Backend/src/lib/ids.ts` mention `Database/migrations/...` as historical
background only - they describe where the id-sequence keys were first seeded,
which the fresh-install `06_master_data.sql` now does directly.)
