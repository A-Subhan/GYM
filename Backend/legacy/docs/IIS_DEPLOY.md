# IIS Deployment Guide

This guide covers deploying the Contoura Labs Gym Management System to Windows Server with IIS, serving both the frontend (static) and backend (Node via reverse proxy) through a single IIS site on port 443 (HTTPS).

---

## Architecture

```
                 ┌──────────────────────────────────────────────┐
   Browser  ───► │  IIS Site (port 443, HTTPS)                 │
                 │                                              │
                 │  ┌────────────────────────────────────────┐  │
                 │  │ URL Rewrite module                     │  │
                 │  │                                        │  │
                 │  │  /api/*  ───────────► ARR Reverse Proxy│─┼──┼──► http://localhost:4000/api/* (Node/PM2)
                 │  │                                        │  │
                 │  │  /*      ───────────► Static files     │  │
                 │  │                       (C:\www\gym\dist)│  │
                 │  └────────────────────────────────────────┘  │
                 └──────────────────────────────────────────────┘
```

The browser sees a single origin (`https://gym.yourcompany.com`). API requests go to `/api/v1/...` which IIS reverse-proxies to the Node backend running under PM2 on port 4000.

---

## Prerequisites

On your Windows Server:

1. **IIS** installed (Web Server role)
2. **URL Rewrite module** — https://www.iis.net/downloads/microsoft/url-rewrite
3. **Application Request Routing (ARR)** — https://www.iis.net/downloads/microsoft/application-request-routing
4. **Node.js 20 LTS** installed
5. **PM2** installed: `npm install -g pm2`
6. **SQL Server 2022** installed and the `GymDB` database created (run all SQL scripts)
7. **SSL certificate** — either from your domain registrar, internal CA, or via **win-acme** (free Let's Encrypt): https://www.win-acme.com/

---

## Step 1: Deploy Files

Create a folder structure on the server:

```
C:\www\gym\
├── dist\                  ← frontend production build (copy from frontend/dist)
└── api\                   ← backend code (copy of GYM-software contents)
    ├── src\
    ├── server.js
    ├── ecosystem.config.js
    ├── package.json
    ├── .env               ← production env
    └── sql\
```

### Build & copy the frontend

On your dev machine:
```bash
cd frontend
# Edit .env to set VITE_API_BASE_URL=/api/v1  (relative — uses same origin)
npm run build
```

Copy the contents of `frontend/dist/` to `C:\www\gym\dist\` on the server.

### Copy the backend

Copy everything in `backend/GYM-software/` to `C:\www\gym\api\` on the server.

### Configure backend `.env`

Edit `C:\www\gym\api\.env`:

```env
PORT=4000
NODE_ENV=production
CLIENT_URL=https://gym.yourcompany.com

DB_SERVER=localhost
DB_PORT=1433
DB_DATABASE=GymDB
DB_USER=sa
DB_PASSWORD=your-strong-sa-password
DB_ENCRYPT=false
DB_TRUST_SERVER_CERTIFICATE=true

JWT_SECRET=your-very-long-random-jwt-secret-at-least-32-chars

APP_NAME=Contoura Gym Management System
DEVELOPER_NAME=Contoura Labs
DEVELOPER_EMAIL=contouralabs@gmail.com
DEVELOPER_PHONE=+92 342 2642366
DEVELOPER_WEBSITE=https://contoura-labs.vercel.app/
```

**Important**: Set `CLIENT_URL` to your production HTTPS URL.

---

## Step 2: Start the Backend with PM2

```bash
cd C:\www\gym\api
npm install --omit=dev
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

Follow the instructions PM2 prints to make it auto-start on boot.

Verify:
```bash
curl http://localhost:4000/health
```

Should return JSON with `"status":"healthy"`.

---

## Step 3: Configure IIS

### 3.1 Enable ARR proxy

1. Open **IIS Manager**.
2. Click the server name (root node) in the left pane.
3. Open **Application Request Routing Cache**.
4. In the right pane, click **Server Proxy Settings**.
5. Check **Enable proxy**.
6. Click **Apply**.

### 3.2 Create the site

1. In IIS Manager, right-click **Sites** → **Add Website**.
2. **Site name**: `GymSystem`
3. **Physical path**: `C:\www\gym\dist`
4. **Binding**:
   - Type: `https`
   - IP address: `All Unassigned`
   - Port: `443`
   - SSL certificate: choose your certificate
5. Click **OK**.

### 3.3 Add URL Rewrite rules

1. Select the `GymSystem` site in the left pane.
2. Open **URL Rewrite**.
3. Click **Add Rule(s)** → **Blank rule** (inbound).

**Rule 1: API reverse proxy**

- **Name**: `ReverseProxyToAPI`
- **Match URL**: `^api/(.*)`
- **Action**: `Rewrite`
- **Rewrite URL**: `http://localhost:4000/api/{R:1}`
- Check **Append query string**.
- Click **Apply**.

> Note: ARR must be enabled (step 3.1) for this to work.

### 3.4 SPA fallback rule

React Router uses client-side routing, so any URL like `/members/123` must serve `index.html`.

Add another blank inbound rule:

- **Name**: `SPAFallback`
- **Match URL**: `.*`
- **Conditions**:
  - Add condition: `{REQUEST_FILENAME}` `Is Not a File`
  - Add condition: `{REQUEST_FILENAME}` `Is Not a Directory`
- **Action**: `Rewrite`
- **Rewrite URL**: `/index.html`
- Click **Apply**.

Make sure the SPA fallback rule is **below** the API reverse-proxy rule in the rule list.

### 3.5 Set proper MIME types

By default, IIS doesn't serve `.svg` files correctly in some setups. Add this to a `web.config` file at `C:\www\gym\dist\web.config`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <staticContent>
      <remove fileExtension=".svg" />
      <mimeMap fileExtension=".svg" mimeType="image/svg+xml" />
      <remove fileExtension=".woff" />
      <mimeMap fileExtension=".woff" mimeType="font/woff" />
      <remove fileExtension=".woff2" />
      <mimeMap fileExtension=".woff2" mimeType="font/woff2" />
    </staticContent>
    <httpProtocol>
      <customHeaders>
        <add name="X-Content-Type-Options" value="nosniff" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="Referrer-Policy" value="strict-origin-when-cross-origin" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
```

---

## Step 4: Test

1. Open `https://gym.yourcompany.com` in your browser.
2. You should see the Contoura Labs branded login page.
3. Login with `contouralabs / Contoura@2024`.
4. Dashboard should load with KPIs and charts.

If the page loads but login fails with a network error, the API reverse proxy isn't working — check:
- ARR proxy is enabled (step 3.1)
- PM2 backend is running (`pm2 status` shows `gym-backend` as `online`)
- The URL Rewrite rule for `/api/*` is correct

---

## Step 5: HTTPS Auto-Renewal (Let's Encrypt)

If using win-acme for free SSL:

```bash
# Download win-acme from https://www.win-acme.com/
# Run wacs.exe
# Choose: Create certificate (default options)
# Pick: IIS binding
# Pick: your GymSystem site
# Follow prompts — it auto-renews via scheduled task
```

---

## Step 6: Backup Plan

Set up SQL Server Maintenance Plans in SSMS:

1. SSMS → Management → Maintenance Plans → New Maintenance Plan
2. Add **Backup Database (Full)** task — schedule daily, save `.bak` to `D:\Backups\GymDB\`
3. Add **Maintenance Cleanup Task** — delete `.bak` files older than 7 days
4. Schedule: daily at 2 AM

Test restore once a quarter: restore the latest `.bak` to a `GymDB_test` database and verify.

---

## Logs

| Component | Location |
|---|---|
| Backend (PM2) | `C:\www\gym\api\logs\pm2-out.log`, `pm2-error.log` |
| Backend (app) | `C:\www\gym\api\logs\combined.log`, `error.log` |
| IIS | Windows Event Viewer → Windows Logs → Application |
| SQL Server | SQL Server Logs (SSMS → Management → SQL Server Logs) |

---

## Updating the Software

To deploy an update:

```bash
# 1. Stop backend
cd C:\www\gym\api
pm2 stop gym-backend

# 2. Pull latest code
git pull

# 3. Run any new SQL scripts (check release notes)

# 4. Install/update dependencies
npm install --omit=dev

# 5. Start backend
pm2 start gym-backend

# 6. For frontend: rebuild on dev machine and copy dist/ to C:\www\gym\dist\
```

---

## Troubleshooting IIS

### 502.3 Bad Gateway

- PM2 backend is not running — run `pm2 status` and `pm2 logs gym-backend`
- ARR proxy is not enabled — see step 3.1

### 404 for /api/* routes

- URL Rewrite rule for `^api/(.*)` is missing or wrong — recheck step 3.3

### Frontend loads but no CSS/JS

- Static file MIME types not configured — see step 3.5
- File permissions — IIS app pool identity needs read access to `C:\www\gym\dist\`

### Login works but immediately redirects to /login

- Cookie/localStorage blocked — check browser console
- `CLIENT_URL` in backend `.env` doesn't match the HTTPS URL — CORS is rejecting the request

---

## Need Help?

Contact Contoura Labs:
- Email: contouralabs@gmail.com
- WhatsApp: +92 342 2642366
- Website: https://contoura-labs.vercel.app/
