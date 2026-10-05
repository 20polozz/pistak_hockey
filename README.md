# PISTAK

**Live match tracking for roller hockey** — *PISTAK, Matchday made simple.*

PISTAK registra en temps real tot el que passa en un partit (gols, faltes, targetes, temps morts,
pauses, descans, incidències…) amb una cronologia precisa. Primera especialització: **hoquei patins**.
Arquitectura preparada per a altres esports de pista.

> **Regla número 1: PISTAK no pot perdre cap esdeveniment d'un partit.**
> Funciona completament sense internet i sense compte.

## Estat

| Fase | Contingut | Estat |
|------|-----------|-------|
| 1 — Core | Offline-first, partit sense títol, cronòmetre, esdeveniments, temps morts (inici/fi), incidències escrites i **de veu**, cronologia editable, desfer, autosave, recuperació, categories configurables, export CSV/JSON | ✅ Android + Web verificats (emulador i navegador), 44 tests en verd |
| 2 — Comptes i núvol | Registre/login, equips i plantilles, partits programats, backend propi (Dart), sincronització push/pull multi-dispositiu, detecció de connexió | ✅ Fet i provat E2E amb servidor real (falta desplegar-lo a internet) |
| 3 — Informes | PDF, CSV, JSON, compartir/descarregar | ✅ Fet |
| 4 — Àudio | Speech-to-Text real (backend) | Fet: `POST /transcribe` (proveïdor compatible OpenAI/Whisper, clau al servidor); s'activa amb `PISTAK_STT_API_KEY` |
| 5 — Wear OS | App Kotlin al rellotge + pont al mòbil (idempotent) | Fet (compila, tests; pendent provar en rellotge real) |
| 6 — Polish | Icona, splash, branding | ✅ Icona/splash fets; resta d'animacions/accessibilitat en curs |

## Plataformes

- **Android** (Flutter)
- **Web / PWA** (Flutter) — Windows, macOS, Linux, Android, iPhone, iPad
- **Wear OS** (Kotlin, fase 5)

## Inici ràpid

```bash
flutter pub get
dart run build_runner build
flutter test
flutter run -d chrome     # o un dispositiu Android
```

Detalls (incloent els fitxers WASM de la base de dades web): **[docs/SETUP.md](docs/SETUP.md)**.

## Documentació

| Document | Contingut |
|----------|-----------|
| [docs/ANALYSIS.md](docs/ANALYSIS.md) | Anàlisi inicial: contradiccions, requisits que falten, decisions |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Capes, carpetes, flux d'un esdeveniment |
| [docs/DATABASE.md](docs/DATABASE.md) | Model de dades local i de servidor |
| [docs/OFFLINE_SYNC.md](docs/OFFLINE_SYNC.md) | Offline-first, cronòmetre, sincronització, riscos |
| [docs/SETUP.md](docs/SETUP.md) | Instal·lació, desenvolupament, tests |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Build Android/Web, desplegament, variables d'entorn |

## Llicència

Propietari. Tots els drets reservats.

## Backend i comptes

El servidor és a [`backend/`](backend/README.md) (Dart + shelf, SQLite, Docker). L'app només mostra
els comptes si es compila amb l'URL del servidor:

```bash
flutter build apk --dart-define=PISTAK_API_URL=https://api.el-teu-domini.cat
flutter build web --dart-define=PISTAK_API_URL=https://api.el-teu-domini.cat
```

Sense aquesta variable PISTAK funciona 100% local, com sempre.
