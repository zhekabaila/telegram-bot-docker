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
   -> /opt/deploy/deploy-start.sh fe|be <sha>     (balas DEPLOY_STARTED < 1 s)
        setsid -> /opt/deploy/deploy.sh fe|be <sha>  (jalan di background)
          flock -> tulis tag ke .env -> compose pull -> up -d
          -> health check 40 s -> sehat? DEPLOY_OK : rollback + DEPLOY_FAILED
   -> Actions polling POST /hooks/status-{fe,be} tiap 5 s (maks 8 menit)
        -> hijau hanya bila STATE=DEPLOY_OK dan TAG=sha-<commit> yang diminta
```

Build **tidak** lagi dilakukan di lxc-6 (RAM host 3,8 GiB, T10).

### Kenapa deploy dipisah (async)

`docker compose pull` untuk image backend 509 MB berjalan >60 s tanpa output.
Cloudflare memutus request yang menggantung tanpa output pada detik ~62
(`curl: (56) Recv failure`), sehingga job CI merah padahal deploy di server
berhasil. Karena itu hook deploy hanya **memicu** lalu langsung balas
`DEPLOY_STARTED`; hasil akhirnya dibaca lewat hook status.

## Isi direktori ini

| File | Tujuan di server |
|---|---|
| `deploy.sh` | `/opt/deploy/deploy.sh` (mode 750, milik `deploy`) — logika deploy + rollback |
| `deploy-start.sh` | `/opt/deploy/deploy-start.sh` — penerima hook deploy, menjalankan `deploy.sh` di background + lock per service (`state/<svc>.lock`, duplikat dibalas `already-running`) |
| `deploy-status.sh` | `/opt/deploy/deploy-status.sh` — penerima hook status, mencetak isi `state/<svc>.status` |
| `hooks.json.example` | dasar `/etc/webhook/hooks.json` — `__DEPLOY_TOKEN__` diganti token asli (4 hook) |
| `webhook.service` | `/etc/systemd/system/webhook.service` |

## Pemasangan (sudah dijalankan pada Fase 6)

```bash
# 1. binary webhook (adnanh) — versi di-pin
curl -fsSL -o /tmp/webhook.tar.gz \
  https://github.com/adnanh/webhook/releases/download/2.8.3/webhook-linux-amd64.tar.gz
tar -xzf /tmp/webhook.tar.gz -C /tmp
install -m 0755 /tmp/webhook-linux-amd64/webhook /usr/local/bin/webhook

# 2. direktori
install -d -o deploy -g deploy -m 755 /opt/deploy /opt/deploy/state /etc/webhook

# 3. hooks.json (token diambil dari file, TIDAK dicetak)
install -m 0644 deploy/hooks.json.example /etc/webhook/hooks.json
sed -i "s|__DEPLOY_TOKEN__|$(cat /tmp/deploy-token.txt)|g" /etc/webhook/hooks.json
chmod 600 /etc/webhook/hooks.json && rm -f /tmp/deploy-token.txt
# WAJIB: webhook berjalan sebagai `deploy`, jadi file harus bisa dibaca `deploy`
# (mode 600 root:root membuat webhook memuat 0 hook -> "Hook not found." pada semua request)
chown deploy:deploy /etc/webhook/hooks.json

# 4. skrip + unit
install -o deploy -g deploy -m 0750 deploy/deploy.sh        /opt/deploy/deploy.sh
install -o deploy -g deploy -m 0750 deploy/deploy-start.sh  /opt/deploy/deploy-start.sh
install -o deploy -g deploy -m 0750 deploy/deploy-status.sh /opt/deploy/deploy-status.sh
install -m 0644 deploy/webhook.service /etc/systemd/system/webhook.service
systemctl daemon-reload && systemctl enable --now webhook
```

Verifikasi cepat setelah restart:

```bash
journalctl -u webhook -n 10 -o cat | grep -E "found [0-9]+ hook|loaded:"
# tanpa token: harus balas "Hook rules were not satisfied." (bukan "Hook not found.")
curl -sS -X POST http://127.0.0.1:9000/hooks/status-fe -d '{"service":"fe"}'
# dengan token benar: isi state/<svc>.status
TOK=$(python3 -c 'import json;print(json.load(open("/etc/webhook/hooks.json"))[0]["trigger-rule"]["and"][0]["match"]["value"])')
curl -sS -X POST http://127.0.0.1:9000/hooks/status-fe \
  -H "X-Deploy-Token: $TOK" -H "Content-Type: application/json" -d '{"service":"fe"}'
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
| semua lulus | tulis `state/<svc>.tag`, `state/<svc>.status` = `DEPLOY_OK`, cetak `DEPLOY_OK` |

Health check:

| Service | URL | Syarat |
|---|---|---|
| `fe` | `http://127.0.0.1:3000/` | HTTP 200 |
| `be` | `http://127.0.0.1:5505/health` | HTTP 200 **dan** body memuat `"status":"ok"` (DB + Redis siap) |

Tag aktif disimpan di dua tempat: `.env` (`FE_TAG`/`BE_TAG`, dibaca compose) dan
`/opt/deploy/state/{fe,be}.tag` (audit). Log: `/opt/deploy/deploy.log`.

Status deploy (`/opt/deploy/state/<svc>.status`) berisi
`STATE=DEPLOY_RUNNING|DEPLOY_OK|DEPLOY_FAILED`, `TAG=`, `OLD_TAG=`, `PID=`,
`UPDATED_AT=`, `MESSAGE=`. Bila skrip berhenti tak terduga, `trap EXIT` menulis
`DEPLOY_FAILED` supaya CI tidak menunggu sampai timeout.

`deploy-start.sh` menolak deploy ganda untuk service yang sama lewat lock
`/opt/deploy/state/<svc>.lock` (dibalas `DEPLOY_STARTED ... already-running`),
sedangkan `flock` di `deploy.sh` tetap menyerialkan fe vs be.

Deploy manual (tanpa GitHub) — jalankan sebagai `deploy`:

```bash
sudo -u deploy /opt/deploy/deploy.sh fe            # pakai tag `latest`
sudo -u deploy /opt/deploy/deploy.sh be <sha-40>   # pakai tag sha-<sha>
```

Memantau deploy yang dipicu webhook:

```bash
tail -f /opt/deploy/deploy.log
cat /opt/deploy/state/fe.status
```

## Keamanan

- Token hanya ada di `/etc/webhook/hooks.json` (600, `deploy:deploy`) dan GitHub secret `DEPLOY_TOKEN`.
- `hooks.json` **tidak** di repo; yang di-commit hanya `hooks.json.example`.
- Webhook berjalan sebagai user `deploy` (bukan root); `deploy` ada di grup `docker`.
- `webhook.service` memakai `ExecStartPre=/usr/bin/test -r /etc/webhook/hooks.json`
  agar service gagal keras (bukan "active dengan 0 hook") bila file tidak terbaca.
- Endpoint webhook terbuka lewat Cloudflare Tunnel. Token salah / hook tidak cocok
  dibalas adnanh dengan **HTTP 200 + `Hook rules were not satisfied.`** (bukan 403),
  dan skrip tidak dijalankan.
