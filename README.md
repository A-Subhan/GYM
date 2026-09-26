# Contoura Gym Management System — Full ERP

A complete Enterprise Resource Planning system for gym/fitness club management.

## Repository Structure

```
GYM/
├── Frontend/                  # Frontend area
│   └── legacy/                # Original Vite + React frontend (reference only)
│       ├── package.json
│       ├── src/               # 41 pages, React Router, Tailwind 3
│       ├── public/
│       └── vite.config.js
│
├── Backend/                   # ✅ Active Backend (Next.js fullstack app)
│   ├── package.json           # Next.js 16 + Prisma 6 + shadcn/ui
│   ├── next.config.ts
│   ├── tsconfig.json
│   ├── tailwind.config.ts
│   ├── eslint.config.mjs
│   ├── bun.lock
│   ├── src/                   # Next.js app (UI + API routes)
│   │   ├── app/
│   │   │   ├── api/           # 42 API route handlers (auth, finance, gym, HR, etc.)
│   │   │   ├── page.tsx       # Main app shell + routing
│   │   │   ├── module-pages.tsx  # All ERP module screens (~3500 LOC)
│   │   │   ├── modules.tsx    # Shared UI primitives
│   │   │   └── layout.tsx
│   │   ├── components/         # shadcn/ui components
│   │   ├── lib/               # Auth, db, accounting, permissions
│   │   └── hooks/
│   ├── public/                # Static assets
│   ├── scripts/
│   │   └── seed.ts            # Database seed script
│   ├── db/                    # Local SQLite dev database (gitignored)
│   ├── .env.example           # Environment template
│   ├── .env                   # Local env (gitignored)
│   └── legacy/                # Original Express + SQL Server backend (reference only)
│       ├── server.js
│       ├── src/
│       └── docs/
│
├── Database/                  # ✅ Database layer (canonical)
│   ├── README.md              # SQL Server setup + backup instructions
│   ├── GymDB.bak              # Real SQL Server backup (23 MB)
│   ├── GymDB-2026-07-11.bak   # Additional SQL Server backup (14 MB)
│   ├── prisma/                # Prisma schema (canonical location)
│   │   ├── schema.prisma              # SQLite for development
│   │   └── schema-sqlserver.prisma    # SQL Server for production
│   └── sql/                   # Raw SQL Server scripts (17 files)
│       ├── 01_schema.sql
│       ├── 02_procedures.sql
│       └── ... (14 more)
│
├── .gitignore
└── README.md                  # This file
```

## Which Implementation Is Active?

| Layer | Active | Legacy (reference only) |
|---|---|---|
| **Frontend** | UI inside `Backend/src/app/` (Next.js App Router) | `Frontend/legacy/` (Vite/React — points to legacy Express) |
| **Backend** | `Backend/src/app/api/` (Next.js API routes, 42 routes) | `Backend/legacy/` (Express, points to legacy SQL Server) |
| **Database** | `Database/prisma/schema.prisma` (Prisma) + `Database/sql/` (SQL Server scripts) | None |

The current app is a **Next.js 16 fullstack application** that combines frontend and backend in one project.
The `Frontend/legacy/` and `Backend/legacy/` folders preserve the original Vite/React and Express/SQL-Server
implementations for reference — they are NOT used by the active app.

## Quick Start

```bash
# Clone
git clone https://github.com/A-Subhan/GYM.git
cd GYM

# Install dependencies
cd Backend
bun install    # or: npm install

# Set up the database (SQLite for dev — no SQL Server required)
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

## Switching to SQL Server (Production)

1. Copy the SQL Server schema to the active schema:
   ```bash
   cp Database/prisma/schema-sqlserver.prisma Database/prisma/schema.prisma
   ```
2. Update `Backend/.env`:
   ```
   DATABASE_URL="sqlserver://localhost:1433;database=GymDB;user=sa;password=YourPassword;encrypt=true;trustServerCertificate=true"
   ```
3. Push schema and seed:
   ```bash
   cd Backend
   bun run db:push
   bun run db:generate
   bun run scripts/seed.ts
   ```

See `Database/README.md` for full SQL Server setup and backup/restore instructions.

## Features

- **Finance**: Chart of Accounts (Charts), CashBook (CPV/CRV), BankBook (BPV/BRV),
  Journal Voucher (JV), Opening Trial Balance (OpenTB/Knock Off), Finance Reports
- **Gym**: Members, Membership Plans, Attendance, Fees & Invoices, Prospects,
  Membership Freeze, Follow-ups, Exercises, Workouts, Diet Plans, Progress
- **HR/Payroll**: Staff (with trainer fields), Shifts, Calendar, Leaves, Overtime,
  Payroll, Payroll Master File (Departments, Designations, Leave Types, etc.)
- **Inventory**: Equipment, Inventory Items, POS/Counter Sales
- **Admin**: Company Information, Branches (Company/Control/Detail hierarchy),
  Users + Roles + Permissions (per-user popup), Audit Log, Admin Defaults (3 tabs)

## Permissions

143 granular permission codes, 7 system roles, per-user permission overrides.
Permissions are enforced on every API route.

## Why Are There Legacy Folders?

The `Frontend/legacy/` and `Backend/legacy/` folders contain the **original** Vite/React
frontend and Express/Node.js backend from the legacy Contoura Gym project. They are
preserved for reference but are NOT used by the active app.

The active application is a **Next.js 16 fullstack rewrite** in `Backend/` that:
- Combines the frontend and backend into a single app (App Router)
- Uses Prisma ORM (SQLite for dev, SQL Server for prod)
- Provides 42 API routes covering all ERP modules
- Has all the latest features (Charts rename, CashBook/BankBook/JV/OpenTB, KnockOff,
  trainer fields, per-user permissions, branch hierarchy, etc.)
