const jwt = require('jsonwebtoken');
const env = require('../config/env');

function signAccessToken(payload) {
  return jwt.sign(payload, env.jwt.secret, { expiresIn: env.jwt.accessExpires });
}

function signRefreshToken(payload) {
  return jwt.sign(payload, env.jwt.secret, { expiresIn: env.jwt.refreshExpires });
}

function verifyToken(token) {
  return jwt.verify(token, env.jwt.secret);
}

module.exports = { signAccessToken, signRefreshToken, verifyToken };
