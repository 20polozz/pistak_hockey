# Model de dades

## Local (SQLite via Drift) — esquema v2

Tots els instants són `INTEGER` en mil·lisegons UTC (precisió completa a totes les plataformes).

### `matches`

| Columna | Tipus | Notes |
|---------|-------|-------|
| id | TEXT PK | UUID v7 |
| sport | TEXT | `roller_hockey` |
| status | TEXT | `not_started` · `live` · `finished` (memòria cau derivada) |
| format_json | TEXT | còpia del `MatchFormat` (parts, durades, temps morts) |
| home_name, away_name, category, competition, venue, season, notes | TEXT? | tot opcional (partit sense títol) |
| scheduled_at | INT? | data/hora del partit |
| home_score, away_score | INT | memòria cau derivada dels esdeveniments |
| started_at, ended_at | INT? | memòria cau derivada |
| created_at, updated_at | INT | |
| device_id | TEXT | dispositiu creador |
| owner_user_id | TEXT? | Fase 2 (nul = sense compte) |
| revision | INT | +1 a cada edició descriptiva |
| sync_status | TEXT | `pending` · `synced` |
| deleted_at | INT? | esborrat suau |

### `match_events` (font de veritat + outbox)

| Columna | Tipus | Notes |
|---------|-------|-------|
| id | TEXT PK | UUID v7 — clau d'idempotència |
| match_id | TEXT | |
| type | TEXT | `MATCH_START`, `MATCH_END`, `PERIOD_START`, `PERIOD_END`, `BREAK_START`, `CLOCK_PAUSE`, `CLOCK_RESUME`, `CLOCK_ADJUST`, `GOAL`, `FOUL`, `CARD`, `TIMEOUT`, `TIMEOUT_END`, `INCIDENT` |
| subtype | TEXT? | `CARD`: yellow/blue/red · `INCIDENT`: text/voice/unjustified · `CLOCK_PAUSE`: timeout |
| team | TEXT? | home/away |
| period | INT | 0 = abans de començar |
| match_time_ms | INT | temps acumulat mostrat (43:21) |
| period_time_ms | INT | temps dins la part |
| occurred_at | INT | hora real (el `timestamp` del domini) |
| created_at, updated_at | INT | |
| device_id | TEXT | |
| action_id | TEXT | agrupa els esdeveniments d'un toc (desfer conjunt) |
| seq | INT | ordre local d'inserció |
| revision | INT | |
| voided_at | INT? | tombstone (desfer / eliminar) |
| sync_status | TEXT | `pending` · `synced` |
| metadata_json | TEXT | p. ex. `{"text": "..."}`, `{"periodElapsedMs": 570000}` |

Índexs: `(match_id, seq)`, `(sync_status)`, `(action_id)`.

### `audio_recordings` (v2)
`id`, `match_id`, `event_id`, `mime_type` (audio/wav), `duration_ms`, `size_bytes`, `bytes` (BLOB, nul si
l'usuari l'elimina), `transcript_status` (pending/done/failed), `attempts`, `last_error`, `revision`,
`sync_status`, `deleted_at`, `created_at`, `updated_at`.

### `app_settings`
Clau/valor: `device_id`, `locale`, `onboarding_done`, `last_format`, `categories` (llista JSON de
`MatchFormat` definits per l'usuari).

### Migracions
`schemaVersion` a `app_database.dart`. Cada canvi d'esquema = nova versió + pas a `onUpgrade`.
**Mai** es recrea la BD d'un usuari.

## Entitats futures (local i servidor)

`Team`, `Player`, `Coach`, `Delegate` (Fase 2) · `Report` (Fase 3) · `AudioRecording`,
`Transcription` (Fase 4). `MatchPeriod` no és taula: es deriva dels esdeveniments de període.
`SyncQueue` no és taula: la columna `sync_status` de cada fila fa d'outbox (no pot desincronitzar-se
de la dada que representa).

## Servidor (PostgreSQL) — esborrany Fase 2

```sql
create table matches (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id),
  sport text not null,
  format jsonb not null,
  home_name text, away_name text, category text, competition text,
  venue text, season text, notes text, scheduled_at timestamptz,
  created_at timestamptz not null, updated_at timestamptz not null,
  device_id uuid not null, revision int not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table match_events (
  id uuid primary key,
  match_id uuid not null references matches(id),
  owner_user_id uuid not null,
  type text not null, subtype text, team text check (team in ('home','away')),
  period int not null, match_time_ms int not null, period_time_ms int not null,
  occurred_at timestamptz not null, created_at timestamptz not null, updated_at timestamptz not null,
  device_id uuid not null, action_id uuid not null, seq int not null,
  revision int not null, voided_at timestamptz, metadata jsonb not null default '{}',
  server_seq bigserial                       -- cursor per al pull incremental
);
create index on match_events (match_id);
create index on match_events (owner_user_id, server_seq);

-- Push idempotent: el mateix esdeveniment N vegades = 1 fila
insert into match_events (...) values (...)
on conflict (id) do update set ... , server_seq = nextval(...)
where excluded.revision > match_events.revision;
```

Row Level Security: `owner_user_id = auth.uid()` a totes les taules.
