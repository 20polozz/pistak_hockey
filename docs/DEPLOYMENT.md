# Desplegament

## Variables d'entorn

Fase 1 **no necessita cap variable**: l'app funciona 100% local.

A partir de la Fase 2:
- **Client** (valors públics, no secrets): `PISTAK_API_BASE_URL`, passat amb
  `flutter build ... --dart-define-from-file=env/prod.json`. Qualsevol cosa compilada al client és
  pública: **mai** hi posis claus privades.
- **Servidor** (secrets): `DATABASE_URL`, secret JWT, clau del servei Speech-to-Text… només a
  l'entorn del backend (gestor de secrets del proveïdor). Plantilla: `.env.example`.

## Android

1. Clau de signatura (una vegada, **fora del repositori**):
   ```bash
   keytool -genkey -v -keystore ~/pistak-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. `android/key.properties` (ignorat per Git) + configuració `signingConfigs` a
   `android/app/build.gradle(.kts)` segons la guia oficial de Flutter "Build and release an Android app".
3. Build:
   ```bash
   flutter build appbundle --release     # Play Store
   flutter build apk --release           # proves directes
   ```

## Web / PWA

```bash
./tool/build_web.sh
```

Fa `flutter build web --release --no-web-resources-cdn` (CanvasKit allotjat a casa: funciona offline)
i genera `build/web/pistak_sw.js`, el service worker propi que precarrega tota l'app perquè obri
sense connexió després de la primera visita.

Puja `build/web/` a qualsevol hosting estàtic **amb HTTPS** (obligatori per a PWA i service worker):
Cloudflare Pages, Netlify, Firebase Hosting, Nginx…

### Capçaleres recomanades

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
Content-Type: application/wasm        (per a *.wasm)
```

COOP/COEP activen l'aïllament d'origen perquè Drift pugui fer servir **OPFS** (emmagatzematge més
durable). `web/_headers` ja les defineix per a Netlify/Cloudflare Pages. Nginx:

```nginx
add_header Cross-Origin-Opener-Policy same-origin always;
add_header Cross-Origin-Embedder-Policy credentialless always;
types { application/wasm wasm; }
location = /pistak_sw.js { add_header Cache-Control "no-cache"; }
```

`pistak_sw.js` ha de servir-se sense cache perquè les actualitzacions arribin.

## Backend (Fase 2)

Vegeu `backend/README.md`: `Dockerfile` llest (binari AOT, usuari no-root, volum `/data`).
1. Desplegar el contenidor amb HTTPS (Fly.io, Railway, Render, VPS + Caddy…).
2. Variables: `PISTAK_JWT_SECRET` (≥32 caràcters, secret del proveïdor), `PISTAK_ORIGINS` (domini web).
   Opcional, transcripció de veu: `PISTAK_STT_API_KEY` (+ `PISTAK_STT_URL`, `PISTAK_STT_MODEL` per a un
   servei compatible amb OpenAI o un Whisper propi). La clau només viu al servidor.
3. Compilar l'app amb `--dart-define=PISTAK_API_URL=https://…`.

## Checklist de release

- [ ] `flutter analyze` sense errors · `flutter test` en verd
- [ ] Test manual en mode avió: nou partit → 2 parts → final → tancar app → reobrir
- [ ] Web instal·lada com a PWA, mode avió, recàrrega: obre i recupera el partit
- [ ] Versió incrementada a `pubspec.yaml`
