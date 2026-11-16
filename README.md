# telegram-bot-docker — deployment stack Sellgram (lxc-6 + lxc-7)

Repo ini **hanya** berisi konfigurasi deployment. Kode aplikasi ada di repo terpisah:

| Repo | Isi | Path di lxc-6 |
|---|---|---|
| `tefa-stemanika/sellgram-be` | Backend Express + Prisma + bot Telegram | `/opt/sellgram/sellgram-be` |
| `tefa-stemanika/sellgram-fe` | Frontend Next.js (output `standalone`) | `/opt/sellgram/sellgram-fe` |
| repo ini | Compose, env contoh, script, dokumentasi | `/opt/sellgram/telegram-bot-docker` |

Target infrastruktur: **lxc-6** (10.0.2.25) untuk aplikasi, **lxc-7** (10.0.2.26) untuk monitoring.
Rencana lengkap: `PLAN-MIGRASI-LXC-DOCKER.md` di repo `caprover-setup`.

## Struktur

```
lxc6-app/                        # stack aplikasi (Fase 1)
  docker-compose.yml
  docker-compose.evolution-host.yml   # overlay fallback T9 (Evolution network host)
  .env.example                   # password compose-level
  .env.backend.example
  .env.evolution.example
  initdb/01-init.sh              # membuat role + database (T3)
scripts/
  backup-db.sh
  restore-db.sh
legacy/                          # arsip stack lama (compose prod, Dockerfile, docs, skill VPS)
lxc7-monitoring/                 # menyusul di Fase 5
```

## Port

| Service | Port host | Keterangan |
|---|---|---|
| frontend | 3000 | Next.js standalone, user non-root (`node`) |
| backend | 5505 | `/health` untuk healthcheck |
| evolution | 8080 | API key wajib di header `apikey` |
| postgres | — | **tidak dipublish** (hanya network internal) |
| redis | — | **tidak dipublish** (hanya network internal) |

Postgres/Redis sengaja tidak terbuka. Kalau Evolution harus pindah ke `network_mode: host`,
keduanya dipublish **ke loopback saja** oleh overlay (lihat di bawah).

## Setup pertama

```bash
cd /opt/sellgram/telegram-bot-docker/lxc6-app

cp .env.example .env
cp .env.backend.example .env.backend
cp .env.evolution.example .env.evolution
chmod 600 .env .env.backend .env.evolution
```

Isi `.env` dengan password baru (`openssl rand -hex 24` untuk setiap variabel), lalu isi
kredensial pihak ketiga di `.env.backend` **langsung di server** (jangan pernah commit).

`EVOLUTION_API_KEY` (di `.env.backend`) dan `AUTHENTICATION_API_KEY` (di `.env.evolution`)
**harus bernilai sama**.

## Menjalankan

```bash
# 1) infrastruktur dulu
docker compose up -d postgres redis
docker compose ps            # tunggu sampai healthy

# 2) build satu per satu (RAM lxc-6 terbatas — T10)
docker compose build backend
docker compose build frontend

# 3) aplikasi
docker compose up -d backend frontend

# 4) Evolution (butuh QR baru; tidak ada sesi lama yang dimigrasi)
docker compose up -d evolution
```

Cek:

```bash
curl http://127.0.0.1:5505/health
curl -I http://127.0.0.1:3000
curl -H "apikey: <EVOLUTION_API_KEY>" http://127.0.0.1:8080/instance/fetchInstances
```

Seed database baru (isi `botCredential` dengan `ENCRYPTION_KEY` yang baru):

```bash
docker compose exec backend npm run db:seed-config
```

## Fallback: Evolution di `network_mode: host` (T9)

Di lxc-4 lama Evolution **memang** berjalan dengan `--network=host` karena bug runc/sysctl di
LXC unprivileged. Kalau versi bridge gagal start, pakai overlay:

```bash
docker compose -f docker-compose.yml -f docker-compose.evolution-host.yml up -d
```

Efeknya: Evolution mendengarkan `:8080` di LXC, Postgres/Redis dipublish ke `127.0.0.1`,
dan backend memanggil Evolution lewat `host.docker.internal:8080`.

Kembali ke bridge: `docker compose up -d` (tanpa overlay).

## Catatan desain

- **T3**: image `postgres` tidak mengenal `POSTGRES_EXTRA`, jadi `evolution_db` dibuat oleh
  `initdb/01-init.sh` (hanya jalan saat volume kosong).
- **T5**: Redis memakai `--maxmemory-policy noeviction` + AOF (syarat BullMQ).
- **T12**: tidak ada `command:` di backend — Dockerfile BE sudah menjalankan
  `prisma db push` lalu `npm start`.
- **T4**: Evolution di-pin ke `v2.3.7`, bukan `latest`.
- **T2**: build memakai Dockerfile milik repo aplikasi, bukan file di `legacy/`.
- `NEXT_PUBLIC_*` tertanam saat build — mengubahnya berarti rebuild image frontend.
- Password harus alfanumerik/hex karena dipakai di dalam URL koneksi.

## Backup / restore

```bash
./scripts/backup-db.sh
./scripts/restore-db.sh /var/backups/sellgram/sellgram-YYYYmmdd-HHMMSS.sql.gz
```

## Legacy

`legacy/` menyimpan stack lama (compose dev/prod, `Dockerfile.*`, `setup-swap.sh`, docs lama,
skill deploy VPS) untuk referensi. **Jangan dipakai untuk lxc-6** — port, build, dan env-nya
sudah tidak sesuai (T11, T13).

## Status fase

- Fase 1 (repo ini) — selesai: compose lxc-6, initdb, env contoh, script, `.gitignore`.
- Fase 5 — akan menambah `lxc7-monitoring/` dan `docker-compose.agents.yml`.
