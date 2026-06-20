---
name: deploy-telegram-bot
description: >-
  Deploy Telegram Bot Docker stack (PostgreSQL, Redis, backend Express/Prisma, frontend Next.js 16)
  ke VPS 1vCPU/1GB RAM. Meliputi setup env, aktivasi swap, transfer file via rsync/git, SSH,
  docker compose build & up, verifikasi service. Gunakan skill ini SETIAP KALI user minta
  deploy, redeploy, update, atau perbaiki deployment telegram-bot-docker ke VPS
  103.150.226.41. Juga untuk troubleshoot container crash/gagal start di VPS yang sama.
---

# Deploy Telegram Bot Docker ke VPS

## Konteks

Stack 4 service: **PostgreSQL 16 Alpine** + **Redis 7 Alpine** + **Backend Express/Prisma** + **Frontend Next.js 16**.

Semua service berjalan di **1 VPS** dengan spesifikasi **1 vCPU, 1 GB RAM**.
Lokasi deployment: `/var/www/telegram-bot-docker/`.

| Service | Port Host | Dockerfile |
|---|---|---|
| Backend | 5505 | `Dockerfile.backend.prod` (context: `../telegram-ai-bot`) |
| Frontend | 5506 | `Dockerfile.frontend.prod` (context: `../order-bot-dashboard`) |
| PostgreSQL | internal | `image: postgres:16-alpine` |
| Redis | internal | `image: redis:7-alpine` |

## Detil Koneksi VPS

| Info | Nilai |
|---|---|
| Host | `103.150.226.41` |
| User | `zhekabaila` |
| SSH | `ssh zhekabaila@103.150.226.41` |
| Project di VPS | `/var/www/telegram-bot-docker/` |
| Swap | `/swapfile 2GB` |

## Alur Deploy

### 1. Persiapan File .env

Dari folder lokal `telegram-bot-docker/`:

```bash
# Backend
cp .env.backend.prod.example .env.backend.prod
# Frontend
cp .env.frontend.prod.example .env.frontend.prod
```

WAJIB ganti nilai sensitif di `.env.backend.prod`:
- `DATABASE_URL` — ganti password
- `JWT_SECRET` — string random panjang
- `ENCRYPTION_KEY` — **64 karakter hex** (32 byte)
- `PUBLIC_BASE_URL` — URL publik HTTPS backend

WAJIB ganti di `.env.frontend.prod`:
- `NEXT_PUBLIC_API_URL` — URL publik backend

### 2. Upload File ke VPS

Gunakan rsync untuk transfer semua file yang diperlukan:

```bash
# Lokal ke VPS. Asumsi sudah SSH key.
rsync -avz --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '*.tar' \
  --exclude '.env.backend' \
  --exclude '.env.frontend' \
  -e "ssh -o StrictHostKeyChecking=no" \
  /Users/zhekabaila/telegram-bot-docker/ \
  zhekabaila@103.150.226.41:/var/www/telegram-bot-docker/

rsync -avz --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  -e "ssh -o StrictHostKeyChecking=no" \
  /Users/zhekabaila/telegram-ai-bot/ \
  zhekabaila@103.150.226.41:/var/www/telegram-ai-bot/

rsync -avz --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '.next' \
  -e "ssh -o StrictHostKeyChecking=no" \
  /Users/zhekabaila/order-bot-dashboard/ \
  zhekabaila@103.150.226.41:/var/www/order-bot-dashboard/
```

**Catatan**: File `.env.backend.prod` dan `.env.frontend.prod` jangan di-exclude!
File `*.tar` dan `node_modules` tidak perlu di-upload karena build dilakukan di VPS.

### 3. SSH & Cek Swap (KRITIS untuk 1GB RAM)

Build **pasti gagal OOM** tanpa swap. Cek dulu:

```bash
ssh zhekabaila@103.150.226.41 "free -h && sudo /sbin/swapon --show"
```

Jika swap tidak aktif:

```bash
# Lewat SSH:
ssh zhekabaila@103.150.226.41 "sudo sh /var/www/telegram-bot-docker/setup-swap.sh"
```

Atau manual:
```bash
ssh zhekabaila@103.150.226.41 "sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo /sbin/swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"
```

### 4. Build & Start Container

```bash
ssh zhekabaila@103.150.226.41 "cd /var/www/telegram-bot-docker && docker compose -f docker-compose.prod.yml up -d --build"
```

**Build bisa memakan waktu 5-10 menit** (npm ci + next build). Jangan timeout. Gunakan timeout 600000ms (10 menit) untuk perintah bash.

### 5. Verifikasi

```bash
ssh zhekabaila@103.150.226.41 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

Semua container harus `Up`:
| Container | Status |
|---|---|
| `telegram_stack_postgres_prod` | Up (healthy) |
| `telegram_stack_redis_prod` | Up (healthy) |
| `telegram_stack_backend_prod` | Up |
| `telegram_stack_frontend_prod` | Up |

### 6. Cek Logs (Jika Ada Masalah)

```bash
ssh zhekabaila@103.150.226.41 "docker compose -f /var/www/telegram-bot-docker/docker-compose.prod.yml logs --tail=50 backend"
ssh zhekabaila@103.150.226.41 "docker compose -f /var/www/telegram-bot-docker/docker-compose.prod.yml logs --tail=50 frontend"
```

## Troubleshooting Umum

### Build gagal / OOM / SSH timeout

**Penyebab**: RAM 1GB habis saat `next build` (puncak ~800-1500MB).

**Solusi perintah** — langkah demi langkah:

1. Tunggu VPS pulih (1-2 menit), lalu coba SSH lagi
2. Cek swap sudah aktif (`free -h`)
3. Coba build satu service dulu:
   ```bash
   ssh zhekabaila@103.150.226.41 "cd /var/www/telegram-bot-docker && docker compose -f docker-compose.prod.yml build backend"
   docker compose -f docker-compose.prod.yml build frontend
   docker compose -f docker-compose.prod.yml up -d
   ```
4. Jika build frontend tetap gagal, restart VPS dulu agar RAM clean:
   ```bash
   ssh zhekabaila@103.150.226.41 "sudo reboot"
   # Tunggu 30 detik, lalu lanjut build
   ```

### Container crash loop / restart terus

```bash
# Cek detail container
ssh zhekabaila@103.150.226.41 "docker inspect telegram_stack_backend_prod | grep -A5 Status"
# Lihat logs
ssh zhekabaila@103.150.226.41 "docker logs telegram_stack_backend_prod --tail 100"
```

**Penyebab umum**:
- Prisma connection refused (postgres belum siap → backend restart sampe postgres healthy)
- `ENCRYPTION_KEY` tidak valid (harus 64 hex chars)
- Port 5505/5506 sudah dipakai service lain

### Ingin update kode saja (tanpa rebuild penuh)

Jika hanya ubah kode (bukan dependency/Dockerfile):
```bash
# 1. rsync ulang kode
rsync -avz --exclude 'node_modules' --exclude '.git' ... (sama seperti step 2)

# 2. Rebuild container di VPS (pakai cache)
ssh zhekabaila@103.150.226.41 "cd /var/www/telegram-bot-docker && docker compose -f docker-compose.prod.yml up -d --build backend"
```

### Ingin stop semua service

```bash
ssh zhekabaila@103.150.226.41 "cd /var/www/telegram-bot-docker && docker compose -f docker-compose.prod.yml down"
```

### Ingin stop + hapus volume (reset database)

```bash
ssh zhekabaila@103.150.226.41 "cd /var/www/telegram-bot-docker && docker compose -f docker-compose.prod.yml down -v"
```

## Aturan Penting

1. **WAJIB cek swap dulu sebelum build** — tanpa swap, build pasti OOM pada 1GB RAM
2. **WAJIB timeout cukup** untuk perintah build — setidaknya 600000ms (10 menit)
3. **Jangan exclude `.env.*.prod`** saat rsync — file env production harus ikut terkirim
4. **SSH bisa timeout** selama build karena RAM penuh — tunggu dan retry
5. **Build frontend adalah yang paling berat** (Next.js 16 + Radix UI) — bisa 3+ menit
6. **Jangan start service order-bot-dashboard secara manual** di VPS — service ini jalan sebagai container `telegram_stack_frontend_prod` via docker compose
7. **Jangan hapus** folder `telegram-ai-bot` atau `order-bot-dashboard` di VPS — mereka dibutuhkan sebagai build context
