# Telegram Stack Production (FE + BE + DB)

File production terpisah agar tidak bentrok dengan setup development.

## File yang dipakai
- docker-compose.prod.yml
- Dockerfile.backend.prod
- Dockerfile.frontend.prod
- .env.backend.prod
- .env.frontend.prod

## Langkah deploy di VPS
1. Edit .env.backend.prod
   - Ganti DATABASE_URL password
   - Ganti JWT_SECRET
   - Ganti ENCRYPTION_KEY (64 hex)
   - Ganti PUBLIC_BASE_URL (HTTPS publik backend)
2. Edit .env.frontend.prod
   - Ganti NEXT_PUBLIC_API_URL (HTTPS backend publik)
3. Jalankan:
   docker compose -f docker-compose.prod.yml up -d --build

## Cek service
- Frontend: http://YOUR_SERVER_IP:3000
- Backend API: http://YOUR_SERVER_IP:5505/api

## Logs
- docker compose -f docker-compose.prod.yml logs -f frontend
- docker compose -f docker-compose.prod.yml logs -f backend
- docker compose -f docker-compose.prod.yml logs -f postgres

## Stop
- docker compose -f docker-compose.prod.yml down

## Catatan penting
- Untuk Telegram webhook, PUBLIC_BASE_URL wajib HTTPS publik.
- Jika belum punya domain, gunakan tunnel HTTPS dari server ke backend port 5505.
- Untuk hardening production, pasang reverse proxy (Nginx/Caddy) dan batasi akses port DB.
