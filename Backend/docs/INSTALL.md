# Installation Guide

This guide walks you through setting up the Contoura Labs Gym Management System on a fresh Windows machine (development or production).

---

## 1. Prerequisites

Install these on your Windows machine:

1. **Microsoft SQL Server 2022 Express** (free)
   - Download: https://www.microsoft.com/en-us/sql-server/sql-server-downloads
   - Choose "Express" edition (free, sufficient for single-gym use)
   - During install, choose **Mixed Mode authentication** and set a strong SA password — save this password, you'll need it.
   - Install **SQL Server Management Studio (SSMS)** alongside it.

2. **Node.js 20 LTS**
   - Download: https://nodejs.org/
   - Choose the LTS version (20.x or higher)
   - This installs `node` and `npm`.

3. **Git**
   - Download: https://git-scm.com/
   - Used for cloning the repos and pushing updates.

4. **PM2** (production only)
   - Install after Node: `npm install -g pm2`
   - Process manager for keeping the Node.js backend running.

5. **IIS** (production only)
   - Windows Server: Server Manager → Add Roles → Web Server (IIS)
   - Windows 10/11: Control Panel → Programs → Turn Windows features on → Internet Information Services
   - Install **URL Rewrite module**: https://www.iis.net/downloads/microsoft/url-rewrite
   - Install **Application Request Routing (ARR)**: https://www.iis.net/downloads/microsoft/application-request-routing

---

## 2. Clone the Repositories

```bash
# Pick a folder, e.g. C:\gym-system
mkdir C:\gym-system
cd C:\gym-system

# Frontend
git clone https://github.com/A-Subhan/Contoura_Labs_Gym.git frontend

# Backend
git clone https://github.com/A-Subhan/Backend-Software.git backend
```

After cloning, your folder should look like:

```
C:\gym-system\
├── frontend\           (React app)
└── backend\
    └── GYM-software\   (Express API + SQL scripts + docs)
```

---

## 3. Set Up the Database

1. Open **SQL Server Management Studio (SSMS)**.
2. Connect to your SQL Server:
   - Server type: `Database Engine`
   - Server name: `localhost` (or `.\SQLEXPRESS` for Express edition)
   - Authentication: `SQL Server Authentication`
   - Login: `sa`
   - Password: (the SA password you set during install)
3. In SSMS, open each SQL file **in order** and execute (F5):

   ```
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\01_schema.sql     → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\02_procedures.sql → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\03_triggers.sql   → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\04_seed.sql       → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\05_sample.sql     → Execute (optional — sample data)
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\06_phase8_procedures.sql → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\07_fixes.sql → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\08_phase9_changes.sql → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\09_master_files_staff_code.sql → Execute
   File → Open → File... → C:\gym-system\backend\GYM-software\sql\10_master_files_module.sql → Execute
   ```

   Each file should print a success message in the Messages pane. If any file errors, fix the issue before continuing.

4. **Verify**: In SSMS Object Explorer, expand `Databases → GymDB → Tables` — you should see ~40 tables.

---

## 4. Configure & Start the Backend

```bash
cd C:\gym-system\backend\GYM-software

# Create your config
copy .env.example .env
notepad .env
```

Edit `.env` and set:

```
DB_SERVER=localhost         (or .\SQLEXPRESS for Express)
DB_PORT=1433
DB_DATABASE=GymDB
DB_USER=sa
DB_PASSWORD=your-sa-password-here
JWT_SECRET=generate-a-random-string-at-least-32-chars-long
```

To generate a strong JWT secret, run: `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`

Then install + run:

```bash
npm install
npm run dev
```

You should see:

```
[server] Contoura Gym Management System running on port 4000 (development)
[server] Developer: Contoura Labs — https://contoura-labs.vercel.app/
[db] Connected to SQL Server localhost:1433/GymDB
```

**Verify**: Open http://localhost:4000/health in your browser — should return JSON with `"status":"healthy"` and Contoura Labs developer info.

---

## 5. Configure & Start the Frontend

```bash
cd C:\gym-system\frontend

copy .env.example .env
notepad .env
```

Set:
```
VITE_API_BASE_URL=http://localhost:4000/api/v1
```

Then:

```bash
npm install
npm run dev
```

Open http://localhost:5173 — you should see the Contoura Labs branded login page.

**Login with**: `contouralabs / Contoura@2024`

---

## 6. Production Build (Frontend)

For production, build the frontend to static files:

```bash
cd C:\gym-system\frontend
npm run build
```

This creates `C:\gym-system\frontend\dist\` containing the static files IIS will serve.

For production, set the frontend's `.env` to point at your production API URL:

```
VITE_API_BASE_URL=https://gym.yourcompany.com/api/v1
```

Then rebuild.

---

## 7. Production Backend with PM2

```bash
cd C:\gym-system\backend\GYM-software
npm install --omit=dev
pm2 start ecosystem.config.js
pm2 save
pm2 startup       # follow the printed instructions to auto-start on boot
```

PM2 will keep the backend running and restart it on crashes or server reboots.

Logs: `C:\gym-system\backend\GYM-software\logs\`

---

## 8. (Optional) IIS Reverse Proxy

See `docs/IIS_DEPLOY.md` for the full IIS configuration that:
- Serves the frontend static files from `dist/`
- Reverse-proxies `/api/*` to `http://localhost:4000/api/*` (the Node backend)
- Enforces HTTPS

---

## 9. Post-Install Checklist

- [ ] Change the `contouralabs` super-admin password (Settings → Users → Edit)
- [ ] Change all demo user passwords or delete the demo users
- [ ] Update Gym Information in Settings (name, address, phone, logo)
- [ ] Configure currency and tax percentage in Settings
- [ ] Create your real branches (if multi-branch)
- [ ] Create your real staff users with appropriate roles
- [ ] Create your membership plans
- [ ] Set up inventory + equipment if applicable
- [ ] Configure backup schedule for the database (see SQL Server Maintenance Plans)

---

## Troubleshooting

### Backend says "Failed to connect to localhost:1433"

- Check SQL Server service is running: `services.msc` → look for "SQL Server (MSSQLSERVER)" or "SQL Server (SQLEXPRESS)"
- Check the server name in `.env` — for Express edition, use `.\SQLEXPRESS` instead of `localhost`
- Check TCP/IP is enabled: SQL Server Configuration Manager → SQL Server Network Configuration → Protocols → enable TCP/IP
- Verify the SA password in `.env` matches what you set during install
- Check Windows Firewall allows port 1433

### Frontend login fails with "Network Error"

- Backend not running — check `npm run dev` in the backend folder
- Wrong `VITE_API_BASE_URL` in frontend `.env`
- CORS issue — backend `.env` `CLIENT_URL` must match the frontend URL (default `http://localhost:5173`)

### "Invalid username or password" but you're sure it's right

- The seed SQL may not have run successfully — re-run `04_seed.sql` and check for errors
- The password may have been changed — try resetting via SSMS (update `Users.PasswordHash`)

### Database connection works in SSMS but not in Node

- Check `.env` `DB_USER` is `sa` (or a SQL auth user, not Windows auth)
- Check `DB_ENCRYPT=false` and `DB_TRUST_SERVER_CERTIFICATE=true` for local dev

---

## Need Help?

Contact Contoura Labs:
- Email: contouralabs@gmail.com
- WhatsApp: +92 342 2642366
- Website: https://contoura-labs.vercel.app/
