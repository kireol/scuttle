# Frigate Roku App — Design

Date: 2026-07-29
Status: Approved (pending user review of this document)

## Purpose

A native Roku (SceneGraph/BrightScript) app for viewing Frigate NVR servers on a TV: a
camera grid home screen resembling the Frigate web portal, full-screen live viewing with
audio, and history playback (Review, Explore, Recordings). Supports multiple Frigate
servers, each with its own address and credentials.

## Requirements

- Configure more than one Frigate server: name, base URL (host:port), auth type, credentials.
- Per-server auth type: none (open port), Frigate native login (0.14+ JWT), or HTTP basic auth.
- Home screen shows all cameras of the active server as a grid of auto-refreshing snapshots
  (~1.5 s cadence), one tab per server (server switcher).
- Selecting a camera plays full-screen live video with audio when the stream carries it.
- Easy camera switching during live view: Left/Right cycles cameras; OK/Down opens a
  thumbnail-strip overlay to jump to any camera.
- History: Review (alerts/detections list → segment playback), Explore (tracked objects
  with filters → clip playback), Recordings (camera/date/hour → continuous playback).
- Targets Frigate 0.14+ only. Current stable at design time: 0.16.x.
- Deployment: sideload (developer mode) now; keep the door open for a store release later.

## Platform constraints (drive the whole design)

- Roku has a single hardware video decoder: only ONE live video can play at a time.
  The grid therefore uses refreshing JPEG snapshots, not simultaneous video.
- Roku cannot play RTSP, WebRTC, or MSE. Live video must be HLS, served by Frigate's
  bundled go2rtc restream.
- Roku decodes H.264 everywhere, H.265 only on newer models, and audio must be AAC.
  Codec mismatches are fixed server-side in Frigate's go2rtc config (e.g. `#audio=aac`),
  documented in the app README — not worked around in the app.
- Poster nodes cannot send auth headers; Video nodes can (HttpAgent headers/cookies).

## Architecture

Approach chosen: fully native app talking directly to Frigate — no companion/bridge
service. A rejected alternative (native app + Docker proxy that transcodes/normalizes)
would guarantee codec compatibility but adds infrastructure the user must host; codec
edge cases are rare and fixable in Frigate config.

### Screens (SceneGraph stack; Back pops)

1. **Home (camera grid)** — top tab strip with one tab per configured server; grid of
   camera tiles (name + snapshot refreshed ~1.5 s) for the active server; a menu row
   linking Review, Explore, Recordings, Settings. OK on a tile → Live Player.
2. **Live Player** — full-screen HLS live with audio. Left/Right = prev/next camera on
   the same server. OK/Down = bottom thumbnail-strip overlay for direct camera selection.
   Back = Home.
3. **Review** — newest-first list of review items (thumbnail, labels, camera, time) with
   an Alerts/Detections filter. OK plays that item's recording segment.
4. **Explore** — grid of tracked objects with camera/label/date filters. OK plays the clip.
5. **Recordings** — pick camera → date → hour; continuous playback with seek. Left/Right
   skip ±30 s; end of hour auto-advances to the next hour.
6. **Settings/Servers** — add/edit/remove servers with Test Connection. First launch with
   no configured servers lands here.

### Data layer

- **Storage:** server configs as JSON in the Roku registry (device-local). Acceptable for
  a sideloaded personal app; revisit if ever published.
- **FrigateClient** (one per server): all HTTP via roUrlTransfer inside Task nodes (UI
  never blocks). Auth modes:
  - none — plain requests
  - basic — `Authorization: Basic …` on every request
  - frigate — `POST /api/login` → JWT; stored and sent on requests; on 401 re-login once,
    then surface the error.
- **Frigate endpoints:** `/api/config` (camera list/capabilities), `/api/version`
  (pre-0.14 warning), `/api/<camera>/latest.jpg` (snapshots), `/api/review` (review
  items), `/api/events` + `/api/events/<id>/thumbnail.jpg` (Explore),
  `/api/events/<id>/clip.mp4` (Explore playback), `/vod/...` HLS (recorded playback),
  go2rtc HLS `stream.m3u8?src=<camera>` for live. Verified against Frigate source:
  Frigate's nginx does NOT proxy go2rtc's HLS endpoint through port 8971 (only the
  MSE/WebRTC websocket paths), so live HLS is fetched directly from go2rtc's own HTTP
  port — `http://<host>:1984/api/stream.m3u8?src=<camera>&mp4` — and each server config
  gains a `go2rtcPort` field (default 1984). Frigate auth accepts
  `Authorization: Bearer <JWT>`, which the app uses instead of cookies.
- **Snapshots:** a Task downloads authenticated JPEGs to `tmp:/` and tiles point at local
  files (Poster can't send headers). One rotating fetch loop covers only on-screen tiles.

### Playback

- **Live:** Video node on go2rtc HLS, low-buffer config; ~3–6 s startup/latency is
  inherent to HLS on Roku. Audio plays when the restream carries AAC.
- **Review item:** `/vod/<camera>/start/<ts>/end/<ts>/master.m3u8` (seekable HLS).
- **Explore clip:** `/api/events/<id>/clip.mp4` (plain MP4).
- **Recordings:** `/vod/<year>-<month>/<day>/<hour>/<camera>/master.m3u8`.
- Video node authenticates via HttpAgent headers/cookies matching the server's auth mode.

### Error handling

- Test Connection hits `/api/config` and reports the specific failure: unreachable, auth
  rejected, not a Frigate server, or version too old.
- Snapshot failures show an "offline" badge on the tile; fetching keeps retrying at the
  normal cadence.
- Playback errors show a human-readable message plus the Roku error detail and a Retry
  button; codec/audio failures include a hint about the `#audio=aac` / H.264 restream fix.
- A down server only affects its own tab; other servers keep working.

### Build & testing

- Plain SceneGraph project layout (manifest, components/, source/), no framework.
- `deploy.sh` zips and sideloads via the Roku dev web API; Roku IP and dev password come
  from an untracked `.env`.
- Pure logic (URL building, auth headers, JSON shaping) lives in standalone `.brs` files,
  separated from UI components, so it stays testable.
- Verification is manual on-device against real Frigate servers using a written
  per-feature test checklist.
- Store certification work (deep linking, signal beacons, TLS requirements) is explicitly
  out of scope now; the structure avoids blocking it later.

## Out of scope

- Two-way audio, PTZ control, Frigate+ features, notifications.
- Pre-0.14 Frigate servers.
- Simultaneous multi-camera live video (impossible on Roku hardware).
- Merged multi-server grid (user chose per-server tabs).
