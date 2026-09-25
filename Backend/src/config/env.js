/**
 * Environment configuration loader.
 * Loads from .env (gitignored) — see .env.example for template.
 */
require('dotenv').config();

const env = {
  port: parseInt(process.env.PORT, 10) || 4000,
  nodeEnv: process.env.NODE_ENV || 'development',
  clientUrl: process.env.CLIENT_URL || 'http://localhost:5173',

  db: {
    server: process.env.DB_SERVER || 'localhost',
    port: parseInt(process.env.DB_PORT, 10) || 1433,
    database: process.env.DB_DATABASE || 'GymDB',
    authType: process.env.DB_AUTH_TYPE || 'default',
    user: process.env.DB_USER || 'sa',
    password: process.env.DB_PASSWORD || '',
    domain: process.env.DB_DOMAIN || '',
    encrypt: String(process.env.DB_ENCRYPT).toLowerCase() === 'true',
    trustServerCertificate:
      String(process.env.DB_TRUST_SERVER_CERTIFICATE).toLowerCase() === 'true',
    poolMax: parseInt(process.env.DB_POOL_MAX, 10) || 10,
    poolMin: parseInt(process.env.DB_POOL_MIN, 10) || 0,
    requestTimeout: parseInt(process.env.DB_REQUEST_TIMEOUT, 10) || 30000,
  },

  jwt: {
    secret: process.env.JWT_SECRET || 'insecure-default-change-me',
    accessExpires: process.env.JWT_ACCESS_EXPIRES || '15m',
    refreshExpires: process.env.JWT_REFRESH_EXPIRES || '7d',
  },

  app: {
    name: process.env.APP_NAME || 'Contoura Gym Management System',
    developer: {
      name: process.env.DEVELOPER_NAME || 'Contoura Labs',
      email: process.env.DEVELOPER_EMAIL || 'contouralabs@gmail.com',
      phone: process.env.DEVELOPER_PHONE || '+92 342 2642366',
      website: process.env.DEVELOPER_WEBSITE || 'https://contoura-labs.vercel.app/',
    },
  },
};

module.exports = env;
