const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const env = require('./config/env');
const { notFound, errorHandler } = require('./middleware/error');
const logger = require('./utils/logger');

// Routes
const authRoutes = require('./routes/authRoutes');
const userRoutes = require('./routes/userRoutes');
const branchRoutes = require('./routes/branchRoutes');
const settingsRoutes = require('./routes/settingsRoutes');
const dashboardRoutes = require('./routes/dashboardRoutes');
const memberRoutes = require('./routes/memberRoutes');
const membershipRoutes = require('./routes/membershipRoutes');
const attendanceRoutes = require('./routes/attendanceRoutes');
const feeRoutes = require('./routes/feeRoutes');
const financeRoutes = require('./routes/financeRoutes');
const auditRoutes = require('./routes/auditRoutes');
const staffRoutes = require('./routes/staffRoutes');
const mastersRoutes = require('./routes/mastersRoutes');
const payrollRoutes = require('./routes/payrollRoutes');
const workoutRoutes = require('./routes/workoutRoutes');
const dietRoutes = require('./routes/dietRoutes');
const progressRoutes = require('./routes/progressRoutes');
const equipmentRoutes = require('./routes/equipmentRoutes');
const inventoryRoutes = require('./routes/inventoryRoutes');
const notificationRoutes = require('./routes/notificationRoutes');
const reportRoutes = require('./routes/reportRoutes');
const backupRoutes = require('./routes/backupRoutes');

const app = express();

/* ---------- Security & basic middleware ---------- */
app.use(helmet());
app.use(
  cors({
    origin: env.clientUrl === '*' ? true : env.clientUrl,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  })
);
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

// Rate limit on /api/auth/login to prevent brute force
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Too many login attempts, please try again later.' } },
});

// General API limiter
const apiLimiter = rateLimit({
  windowMs: 1 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
});

/* ---------- Static files for uploads ---------- */
app.use('/uploads', express.static(require('path').join(__dirname, '..', 'uploads')));

/* ---------- Health check (public) ---------- */
app.get('/health', (req, res) => {
  res.json({
    success: true,
    data: {
      status: 'healthy',
      service: env.app.name,
      developer: env.app.developer,
      time: new Date().toISOString(),
    },
    message: 'Service is up',
  });
});

/* ---------- API routes ---------- */
const API_BASE = '/api/v1';

app.use(`${API_BASE}/auth/login`, loginLimiter);
app.use(`${API_BASE}`, apiLimiter);

app.use(`${API_BASE}/auth`, authRoutes);
app.use(`${API_BASE}/users`, userRoutes);
app.use(`${API_BASE}/branches`, branchRoutes);
app.use(`${API_BASE}/settings`, settingsRoutes);
app.use(`${API_BASE}/dashboard`, dashboardRoutes);
app.use(`${API_BASE}/members`, memberRoutes);
app.use(`${API_BASE}/memberships`, membershipRoutes);
app.use(`${API_BASE}/attendance`, attendanceRoutes);
app.use(`${API_BASE}/fees`, feeRoutes);
app.use(`${API_BASE}/finance`, financeRoutes);
app.use(`${API_BASE}/audit-logs`, auditRoutes);
app.use(`${API_BASE}/staff`, staffRoutes);
app.use(`${API_BASE}/masters`, mastersRoutes);
app.use(`${API_BASE}/payroll`, payrollRoutes);
app.use(`${API_BASE}/workouts`, workoutRoutes);
app.use(`${API_BASE}/diet`, dietRoutes);
app.use(`${API_BASE}/progress`, progressRoutes);
app.use(`${API_BASE}/equipment`, equipmentRoutes);
app.use(`${API_BASE}/inventory`, inventoryRoutes);
app.use(`${API_BASE}/notifications`, notificationRoutes);
app.use(`${API_BASE}/reports`, reportRoutes);
app.use(`${API_BASE}/backup`, backupRoutes);

/* ---------- 404 + error handler ---------- */
app.use(notFound);
app.use(errorHandler);

module.exports = app;
