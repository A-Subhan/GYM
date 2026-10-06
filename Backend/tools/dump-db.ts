// Dump the SQLite database to a SQL file with CREATE TABLE + INSERT statements
import { PrismaClient } from '@prisma/client'
import { readFileSync, writeFileSync } from 'fs'
import path from 'path'

const db = new PrismaClient()

// SQLite stores schema in sqlite_master. We use Prisma's raw query to get all tables.
async function main() {
  const out: string[] = []
  out.push('-- Contoura Gym Management System — database dump')
  out.push('-- Generated: ' + new Date().toISOString())
  out.push('-- Database: GymDB (SQLite source; compatible with SQL Server after minor adjustments)')
  out.push('')
  out.push('PRAGMA foreign_keys=OFF;')
  out.push('BEGIN TRANSACTION;')
  out.push('')

  // Get all tables from sqlite_master via Prisma's raw query
  const tables = await db.$queryRawUnsafe<{name: string, sql: string}[]>(
    `SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE '_prisma%' AND name NOT LIKE 'sqlite_%' ORDER BY name;`
  )

  for (const t of tables) {
    out.push('-- -----------------------------------------------------------')
    out.push(`-- Table: ${t.name}`)
    out.push('-- -----------------------------------------------------------')
    out.push(`DROP TABLE IF EXISTS "${t.name}";`)
    out.push(t.sql + ';')
    out.push('')

    // Dump all rows
    const cols = await db.$queryRawUnsafe<{name: string}[]>(
      `PRAGMA table_info("${t.name}");`
    )
    const colNames = cols.map(c => c.name)

    const rows = await db.$queryRawUnsafe<any[]>(
      `SELECT * FROM "${t.name}";`
    )
    if (rows.length > 0) {
      for (const row of rows) {
        const values = colNames.map(c => {
          const v = row[c]
          if (v === null) return 'NULL'
          if (typeof v === 'number') return String(v)
          if (typeof v === 'boolean') return v ? '1' : '0'
          if (v instanceof Date) return `'${v.toISOString()}'`
          // string — escape single quotes
          return `'${String(v).replace(/'/g, "''")}'`
        })
        out.push(`INSERT INTO "${t.name}" (${colNames.map(c => `"${c}"`).join(', ')}) VALUES (${values.join(', ')});`)
      }
      out.push('')
    }
  }

  out.push('COMMIT;')
  out.push('')

  const dumpPath = path.join(process.cwd(), 'database_dump.sql')
  writeFileSync(dumpPath, out.join('\n'))
  console.log(`Dump written to ${dumpPath}`)
  console.log(`Tables: ${tables.length}`)
  console.log(`Lines: ${out.length}`)
}

main().then(() => db.$disconnect()).catch(e => { console.error(e); process.exit(1) })
