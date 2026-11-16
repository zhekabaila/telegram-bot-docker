#!/usr/bin/env bash
# Backup database stack Sellgram di lxc-6 (data baru, bukan warisan stack lama).
#
# Pakai:  ./scripts/backup-db.sh
# Env opsional:
#   APP_DIR   (default /opt/sellgram/telegram-bot-docker/lxc6-app)
#   DEST      (default /var/backups/sellgram)
#   KEEP_DAYS (default 14)
#
# Contoh cron harian 02:30:
#   30 2 * * * /opt/sellgram/telegram-bot-docker/scripts/backup-db.sh >> /var/log/sellgram-backup.log 2>&1

set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/sellgram/telegram-bot-docker/lxc6-app}"
DEST="${DEST:-/var/backups/sellgram}"
KEEP_DAYS="${KEEP_DAYS:-14}"

[[ -f "$APP_DIR/docker-compose.yml" ]] || { echo "compose tidak ditemukan: $APP_DIR" >&2; exit 1; }

mkdir -p "$DEST"
chmod 700 "$DEST"

ts="$(date +%Y%m%d-%H%M%S)"
out="$DEST/sellgram-$ts.sql.gz"

# pg_dumpall menyertakan role (sellgram_app, evolution) + seluruh database
docker compose -f "$APP_DIR/docker-compose.yml" exec -T postgres \
  pg_dumpall -U postgres --clean --if-exists | gzip -9 > "$out"

gzip -t "$out"
echo "$(date -Is) OK $out $(du -h "$out" | cut -f1)" | tee -a "$DEST/backup.log"

find "$DEST" -maxdepth 1 -name 'sellgram-*.sql.gz' -mtime "+$KEEP_DAYS" -print -delete
