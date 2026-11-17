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
#
# Anti-duplikat: lock per service (state/<svc>.lock) dipegang oleh proses anak
# (fd diwarisi, lock flock ikut hidup setelah skrip ini keluar), jadi dua
# permintaan untuk service yang sama tidak menumpuk.
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
SVC_LOCK="${SVC_LOCK:-$STATE_DIR/${SERVICE}.lock}"

# --- anti-duplikat: lock per service ---------------------------------------
exec 8>"$SVC_LOCK" || { echo "DEPLOY_FAILED tidak bisa membuka lock $SVC_LOCK"; exit 1; }
if ! flock -n 8; then
  cur_tag="$(sed -n 's/^TAG=//p' "$STATUS_FILE" 2>/dev/null | tail -n 1)"
  echo "DEPLOY_STARTED service=${SERVICE} tag=${cur_tag:-$TAG} already-running"
  exit 0
fi

# Status awal ditulis SEBELUM proses anak dijalankan, supaya (a) CI tidak
# pernah membaca status lama setelah DEPLOY_STARTED, dan (b) tulisan status
# dari deploy.sh selalu datang sesudahnya (tidak tertimpa RUNNING).
write_running() {
  local tmp="$STATUS_FILE.tmp"
  {
    printf 'STATE=DEPLOY_RUNNING\n'
    printf 'SERVICE=%s\n' "$SERVICE"
    printf 'TAG=%s\n' "$TAG"
    printf 'OLD_TAG=\n'
    printf 'PID=\n'
    printf 'UPDATED_AT=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'MESSAGE=memulai %s\n' "$TAG"
  } > "$tmp" 2>/dev/null && mv "$tmp" "$STATUS_FILE" 2>/dev/null
}

[ -x "$DEPLOY_SH" ] || { echo "DEPLOY_FAILED $DEPLOY_SH tidak bisa dieksekusi"; exit 1; }
write_running

# setsid: proses + sesi baru, lepas dari process group webhook.
# fd 8 sengaja diwariskan agar lock per service tetap dipegang proses anak.
# stdout/stderr -> /dev/null karena deploy.sh menulis sendiri ke deploy.log (tee).
setsid nohup "$DEPLOY_SH" "$SERVICE" "$COMMIT" >/dev/null 2>&1 </dev/null 8>&8 &
PID=$!

echo "DEPLOY_STARTED service=${SERVICE} tag=${TAG} pid=${PID}"
exit 0
