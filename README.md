# Scuttle for Roku

> **Developer's note:** This app allows for viewing live Frigate cameras on a native Roku app.
> It has worked well for me and my family. Due to limitations of Roku apps with streaming and
> go2rtc HLS limitations, certain decisions were made. Streaming often needs to be remuxed or
> re-encoded, so it may take time for your streams to start (5-15 seconds for me). I spent a lot
> of time working through this project to get it running as best as possible. I have not
> published the app to Roku due to time, so I'm offering the source code here, for free. Enjoy!

A native Roku SceneGraph channel for [Frigate NVR](https://frigate.video) 0.14+. It connects
directly to one or more Frigate servers over their HTTP APIs and go2rtc restream ports — there
is no cloud service, companion app, or third-party backend involved.

## What it is

Scuttle for Roku gives you:

- A **home screen** per configured server: a tab per server, a menu (Review / Explore /
  Recordings / Settings), and a grid of tiles — one per enabled camera — each showing a
  periodically refreshed live snapshot.
- A **full-screen live player** with audio: selecting a camera tile opens an HLS stream (video +
  AAC audio) served by go2rtc, with left/right camera switching and a thumbnail picker strip.
- **Review** playback: Frigate's alert/detection timeline, with thumbnails and one-key toggling
  between severities, each item playable as a recorded clip.
- **Explore** playback: the tracked-objects timeline with camera/label/time-window filters, each
  event playable as its recorded clip (when Frigate has one).
- **Recordings** playback: browse by camera → day → hour, with auto-advance into the next hour
  and ±30s seek.
- **Multiple servers**: add, edit, and switch between any number of Frigate servers, each with
  its own address and authentication settings.

## Roku platform constraints

A few limits of the Roku platform shape how the app works, and are worth understanding up front:

- **One video decoder.** A Roku can only decode one video stream at a time, so the home screen
  cannot show live video tiles for every camera simultaneously. Instead it polls each camera's
  JPEG snapshot endpoint on a short interval and displays those as the grid — full-motion live
  video is only available one camera at a time, in the full-screen player.
- **HLS only for live video.** The full-screen live player consumes Frigate's go2rtc restream as
  an HLS (`.m3u8`) stream. Raw RTSP is not used directly by the Roku.
- **Codec requirements.** The Roku's hardware decoder needs **H.264** video; audio must be
  **AAC**. Streams encoded any other way (e.g. H.265, or audio codecs like PCMU/PCMA/Opus) will
  fail to play or will play with no sound — see Troubleshooting below and the server
  requirements section for how to fix this in go2rtc.

## Frigate server requirements

- **Frigate 0.14 or newer.** The app talks to the `/api/config`, `/api/review`, `/api/events`,
  `/api/labels`, `/api/<camera>/recordings/summary`, and `/vod/...` endpoints as they exist in
  Frigate 0.14+; older Frigate versions are not supported.
- **go2rtc restream** must be configured for every camera you want to view live. The Roku
  reaches go2rtc directly over its HTTP port (default **1984**), so that port must be reachable
  from the Roku on your LAN — check firewall/VLAN rules if the Roku and Frigate are on separate
  network segments.
- **Audio: the go2rtc stream must carry AAC.** Frigate's default RTSP source is often
  video-only, or uses an audio codec the Roku can't decode. Add an AAC transcode leg to the
  camera's go2rtc stream, for example:

  ```yaml
  go2rtc:
    streams:
      front_door:
        - rtsp://user:pass@10.0.0.20:554/stream1
        - "ffmpeg:front_door#audio=aac"
  ```

  If the camera's video is not H.264 either, add `#video=h264` to the same transcode leg (e.g.
  `"ffmpeg:front_door#video=h264#audio=aac"`).

- **Auth modes.** The app supports three, matched to how Frigate is commonly deployed:
  - **None** — Frigate's API with no authentication (historically the default on port 5000).
  - **Frigate login** — Frigate's built-in authentication (port 8971), which issues a JWT the
    app stores and sends as `Authorization: Bearer <token>`, re-logging in automatically when it
    expires.
  - **HTTP basic** — for Frigate placed behind a reverse proxy that enforces its own basic-auth
    credentials; the app sends `Authorization: Basic <base64>`.

  Whichever mode protects the main Frigate API, **the go2rtc port itself is not authenticated**
  on the LAN (go2rtc has no auth mechanism of its own). This means anyone who can reach the
  go2rtc HTTP port can pull live video from your cameras without credentials, regardless of the
  auth mode configured above. Keep the go2rtc port off any network segment you don't trust, and
  don't forward it to the internet.

## Install

Short version: see [INSTALL.md](INSTALL.md).

1. Install [MediaMTX](https://github.com/bluenviron/mediamtx) on your Frigate server, next to
   Frigate, using the `mediamtx.yml` from the *Live video reliability* section below. Roku's
   player can't use go2rtc's own HLS, so this is what makes live video work; the app
   auto-detects it on port 8888.
2. Enable developer mode on your Roku (Home 3x, Up 2x, Right, Left, Right, Left, Right on the
   remote, then follow the on-screen instructions to set a device password and note the Roku's
   IP address).
3. Copy the environment template and fill in your Roku's details:

   ```bash
   cp .env.example .env
   ```

   Edit `.env`:

   ```
   ROKU_IP=192.168.1.50
   ROKU_DEV_PASSWORD=yourdevpassword
   ```

4. Deploy:

   ```bash
   ./deploy.sh
   ```

   This zips the channel and installs it to the Roku at `ROKU_IP` over the developer web
   installer. On first launch (no servers configured), the app opens straight to the server
   list — add a server there before continuing.

## Usage

Remote-key behavior differs by screen:

- **Home screen (server tabs / menu / camera grid).** Arrow keys move between three focus
  zones. From the top row of the camera grid, Up moves focus to the menu (Review / Explore /
  Recordings / Settings); from the menu, Up moves to the server tabs (only reachable focus point
  when multiple servers are configured) and Down returns to the grid. On the tabs, Left/Right
  switches the active server (reloading its cameras); Down or OK moves down to the menu. On the
  menu, Left/Right moves between items and OK opens the selected screen. On the grid, OK opens
  the full-screen live player for the focused camera.
- **Live player.** Left/Right switches to the previous/next camera (wrapping at both ends).
  Down or OK opens a thumbnail picker strip along the bottom; within the strip, Left/Right moves
  between cameras and OK jumps straight to the picked camera; Back closes the strip without
  switching. If a stream errors, OK retries it. The `*` key is not used on this screen. Back
  (outside the strip) returns to the home screen.
- **Review screen.** The `*` key toggles the list between Alerts and Detections and reloads it.
  OK on an item plays the recorded clip for that review segment.
- **Explore screen.** Up moves focus from the event grid to the filter chip row (Camera / Label
  / When). Left/Right moves between chips; OK cycles the focused chip's value and refetches the
  event list; Down returns focus to the grid. OK on an event plays its clip, when one exists.
- **Recordings screen.** Left/Right moves focus between the camera, day, and hour lists; OK on
  an item drills into the next list (camera → day → hour) or, on an hour, starts playback.
- **Playback (Review clips, Explore clips, Recordings hours).** Left/Right seeks back/forward 30
  seconds. When an hour finishes during Recordings playback, the next hour starts automatically;
  after the last hour, playback closes. If playback errors, OK retries.
- **Back**, on any screen, returns to the previous screen (or exits the channel from the home
  screen with no history).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Live view fails to play, or errors with a codec hint | The camera's go2rtc stream isn't H.264 video / AAC audio. Confirm from a PC with `http://<host>:1984/api/stream.m3u8?src=<cam>&mp4` in VLC — if that plays but the Roku doesn't, the codec is the problem, not connectivity. Add `#video=h264#audio=aac` to the camera's go2rtc stream config (see the server requirements section above) and restart go2rtc. |
| Live view can't connect at all | Confirm go2rtc's HTTP port (default 1984) is reachable from the Roku's network — test the same VLC URL as above from a machine on the same segment as the Roku. Firewalls or VLAN isolation between the Roku and Frigate are the usual cause. |
| Requests fail with a 401 / "Auth rejected" | The server's configured auth type doesn't match Frigate's. Check the auth type and credentials in Settings → Edit Server; for Frigate-login mode, confirm the username/password against Frigate's own login page. |
| Review or Explore list is always empty | Either the Frigate server is older than 0.14 (these endpoints/response shapes are not supported on earlier versions), or there genuinely are no review items / tracked-object events yet — check the Frigate web UI's own Review/Explore tabs for the same server. |
| Recordings has gaps or missing days/hours | Frigate's recording retention settings (`record.retain` / per-camera retention) control how long segments are kept; a gap in the day/hour list usually means retention already expired that period, not an app bug. |
| No audio during live view or playback | The stream's go2rtc config doesn't include an AAC audio leg. Follow the audio config snippet in the server requirements section to add `#audio=aac`. |

## Development

Two verification paths are available, depending on whether a physical Roku is at hand:

- **`./deploy.sh --test`** — builds and installs the channel, then launches it in test mode and
  runs the on-device BrightScript test suite. Test output streams over the Roku's debug console
  (telnet port 8085); the script itself connects to that port, captures the output to
  `out/test.log`, and prints the `[TESTS START]`…`[TESTS DONE]` (or `[TESTS FAILED]`) block. This
  requires a real Roku reachable at `ROKU_IP` with developer mode enabled.
- **`./check.sh`** — an off-device check that compiles the whole project with the BrighterScript
  compiler (`bsc`) and reports `CHECK OK` or `CHECK FAILED`. This doesn't touch a Roku at all; it
  only validates that the BrightScript/XML compiles, so it's useful for quick iteration or CI
  when no device is available, but it cannot substitute for `--test` or manual on-device
  verification of actual behavior.

`DEVICE_CHECKLIST.md` in the repo root tracks the full manual, on-device verification pass —
every checklist item across all tasks that could not be exercised without a physical Roku. Run
through it in order once a device is available.

## Screensaver and wall-dashboard use

Roku channels cannot disable the OS screensaver; only active video playback
suppresses it. When live view falls back to snapshot mode (refreshing stills),
Scuttle plays a tiny bundled black clip (`images/keepalive.mp4`) on loop
underneath the stills to keep the screensaver away, so a wall-mounted camera
dashboard is not interrupted. If Roku ever changes this behavior, the worst
case is the system screensaver appearing during snapshot mode — press any
button to dismiss it.

## Live video reliability (Roku vs go2rtc HLS)

Live video through go2rtc's HLS endpoint starts and then dies on Roku with
`mpr zero length playlist`. Empirically (tested against go2rtc 1.9.10, VLC
plays the same URLs fine): go2rtc serves 0.5-second segments and keeps only
~1 second of playlist window, for both MPEG-TS and fMP4 segment modes, and
regardless of the restream's GOP settings — its HLS is a debugging feature,
not a production packager. Roku's HLS player needs several seconds of
window and refuses to re-poll an empty playlist, so it cannot survive on
this. The app detects the error signature and shows a tip in the * overlay,
then falls back to full-resolution refreshing snapshots.

To get real live video on Roku, put a proper HLS packager next to Frigate
and point it at the same streams — MediaMTX is the lightest option:

```yaml
# mediamtx.yml — pulls from go2rtc's RTSP, serves spec-compliant HLS
hlsVariant: mpegts       # muxed TS: video AND audio play on Roku (even the
                         # cameras' 8kHz AAC as-is). fmp4 keeps audio in a
                         # separate rendition that corrupts Roku's demuxer.
hlsSegmentCount: 20      # ~40s of runway — Roku loses the live edge on less
hlsSegmentDuration: 1s
paths:
  "~^(.+)$":
    source: rtsp://127.0.0.1:8554/$G1
    sourceOnDemand: yes
```

Caveat: HEVC camera mains may not play over TS (Roku's HEVC-in-TS support
is spotty) — the h264 `_roku` restreams are the reliable route and carry
the audio. No `-ar` resampling is needed with mpegts.

MediaMTX then serves `http://<host>:8888/<stream>/index.m3u8`, which
Roku's player handles. **The app auto-detects MediaMTX**: on every connect it
probes the server's MediaMTX port (default 8888, editable per server) and,
when present, prefers it as the first route for every stream tier — and
clears any stored snapshot downgrade so video is retried immediately. A
wildcard path config means no per-camera setup:

```yaml
paths:
  "~^(.+)$":
    source: rtsp://127.0.0.1:8554/$G1
    sourceOnDemand: yes
```

Confirmed working end-to-end (Aug 2026): Roku plays HEVC camera mains via
MediaMTX's ~15s playlist window, where go2rtc's own HLS always failed.
