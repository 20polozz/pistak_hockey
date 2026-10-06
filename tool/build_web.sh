#!/usr/bin/env bash
# Production web/PWA build. Self-hosts CanvasKit (no CDN → works offline and
# with cross-origin isolation) and generates the offline service worker.
set -euo pipefail
cd "$(dirname "$0")/.."

for f in web/sqlite3.wasm web/drift_worker.js; do
  [[ -f "$f" ]] || { echo "Missing $f — see docs/SETUP.md (Web database files)"; exit 1; }
done

flutter build web --release --no-web-resources-cdn "$@"
# Not used by this (JS + CanvasKit) build: debug symbols and the renderers of
# WebAssembly builds. Keeps the upload small (Cloudflare Pages / Telegram).
rm -f build/web/canvaskit/*.symbols build/web/canvaskit/*/*.symbols \
      build/web/canvaskit/skwasm* build/web/canvaskit/wimp*
rm -rf build/web/canvaskit/webparagraph
python3 tool/gen_service_worker.py build/web
(cd build/web && rm -f ../../WEB_PER_PUJAR/pistak-hockey-web.zip && mkdir -p ../../WEB_PER_PUJAR && zip -qr ../../WEB_PER_PUJAR/pistak-hockey-web.zip .)
echo "Done: build/web"
