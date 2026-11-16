# CI/CD Docker — webhook deploy di lxc-6 (Fase 6)

Alur lengkap:

```
push ke main (sellgram-fe / sellgram-be)
   -> GitHub Actions: docker build --platform linux/amd64
   -> push ghcr.io/tefa-stemanika/sellgram-{fe,be}:sha-<commit> + :latest
   -> POST https://deploy-{fe,be}.coreapps.web.id/hooks/deploy-{fe,be}
        header X-Deploy-Token: <DEPLOY_TOKEN>
        body   {"service":"fe|be","sha":"<40 char sha>"}
   -> webhook (adnanh) di lxc-6, port 9000
   -> /opt/deploy/deploy.sh fe|be <sha>
        flock -> tulis tag ke .env -> compose pull -> up -d
        -> health check 40 s -> sehat? DEPLOY_OK : rollback + DEPLOY_FAILED
   -> Actions hijau hanya jika respons memuat DEPLOY_OK
```

Build **tidak** lagi dilakukan di lxc-6 (RAM host 3,8 GiB, T10).

## Isi direktori ini

| File | Tujuan di server |
|---|---|
| `deploy.sh` | `/opt/deploy/deploy.sh` (mode 750, milik `deploy`) |
| `hooks.json.example` | dasar `/etc/webhook/hooks.json` — `__DEPLOY_TOKEN__` diganti token asli |
| `webhook.service` | `/etc/systemd/system/webhook.service` |

## Pemasangan (sudah dijalankan pada Fase 6)

```bash
# 1. binary webhook (adnanh) — versi di-pin
curl -fsSL -o /tmp/webhook.tar.gz \
  https://github.com/adnanh/webhook/releases/download/2.8.2/webhook-linux-amd64.tar.gz
tar -xzf /tmp/webhook.tar.gz -C /tmp
install -m 0755 /tmp/webhook-linux-amd64/webhook /usr/local/bin/webhook

# 2. direktori
install -d -o deploy -g deploy -m 755 /opt/deploy /opt/deploy/state /etc/webhook

# 3. hooks.json (token diambil dari file, TIDAK dicetak)
install -m 0644 deploy/hooks.json.example /etc/webhook/hooks.json
sed -i "s|__DEPLOY_TOKEN__|$(cat /tmp/deploy-token.txt)|g" /etc/webhook/hooks.json
chmod 600 /etc/webhook/hooks.json && rm -f /tmp/deploy-token.txt

# 4. skrip + unit
install -o deploy -g deploy -m 0750 deploy/deploy.sh /opt/deploy/deploy.sh
install -m 0644 deploy/webhook.service /etc/systemd/system/webhook.service
systemctl daemon-reload && systemctl enable --now webhook
```

## deploy.sh

```
deploy.sh <fe|be> [sha]      # sha = commit penuh -> tag sha-<sha>; tanpa sha -> latest
```

| Langkah | Perilaku bila gagal |
|---|---|
| `flock -w 300` | `DEPLOY_FAILED` (deploy lain sedang jalan) |
| `docker compose pull <svc>` | tag di `.env` dikembalikan, container lama **tidak** disentuh |
| `docker compose up -d <svc>` | rollback ke tag sebelumnya |
| health check 40 s | rollback ke tag sebelumnya + `up -d` ulang |
| container tidak `running` | rollback |
| semua lulus | tulis `state/<svc>.tag`, cetak `DEPLOY_OK` |

Health check:

| Service | URL | Syarat |
|---|---|---|
| `fe` | `http://127.0.0.1:3000/` | HTTP 200 |
| `be` | `http://127.0.0.1:5505/health` | HTTP 200 **dan** body memuat `"status":"ok"` (DB + Redis siap) |

Tag aktif disimpan di dua tempat: `.env` (`FE_TAG`/`BE_TAG`, dibaca compose) dan
`/opt/deploy/state/{fe,be}.tag` (audit). Log: `/opt/deploy/deploy.log`.

Deploy manual (tanpa GitHub) — jalankan sebagai `deploy`:

```bash
sudo -u deploy /opt/deploy/deploy.sh fe            # pakai tag `latest`
sudo -u deploy /opt/deploy/deploy.sh be <sha-40>   # pakai tag sha-<sha>
```

## Keamanan

- Token hanya ada di `/etc/webhook/hooks.json` (600) dan GitHub secret `DEPLOY_TOKEN`.
- `hooks.json` **tidak** di repo; yang di-commit hanya `hooks.json.example`.
- Webhook berjalan sebagai user `deploy` (bukan root); `deploy` ada di grup `docker`.
- Endpoint webhook terbuka lewat Cloudflare Tunnel; token wajib cocok, selain itu
  adnanh membalas **403** dan skrip tidak dijalankan.
