# Install (TL;DR)

**You need:** a Roku on the same network as your Frigate server, a computer with `git`, `zip`,
and `curl` (macOS/Linux have these; on Windows use WSL or Git Bash), Frigate 0.14+ with
go2rtc, and MediaMTX running next to Frigate (step 1).

## 1. Install MediaMTX on your Frigate server

Roku's video player can't play go2rtc's built-in HLS (it keeps too little playlist window), so
live video needs a proper HLS packager alongside Frigate. Install
[MediaMTX](https://github.com/bluenviron/mediamtx) on the same host as Frigate (a binary
release or the `bluenviron/mediamtx` Docker image) and use this `mediamtx.yml`:

```yaml
hlsVariant: mpegts
hlsSegmentCount: 20
hlsSegmentDuration: 1s
paths:
  "~^(.+)$":
    source: rtsp://127.0.0.1:8554/$G1
    sourceOnDemand: yes
```

Make sure port **8888** is reachable from the Roku. The app auto-detects MediaMTX on connect —
no per-camera setup is needed. See *Live video reliability* in the [README](README.md) for the
details and codec notes.

## 2. Put your Roku in developer mode

On the remote press: **Home ×3, Up ×2, Right, Left, Right, Left, Right**. Accept the agreement,
set a dev password, and note the IP address shown on screen.

## 3. Download the app

```bash
git clone https://github.com/kireol/frigate-roku.git
cd frigate-roku
```

(Or click **Code → Download ZIP** on GitHub, unzip it, and `cd` into the folder.)

## 4. Tell it where your Roku is

```bash
cp .env.example .env
```

Edit `.env` and set `ROKU_IP` and `ROKU_DEV_PASSWORD` to the values from step 2. The other
lines are optional.

## 5. Install it

```bash
./deploy.sh
```

You should see `Install OK`. The app launches on the Roku automatically.

## 6. Add your Frigate server

The first launch opens the server list. Add your Frigate address (e.g.
`http://192.168.1.10:8971`), pick the auth mode that matches your setup (None / Frigate login /
HTTP basic), and save. Your cameras appear on the home screen.

**Done.** The channel shows up as **Scuttle** on the Roku home screen. To update later:
`git pull && ./deploy.sh`.

## If something's off

- **Install FAILED** → check `ROKU_IP`/password in `.env`, and that dev mode is still enabled
  (it turns off if you factory reset).
- **Live video won't play / no sound** → go2rtc must serve **H.264 + AAC** and port **1984**
  must be reachable from the Roku. See *Frigate server requirements* in the
  [README](README.md) for the one-line go2rtc fix.
- **Cameras missing** → only cameras enabled in Frigate are shown.
