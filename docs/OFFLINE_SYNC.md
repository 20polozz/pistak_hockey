# Offline-first, cronòmetre i sincronització

## Garanties de la Fase 1

| Situació | Què passa |
|----------|-----------|
| Sense internet / sense WiFi / servidor caigut | Res canvia: cap acció depèn de la xarxa. |
| Sense compte | Tot funciona; les dades viuen al dispositiu. |
| App tancada, en segon pla, pantalla apagada | Cada acció ja és a disc (transacció SQLite confirmada). El temps es recalcula dels timestamps en tornar. |
| Reinici del dispositiu | Igual: en obrir, la pantalla d'inici mostra **Partit en curs → CONTINUAR PARTIT**. |
| Doble toc molt ràpid | Cua sèrie per partit; cada acció llegeix l'estat persistit. |
| Error en un toc | Es mostra sempre (snackbar vermell); mai es descarta en silenci. |
| Emmagatzematge local no disponible | L'app no deixa registrar (pantalla d'error) en lloc de fingir que guarda. |

## Durabilitat per plataforma

- **Android**: SQLite natiu, `journal_mode=WAL`, `synchronous=FULL` → cada commit és a disc.
- **Web**: SQLite WASM. Drift tria el millor backend disponible:
  1. **OPFS** (Origin Private File System) — el més robust. Requereix aïllament d'origen
     (capçaleres COOP/COEP, vegeu DEPLOYMENT.md).
  2. **IndexedDB** — alternativa (p. ex. Safari sense aïllament). Drift escriu a IndexedDB de manera
     asíncrona; hi ha una finestra petita en què tancar la pestanya *just* després d'un toc podria
     perdre l'últim canvi.
- Es demana `navigator.storage.persist()` perquè el navegador no esborri les dades.
- iOS/Safari pot esborrar dades de webs **no instal·lades** després de dies sense ús → recomanar
  "Afegir a la pantalla d'inici". La sincronització al núvol (Fase 2) és la protecció definitiva.

**Millora planificada (enduriment web):** diari d'emergència síncron a `localStorage` per a cada
esdeveniment, esborrat quan Drift confirma la persistència, i reproduït a l'arrencada. Tanca la
finestra d'IndexedDB descrita abans.

## Cronòmetre

Vegeu ANALYSIS.md §10. Resum:

```
tempsPart(now)   = acumulat + (corrent ? now − desDe : 0)       (mai negatiu)
tempsPartit(now) = duradaPart × (part − 1) + tempsPart(now)
```

| Esdeveniment | Efecte |
|--------------|--------|
| `PERIOD_START` | part = n, acumulat = 0, corrent |
| `CLOCK_PAUSE` | acumulat += now − desDe, aturat |
| `CLOCK_RESUME` | desDe = now, corrent |
| `CLOCK_ADJUST` | acumulat = valor (alinear amb el marcador oficial) |
| `PERIOD_END` | atura i tanca la part |
| `BREAK_START` | descans (no compta temps de partit) |
| `MATCH_END` | final |
| `TIMEOUT` (+ `CLOCK_PAUSE` si el format ho diu) | compte enrere del temps mort |

La UI només repinta cada 250 ms. El valor sempre surt dels timestamps guardats.

## Sincronització (implementada: backend/ + HttpSyncApi)

```
Dispositiu → SQLite (outbox: sync_status = pending) → SyncEngine → API HTTPS → PostgreSQL
```

1. **Disparadors**: login, canvi de connectivitat (`poke()`), retorn a primer pla, cada 30 s;
   *backoff* exponencial (5 s → 5 min) si falla.
2. **Ordre**: primer partits (pares), després esdeveniments, en lots de 200.
3. **Idempotència**: el servidor fa *upsert* per `id` i només actualitza si `revision` és més alta.
   Reenviar el mateix lot (p. ex. perquè la connexió es va tallar abans de l'ACK) no crea duplicats.
4. **ACK amb control de revisió**: el client marca `synced` només si la revisió local és la mateixa
   que s'ha enviat. Si l'usuari ha editat l'esdeveniment mentrestant, continua pendent.
5. **Mai bloqueja l'usuari**: l'estat (verd / taronja / gris) és informatiu.
6. **Pull** (multi-dispositiu): `GET /sync/pull?since=<server_seq>`; s'aplica amb la mateixa regla
   de revisions i `insertOrIgnore`.

Test que ho demostra: `test/data/offline_sync_test.dart` (51 esdeveniments offline → tancar →
reobrir → tall de connexió abans de l'ACK → resincronitzar → 0 duplicats, 0 pèrdues).

## Àudio i transcripció (implementat a la Fase 1, excepte el servei STT)

Implementació actual:
- `AudioCaptureService` (paquet `record`): PCM 16 bits, 16 kHz, mono → WAV. Igual a Android i Web.
- Els bytes es guarden a la taula `audio_recordings` de la mateixa BD local (esquema v2), abans de
  crear l'esdeveniment `INCIDENT/voice` (amb `metadata.audioId`). El moment és el del toc a INCIDÈNCIA.
- Sense micròfon o sense permís → es registra igualment una incidència (sense àudio).
- `TranscriptionQueue` processa els pendents cada 2 min i després de cada gravació; amb
  `NoTranscriptionService` (Fase 1) tot queda `pending`. La transcripció s'escriu com a text editable
  de l'esdeveniment, **sense sobreescriure mai** un text escrit a mà. 5 errors → `failed` (l'àudio es manté).
- Reproduir (`audioplayers`) i eliminar l'àudio des de la cronologia.

```
INCIDÈNCIA → veu → gravar (record) → BD local → MatchEvent(INCIDENT/voice, audioId)
→ el partit continua
→ cua de pujada pròpia (no bloqueja la d'esdeveniments) → Storage privat
→ feina al servidor → Speech-to-Text → transcripció (pending/processing/done/failed)
```
Si la transcripció falla, l'àudio continua existint. L'usuari pot esborrar àudios (GDPR/LOPDGDD).


## Estat actual de la sincronització (Fase 2)

- **Client**: `HttpSyncApi` (HTTPS), `RemoteAuthService` (token a `flutter_secure_storage`),
  `SyncEngine` push → pull amb cursor per usuari, reintents amb *backoff*, i `connectivity_plus`
  per sincronitzar en el moment que torna la connexió.
- **Servidor**: `backend/` — upsert idempotent per id+revisió, aïllament per usuari, pull incremental.
- **Regla de conflicte**: guanya la revisió més alta; una còpia local amb canvis pendents no es
  sobreescriu mai amb dades del servidor fins que s'ha enviat.
- **Prova E2E** (`test/data/backend_e2e_test.dart`): servidor real, mòbil sense cobertura
  (17 esdeveniments), torna la cobertura → s'envien una sola vegada, una tauleta amb el mateix
  compte rep el partit sencer, una edició a la tauleta arriba al mòbil, un altre usuari no veu res.
- Pendent: sincronitzar també equips/plantilles i els àudios (mateix protocol, nous `kind`).
