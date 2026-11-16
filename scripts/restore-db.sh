#!/usr/bin/env bash
# Restore database stack Sellgram di lxc-6 dari hasil scripts/backup-db.sh.
#
# Pakai:  ./scripts/restore-db.sh /var/backups/sellgram/sellgram-YYYYmmdd-HHMMSS.sql.gz
#
# PERINGATAN: menimpa seluruh isi database stack. Butuh konfirmasi manual.

set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/sellgram/telegram-bot-docker/lxc6-app}"
FILE="${1:-}"

[[ -n "$FILE" ]] || { echo "pakai: $0 <file.sql.gz>" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "file tidak ada: $FILE" >&2; exit 1; }
gzip -t "$FILE"

read -r -p "Timpa database stack Sellgram dengan '$FILE'? ketik 'ya': " jawab
[[ "$jawab" == "ya" ]] || { echo "dibatalkan"; exit 1; }

gunzip -c "$FILE" | docker compose -f "$APP_DIR/docker-compose.yml" exec -T postgres \
  psql -v ON_ERROR_STOP=1 -U postgres -d postgres

echo "$(date -Is) restore selesai dari $FILE" | tee -a "${DEST:-/var/backups/sellgram}/restore.log" 2>/dev/null || true
