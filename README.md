# Contoura Gym Management System — Full ERP

A complete Enterprise Resource Planning system for gym/fitness club management.

## Project Structure

```
GYM/
├── Frontend/          # Original Vite + React frontend (legacy reference)
├── Backend/           # Original Express + Node.js backend (legacy reference)
├── Database/           # SQL Server database setup, scripts, and backups
│   ├── GymDB.bak       # Real SQL Server backup (23 MB)
│   ├── GymDB-2026-07-11.bak  # Additional SQL Server backup (14 MB)
│   ├── README.md       # SQL Server setup instructions
│   └── sql/            # SQL Server schema and migration scripts
├── src/                # Current Next.js 16 fullstack application
│   ├── app/            # App Router pages + API routes
│   │   ├── api/        # Backend API route handlers
│   │   ├── module-pages.tsx  # Frontend module components
│   │   ├── page.tsx    # Main app shell + routing
│   │   └── layout.tsx  # Root layout
│   ├── components/     # shadcn/ui components
│   ├── lib/            # Auth, db, accounting utilities
│   └── hooks/          # React hooks
├── prisma/            # Prisma ORM schema
│   ├── schema.prisma        # Active schema (SQLite for dev)
│   └── schema-sqlserver.prisma  # SQL Server schema for production
├── scripts/           # Seed and test scripts
└── package.json       # Next.js dependencies
```

## Current Working Application

The current working implementation is a **Next.js 16 fullstack app** at the repository root.
It combines the frontend and backend into a single application:

- **Frontend**: Next.js App Router + React + Tailwind CSS 4 + shadcn/ui
- **Backend**: Next.js API routes + Prisma ORM
- **Database**: SQLite for development, SQL Server for production (configurable)

The `Frontend/` and `Backend/` folders contain the **original legacy implementation**
(Vite/React frontend + Express/Node backend) preserved for reference. They are not
required to run the current Next.js application.

## Database

The current Next.js app uses **SQLite** for local development (no setup required).
For production, it supports **Microsoft SQL Server** via the `prisma/schema-sqlserver.prisma` file.

See `Database/README.md` for:
- How to switch to SQL Server
- How to generate a fresh `GymDB.bak` backup
- How to restore from backup
- All SQL Server schema scripts

## Quick Start

```bash
# Install dependencies
bun install

# Set up the database (SQLite for dev)
bun run db:push
bun run db:generate

# Seed initial data (admin user, COA, branches, etc.)
bun run scripts/seed.ts

# Start the dev server
bun run dev
# Open http://localhost:3000
```

## Login

- Username: `admin`
- Password: `admin123` (case-insensitive)

## Features

- **Finance**: Chart of Accounts (Charts), CashBook (CPV/CRV), BankBook (BPV/BRV),
  Journal Voucher (JV), Opening Trial Balance (OpenTB/Knock Off), Finance Reports
- **Gym**: Members, Membership Plans, Attendance, Fees & Invoices, Prospects,
  Membership Freeze, Follow-ups, Exercises, Workouts, Diet Plans, Progress
- **HR/Payroll**: Staff, Shifts, Calendar, Leaves, Overtime, Payroll, Payroll Master File
- **Inventory**: Equipment, Inventory Items, POS/Counter Sales
- **Admin**: Company Information, Branches (Company/Control/Detail hierarchy),
  Users + Roles + Permissions (per-user popup), Audit Log, Admin Defaults (3 tabs)

## Permissions

143 granular permission codes, 7 system roles, per-user permission overrides.
Permissions are enforced on every API route.
