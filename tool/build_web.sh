#!/usr/bin/env bash
# Production web/PWA build. Self-hosts CanvasKit (no CDN → works offline and
# with cross-origin isolation) and generates the offline service worker.
set -euo pipefail
cd "$(dirname "$0")/.."

for f in web/sqlite3.wasm web/drift_worker.js; do
  [[ -f "$f" ]] || { echo "Missing $f — see docs/SETUP.md (Web database files)"; exit 1; }
done

flutter build web --release --no-web-resources-cdn "$@"
python3 tool/gen_service_worker.py build/web
echo "Done: build/web"
