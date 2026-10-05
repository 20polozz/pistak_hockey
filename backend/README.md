# PISTAK API (backend)

Small Dart server (shelf) with **accounts** and **offline-first sync**. No vendor lock-in:
storage is behind the `Store` interface (SQLite today; a PostgreSQL implementation can be
added without touching the routes or the app).

## Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | – | liveness |
| POST | `/auth/register` | – | `{email, password}` → `{token, userId, email}` (201) |
| POST | `/auth/login` | – | `{email, password}` → `{token, userId, email}`; 10 failures/15 min → 429 |
| POST | `/sync/push` | Bearer | `{matches:[…], events:[…]}` → `{accepted:{matches:{id:rev}, events:{id:rev}}, rejected:{id:reason}}` |
| GET | `/sync/pull?since=N` | Bearer | changes of *this user* after server cursor N → `{matches, events, cursor}` |

## Guarantees

- **Idempotent**: upsert by id; a document is only replaced by a **higher revision**. Re-sending
  after a lost acknowledgement never duplicates anything.
- **Isolation**: every document belongs to the user that first pushed it; other users get
  `forbidden` and never see it in `/sync/pull`.
- **Passwords**: PBKDF2-HMAC-SHA256 (120 000 iterations, random salt), never stored in clear.
- **Tokens**: HS256 JWT, 30-day expiry, secret from the environment only.
- **Durability**: SQLite WAL + `synchronous=FULL`.

## Run locally

```bash
cd backend
dart pub get
dart test                       # 9 API tests
PISTAK_JWT_SECRET=$(openssl rand -hex 32) dart run bin/server.dart
```

Then build the app against it:

```bash
flutter run -d chrome --dart-define=PISTAK_API_URL=http://localhost:8080
```

Without `PISTAK_API_URL` the app hides accounts and works 100 % locally.

## Environment

| Variable | Required | Default |
|---|---|---|
| `PISTAK_JWT_SECRET` | yes (≥ 32 chars) | – |
| `PISTAK_DB` | no | `pistak.sqlite` |
| `PORT` | no | `8080` |
| `PISTAK_ORIGINS` | no | `*` (set your web domain in production) |

## Deploy

`Dockerfile` builds an AOT binary running as a non-root user with the database on the `/data`
volume. Put it behind HTTPS (any reverse proxy / PaaS: Fly.io, Railway, Render, a VPS with
Caddy…). Back up `/data/pistak.sqlite` (e.g. Litestream) or switch to PostgreSQL when needed.
