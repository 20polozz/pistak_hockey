# PISTAK backend (Fase 2)

No implementat a la Fase 1 (l'app no el necessita). Contracte ja definit al client:
`lib/sync/remote_sync_api.dart`.

## Proposta

- **PostgreSQL** (decidit): esquema a `docs/DATABASE.md`, RLS per usuari.
- **Capa d'API** (a confirmar a l'inici de la Fase 2): Supabase (Auth + Storage + funcions SQL)
  o API pròpia (Dart Frog / Node) + Postgres + S3.

## Endpoints

| Mètode | Ruta | Descripció |
|--------|------|------------|
| POST | `/auth/*` | registre, login, refresc de token |
| POST | `/sync/push` | `{matches:[…], events:[…]}` → `{accepted:{id: revision}}` (idempotent) |
| GET | `/sync/pull?since=<cursor>` | canvis d'altres dispositius |
| CRUD | `/teams`, `/teams/{id}/players`… | equips (opcional) |
| POST | `/audio` | pujada d'àudio (Fase 4) → transcripció asíncrona |
| GET | `/matches/{id}/report.pdf` | (opcional; el PDF també es pot generar al client) |

Seguretat: HTTPS, contrasenyes amb hash (bcrypt/argon2 o proveïdor d'auth), tokens d'accés curts +
refresc, validació de tots els camps, `owner_user_id` sempre del token (mai del cos de la petició).
