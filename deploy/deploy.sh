#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# /opt/deploy/deploy.sh — deploy satu service Sellgram dari image GHCR (Fase 6)
#
# Dipanggil webhook adnanh lewat /etc/webhook/hooks.json:
#   deploy.sh fe <sha>   -> frontend, image ghcr.io/tefa-stemanika/sellgram-fe:sha-<sha>
#   deploy.sh be <sha>   -> backend,  image ghcr.io/tefa-stemanika/sellgram-be:sha-<sha>
#   deploy.sh fe         -> tag `latest` (deploy manual tanpa commit)
#
# Kontrak keluaran (dibaca GitHub Actions, lihat .github/workflows/deploy.yml):
#   stdout memuat DEPLOY_OK     -> exit 0
#   stdout memuat DEPLOY_FAILED -> exit 1 (termasuk bila sudah di-rollback)
#
# Alur:
#   1. flock                      -> dua deploy tidak boleh bersamaan
#   2. catat tag aktif (dari .env, cadangan state file)
#   3. tulis tag baru ke .env     -> compose membaca ${BE_TAG}/${FE_TAG}
#   4. docker compose pull <svc>  -> gagal = tag dikembalikan, container lama tetap jalan
#   5. docker compose up -d <svc>
#   6. health check 40 detik
#   7. sehat    : simpan tag baru, cetak DEPLOY_OK
#      tidak    : kembalikan tag lama + up -d ulang, cetak DEPLOY_FAILED
#
# Override untuk pengujian (JANGAN dipakai di produksi):
#   COMPOSE_DIR, HEALTH_URL, HEALTH_TIMEOUT, STATE_DIR, LOCK_FILE, LOG_FILE
# ---------------------------------------------------------------------------

set -uo pipefail

# Docker mencari plugin (compose) lewat $HOME — pastikan tidak kosong/terwarisi
# dari root saat skrip dijalankan lewat sudo tanpa -H.
export HOME="${HOME:-/home/deploy}"
if [ ! -d "$HOME" ] || [ "$HOME" = "/root" ]; then HOME=/home/deploy; export HOME; fi

SERVICE="${1:-}"
COMMIT="${2:-}"

COMPOSE_DIR="${COMPOSE_DIR:-/opt/sellgram/telegram-bot-docker/lxc6-app}"
STATE_DIR="${STATE_DIR:-/opt/deploy/state}"
LOCK_FILE="${LOCK_FILE:-/opt/deploy/deploy.lock}"
LOG_FILE="${LOG_FILE:-/opt/deploy/deploy.log}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-40}"
HEALTH_URL="${HEALTH_URL:-}"

case "$SERVICE" in
  fe) COMPOSE_SVC="frontend"; TAG_VAR="FE_TAG"; DEFAULT_HEALTH="http://127.0.0.1:3000/" ;;
  be) COMPOSE_SVC="backend";  TAG_VAR="BE_TAG"; DEFAULT_HEALTH="http://127.0.0.1:5505/health" ;;
  *) echo "DEPLOY_FAILED argumen tidak valid: '${SERVICE}' (pakai: fe|be [sha])"; exit 1 ;;
esac
HEALTH_URL="${HEALTH_URL:-$DEFAULT_HEALTH}"
STATE_FILE="$STATE_DIR/${SERVICE}.tag"

# --- validasi commit: hanya hex, agar tidak bisa menyuntik nilai ke .env / nama image
if [ -n "$COMMIT" ] && ! printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{7,40}$'; then
  echo "DEPLOY_FAILED commit tidak valid (harus 7-40 karakter hex): ${COMMIT}"
  exit 1
fi
if [ -n "$COMMIT" ]; then NEW_TAG="sha-${COMMIT}"; else NEW_TAG="latest"; fi

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null \
  || { echo "DEPLOY_FAILED tidak bisa membuat direktori state/log"; exit 1; }

# Semua keluaran -> stdout (dibaca webhook / GitHub Actions) + file log.
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== $(date -u '+%Y-%m-%dT%H:%M:%SZ') deploy service=${SERVICE} tag=${NEW_TAG} ====="

# --- 1. flock: satu deploy pada satu waktu ---------------------------------
exec 9>"$LOCK_FILE" || { echo "DEPLOY_FAILED tidak bisa membuka lock file"; exit 1; }
if ! flock -w 300 9; then
  echo "DEPLOY_FAILED deploy lain masih berjalan lebih dari 300 detik"
  exit 1
fi

# --- prasyarat -------------------------------------------------------------
cd "$COMPOSE_DIR" 2>/dev/null \
  || { echo "DEPLOY_FAILED direktori compose tidak ada: $COMPOSE_DIR"; exit 1; }
[ -f docker-compose.yml ] || { echo "DEPLOY_FAILED docker-compose.yml tidak ditemukan di $COMPOSE_DIR"; exit 1; }
[ -f .env ]               || { echo "DEPLOY_FAILED .env tidak ditemukan di $COMPOSE_DIR"; exit 1; }

# --- helper ----------------------------------------------------------------
read_tag() {
  sed -n "s/^${TAG_VAR}=//p" .env 2>/dev/null | tail -n 1
}

write_tag() {  # $1 = nilai tag baru
  local val="$1" tmp
  tmp="$(mktemp "$COMPOSE_DIR/.env.XXXXXX")" || return 1
  if grep -q "^${TAG_VAR}=" .env 2>/dev/null; then
    awk -v k="$TAG_VAR" -v v="$val" \
      'index($0, k"=") == 1 { print k"="v; next } { print }' .env > "$tmp"
  else
    cat .env > "$tmp"
    printf '%s=%s\n' "$TAG_VAR" "$val" >> "$tmp"
  fi
  chmod 600 "$tmp" && mv "$tmp" .env
}

wait_healthy() {  # $1 = jumlah percobaan (1 detik per percobaan)
  local i code
  for i in $(seq 1 "$1"); do
    code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$HEALTH_URL" 2>/dev/null || true)"
    if [ "$code" = "200" ]; then
      if [ "$SERVICE" = "be" ]; then
        # backend: pastikan DB + Redis benar-benar siap, bukan sekadar HTTP 200
        if curl -sS -m 5 "$HEALTH_URL" 2>/dev/null | grep -q '"status":"ok"'; then
          echo "[health] OK setelah ${i}s (${HEALTH_URL})"
          return 0
        fi
      else
        echo "[health] OK setelah ${i}s (${HEALTH_URL})"
        return 0
      fi
    fi
    sleep 1
  done
  echo "[health] GAGAL setelah ${1}s (HTTP terakhir: ${code:-tidak ada respons})"
  return 1
}

container_running() {
  docker compose ps --status running --services 2>/dev/null | grep -qx "$COMPOSE_SVC"
}

rollback() {  # $1 = alasan
  echo "[rollback] alasan: $1"
  if [ -z "${OLD_TAG:-}" ] || [ "$OLD_TAG" = "$NEW_TAG" ]; then
    echo "[rollback] TIDAK BISA: tidak ada tag sebelumnya yang berbeda (deploy pertama?)"
    echo "DEPLOY_FAILED"
    exit 1
  fi
  echo "[rollback] ${NEW_TAG} -> ${OLD_TAG}"
  write_tag "$OLD_TAG" || { echo "DEPLOY_FAILED gagal menulis .env saat rollback"; exit 1; }
  docker compose pull "$COMPOSE_SVC" || echo "[rollback] pull gagal, coba image yang sudah ada di lokal"
  docker compose up -d "$COMPOSE_SVC"       || echo "[rollback] up -d gagal"
  if wait_healthy "$HEALTH_TIMEOUT"; then
    echo "[rollback] service kembali sehat pada tag ${OLD_TAG}"
  else
    echo "[rollback] PERINGATAN: service tetap tidak sehat, perlu tindakan manual"
  fi
  echo "DEPLOY_FAILED"
  exit 1
}

# --- 2. tag aktif sekarang -------------------------------------------------
OLD_TAG="$(read_tag || true)"
if [ -z "${OLD_TAG:-}" ] && [ -f "$STATE_FILE" ]; then
  OLD_TAG="$(cat "$STATE_FILE" 2>/dev/null || true)"
fi
echo "[deploy] tag aktif: ${OLD_TAG:-<kosong>} -> target: ${NEW_TAG}"

# --- 3. tulis tag baru -----------------------------------------------------
write_tag "$NEW_TAG" || { echo "DEPLOY_FAILED gagal menulis ${TAG_VAR} ke .env"; exit 1; }

# --- 4. pull ---------------------------------------------------------------
echo "[deploy] docker compose pull ${COMPOSE_SVC}"
if ! docker compose pull "$COMPOSE_SVC"; then
  rollback "docker compose pull gagal (tag ${NEW_TAG} tidak ada / package privat / network?)"
fi

# --- 5. up -d --------------------------------------------------------------
echo "[deploy] docker compose up -d ${COMPOSE_SVC}"
if ! docker compose up -d "$COMPOSE_SVC"; then
  rollback "docker compose up -d gagal"
fi

# --- 6. health check 40 detik ---------------------------------------------
echo "[deploy] health check maksimal ${HEALTH_TIMEOUT}s -> ${HEALTH_URL}"
if ! wait_healthy "$HEALTH_TIMEOUT"; then
  rollback "health check gagal"
fi
if ! container_running; then
  rollback "container ${COMPOSE_SVC} tidak berstatus running"
fi

# --- 7. sukses -------------------------------------------------------------
printf '%s\n' "$NEW_TAG" > "$STATE_FILE" && chmod 600 "$STATE_FILE"
echo "[deploy] SUKSES: ${SERVICE} (${COMPOSE_SVC}) -> ${NEW_TAG}"
echo "DEPLOY_OK"
exit 0
