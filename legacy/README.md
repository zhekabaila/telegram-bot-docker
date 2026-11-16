# Telegram Stack Docker (FE + BE + DB)

Folder ini dipakai untuk menjalankan seluruh stack sekaligus:
- Frontend Next.js (`../order-bot-dashboard`)
- Backend Express + Telegram bot (`../telegram-ai-bot`)
- PostgreSQL

## 1) Siapkan env

1. Salin `.env.backend.example` menjadi `.env.backend`
2. Salin `.env.frontend.example` menjadi `.env.frontend`
3. Isi minimal value berikut di `.env.backend`:
- `JWT_SECRET`
- `ENCRYPTION_KEY` (64 hex chars)

## 2) Jalankan satu perintah

```bash
docker compose up -d --build
```

## 3) Akses service

- Frontend: `http://localhost:3000`
- Backend API: `http://localhost:5505/api`
- Health API: `http://localhost:5505/api/health`
- PostgreSQL host port: `localhost:5284`

## 4) Logs

```bash
docker compose logs -f frontend
docker compose logs -f backend
docker compose logs -f postgres
```

## 5) Stop

```bash
docker compose down
```

## 6) Reset DB volume (opsional)

```bash
docker compose down -v
```

## Catatan webhook Telegram

Karena backend mode webhook, Telegram membutuhkan URL HTTPS publik.
Untuk local dev gunakan tunnel (ngrok/cloudflared) yang mengarah ke backend `http://localhost:5505`.
