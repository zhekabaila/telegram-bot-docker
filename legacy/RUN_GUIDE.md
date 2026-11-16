# Panduan Menjalankan Project (Development & Production)

Panduan ini menjelaskan cara menjalankan stack berikut dengan Docker Compose:

- Frontend Next.js
- Backend Node.js + Prisma
- PostgreSQL

## Prasyarat

- Docker dan Docker Compose sudah terpasang
- Folder sibling project tersedia:
  - `../telegram-ai-bot` (backend)
  - `../order-bot-dashboard` (frontend)
- Sudah menyiapkan file environment sesuai mode

## 1. Menjalankan Development Local

### A. Siapkan file env development

Di folder ini, pastikan file berikut ada:

- `.env.backend`
- `.env.frontend`

Jika belum ada, salin dari file example di masing-masing project, lalu isi nilai penting seperti:

- `JWT_SECRET`
- `ENCRYPTION_KEY` (64 karakter hex)
- variabel API/public URL yang dibutuhkan aplikasi

### B. Build dan jalankan service dev

```bash
docker compose up -d --build
```

### C. Akses service dev

- Frontend: `http://localhost:3000`
- Backend API: `http://localhost:5505/api`
- Health check backend: `http://localhost:5505/api/health`
- PostgreSQL host port: `localhost:5284`

### D. Lihat logs dev

```bash
docker compose logs -f frontend
docker compose logs -f backend
docker compose logs -f postgres
```

### E. Stop dev

```bash
docker compose down
```

### F. Reset database dev (opsional)

```bash
docker compose down -v
```

## 2. Menjalankan Production

Mode production menggunakan file compose terpisah agar konfigurasi tidak bercampur dengan development.

### A. Siapkan file env production

Di folder ini, pastikan file berikut ada:

- `.env.backend.prod`
- `.env.frontend.prod`

Pastikan nilai sensitif sudah diganti, minimal:

- `DATABASE_URL` (password production)
- `JWT_SECRET`
- `ENCRYPTION_KEY` (64 karakter hex)
- `PUBLIC_BASE_URL` (harus HTTPS publik)
- `NEXT_PUBLIC_API_URL` (URL backend publik)

### B. Build dan jalankan service production

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

### C. Akses service production

- Frontend: `http://<SERVER_IP>:3000`
- Backend API: `http://<SERVER_IP>:5505/api`

Jika sudah pakai reverse proxy + domain HTTPS, gunakan URL domain Anda.

### D. Lihat logs production

```bash
docker compose -f docker-compose.prod.yml logs -f frontend
docker compose -f docker-compose.prod.yml logs -f backend
docker compose -f docker-compose.prod.yml logs -f postgres
```

### E. Stop production

```bash
docker compose -f docker-compose.prod.yml down
```

## 3. Troubleshooting Singkat

### Rebuild bersih image

Jika ada perubahan dependency atau cache bermasalah:

```bash
docker compose build --no-cache
docker compose -f docker-compose.prod.yml build --no-cache
```

### Cek status container

```bash
docker compose ps
docker compose -f docker-compose.prod.yml ps
```

### Catatan webhook Telegram

Untuk mode webhook, backend membutuhkan URL HTTPS publik:

- Local dev: gunakan tunnel (ngrok/cloudflared) ke `http://localhost:5505`
- Production: gunakan domain HTTPS atau reverse proxy dengan TLS

## 4. Mulai dari Nol (Hapus Semua Data)

Gunakan bagian ini jika Anda ingin benar-benar mulai ulang dari awal, termasuk database.

### A. Matikan dan hapus semua resource Compose

Perintah ini akan menghapus container, network, dan volume yang dipakai stack:

```bash
docker compose down -v --remove-orphans
docker compose -f docker-compose.prod.yml down -v --remove-orphans
```

### B. (Opsional) Hapus image yang dipakai project

Jika ingin build ulang benar-benar bersih dari image lama:

```bash
docker compose down --rmi all
docker compose -f docker-compose.prod.yml down --rmi all
```

### C. (Opsional) Hapus volume yang tersisa secara manual

Kadang ada volume lama yang masih tertinggal. Cek dan hapus manual:

```bash
docker volume ls | grep telegram
docker volume rm <NAMA_VOLUME>
```

Contoh volume yang biasanya muncul:

- `telegram-bot-docker_postgres_data`
- `telegram-bot-docker_postgres_data_prod`
- `telegram-bot-docker_backend_node_modules`
- `telegram-bot-docker_frontend_node_modules`

### D. Jalankan ulang dari nol

Setelah cleanup selesai, jalankan kembali:

```bash
docker compose up -d --build
```

Atau untuk mode production:

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

## 5. Reload Docker Saat File .env atau Kode Berubah

Bagian ini khusus untuk reload service `backend` atau `frontend` tanpa harus mematikan semua service.

### A. Development: jika ubah kode

Pada mode development, source code di-mount sebagai volume, jadi biasanya perubahan kode otomatis terbaca oleh `npm run dev`.

Jika perubahan tidak terbaca, restart service yang dibutuhkan:

```bash
docker compose restart backend
docker compose restart frontend
```

### B. Development: jika ubah file .env

Perubahan `.env.backend` atau `.env.frontend` butuh recreate container agar env baru ter-load:

```bash
docker compose up -d --force-recreate backend
docker compose up -d --force-recreate frontend
```

Jika ada perubahan dependency atau Dockerfile, gunakan build ulang service terkait:

```bash
docker compose up -d --build backend
docker compose up -d --build frontend
```

### C. Production: jika ubah kode

Untuk production, perubahan kode membutuhkan rebuild image lalu recreate service:

```bash
docker compose -f docker-compose.prod.yml up -d --build backend
docker compose -f docker-compose.prod.yml up -d --build frontend
```

### D. Production: jika ubah file .env

Perubahan `.env.backend.prod` atau `.env.frontend.prod` minimal perlu recreate container:

```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate backend
docker compose -f docker-compose.prod.yml up -d --force-recreate frontend
```

Jika sekaligus ada perubahan kode/dependency, gunakan opsi `--build` juga.
