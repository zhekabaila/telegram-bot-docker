#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# /opt/deploy/deploy-status.sh — hook status untuk GitHub Actions (Fase 6)
#
#   deploy-status.sh fe|be
#
# Mencetak isi /opt/deploy/state/<svc>.status:
#   STATE=DEPLOY_RUNNING | DEPLOY_OK | DEPLOY_FAILED
#   SERVICE=, TAG=, OLD_TAG=, PID=, UPDATED_AT=, MESSAGE=
#
# SELALU exit 0 (juga saat deploy gagal/tidak ada status): adnanh membalas
# HTTP 500 bila perintah exit != 0, dan yang menentukan hasil CI adalah isi
# STATE=... (di-grep workflow), bukan kode HTTP.
# ---------------------------------------------------------------------------

set -uo pipefail

SERVICE="${1:-}"
STATE_DIR="${STATE_DIR:-/opt/deploy/state}"

case "$SERVICE" in
  fe|be) ;;
  *) echo "STATE=ERROR"; echo "MESSAGE=argumen tidak valid: '${SERVICE}' (pakai: fe|be)"; exit 0 ;;
esac

STATUS_FILE="$STATE_DIR/${SERVICE}.status"
if [ ! -r "$STATUS_FILE" ]; then
  echo "STATE=UNKNOWN"
  echo "SERVICE=${SERVICE}"
  echo "TAG="
  echo "UPDATED_AT="
  echo "MESSAGE=belum ada deploy yang dijalankan untuk ${SERVICE}"
  exit 0
fi

cat "$STATUS_FILE"
exit 0
