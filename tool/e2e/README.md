# Web E2E smoke test (Playwright)

Used to verify the real `build/web` output in headless Chromium (Phase 1 verification).

```bash
pip install playwright && python -m playwright install chromium
python tool/e2e/serve.py &              # serves build/web with COOP/COEP on :8765
python tool/e2e/browse.py steps.json    # runs click/type/reload/offline steps, saves screenshots
```

`steps.json` example (412×900 phone viewport, fake microphone enabled):

```json
[["goto"],["wait",5000],["click",206,828],["wait",600],["click",206,828],
 ["wait",1500],["click",206,104],["wait",1500],["click",206,808],["wait",3000],
 ["click",105,332],["offline",true],["reload"],["wait",6000],["shot","after_reload"]]
```

Verified on 2026-10-05: onboarding, new untitled match, start, goals, fouls, cards + team assignment,
timeout start/end, half-time, 2nd half (starts at 25:00), written and voice incidents (recording +
playback), end of match, summary, timeline, match details edit, language switch (ca/es/en,
persisted), responsive tablet layout, and **full offline**: app reload with no network (service
worker), new match recorded offline, reload → "Partit en curs" with all events (OPFS storage).

## Android (emulator, 2026-10-05)

Release APK installed on `Medium_Phone_API_37.0` through the runner (`install`, `launchapp`,
`tap`, `screencap`): onboarding, new match, start, goals, foul, timeout start/end, voice incident
(microphone permission prompt, recording, stored with the time of the tap), timeline. Then the
**emulator process was killed** (power-loss simulation) and cold-booted: the app showed
"Match in progress" and restored the exact state (paused at 00:16, timeout running, 2-0).
