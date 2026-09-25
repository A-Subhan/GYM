/**
 * Contoura Labs — Gym Management System
 * Backend entry point
 */
const app = require('./src/app');
const env = require('./src/config/env');
const { getPool } = require('./src/config/db');
const logger = require('./src/utils/logger');

async function start() {
  try {
    // Try to connect to DB on boot, but don't block the API from starting.
    // Routes will surface a clear error if DB is unavailable.
    getPool().catch((err) => {
      logger.warn(`[server] DB not yet available (${err.message}). API will start; DB calls will fail until DB is reachable.`);
    });

    const server = app.listen(env.port, () => {
      logger.info(`[server] ${env.app.name} running on port ${env.port} (${env.nodeEnv})`);
      logger.info(`[server] Developer: ${env.app.developer.name} — ${env.app.developer.website}`);
    });

    // Graceful shutdown
    const shutdown = async (signal) => {
      logger.info(`[server] ${signal} received, shutting down...`);
      server.close(async () => {
        const { closePool } = require('./src/config/db');
        await closePool();
        logger.info('[server] Closed out remaining connections.');
        process.exit(0);
      });
      // Force-exit after 10s if graceful close hangs
      setTimeout(() => process.exit(1), 10000).unref();
    };
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  } catch (err) {
    logger.error('[server] Failed to start: ' + err.message);
    process.exit(1);
  }
}

start();
