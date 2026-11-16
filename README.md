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
  docker-compose.local-image.yml      # overlay DARURAT: pakai image lokal Fase 3 (tanpa GHCR)
  .env.example                   # password compose-level
  .env.backend.example
  .env.evolution.example
  initdb/01-init.sh              # membuat role + database (T3)
scripts/
  backup-db.sh
  restore-db.sh
deploy/                          # CI/CD Fase 6: webhook + skrip deploy di lxc-6
  deploy.sh                      # flock, pull, up -d, health 40 s, rollback
  hooks.json.example             # dasar /etc/webhook/hooks.json (token diganti di server)
  webhook.service                # unit systemd adnanh/webhook, port 9000
  README.md                      # alur + pemasangan + uji rollback
legacy/                          # arsip stack lama (compose prod, Dockerfile, docs, skill VPS)
lxc7-monitoring/                 # stack monitoring lxc-7 (Fase 5)
  docker-compose.yml             # prometheus, grafana, portainer, pve-exporter, blackbox
  prometheus/prometheus.yml
  pve-exporter/pve.yml.example   # token asli hanya di server (pve.yml, chmod 600)
  grafana/provisioning/          # datasource + provider dashboard
  grafana/dashboards/            # 1860, 10347, 14282, 7587 (sudah diproses)
lxc6-app/docker-compose.agents.yml  # node-exporter, cAdvisor, portainer-agent (Fase 5)
```

## Port

| Service | Port host | Keterangan |
|---|---|---|
| frontend | 3000 | Next.js standalone, user non-root (`node`) |
| backend | 5505 | `/health` untuk healthcheck |
| evolution | 8080 | API key wajib di header `apikey` |
| postgres | — | **tidak dipublish** (hanya network internal) |
| redis | — | **tidak dipublish** (hanya network internal) |
| cAdvisor (agent) | 8082 | Fase 5, di lxc-6 |
| webhook deploy | 9000 | Fase 6, adnanh/webhook, di lxc-6 (hanya lewat Cloudflare Tunnel) |
| portainer-agent | 9001 | Fase 5, di lxc-6 |
| node-exporter | 9100 | Fase 5, `network_mode: host` di lxc-6 |
| Grafana (lxc-7) | 3000 | Fase 5 |
| Portainer (lxc-7) | 9443 | HTTPS, target tunnel pakai *No TLS Verify* |
| Prometheus (lxc-7) | — | **tidak dipublish**, hanya network `mon` |

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

# 2) image aplikasi di-pull dari GHCR (Fase 6 — tidak ada build di lxc-6)
docker compose pull backend frontend

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
- **T2**: image dibangun GitHub Actions dari `Dockerfile` milik repo aplikasi, bukan file di
  `legacy/` (sejak Fase 6 tidak ada `build:` di compose).
- `NEXT_PUBLIC_*` tertanam saat build — nilainya jadi `build-args` di workflow FE, jadi
  mengubahnya berarti push + rebuild image (bukan edit `.env`).
- Password harus alfanumerik/hex karena dipakai di dalam URL koneksi.

## CI/CD — image GHCR + webhook (Fase 6)

`backend` dan `frontend` memakai image jadi, bukan `build:`:

```yaml
image: ghcr.io/tefa-stemanika/sellgram-be:${BE_TAG:-latest}
image: ghcr.io/tefa-stemanika/sellgram-fe:${FE_TAG:-latest}
```

`BE_TAG`/`FE_TAG` ada di `.env` dan **diisi otomatis** oleh `/opt/deploy/deploy.sh`
(`sha-<commit>`). Alur: push ke `main` → Actions build `linux/amd64` + push GHCR →
POST webhook lxc-6 → `pull` + `up -d` + health check 40 s → `DEPLOY_OK`, atau rollback
ke tag sebelumnya + `DEPLOY_FAILED`.

Pemasangan webhook di lxc-6 dan uji rollback: lihat **`deploy/README.md`**.

Deploy manual:

```bash
sudo -u deploy /opt/deploy/deploy.sh fe          # tag `latest`
sudo -u deploy /opt/deploy/deploy.sh be <sha>    # tag `sha-<sha>`
```

Rollback = jalankan `deploy.sh` dengan tag lama, atau tulis `FE_TAG`/`BE_TAG` di `.env`
lalu `docker compose up -d <svc>`.

Bila GHCR tidak bisa dipakai sama sekali, pakai overlay image lokal Fase 3:

```bash
docker compose -f docker-compose.yml -f docker-compose.local-image.yml up -d backend frontend
```

## Backup / restore

```bash
./scripts/backup-db.sh
./scripts/restore-db.sh /var/backups/sellgram/sellgram-YYYYmmdd-HHMMSS.sql.gz
```

## Legacy

`legacy/` menyimpan stack lama (compose dev/prod, `Dockerfile.*`, `setup-swap.sh`, docs lama,
skill deploy VPS) untuk referensi. **Jangan dipakai untuk lxc-6** — port, build, dan env-nya
sudah tidak sesuai (T11, T13).

## Monitoring (Fase 5)

Agent di **lxc-6**, server di **lxc-7**.

```bash
# lxc-6 — overlay agent (project tetap "sellgram")
cd /opt/sellgram/telegram-bot-docker/lxc6-app
docker compose -f docker-compose.yml -f docker-compose.agents.yml up -d

# lxc-7 — stack monitoring
cd /opt/monitoring
cp .env.example .env && chmod 600 .env       # isi GRAFANA_ADMIN_PASSWORD
cp pve-exporter/pve.yml.example pve-exporter/pve.yml && chmod 600 pve-exporter/pve.yml
sudo chown 101:101 pve-exporter/pve.yml          # user `prometheus` di image pve-exporter
docker compose up -d
```

Versi image di-pin (bukan `latest`): node-exporter `v1.12.1`, cAdvisor `v0.60.6`,
portainer-ce/agent `2.45.3`, prometheus `v3.15.1`, grafana `13.3.0`,
pve-exporter `3.11.0`, blackbox `v0.29.1`.

Admin Portainer dibuat saat start dari `portainer/admin_password` (mode 600, tidak di git),
lewat flag `--admin-password-file`. Tanpa itu Portainer masuk mode *timeout* bila admin tidak
dibuat dalam 5 menit. Ganti password lewat **My account** setelah login. Agent lxc-6
didaftarkan sebagai environment `https://10.0.2.25:9001` (TLS + skip verify, cert agent self-signed).

Grafana dan Portainer **wajib** di balik Cloudflare Access sebelum hostname diarahkan publik.

Dashboard (provisioning, folder **Sellgram**): 1860 Node Exporter Full,
10347 Proxmox via Prometheus, 14282 cAdvisor exporter, 7587 Blackbox Exporter.

Token Proxmox: user `monitor@pve` + role `PVEAuditor` + API token `prom`
(`--privsep 0`). Nilainya **hanya** di `lxc7-monitoring/pve-exporter/pve.yml` di server.

## Status fase

- Fase 1 (repo ini) — selesai: compose lxc-6, initdb, env contoh, script, `.gitignore`.
- Fase 5 — selesai: `lxc7-monitoring/` + `lxc6-app/docker-compose.agents.yml`.
- Fase 6 — selesai: image GHCR + `deploy/` (webhook adnanh, `deploy.sh` dengan flock,
  health check 40 s, rollback), compose lxc-6 tanpa `build:`.
