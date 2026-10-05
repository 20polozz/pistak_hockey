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
| 1 — Core | Offline-first, partit sense títol, cronòmetre, esdeveniments, temps morts (inici/fi), incidències escrites i **de veu**, cronologia editable, desfer, autosave, recuperació, categories configurables, export CSV/JSON | ✅ Compila (Android + Web), 44 tests en verd |
| 2 — Comptes i núvol | Registre, login, equips, partits programats, backend, sincronització | Preparada (contractes `RemoteSyncApi`, `AuthService`, outbox) |
| 3 — Informes | PDF, estadístiques avançades | Resum + export CSV/JSON fets; falta PDF |
| 4 — Àudio | Speech-to-Text real (backend) | Gravació local + cua de transcripció ja fetes; falta el servei |
| 5 — Wear OS | App Kotlin al rellotge | Dissenyada |
| 6 — Polish | Animacions, icona, splash… | — |

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
