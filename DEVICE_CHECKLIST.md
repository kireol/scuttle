# Device Verification Checklist

## Task 1

The following on-device verification steps were skipped (no Roku device available):
- Deploy via `./deploy.sh`
- TV shows the skeleton text "Frigate for Roku — skeleton OK"

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 2

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: PASS: math works, [TESTS DONE], exit 0

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 3

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: all Test_ServerStore asserts PASS, [TESTS DONE], exit 0

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 4

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: all Test_FrigateUrls asserts PASS (including the base64 basic-auth and cookie-parse asserts, which exercise roByteArray/string APIs only a real device fully verifies), [TESTS DONE], exit 0

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 5

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: install OK and existing tests still print `[TESTS DONE]` (a BrightScript compile error in the new component would abort launch)

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

Functional ApiTask verification (auth, re-login, sync HTTP requests) happens in Task 6's Test Connection checklist.

## Task 6

The following on-device verification steps were skipped (no Roku device available):

Run: `./deploy.sh`, then on the TV:

1. Fresh install (no servers) opens Server list with only "+ Add Server".
2. Add a server: enter name, URL, auth settings for a REAL Frigate server on your LAN.
3. Test Connection with correct credentials → "OK v0.16.x — N cameras found".
4. Test Connection with wrong password (frigate auth) → "Auth rejected (401)".
5. Test Connection with wrong IP → "Unreachable: ..." within ~15 s.
6. Save; relaunch the channel (Home, reopen) → server persists.
7. Edit → Delete Server → list is empty again. Re-add and save for later tasks.

Expected: all 7 pass. Also confirms Task 5's ApiTask works, including Frigate-auth login (check the server's registry entry got a token by re-entering edit — Test Connection after save should succeed without re-login).

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 7

The following on-device verification steps were skipped (no Roku device available):

Run: `./deploy.sh`, then on the TV:

1. Home shows your server's name highlighted as a tab, menu row, and a grid tile per enabled camera (alphabetical).
2. Tiles fill with snapshots and visibly refresh (~1–2 s cadence; watch a camera with motion).
3. With a second server configured: Up to tabs, Left/Right switches server; grid reloads with that server's cameras.
4. Unplug/wrong-IP server tab shows the failure message in the status line; other tab still works.
5. Kill one camera (or use a disabled one) → its tile shows the red `offline` badge, others keep refreshing.
6. Up from top grid row reaches menu; OK on Settings opens the server list; Back returns and snapshots resume.
7. Let it run 10 minutes — no crash, no visible memory stutter (tmp files are capped by the 2-generation delete).

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)
