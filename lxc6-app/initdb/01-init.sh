#!/bin/sh
# initdb untuk stack Sellgram (T3)
#
# Image postgres resmi TIDAK mengenal variabel POSTGRES_EXTRA, jadi database
# evolution_db tidak pernah dibuat oleh compose lama. Script ini dijalankan
# otomatis oleh entrypoint postgres HANYA saat data directory masih kosong.
#
# Password role dibaca dari environment container (dikirim lewat compose):
#   SELLGRAM_APP_PASSWORD, EVOLUTION_DB_PASSWORD
# Gunakan password alfanumerik/hex (mis. `openssl rand -hex 24`) agar aman
# ditempatkan di DATABASE_URL.

set -e

: "${SELLGRAM_APP_PASSWORD:?SELLGRAM_APP_PASSWORD belum diset}"
: "${EVOLUTION_DB_PASSWORD:?EVOLUTION_DB_PASSWORD belum diset}"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
CREATE ROLE sellgram_app LOGIN PASSWORD '${SELLGRAM_APP_PASSWORD}';
CREATE ROLE evolution    LOGIN PASSWORD '${EVOLUTION_DB_PASSWORD}';
CREATE DATABASE db_telegram_bot OWNER sellgram_app;
CREATE DATABASE evolution_db    OWNER evolution;
SQL
