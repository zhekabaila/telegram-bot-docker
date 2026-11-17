#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# /opt/deploy/deploy-start.sh — penerima hook webhook (async), Fase 6
#
# Dipanggil /etc/webhook/hooks.json (deploy-fe / deploy-be):
#   deploy-start.sh fe <sha>
#
# Kenapa wrapper terpisah: `docker compose pull` untuk image 509 MB berjalan
# >60 s tanpa output, dan Cloudflare memutus request tanpa output pada detik
# ~62 (curl exit 56). Deploy tidak boleh bergantung pada satu request panjang.
#
# Kontrak: langsung balas satu baris `DEPLOY_STARTED ...` (<1 s), lalu
# deploy.sh berjalan di sesi terpisah (setsid) sehingga tetap hidup walau
# proses webhook selesai/restart. Progres dibaca lewat deploy-status.sh.
# ---------------------------------------------------------------------------

set -uo pipefail

# Docker mencari plugin (compose) lewat $HOME; jangan mewarisi HOME=/root.
export HOME="${HOME:-/home/deploy}"
if [ ! -d "$HOME" ] || [ "$HOME" = "/root" ]; then HOME=/home/deploy; export HOME; fi

SERVICE="${1:-}"
COMMIT="${2:-}"
DEPLOY_SH="${DEPLOY_SH:-/opt/deploy/deploy.sh}"
STATE_DIR="${STATE_DIR:-/opt/deploy/state}"

case "$SERVICE" in
  fe|be) ;;
  *) echo "DEPLOY_FAILED argumen tidak valid: '${SERVICE}' (pakai: fe|be [sha])"; exit 1 ;;
esac

# Validasi sama seperti deploy.sh: cegah nilai aneh masuk ke .env / nama image.
if [ -n "$COMMIT" ] && ! printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{7,40}$'; then
  echo "DEPLOY_FAILED commit tidak valid (harus 7-40 karakter hex)"
  exit 1
fi
if [ -n "$COMMIT" ]; then TAG="sha-${COMMIT}"; else TAG="latest"; fi

mkdir -p "$STATE_DIR" 2>/dev/null || { echo "DEPLOY_FAILED tidak bisa membuat $STATE_DIR"; exit 1; }
STATUS_FILE="$STATE_DIR/${SERVICE}.status"

# Idempoten: bila deploy service ini masih berjalan, jangan tumpuk (flock di
# deploy.sh akan membuat yang kedua menunggu 300 s lalu gagal).
if [ -r "$STATUS_FILE" ]; then
  cur_state="$(sed -n 's/^STATE=//p' "$STATUS_FILE" | tail -n 1)"
  cur_pid="$(sed -n 's/^PID=//p' "$STATUS_FILE" | tail -n 1)"
  cur_tag="$(sed -n 's/^TAG=//p' "$STATUS_FILE" | tail -n 1)"
  if [ "$cur_state" = "DEPLOY_RUNNING" ] && [ -n "$cur_pid" ] && kill -0 "$cur_pid" 2>/dev/null; then
    echo "DEPLOY_STARTED service=${SERVICE} tag=${cur_tag:-$TAG} pid=${cur_pid} already-running"
    exit 0
  fi
fi

# setsid: proses baru + sesi baru, lepas dari process group webhook.
# stdout/stderr -> /dev/null karena deploy.sh menulis sendiri ke deploy.log (tee).
setsid nohup "$DEPLOY_SH" "$SERVICE" "$COMMIT" >/dev/null 2>&1 </dev/null &
PID=$!

echo "DEPLOY_STARTED service=${SERVICE} tag=${TAG} pid=${PID}"
exit 0
