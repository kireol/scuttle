# Live view improvements — design

Date: 2026-08-01
Status: implemented in same session (autonomous run; decisions recorded here)

## Requirements (from user)

1. Hide the "snapshot view — OK to retry video" text.
2. If a downgrade happens on one camera on a server, downgrade all cameras
   for that server to the same level.
3. Max 10s timeout for video feeds before downgrading.
4. Show current FPS in the upper-right corner while playing.
5. Per-server choice of snapshot vs video mode; in video mode, discover
   go2rtc stream types (e.g. `_main`, `_sub`, `_roku`) and let the user pick.
6. Switching servers clears the camera grid completely before reloading.
7. Human-readable errors instead of raw HTTP codes.
8. No app exit on up/back without a confirmation dialog.

## Decisions

- **Downgrade levels = stream tiers.** LivePlayerScreen's flat URL attempt
  list becomes a list of tiers: tier 0 = main stream (raw port + proxy),
  tier 1 = sub stream, tier 2 = `_roku` transcode; below that, snapshot
  mode. `m.serverTier` / `m.serverSnapshot` are session-wide for the player
  (one player session = one server): when camera A falls to tier N, every
  camera starts at tier N. Pressing OK in snapshot/error state resets the
  server back to tier 0 and retries. Scope is the player session, not
  persisted — a fresh visit retries full quality.
- **Watchdog 15s → 10s** per explicit request. Note: a cold `_roku` ffmpeg
  transcode can need ~8s before its master playlist answers, so 10s is
  tight but acceptable; the warmup polling absorbs most of it.
- **FPS source = Frigate `/api/stats` `cameras.<cam>.camera_fps`.** Roku's
  Video node does not expose decoder FPS, so the camera's real FPS from
  Frigate is shown instead, polled every 5s while state = playing.
- **Per-server fields** `liveMode` (`video`|`snapshot`, default video) and
  `streamType` (`auto` or a suffix like `_sub`), stored on the server
  record with migration defaults in `ServerStore_Load`. Edit screen: OK
  cycles liveMode; streamType fetches `/api/go2rtc/api/streams`, derives
  the available suffix set, and offers a dialog pick. `auto` keeps the
  existing main→sub→_roku fallback chain; a fixed type uses only that
  variant (then snapshot fallback). `liveMode=snapshot` skips video
  entirely and OK opens the camera switcher instead of retrying video.
- **Server switch** clears grid content + camera/stream maps whenever the
  loaded server id changes (also fixes stale `liveStreamsSub` never being
  reset between servers).
- **Errors**: reuse existing `Frigate_FriendlyError` in ExploreScreen and
  RecordingsScreen; add the missing `FrigateUrls.brs` include to
  ServerEditScreen.xml (it already called `Frigate_FriendlyError` without
  it — latent crash).
- **Exit guard**: back already routes through the confirm dialog from all
  HomeScreen zones; "up" at the tabs row is now consumed so nothing can
  bubble out of the app.

## Follow-up (same day): visibility + save flow

- **Loading indicator**: while a source is being tried, the bottom-left
  shows "Loading <stream> (direct|proxy) ..."; snapshot mode shows
  "Loading snapshot mode ..." until the first still lands.
- **First-play hint**: once per player session, when the first camera
  reaches "playing", a centered bottom label says "Press * for stream
  info" for 5 seconds.
- **\* info overlay** (the `options` key): camera, server, stream name or
  snapshot mode, route (go2rtc port vs Frigate proxy), player state,
  resolution (from the Video node's streamingSegment), stream bitrate,
  measured bandwidth, camera FPS (from /api/stats, kept fresh while the
  overlay is open even in snapshot mode), and quality tier N of M.
  Toggles on/off; updates live as the tier cascade progresses.
- **Save flow**: saving a server now shows a "Server saved" dialog with
  "View <name> cameras" (scene.goToServerId + popToRoot → home lands on
  that server's tab) or "Back to settings" (old closeMe behavior).
- **Remote diagnosis**: video starts then dies with go2rtc's
  "mpr zero length playlist" even on the LAN — the 1s playlist window
  limitation, not purely bandwidth. The tier cascade now lands it in
  snapshot mode quickly, and the overlay makes the state visible.
