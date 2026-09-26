# Backend — Contoura Gym Management System

This folder contains the **original Express + Node.js backend** from the legacy Contoura Gym project.

## Contents

- `server.js` — Express server entry point
- `package.json` — Express/Node dependencies
- `src/` — Backend source (controllers, services, models, routes, middleware, validators)
- `sql/` — SQL Server schema and migration scripts (also available in `../Database/sql/`)
- `scripts/` — Maintenance scripts (seed, reset, fix-admin, test-finance)
- `docs/` — API documentation, RBAC, install, IIS deployment guides
- `ecosystem.config.js` — PM2 process manager configuration
- `uploads/backups/` — Real SQL Server database backups (also in `../Database/`)

## Original Tech Stack

- Express.js (web framework)
- MSSQL npm package (SQL Server driver)
- JSON Web Tokens (authentication)
- Bcrypt (password hashing)
- Multer (file uploads)
- Winston (logging)
- Helmet (security headers)
- CORS (cross-origin)

## Original Database

This backend connects to **Microsoft SQL Server** using the `mssql` npm package.
The database connection configuration was in `src/config/db.js` and `src/config/env.js`.

## Current Working Backend

The current working backend is the **Next.js 16 API routes** at `/src/app/api/`.
The Next.js app combines frontend and backend — API routes are server-side functions
in the same application.

Current backend features:
- Prisma ORM (supports both SQLite for dev and SQL Server for production)
- 40+ API route handlers covering all ERP modules
- bcrypt + Web Crypto JWT authentication
- 143 granular permission codes
- 7 system roles (Super Admin, Owner, Manager, Accountant, Receptionist, Trainer, Staff)

## Running This Legacy Backend (Optional)

This Express backend is preserved for reference. To run it standalone:

```bash
cd Backend
npm install
# Configure SQL Server connection in src/config/env.js
npm run dev
# Server starts on http://localhost:5000
```

> Note: This legacy backend requires Microsoft SQL Server to be installed and running.

## SQL Server Database Setup

See `../Database/README.md` for SQL Server connection details and backup instructions.
The SQL schema scripts are in `../Database/sql/` (and duplicated in `sql/` here).
