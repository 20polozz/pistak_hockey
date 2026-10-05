# Arquitectura

Vegeu també [ANALYSIS.md](ANALYSIS.md) per al raonament de cada decisió.

## Capes

```
lib/
├── main.dart              Arrencada: obre la BD, deviceId, idioma → ProviderScope
├── app/                   MaterialApp, tema (PistakColors), localització
├── core/                  Clock (System/Fake/Fixed), IdGenerator (UUID v7), format de temps
├── domain/                PUR DART — no importa Flutter ni Drift
│   ├── sport/             SportDefinition, MatchFormat, rollerHockey, Sports (registre)
│   ├── match/             MatchEvent, MatchInfo, MatchState, MatchProjector, EventFactory
│   └── repositories/      MatchRepository (interfície)
├── data/
│   ├── db/                Drift: tables.dart, app_database.dart, connection.dart
│   └── repositories/      DriftMatchRepository, SettingsRepository
├── sync/                  SyncEngine + RemoteSyncApi (Fase 1: OfflineOnlyApi)
├── auth/                  AuthService (Fase 1: GuestAuthService)
├── services/              Wakelock + hàptic (MatchSessionService)
├── l10n/                  app_ca.arb, app_es.arb, app_en.arb (generats per tool/gen_arb.py)
└── ui/
    ├── providers.dart     Injecció de dependències (Riverpod)
    ├── match_controller.dart  Cua d'accions per partit
    ├── screens/           onboarding, home, match, timeline, details, summary, settings
    └── widgets/           EventButton, SyncBadge, TickerBuilder, etiquetes
```

Regla de dependències: `ui → (controller) → domain ← data`. El domini no coneix ningú.

## Flux d'un toc ("GOL LOCAL")

```
EventButton.onTap
  → haptic (immediat)
  → MatchController.goal(home)
      · captura l'instant del toc (Clock.now)
      · cua sèrie per partit (dos tocs ràpids no s'encavalquen)
      · llegeix l'estat PERSISTIT → MatchProjector
      · EventFactory crea MatchEvent (UUID v7, matchTime, period, actionId)
  → DriftMatchRepository.appendEvents  ── 1 transacció SQLite ──
      · INSERT event (seq definitiu, syncStatus = pending)
      · recalcula memòria cau del partit (marcador, estat)
      · COMMIT → és a disc
  → la consulta reactiva de Drift emet → la UI es redibuixa des de la BD
  → (Fase 2) SyncEngine envia l'outbox quan hi hagi compte + xarxa
```

La UI **mai** mostra un estat que no estigui guardat.

## Esdeveniments i projecció

- `MatchEvent` és immutable. Edició = nova `revision`. Esborrat/desfer = `voidedAt` (tombstone).
- `MatchProjector.project(format, events)` és una funció pura que retorna `MatchState`
  (fase, part, rellotge, marcador, faltes per part, targetes, temps morts, incidències).
- És tolerant: una transició invàlida s'ignora i es registra a `anomalies`, mai fa petar el partit.

## Multi-esport

Un esport = una `SportDefinition` (tipus d'esdeveniment, colors de targeta, formats per defecte).
El tipus d'esdeveniment no porta l'equip (`GOAL` + `team`), el rellotge només depèn de `MatchFormat`,
i la sincronització no sap res de l'esport. Afegir futbol sala = nou fitxer `futsal.dart` + botons.

## Gestió d'estat

Riverpod 2: `StreamProvider` sobre consultes reactives de Drift; `matchViewProvider` combina
partit + esdeveniments + projecció. Dependències d'infraestructura (`databaseProvider`,
`deviceIdProvider`) es sobreescriuen a `main.dart` i als tests.

## Wear OS (Fase 5)

```
Wear OS (Kotlin/Compose) → Room (cua local) → Data Layer API (MessageClient)
  → servei Android natiu → MethodChannel → MatchRepository.appendEvents (insertOrIgnore)
```
Els esdeveniments del rellotge porten UUID propi: si arriben dues vegades, el segon és un no-op.
