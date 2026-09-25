#!/usr/bin/env node

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const bcrypt = require('bcryptjs');
const { getPool } = require('../src/config/db');

function looksLikeBcryptHash(value) {
  return typeof value === 'string' && /^\$2[aby]\$/.test(value);
}

function parseArgs() {
  const args = new Set(process.argv.slice(2).map((arg) => arg.toLowerCase()));
  return {
    apply: args.has('--apply') || args.has('-a'),
    dryRun: args.has('--dry-run') || args.has('-d') || (!args.has('--apply') && !args.has('-a')),
    verbose: args.has('--verbose') || args.has('-v'),
  };
}

async function main() {
  const { apply, dryRun, verbose } = parseArgs();

  const pool = await getPool();

  const result = await pool.request().query(`
    SELECT UserID, Username, Email, PasswordHash
    FROM Users
    WHERE IsDeleted = 0
      AND PasswordHash IS NOT NULL
    ORDER BY UserID;
  `);

  const users = result.recordset.filter((user) => {
    const passwordHash = user.PasswordHash;
    return typeof passwordHash === 'string' && passwordHash.trim() !== '' && !looksLikeBcryptHash(passwordHash.trim());
  });

  console.log(`Legacy/plaintext passwords found: ${users.length}`);

  if (!users.length) {
    console.log('No password migration needed. All stored hashes already look like bcrypt values.');
    return;
  }

  if (dryRun) {
    console.log('Dry run only. No database rows were updated.');
    users.forEach((user) => {
      console.log(`- ${user.Username} (${user.Email}) -> will hash legacy value`);
    });
    console.log('Run with --apply to update the database.');
    return;
  }

  let updated = 0;
  for (const user of users) {
    const currentPassword = String(user.PasswordHash ?? '').trim();
    const newHash = bcrypt.hashSync(currentPassword, 10);

    await pool.request()
      .input('UserID', user.UserID)
      .input('PasswordHash', newHash)
      .query(`
        UPDATE Users
        SET PasswordHash = @PasswordHash,
            UpdatedAt = SYSUTCDATETIME()
        WHERE UserID = @UserID;
      `);

    updated += 1;
    if (verbose) {
      console.log(`Updated user ${user.UserID} (${user.Username})`);
    }
  }

  console.log(`Migration complete. Updated ${updated} user(s).`);
  console.log('Please restart the backend or sign out/in to ensure the new bcrypt comparison is used.');
}

if (require.main === module) {
  main().catch((error) => {
    console.error('Password migration failed:');
    console.error(error);
    process.exit(1);
  });
}

module.exports = { main, looksLikeBcryptHash };
