# Setup — instal·lació i desenvolupament

## Requisits

- **Flutter ≥ 3.32** (canal stable) — `flutter --version`
- Android Studio / SDK d'Android (per a Android)
- Chrome (per a web)
- Python 3 (scripts de `tool/`)
- Git

## 0. Treballar amb Claude (executor local)

`PISTAK_RUNNER.bat` (doble clic, deixa la finestra oberta) executa **només** una llista tancada
d'accions Flutter (`tool/windows/pistak_runner.ps1`): `pubget`, `codegen`, `l10n`, `analyze`, `test`,
`apk`, `web`, `doctor`, `create`, `clean`, i per a Android `emulators`, `launchemu`, `install`,
`launchapp`, `screencap`, `tap`. No accepta ordres lliures. Les feines arriben com a fitxers a
`.runner/queue` i els resultats queden a `.runner/out` (ignorat per Git). Tanca la finestra per aturar-lo.

## 1. Generar les carpetes de plataforma (ja fet)

El repositori conté el codi (`lib/`, `test/`, `web/index.html`, `web/manifest.json`…), però no les
carpetes generades per Flutter. Executa **una vegada**:

```bash
flutter create . --project-name pistak --org cat.pistak --platforms android,web
rm test/widget_test.dart   # plantilla de Flutter que no compila amb PISTAK
```

`flutter create` no sobreescriu fitxers existents. Després:
- `android/app/src/main/AndroidManifest.xml` → `android:label="PISTAK"` + permís `RECORD_AUDIO`.
- Android necessita l'**NDK 28.2.13676358** (Android Studio → Settings → Android SDK → SDK Tools →
  NDK (Side by side) → Show package details). Ja està instal·lat en aquest PC.

## 2. Dependències i codi generat

```bash
flutter pub get                                           # també genera la localització (gen-l10n)
dart run build_runner build   # genera app_database.g.dart (Drift)
```

Mentre desenvolupes: `dart run build_runner watch --delete-conflicting-outputs`.

## 3. Fitxers de base de dades per a la web (ja inclosos: sqlite3 2.9.4 · drift 2.31.0)

Drift a la web necessita dos fitxers a `web/` amb versions **compatibles** amb `pubspec.lock`:

| Fitxer | D'on | Versió |
|--------|------|--------|
| `web/sqlite3.wasm` | Releases de `simolus3/sqlite3.dart` a GitHub (asset `sqlite3.wasm`) | la de `sqlite3` a `pubspec.lock` |
| `web/drift_worker.js` | Releases de `simolus3/drift` a GitHub (asset `drift_worker.js`) | la de `drift` a `pubspec.lock` |

```bash
grep -A2 "^  sqlite3:" pubspec.lock
grep -A2 "^  drift:" pubspec.lock
```

Consulta la guia oficial "Web" de la documentació de Drift si canvien els noms dels assets.

## 4. Executar

```bash
flutter run -d chrome          # web
flutter run -d <android-id>    # Android (flutter devices)
```

## 5. Tests

```bash
flutter test                      # tots
flutter test test/domain          # cronòmetre i esdeveniments (Dart pur)
flutter test test/data            # BD real + test crític offline/sync
```

Els tests de `test/data` usen SQLite natiu de l'ordinador (a Windows ja funciona amb les
dependències actuals; si algun dia falla):
- **Linux**: `sudo apt install libsqlite3-dev`
- **macOS**: inclòs
- **Windows**: descarrega `sqlite3.dll` (sqlite.org → *Precompiled Binaries for Windows*, 64-bit)
  i posa'l al `PATH` o a la carpeta des d'on executes `flutter test`.

## 6. Textos i traduccions

Els textos es defineixen a **`tool/gen_arb.py`** (una fila = en/ca/es):

```bash
python3 tool/gen_arb.py    # regenera lib/l10n/app_{en,ca,es}.arb
flutter gen-l10n           # (o flutter pub get / flutter run, que ho fan sols)
```

Mai textos directament dins dels widgets: `AppLocalizations.of(context).clau`.

## 7. Git

```bash
git init -b main
git add . && git commit -m "feat: PISTAK phase 1 core (offline-first match recording)"
git checkout -b develop
git checkout -b feature/<nom>     # treball diari
```

- `main`: versions publicables · `develop`: integració · `feature/*`: una funcionalitat per branca.
- `.gitignore` ja exclou `build/`, `.env`, claus, `*.g.dart` i codi de localització generat.
- Missatges de commit: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.

## Anàlisi estàtica

```bash
flutter analyze
dart format lib test
```
