# PISTAK Wear OS (Fase 5)

App nativa **Kotlin + Compose for Wear OS**. Interfície mínima: temps, marcador i botons
GOL / FALTA / TARGETES / PAUSA.

```
Rellotge: toc → MatchEvent (UUID, timestamp) → Room (cua local)
        → Data Layer API (MessageClient) → mòbil Android
Mòbil:   WearableListenerService → MethodChannel → MatchRepository.appendEvents (insertOrIgnore)
        → ACK al rellotge → s'esborra de la cua del rellotge
```

Si el rellotge perd el mòbil, la cua es manté i es reenvia; els duplicats són impossibles perquè
l'ID el genera el rellotge. Només funciona amb l'app Android (no amb la web).
