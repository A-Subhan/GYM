const bcrypt = require('bcryptjs');

function normalizePlainPassword(value) {
  return String(value ?? '').trim();
}

function isBcryptHash(value) {
  return typeof value === 'string' && /^(\$2[aby]|\$2[aby]\$)/.test(value);
}

function hashPassword(plain) {
  return bcrypt.hashSync(normalizePlainPassword(plain), 10);
}

function comparePassword(plain, hash) {
  const candidate = normalizePlainPassword(plain);
  const stored = normalizePlainPassword(hash);

  if (!stored) return false;

  if (isBcryptHash(stored)) {
    return bcrypt.compareSync(candidate, stored);
  }

  return candidate.toLowerCase() === stored.toLowerCase();
}

module.exports = { hashPassword, comparePassword };
