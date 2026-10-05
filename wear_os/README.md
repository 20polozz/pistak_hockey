# PISTAK Wear OS

App nativa **Kotlin + Compose for Wear OS** (projecte Gradle independent). Interfície mínima:
temps, marcador i botons GOL L/V, FALTA L/V, targetes G/B/R, TM L/V, PAUSA/REPRENDRE, INCIDÈNCIA.

## Flux (cap toc es perd)

```
Rellotge: toc → WatchCommand {id UUID, cmd, team, color, at} → cua durable (SharedPreferences)
        → MessageClient /pistak/cmd → mòbil
Mòbil:   WearListenerService → wear_inbox.jsonl (fsync) → ACK /pistak/ack → el rellotge l'esborra
Flutter: WearBridge llegeix la safata → WearCommandProcessor → MatchController.applyExternal
        → esdeveniments guardats a Drift → s'esborra de la safata
Mòbil → rellotge: /pistak/state {home, away, label, running, matchMs, atMs}
```

* **Idempotent:** els IDs dels esdeveniments es deriven (UUID v5) de l'ID de la comanda,
  generat al rellotge. Una comanda repetida (ACK perdut, app reiniciada) no crea duplicats.
* **Hora del toc:** s'usa `at` del rellotge (mai en el futur respecte al mòbil).
* **Rellotge sense mòbil:** la cua es manté i es reenvia cada pocs segons.
* El cronòmetre del rellotge es calcula amb timestamps, no amb un comptador.
* Només amb l'app Android (no amb la web). Les dues apps han de tenir el mateix
  `applicationId` (`cat.pistak.app`) i la mateixa signatura.

## Compilar

`wear_os/local.properties` (no es puja a git) amb `sdk.dir=...`, i després
l'acció `wearbuild` del runner (`gradlew.bat assembleDebug`).
APK: `wear_os/app/build/outputs/apk/debug/app-debug.apk`.

Tests de la lògica del mòbil: `test/data/wear_commands_test.dart`.
