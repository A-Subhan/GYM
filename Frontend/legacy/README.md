# Frontend — Contoura Gym Management System

This folder contains the **original Vite + React frontend** from the legacy Contoura Gym project.

## Contents

- `index.html` — Vite entry HTML
- `package.json` — Vite/React dependencies
- `vite.config.js` — Vite configuration
- `src/` — React application source (pages, components, context, services)
- `public/` — Static assets (logo, favicon)
- `tailwind.config.js` — Tailwind CSS configuration
- `postcss.config.js` — PostCSS configuration

## Original Tech Stack

- Vite 5 (build tool)
- React 18 (UI library)
- Tailwind CSS (styling)
- React Router (routing)
- Axios (HTTP client)
- Lucide React (icons)
- React Hook Form (forms)

## Current Working Frontend

The current working frontend is the **Next.js 16 fullstack app** at the repository root (`/src/app/`). This Next.js app combines the frontend and backend into a single application using:
- Next.js 16 App Router
- React Server Components
- Tailwind CSS 4
- shadcn/ui component library

To run the current frontend:
```bash
bun install
bun run dev
# Open http://localhost:3000
```

## Running This Legacy Frontend (Optional)

This Vite/React frontend is preserved for reference. To run it standalone:

```bash
cd Frontend
npm install
npm run dev
# Open http://localhost:5173
```

> Note: This legacy frontend expects the Express backend from `../Backend/` to be running on port 5000.

## Original Backend Connection

This frontend was originally configured to connect to:
- `http://localhost:5000/api` (Express backend in `../Backend/`)

The current Next.js implementation uses same-origin API routes (`/api/...`).
