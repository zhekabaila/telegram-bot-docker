# AGENTS.md

## What this repo is

Docker Compose orchestration for a 4-service stack. No application code here — only compose files, Dockerfiles, env examples, and docs. App code lives in sibling projects.

| Service | Sibling project |
|---|---|
| Frontend (Next.js 16) | `../order-bot-dashboard` |
| Backend (Express + Prisma + Telegram bot) | `../telegram-ai-bot` |
| PostgreSQL 16 Alpine | — |
| Redis 7 Alpine | — |

Key architecture fact: `docker-compose.yml` sets `context: ../telegram-ai-bot` (or `../order-bot-dashboard`) but references Dockerfiles in **this** repo via `dockerfile: ../telegram-bot-docker/Dockerfile.*`. The Dockerfiles in this repo are actively used — do not delete them.

`package-lock.json` here is a dummy (empty dependencies). All real `package.json` and lockfiles are in sibling projects.

## Developer commands

| Action | Dev | Production |
|---|---|---|
| Start | `docker compose up -d --build` | `docker compose -f docker-compose.prod.yml up -d --build` |
| Stop | `docker compose down` | `docker compose -f docker-compose.prod.yml down` |
| Reset DB (wipe volumes) | `docker compose down -v` | `docker compose -f docker-compose.prod.yml down -v` |
| Rebuild single service | `docker compose up -d --build backend` | `docker compose -f docker-compose.prod.yml up -d --build backend` |
| Reload env (no build) | `docker compose up -d --force-recreate backend` | `docker compose -f docker-compose.prod.yml up -d --force-recreate backend` |
| Clean rebuild (no cache) | `docker compose build --no-cache` | `docker compose -f docker-compose.prod.yml build --no-cache` |
| Nuke everything | `docker compose down -v --rmi all --remove-orphans` | `docker compose -f docker-compose.prod.yml down -v --rmi all --remove-orphans` |
| Restart service (code unchanged) | `docker compose restart backend` | `docker compose -f docker-compose.prod.yml restart backend` |
| Follow logs | `docker compose logs -f backend` | `docker compose -f docker-compose.prod.yml logs -f backend` |

Never mix dev and prod compose files.

## Setup

1. Copy `.env.*.example` → `.env.*` (all `.env.*` are gitignored)
2. `ENCRYPTION_KEY` must be exactly 64 hex characters
3. `REDIS_URL` defaults to `redis://redis:6379` — compose injects this automatically if not set in `.env.backend`

## Ports

| Service | Container | Host |
|---|---|---|
| Frontend | 5506 | 5506 |
| Backend API | 5505 | 5505 |
| PostgreSQL | 5432 | 5284 |
| Redis | 6379 | 6379 (dev only) |

Backend API base: `http://localhost:5505/api`

## Gotchas

- Backend runs `npm run db:push` (Prisma schema push) on every dev start — hardcoded in compose command
- Frontend dev uses `WATCHPACK_POLLING=true` for hot reload inside Docker on macOS
- Frontend Dockerfiles install with `--legacy-peer-deps`
- Dev mode mounts source as volume (`../telegram-ai-bot:/app`) — code changes reflect immediately; prod copies at build time
- Named volumes (`backend_node_modules`, `frontend_node_modules`) prevent host `node_modules` from shadowing container-installed deps
- Backend depends on both Postgres and Redis health checks (`condition: service_healthy`)
- HEALTHCHECK in backend Dockerfiles uses `wget` on `${PORT}/health` — dev relies on compose-injected `PORT` env var; prod Dockerfile hardcodes `ENV PORT=5505`
- Telegram webhook mode requires HTTPS public URL. For local dev, use a tunnel (ngrok/cloudflared) pointing to `localhost:5505`
- `docker compose build --no-cache` fixes dependency caching issues during builds
- `--force-recreate` is for env-only changes (no build needed); `--build` is for code/Dockerfile changes in prod
