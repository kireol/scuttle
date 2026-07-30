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

## Task 8

The following on-device verification steps were skipped (no Roku device available):

Run: `./deploy.sh`, then on the TV:

1. OK on a grid tile → full-screen live video within ~3–6 s; camera name overlays then fades.
2. Audio is audible on a camera whose go2rtc stream has AAC audio (talk near the camera / check a doorbell).
3. Left/Right switches to prev/next camera; wraps at both ends.
4. Down/OK opens the bottom thumbnail strip; Left/Right moves; OK jumps to that camera; Back closes strip without switching.
5. Back from playback returns to the grid; snapshots still refreshing; enter a different camera — plays.
6. Point a server entry at a bogus go2rtc port → error panel with URL + codec hint; OK retries; Back exits.
7. No stutter after 5+ minutes on one camera.

If step 1 fails on all cameras: verify from a PC that `http://<host>:1984/api/stream.m3u8?src=<cam>&mp4` plays in VLC. If VLC works but Roku errors, check the camera's codec (`ffprobe` the stream) — H.265 on an older Roku is the usual cause; fix server-side per the hint text.

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 9

The following on-device verification steps were skipped (no Roku device available):

Run: `./deploy.sh`, then on the TV:

1. Home → Review lists recent alerts with thumbnails, labels, and local times, newest first.
2. `*` toggles to Detections and back; list refetches.
3. OK on an item plays the recording of that segment; audio present if recorded; Left/Right seek ±30 s.
4. On a frigate-auth server: playback works (Bearer over `HttpHeaders`). If it 401s, apply the documented `HttpCookies` fallback in VodPlayerScreen and re-verify.
5. Back returns to the list, then to Home.
6. A server with no review items shows "0 items", no crash.

Bearer-vs-HttpCookies fallback note (brief Step 1): `VodPlayerScreen.brs`'s `authHeaderStrings()` sends the Frigate JWT as `Authorization: Bearer <token>` via the content node's `HttpHeaders` field, as written in the brief. Whether the Roku video player actually honors a Bearer `Authorization` header on HLS/MP4 segment requests (vs. silently dropping it, causing 401s against a frigate-auth server) can only be determined on a real device. If checklist item 4 above 401s, switch the `else if s.authType = "frigate" and s.token <> ""` branch in `authHeaderStrings()` to send the token as a cookie instead — e.g. `content.HttpCookies = ["frigate_token=" + s.token]` — and re-run item 4 to confirm playback succeeds.

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 10

The following on-device verification steps were skipped (no Roku device available):

Run: `./deploy.sh`, then on the TV:

1. Home → Explore shows a grid of recent tracked objects with thumbnails, label, camera, local time.
2. Up to chip bar; OK cycles Camera/Label/When values; grid refetches each time; combinations work (e.g. person + one camera + 7d).
3. OK on an event plays its clip (MP4); seek works; Back returns with filters intact.
4. An event without a clip shows "This event has no clip" instead of erroring.
5. Works on both servers (auth and no-auth).

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 11

The following on-device verification steps were skipped (no Roku device available):

Run: `./deploy.sh`, then on the TV:

1. Home → Recordings lists cameras; OK loads days (only days that have recordings).
2. OK on a day lists its hours in local time; OK on an hour starts playback of that hour.
3. Left/Right seek ±30 s inside the hour; when an hour finishes, the next hour starts automatically; after the last hour the player closes.
4. Works on a frigate-auth server (VOD requests carry auth).
5. A camera with retention disabled shows "No recordings summary"/0 days, no crash.

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)
