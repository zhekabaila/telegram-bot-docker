# AGENTS.md

## What this repo is

Docker Compose orchestration for a 4-service stack. No application code here — only compose files, Dockerfiles, env examples, and docs. App code lives in sibling projects.

| Service | Sibling project |
|---|---|
| Frontend (Next.js 16) | `../order-bot-dashboard` |
| Backend (Express + Prisma + Telegram bot) | `../telegram-ai-bot` |
| PostgreSQL 16 Alpine (`image: postgres:16-alpine`) | — |
| Redis 7 Alpine (`image: redis:7-alpine`) | — |

Key architecture fact: compose files set `context: ../telegram-ai-bot` (or `../order-bot-dashboard`) but reference Dockerfiles in **this** repo via `dockerfile: ../telegram-bot-docker/Dockerfile.*`. The Dockerfiles here are actively used — do not delete them.

`package-lock.json` here is a dummy (empty dependencies). All real `package.json` and lockfiles are in sibling projects.

## Ports

| Service | Container | Host |
|---|---|---|
| Frontend | 5506 | 5506 |
| Backend API | 5505 | 5505 |
| PostgreSQL | 5432 | 5284 |
| Redis | 6379 | 6379 (dev only, not exposed in prod) |

Backend API base: `http://localhost:5505/api`

**Stale-doc trap:** `README.md` and `RUN_GUIDE.md` claim frontend is at port 3000. **They are wrong.** Compose files set port 5506 — trust compose over those docs.

## Developer commands

| Action | Dev | Production |
|---|---|---|
| Start | `docker compose up -d --build` | `docker compose -f docker-compose.prod.yml up -d --build` |
| Stop | `docker compose down` | `docker compose -f docker-compose.prod.yml down` |
| Reset DB (wipe volumes) | `docker compose down -v` | `docker compose -f docker-compose.prod.yml down -v` |
| Rebuild single service | `docker compose up -d --build <svc>` | `docker compose -f docker-compose.prod.yml up -d --build <svc>` |
| Reload env (no build) | `docker compose up -d --force-recreate <svc>` | `docker compose -f docker-compose.prod.yml up -d --force-recreate <svc>` |
| Clean rebuild (no cache) | `docker compose build --no-cache` | `docker compose -f docker-compose.prod.yml build --no-cache` |
| Nuke everything | `docker compose down -v --rmi all --remove-orphans` | `docker compose -f docker-compose.prod.yml down -v --rmi all --remove-orphans` |
| Restart service | `docker compose restart <svc>` | `docker compose -f docker-compose.prod.yml restart <svc>` |
| Follow logs | `docker compose logs -f <svc>` | `docker compose -f docker-compose.prod.yml logs -f <svc>` |

Never mix dev and prod compose files.

## Setup

1. Copy `.env.*.example` → `.env.*` (all `.env.*` are gitignored)
2. `ENCRYPTION_KEY` must be exactly 64 hex characters
3. `REDIS_URL` defaults to `redis://redis:6379` — compose injects this automatically if not set in `.env.backend`

## Gotchas

- Backend runs `npm run db:push` (Prisma schema push) on every start — hardcoded in compose `command`
- Frontend dev uses `WATCHPACK_POLLING=true` for hot reload inside Docker on macOS
- Frontend Dockerfiles install with `--legacy-peer-deps`
- Dev mode mounts source as volume (`../telegram-ai-bot:/app`) — code changes reflect immediately; prod copies at build time
- Named volumes (`backend_node_modules`, `frontend_node_modules`) prevent host `node_modules` from shadowing
- Backend depends on both Postgres and Redis health checks (`condition: service_healthy`)
- HEALTHCHECK in backend Dockerfiles uses `wget` on `${PORT}/health` — dev relies on compose-injected `PORT` env var; prod hardcodes `ENV PORT=5505`
- Prod compose sets CPU/memory limits on all services (deploy.resources) — useful to know when troubleshooting OOM
- Telegram webhook mode requires HTTPS public URL; for local dev use a tunnel (ngrok/cloudflared) pointing to `localhost:5505`
- `--force-recreate` is for env-only changes; `--build` is for code/Dockerfile changes

## Deploy to VPS

A dedicated deploy skill lives at `.opencode/skills/deploy-telegram-bot/`. Use it when the user asks to deploy/redeploy/update to VPS `103.150.226.41`. Key facts the skill covers that are not repeated here:

- Stale local READMEs: the docs say port 3000 for frontend — port 5506 is correct
- Swap check is mandatory before building on 1GB RAM VPS (`sudo sh setup-swap.sh`)
- Build can take 5-10 min; set bash timeout to 600000ms
- Never exclude `.env.*.prod` files during rsync; do exclude `node_modules/`, `.next/`, `*.tar`, `.git/`
