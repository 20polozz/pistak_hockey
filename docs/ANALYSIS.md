# PISTAK — Anàlisi tècnica inicial

> Document de decisions previ a la implementació. Respon als 18 punts de la secció 62 de l'especificació.
> Les decisions marcades amb **[DECISIÓ]** són les que s'han aplicat a la Fase 1.

---

## 1. Lectura global

L'especificació és coherent i té una prioritat clara: **no perdre cap esdeveniment, offline-first**.
Tot el disseny que segueix es deriva d'aquesta regla: el dispositiu és la font de veritat durant el partit,
el núvol és una còpia sincronitzada, i cap acció de registre depèn de la xarxa.

## 2. Contradiccions i tensions detectades

| # | Tensió | Resolució proposada |
|---|--------|---------------------|
| C1 | Esdeveniment `GOAL_HOME` / `GOAL_AWAY` (sec. 8) vs. arquitectura multi-esport (sec. 2). Codificar l'equip dins del tipus multiplica els tipus per cada esport. | **[DECISIÓ]** `type = GOAL` + columna `team = home/away`. A l'exportació/JSON es pot derivar `GOAL_HOME` si cal. |
| C2 | Targetes "d'un sol toc" (sec. 14, 23) però l'informe vol targetes per equip (sec. 26). | **[DECISIÓ]** El toc crea l'esdeveniment immediatament **sense equip**. Apareix una barra no bloquejant "Assigna equip: LOCAL / VISITANT" i també es pot assignar més tard a la cronologia. Mai es perd el registre per no haver triat equip. |
| C3 | "Sense confirmacions" (sec. 24) vs. accions destructives com finalitzar la part o el partit. | **[DECISIÓ]** Gols, faltes, targetes, temps morts, incidències i pausa/represa: **sense confirmació** + DESFER. Final de part i final de partit: **una confirmació** (un error aquí altera el cronòmetre i l'estat del partit). També es poden desfer. |
| C4 | La cronologia d'exemple (sec. 25) mostra temps acumulat (2a part 43:21, final 50:00), però una part real pot durar més del nominal al rellotge del dispositiu. | **[DECISIÓ]** Temps mostrat = `durada nominal × parts anteriors + temps transcorregut a la part actual`. La 2a part sempre comença a 25:00 (en 2×25). Es guarda també `periodTimeMs`. |
| C5 | El cronòmetre de PISTAK no és el marcador oficial: en hoquei patins es para el temps a moltes aturades (segons categoria). | **[DECISIÓ]** Pausa/represa manual + esdeveniment `CLOCK_ADJUST` per corregir el temps de la part i alinear-lo amb el marcador oficial. |
| C6 | "Temps mort pot afectar el cronòmetre" (sec. 15) sense dir com. | **[DECISIÓ]** Configurable per format (`stopClockOnTimeout`). Si és cert i el rellotge corre, el temps mort genera `TIMEOUT` + `CLOCK_PAUSE` (mateix `actionId`, es desfan junts). |
| C7 | "Descans" com a botó independent (sec. 9) vs. seqüència Final 1a part → Descans → Inici 2a part (sec. 16). | **[DECISIÓ]** El botó "FINAL 1a PART" registra `PERIOD_END` + `BREAK_START`; "INICIAR 2a PART" registra `PERIOD_START`. Les tres línies apareixen a la cronologia. |
| C8 | PWA a iPhone + "no perdre dades": Safari pot esborrar l'emmagatzematge de webs no instal·lades després de dies sense ús. | Demanem `navigator.storage.persist()`, recomanem instal·lar-la a la pantalla d'inici, i la sincronització al núvol (Fase 2) és la xarxa de seguretat definitiva. Documentat com a risc. |
| C9 | Wear OS ↔ Web: el rellotge només pot parlar amb l'app Android (Data Layer API), no amb la web. | Wear OS només funcionarà amb l'app Android. |

## 3. Requisits que falten (o a concretar)

1. **Pròrroga i penals** (eliminatòries): el model de períodes ja admet períodes extra; caldrà definir la UI (fase posterior).
2. **Faltes acumulades per part**: en hoquei patins compten per a la falta directa. **[DECISIÓ]** Es mostren comptadors de faltes per equip i part. El llindar concret es deixarà configurable, no codificat.
3. **Exclusions temporals (targeta blava = 2 min)**: no demanat; el model ho admet amb `metadata`. Futur: comptador d'inferioritat.
4. **Correcció del cronòmetre** (vegeu C5) — **[DECISIÓ]** inclòs a la Fase 1.
5. **Pantalla sempre encesa** durant el partit — **[DECISIÓ]** `wakelock_plus` a la pantalla de partit.
6. **Compte creat després d'haver jugat partits sense compte**: cal "reclamar" els partits locals → previst a la Fase 2 (`ownerUserId` nul fins aleshores).
7. **Diversos dispositius registrant el mateix partit** (dues persones a la grada): el model ho suporta (UUID + `deviceId`), però la fusió de rellotges no està definida. Fase posterior.
8. **Retenció i esborrat de dades/àudios** (GDPR): política de retenció a definir abans de la Fase 4.
9. **Format de temps**: compte endavant (com molts marcadors) o compte enrere? L'especificació mostra compte endavant → **[DECISIÓ]** endavant; compte enrere com a opció de visualització futura.
10. **Rellotge del sistema modificat** durant el partit (canvi d'hora manual): vegeu secció 10.

## 4. Arquitectura proposada

```
┌───────────────────────────── Flutter app (Android + Web/PWA) ─────────────────────────────┐
│  UI (screens/widgets)  ──►  Controllers (Riverpod)  ──►  Domain (pur Dart, sense Flutter) │
│                                                     │      • MatchEvent / MatchInfo         │
│                                                     │      • SportDefinition / MatchFormat  │
│                                                     │      • MatchProjector (rellotge+marc.)│
│                                                     │      • EventFactory (comandes)        │
│                                                     ▼                                       │
│                                    Repositories (interfície al domini)                     │
│                                                     │                                       │
│                         Data: Drift (SQLite) ◄──────┴────► SyncEngine ──► RemoteSyncApi     │
└──────────────────────────────────────────────────────────────────────────────┬────────────┘
                                                                               │ HTTPS (Fase 2)
                                                         API + PostgreSQL + Object Storage
Wear OS (Kotlin, Fase 5) ── Data Layer API ──► app Android ──► mateix repositori local
```

Principis:
- **Event sourcing**: el partit és una llista d'esdeveniments immutables (append-only). Marcador, rellotge
  i estadístiques es **projecten** a partir dels esdeveniments. Les edicions incrementen `revision`; els
  esborrats són *tombstones* (`voidedAt`), mai `DELETE`.
- **El domini no depèn de Flutter ni de la base de dades** → testable amb tests unitaris purs i reutilitzable.
- **Esport com a configuració**: `SportDefinition` (tipus d'esdeveniment disponibles, colors de targeta,
  formats per defecte) + `MatchFormat` (parts, durades, temps morts…). Afegir futbol sala = nova definició.

## 5. Tecnologies i per què

| Àrea | Tria | Alternatives considerades | Motiu |
|------|------|---------------------------|-------|
| App | **Flutter + Dart** | — | Requisit; un sol codi per Android i Web. |
| Estat | **Riverpod 2** | Bloc, Provider | Simple, testable, sense codegen obligatori, bona injecció de dependències. |
| BD local | **Drift (SQLite)** | Isar, Hive, sembast, sqflite | Vegeu punt 13. |
| IDs | **UUID v7** (`uuid`) | UUID v4 | Únics globalment i ordenables per temps (índexs més eficients al servidor). |
| i18n | **gen-l10n + ARB** (oficial Flutter) | easy_localization | Eina oficial, tipada, sense dependències externes. |
| Pantalla encesa | `wakelock_plus` | — | Android + Web. |
| Wear OS | **Kotlin + Compose for Wear OS** | Flutter a Wear | La integració nativa (Data Layer, Tiles, ambient) és clarament millor. |
| Servidor | **PostgreSQL** + API (vegeu punt 14) | Firebase/Firestore | Model relacional, constraints d'unicitat per idempotència. |

## 6. Estructura de carpetes

```
pistak/
├── lib/
│   ├── main.dart                 # arrencada, injecció de dependències
│   ├── app/                      # MaterialApp, tema, navegació
│   ├── core/                     # Clock, IDs, format de temps
│   ├── domain/
│   │   ├── sport/                # SportDefinition, MatchFormat, hoquei patins
│   │   ├── match/                # MatchEvent, MatchInfo, MatchState, projector, EventFactory
│   │   └── repositories/         # interfícies
│   ├── data/
│   │   ├── db/                   # Drift: taules, base de dades, connexió
│   │   └── repositories/         # implementacions Drift
│   ├── sync/                     # SyncEngine + RemoteSyncApi (Fase 2: implementació HTTP)
│   ├── auth/                     # AuthService (Fase 1: convidat)
│   ├── services/                 # wakelock, hàptic
│   ├── l10n/                     # app_ca.arb, app_es.arb, app_en.arb
│   └── ui/                       # providers, screens, widgets
├── test/                         # domini, dades, sync
├── web/                          # index.html, manifest.json (PWA), sqlite3.wasm, drift_worker.js
├── android/                      # generat per `flutter create`
├── backend/                      # Fase 2
├── wear_os/                      # Fase 5 (Kotlin)
└── docs/
```

## 7. Model de dades

Vegeu [DATABASE.md](DATABASE.md). Resum de l'esdeveniment:

```json
{
  "id": "0192f8c4-...-uuidv7",
  "matchId": "0192f8c0-...",
  "type": "GOAL",            // GOAL, FOUL, CARD, TIMEOUT, INCIDENT, MATCH_START, PERIOD_END, ...
  "subtype": null,           // CARD → yellow|blue|red ; INCIDENT → text|voice|unjustified ; CLOCK_PAUSE → timeout
  "team": "home",            // home | away | null
  "period": 1,
  "matchTimeMs": 522000,     // 08:42
  "periodTimeMs": 522000,
  "timestamp": "2026-10-12T16:38:42.120Z",  // hora real
  "createdAt": "...", "updatedAt": "...",
  "deviceId": "uuid", "actionId": "uuid", "seq": 17,
  "revision": 1, "voidedAt": null, "syncStatus": "pending",
  "metadata": {}
}
```

`actionId` agrupa els esdeveniments generats per un sol toc (p. ex. temps mort + pausa) perquè DESFER els
anul·li junts. `seq` és l'ordre local d'inserció (desempat).

## 8. Sistema offline-first

Flux d'un toc a "GOL LOCAL":
1. Vibració hàptica immediata (feedback < 16 ms).
2. `EventFactory` crea l'esdeveniment amb el temps calculat a partir de l'estat actual i `now`.
3. **Transacció SQLite**: insert de l'esdeveniment + actualització de la memòria cau del partit (marcador, estat).
   Quan la transacció fa *commit*, l'esdeveniment ja és a disc.
4. La UI escolta la BD (consultes reactives de Drift) → marcador i cronologia s'actualitzen **des del que és
   persistit**, mai des d'un estat en RAM que es pugui perdre.
5. L'esdeveniment queda amb `syncStatus = pending` (la taula d'esdeveniments és la cua de sortida / *outbox*).
6. El `SyncEngine` (Fase 2) l'enviarà quan hi hagi compte i connexió.

Durabilitat: a Android, SQLite en mode WAL amb `synchronous=FULL`. A Web, SQLite WASM sobre OPFS
(o IndexedDB com a alternativa). Vegeu [OFFLINE_SYNC.md](OFFLINE_SYNC.md) per als riscos de la web.

## 9. Sincronització

- **Push**: lots d'esdeveniments `pending` → `POST /sync/push`. El servidor fa `INSERT … ON CONFLICT (id) DO UPDATE
  WHERE excluded.revision > events.revision`. Enviar el mateix esdeveniment 10 vegades = 1 fila. **Idempotent.**
- **Ack**: el servidor retorna `{id, revision}` acceptats. El client marca `synced` **només si la revisió local
  no ha canviat** mentrestant (si l'usuari l'ha editat durant l'enviament, segueix pendent).
- **Pull** (multi-dispositiu): `GET /sync/pull?since=<cursor>` amb un cursor monotònic del servidor.
- **Disparadors**: canvi de connectivitat, cada N segons amb *backoff* exponencial, en tornar a primer pla.
- **Conflictes**: improbables (cada esdeveniment té un únic autor i ID). Regla: guanya la `revision` més alta;
  els esborrats són tombstones i també es sincronitzen.

## 10. Cronòmetre

**No hi ha cap comptador que incrementi.** El temps és una funció pura dels esdeveniments:

```
estat = projectar(esdeveniments_ordenats)
tempsPart(now) = acumulat + (corrent ? now − desDe : 0)
tempsPartit(now) = duradaNominal × (part − 1) + tempsPart(now)
```

- `PERIOD_START` → corrent, acumulat = 0. `CLOCK_PAUSE` → acumulat += now − desDe. `CLOCK_RESUME` → desDe = now.
- `CLOCK_ADJUST` fixa l'acumulat a un valor concret (correcció manual).
- La UI només **repinta** cada 200 ms; el valor sempre es recalcula des dels timestamps.
- Pantalla apagada, segon pla, app tancada, reinici: en tornar, es llegeixen els esdeveniments i el temps és correcte.
- Risc: si l'usuari canvia l'hora del sistema durant el partit, el temps salta. Mitigació futura a Android:
  guardar també `elapsedRealtime` (monotònic) i detectar discrepàncies; `CLOCK_ADJUST` permet corregir-ho ara.
- Els durades vénen de `MatchFormat`, guardat dins del partit (una còpia), mai codificades al cronòmetre.

## 11. Gestió d'esdeveniments

- Comandes (`EventFactory`) validen transicions del rellotge (no es pot pausar si no corre) però **mai rebutgen
  un esdeveniment de registre** (gol, falta…): sempre es guarda.
- Les accions de l'usuari s'executen en una cua seqüencial per partit (dos tocs ràpids no es trepitgen).
- DESFER = marcar com `voidedAt` tots els esdeveniments de l'última acció. Es pot restaurar des de la cronologia.
- Editar = nova `revision` (equip, temps de partit, text). L'historial complet es conserva.

## 12. Android, Web/PWA i Wear OS

- **Android**: Flutter, SQLite natiu (`sqlite3_flutter_libs`), wakelock, hàptic. Distribució via Play Store.
- **Web/PWA**: el mateix codi Flutter; `manifest.json`, service worker de Flutter per funcionar offline després
  de la primera càrrega; SQLite WASM. Ha de servir-se amb HTTPS (requisit de PWA i service worker) i, idealment,
  amb capçaleres COOP/COEP perquè Drift pugui fer servir OPFS (vegeu DEPLOYMENT.md).
- **Wear OS (Fase 5)**: app Kotlin/Compose amb cua local (Room) → `MessageClient`/`DataClient` → servei Android
  que rep i escriu al mateix repositori local (via platform channel). Els esdeveniments del rellotge porten el
  seu propi `deviceId` i UUID: si arriben dues vegades, el mateix mecanisme d'idempotència els descarta.

## 13. Base de dades local: Drift (SQLite)

| Opció | Android | Web | Transaccions | Consultes | Estat |
|-------|---------|-----|--------------|-----------|-------|
| **Drift** | SQLite natiu | SQLite WASM (OPFS/IndexedDB) | Sí (ACID) | SQL, reactives | Mantingut activament |
| Isar | Sí | Limitat | Sí | Sí | Manteniment incert |
| Hive | Sí | IndexedDB | No reals | Clau-valor | Sense consultes |
| sqflite | Sí | No (oficialment) | Sí | SQL | No cobreix web |

**[DECISIÓ] Drift**: mateix motor (SQLite) a totes les plataformes, transaccions ACID (marcador i esdeveniment
s'escriuen junts o res), migracions versionades, consultes reactives per a la UI.

## 14. Base de dades del servidor

**PostgreSQL** (decisió ferma): relacional, `UNIQUE`/`ON CONFLICT` per idempotència, JSONB per a `metadata`,
Row Level Security per separar dades entre usuaris.

Capa d'API (a decidir a l'inici de la Fase 2, comparació breu):
- **Supabase** (Postgres + Auth + Storage + Edge Functions, autoallotjable): menys codi propi, auth segura ja feta.
- **API pròpia** (p. ex. Dart Frog o Node/Fastify) + Postgres + S3: més control, més manteniment.
Recomanació inicial: **Supabase** per velocitat i seguretat, mantenint la lògica de sync en una funció SQL
pròpia perquè migrar a API pròpia sigui possible.

## 15. Àudios (Fase 4)

Gravació (`record`) → fitxer local (AAC/Opus) → fila `AudioRecording` lligada a l'esdeveniment `INCIDENT/voice`
→ cua de pujada separada de la dels esdeveniments → Storage privat per usuari. L'esdeveniment existeix encara
que l'àudio no s'hagi pujat mai. A la web, l'àudio es guarda a OPFS/IndexedDB. Permís de micròfon demanat
només en el primer ús, amb explicació. Opció d'esborrar àudios.

## 16. Transcripció (Fase 4)

Desacoblada: el servidor rep l'àudio i una feina en segon pla crida un servei Speech-to-Text (candidats reals:
OpenAI transcriptions API, Google Cloud Speech-to-Text; tots dos suporten català). La clau només viu al servidor.
Estat de la transcripció: `pending → processing → done | failed` amb reintents. Si falla, l'àudio es conserva.

## 17. Traduccions

`flutter gen-l10n` amb `lib/l10n/app_{ca,es,en}.arb`. Claus en camelCase (gen-l10n exigeix identificadors
Dart vàlids): `match.start` → `actionStartMatch`, etc. Idioma: del dispositiu per defecte o triat manualment
(guardat a la BD local). Cap text a dins dels widgets.

## 18. Tests

- **Domini (unitaris purs)**: projector i cronòmetre amb un `FakeClock` (iniciar, pausar, reprendre, descans,
  2a part, final, ajust, temps mort, desfer, "reinici" = tornar a projectar des dels esdeveniments).
- **Dades (Drift amb SQLite real en fitxer temporal)**: test crític — 50 esdeveniments sense xarxa, tancar la BD,
  reobrir-la, comprovar-los tots; sincronitzar amb un servidor fals que falla a mig enviament, reintentar,
  verificar zero duplicats i zero pèrdues.
- **Sync**: idempotència, revisions concurrents.
- **Widgets/integració** (següent iteració): flux NOU PARTIT → registre → final amb `integration_test`.
