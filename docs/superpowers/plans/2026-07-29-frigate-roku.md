# Frigate Roku App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native Roku SceneGraph app that shows Frigate NVR camera grids (auto-refreshing snapshots), full-screen live HLS video with audio, and history playback (Review, Explore, Recordings) across multiple Frigate servers with per-server auth.

**Architecture:** Pure BrightScript/SceneGraph, no frameworks, talking directly to Frigate 0.14+ HTTP APIs. All HTTP runs in Task nodes; a single synchronous `ApiTask` handles auth (none/basic/Frigate JWT with auto re-login). Images requiring auth are downloaded to `tmp:/` because Poster can't send headers; Video nodes send auth via `ifHttpAgent` (`AddHeader`). Live video is HLS straight from go2rtc's HTTP port (Frigate does not proxy it).

**Tech Stack:** BrightScript, SceneGraph (Roku OS 10+), bash deploy script using Roku dev web API + ECP, on-device test runner read over the debug telnet console (port 8085).

## Global Constraints

- Frigate servers are 0.14+ only; current stable 0.16.x. No fallbacks for older versions.
- Server config fields (exact names, used everywhere): `id`, `name`, `baseUrl`, `go2rtcPort` (integer, default 1984), `authType` (`"none"` | `"basic"` | `"frigate"`), `username`, `password`, `token`.
- Frigate JWT is sent as `Authorization: Bearer <token>`; basic auth as `Authorization: Basic <base64>`.
- Live HLS URL shape: `http://<host-of-baseUrl>:<go2rtcPort>/api/stream.m3u8?src=<camera>&mp4`.
- Roku plays only H.264 (H.265 on newer models) + AAC; codec problems are fixed server-side, the app only surfaces hints.
- One video decoder: never more than one Video node playing.
- Authenticated images are always downloaded to `tmp:/` by a Task, never loaded by URL in a Poster.
- Sideload deployment only (developer mode). No store-certification work (no deep linking, no beacons).
- UI designed at 1920x1080 (`ui_resolutions=fhd`).
- No external BrightScript libraries or frameworks (no rooibos, no ropm).
- All source lives in `the repo root`. Commit after every task.
- Registry section name for persistence: `"frigate_servers"`, key `"servers"` (JSON array).

## Testing model (read once)

Pure-logic code is tested by an **on-device test runner**: `deploy.sh --test` sideloads the app, launches it with ECP query `RunTests=true`, and reads pass/fail lines from the Roku debug console (telnet port 8085). `Main()` sees `args.RunTests` and runs `RunAllTests()` instead of the UI. A task's "run test" step means: `./deploy.sh --test` and read the console output. UI screens are verified manually (checklists in their tasks) since there is no display automation.

`.env` (untracked) must exist with `ROKU_IP=<device ip>` and `ROKU_DEV_PASSWORD=<dev password>`. If no Roku is reachable, mark the task's device steps as blocked and stop — do not fake results.

---

### Task 1: Project skeleton + deploy script

**Files:**
- Create: `manifest`
- Create: `.gitignore`, `.env.example`
- Create: `tools/make_placeholder_images.py`
- Create: `source/Main.brs`
- Create: `components/AppScene.xml`, `components/AppScene.brs`
- Create: `deploy.sh`

**Interfaces:**
- Produces: `AppScene` (scene component all screens attach into; has function `AddScreen`/`RemoveScreen` added in Task 6), `deploy.sh` (plain deploy) and `deploy.sh --test` (test mode, completed in Task 2).

- [ ] **Step 1: Write manifest, .gitignore, .env.example**

`manifest` (note: manifest has no comments and no blank first line):

```
title=Frigate
major_version=0
minor_version=1
build_version=1
mm_icon_focus_hd=pkg:/images/icon_focus_hd.png
mm_icon_focus_sd=pkg:/images/icon_focus_sd.png
splash_screen_fhd=pkg:/images/splash_fhd.png
splash_screen_hd=pkg:/images/splash_hd.png
splash_screen_sd=pkg:/images/splash_sd.png
splash_color=#101418
ui_resolutions=fhd
```

`.gitignore`:

```
.env
out/
__pycache__/
```

`.env.example`:

```
ROKU_IP=192.168.1.50
ROKU_DEV_PASSWORD=yourdevpassword
```

- [ ] **Step 2: Generate placeholder images**

`tools/make_placeholder_images.py` — writes solid-color PNGs with only stdlib:

```python
#!/usr/bin/env python3
"""Generate solid-color placeholder PNGs for the Roku manifest."""
import os, struct, zlib

def write_png(path, w, h, rgb):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    row = b"\x00" + bytes(rgb) * w
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(row * h))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)

os.makedirs("images", exist_ok=True)
teal = (16, 84, 92)
write_png("images/icon_focus_hd.png", 290, 218, teal)
write_png("images/icon_focus_sd.png", 246, 140, teal)
write_png("images/splash_fhd.png", 1920, 1080, (16, 20, 24))
write_png("images/splash_hd.png", 1280, 720, (16, 20, 24))
write_png("images/splash_sd.png", 720, 480, (16, 20, 24))
print("wrote images/")
```

Run: `python3 tools/make_placeholder_images.py`
Expected: `wrote images/` and 5 PNGs under `images/`. Commit the PNGs (they are tiny).

- [ ] **Step 3: Write Main.brs and AppScene**

`source/Main.brs`:

```brightscript
sub Main(args as dynamic)
    if args <> invalid and args.RunTests <> invalid
        RunAllTests()
        return
    end if
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("AppScene")
    screen.Show()
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        end if
    end while
end sub

' Replaced by the real runner in Task 2; needed so RunTests launches compile.
sub RunAllTests()
    print "[TESTS START]"
    print "[TESTS DONE]"
end sub
```

`components/AppScene.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="AppScene" extends="Scene">
    <script type="text/brightscript" uri="pkg:/components/AppScene.brs" />
    <children>
        <Rectangle id="background" width="1920" height="1080" color="0x101418FF" />
        <Label id="placeholder" text="Frigate for Roku — skeleton OK"
               translation="[760, 520]" color="0xE0E6EAFF" />
    </children>
</component>
```

`components/AppScene.brs`:

```brightscript
sub init()
    m.top.backgroundColor = "0x101418FF"
    m.top.backgroundUri = ""
end sub
```

- [ ] **Step 4: Write deploy.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
[[ -f .env ]] || { echo "Missing .env (copy .env.example)"; exit 1; }
source .env

mkdir -p out
rm -f out/app.zip
zip -rq out/app.zip manifest source components images

# Exit any running channel so install always succeeds
curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/keypress/Home"
sleep 1

RESULT=$(curl -s --user "rokudev:$ROKU_DEV_PASSWORD" --digest \
    -F "mysubmit=Install" -F "archive=@out/app.zip" \
    "http://$ROKU_IP/plugin_install")
if echo "$RESULT" | grep -qE "Install Success|Identical to previous version"; then
    echo "Install OK"
else
    echo "Install FAILED"; echo "$RESULT" | grep -oE "<font[^>]*>[^<]*" | head -5
    exit 1
fi

if [[ "${1:-}" == "--test" ]]; then
    LOG=out/test.log
    : > "$LOG"
    # Connect console BEFORE launching so no output is missed
    ( timeout 40 nc "$ROKU_IP" 8085 > "$LOG" 2>/dev/null || true ) &
    NC_PID=$!
    sleep 1
    curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/launch/dev?RunTests=true"
    for _ in $(seq 1 35); do
        grep -q "\[TESTS DONE\]\|\[TESTS FAILED\]" "$LOG" && break
        sleep 1
    done
    kill "$NC_PID" 2>/dev/null || true
    sed -n '/\[TESTS START\]/,/\[TESTS DONE\]\|\[TESTS FAILED\]/p' "$LOG"
    grep -q "\[TESTS DONE\]" "$LOG" && exit 0
    echo "TESTS FAILED (or no output)"; exit 1
fi
```

Run: `chmod +x deploy.sh`

- [ ] **Step 5: Deploy and verify**

Run: `./deploy.sh`
Expected: `Install OK`, and the TV shows "Frigate for Roku — skeleton OK".

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: project skeleton, manifest, deploy script"
```

---

### Task 2: On-device test harness

**Files:**
- Create: `source/tests/TestRunner.brs`
- Modify: `source/Main.brs` (delete the placeholder `RunAllTests`)

**Interfaces:**
- Produces: `T(name as string, cond as boolean, r as object)` assertion helper; `RunAllTests()` which each later logic task extends by adding one `Test_Xxx(r)` call; `[TESTS START]`/`[TESTS DONE]`/`[TESTS FAILED]` console protocol consumed by `deploy.sh --test`.

- [ ] **Step 1: Write the runner with a failing sanity test**

`source/tests/TestRunner.brs`:

```brightscript
sub T(name as string, cond as boolean, r as object)
    if cond
        r.passed = r.passed + 1
        print "  PASS: "; name
    else
        r.failed = r.failed + 1
        print "  FAIL: "; name
    end if
end sub

sub RunAllTests()
    print "[TESTS START]"
    r = {passed: 0, failed: 0}
    Test_Sanity(r)
    print "passed: "; r.passed; " failed: "; r.failed
    if r.failed > 0
        print "[TESTS FAILED]"
    else
        print "[TESTS DONE]"
    end if
end sub

sub Test_Sanity(r as object)
    print "Test_Sanity"
    T("math works", 1 + 1 = 3, r)  ' deliberately failing first
end sub
```

Remove the placeholder `RunAllTests` sub from `source/Main.brs` (all `source/*.brs` files share one scope, so the runner is visible to `Main`).

- [ ] **Step 2: Run and verify it fails**

Run: `./deploy.sh --test`
Expected: output contains `FAIL: math works` and `[TESTS FAILED]`, exit code 1.

- [ ] **Step 3: Fix the sanity test**

Change the assertion to `1 + 1 = 2`.

- [ ] **Step 4: Run and verify it passes**

Run: `./deploy.sh --test`
Expected: `PASS: math works`, `[TESTS DONE]`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: on-device test harness over debug console"
```

---

### Task 3: ServerStore (registry persistence)

**Files:**
- Create: `source/ServerStore.brs`
- Modify: `source/tests/TestRunner.brs` (add `Test_ServerStore(r)` call in `RunAllTests`)
- Create: `source/tests/Test_ServerStore.brs`

**Interfaces:**
- Produces:
  - `ServerStore_Load() as object` — array of server AAs (order preserved)
  - `ServerStore_SaveAll(servers as object)` — writes whole array
  - `ServerStore_Upsert(server as object)` — insert or replace by `id`, then save
  - `ServerStore_Delete(id as string)`
  - `ServerStore_GetById(id as string) as dynamic` — server AA or invalid
  - `ServerStore_NewServer() as object` — fresh AA with all Global-Constraints fields defaulted (`go2rtcPort: 1984`, `authType: "none"`, empty strings elsewhere, generated `id`)

- [ ] **Step 1: Write failing tests**

`source/tests/Test_ServerStore.brs`:

```brightscript
sub Test_ServerStore(r as object)
    print "Test_ServerStore"
    ' isolate: wipe section first
    sec = CreateObject("roRegistrySection", "frigate_servers")
    sec.Delete("servers")
    sec.Flush()

    T("load empty returns []", ServerStore_Load().Count() = 0, r)

    s = ServerStore_NewServer()
    T("new server has id", s.id <> "", r)
    T("new server defaults go2rtcPort", s.go2rtcPort = 1984, r)
    T("new server defaults authType", s.authType = "none", r)

    s.name = "Home"
    s.baseUrl = "http://10.0.0.5:8971"
    ServerStore_Upsert(s)
    loaded = ServerStore_Load()
    T("upsert inserts", loaded.Count() = 1, r)
    T("fields persist", loaded[0].name = "Home" and loaded[0].baseUrl = "http://10.0.0.5:8971", r)

    s.name = "Home2"
    ServerStore_Upsert(s)
    loaded = ServerStore_Load()
    T("upsert replaces by id", loaded.Count() = 1 and loaded[0].name = "Home2", r)

    T("getById finds", ServerStore_GetById(s.id).name = "Home2", r)
    T("getById miss is invalid", ServerStore_GetById("nope") = invalid, r)

    ServerStore_Delete(s.id)
    T("delete removes", ServerStore_Load().Count() = 0, r)
end sub
```

In `RunAllTests`, add `Test_ServerStore(r)` after `Test_Sanity(r)`.

- [ ] **Step 2: Run to verify failure**

Run: `./deploy.sh --test`
Expected: compile error on the console (`ServerStore_Load` not found) or FAILs — either counts as the failing state.

- [ ] **Step 3: Implement ServerStore**

`source/ServerStore.brs`:

```brightscript
function ServerStore_Section() as object
    return CreateObject("roRegistrySection", "frigate_servers")
end function

function ServerStore_Load() as object
    sec = ServerStore_Section()
    if sec.Exists("servers")
        data = ParseJson(sec.Read("servers"))
        if data <> invalid and GetInterface(data, "ifArray") <> invalid then return data
    end if
    return []
end function

sub ServerStore_SaveAll(servers as object)
    sec = ServerStore_Section()
    sec.Write("servers", FormatJson(servers))
    sec.Flush()
end sub

sub ServerStore_Upsert(server as object)
    servers = ServerStore_Load()
    replaced = false
    for i = 0 to servers.Count() - 1
        if servers[i].id = server.id
            servers[i] = server
            replaced = true
            exit for
        end if
    end for
    if not replaced then servers.Push(server)
    ServerStore_SaveAll(servers)
end sub

sub ServerStore_Delete(id as string)
    servers = ServerStore_Load()
    kept = []
    for each s in servers
        if s.id <> id then kept.Push(s)
    end for
    ServerStore_SaveAll(kept)
end sub

function ServerStore_GetById(id as string) as dynamic
    for each s in ServerStore_Load()
        if s.id = id then return s
    end for
    return invalid
end function

function ServerStore_NewServer() as object
    di = CreateObject("roDeviceInfo")
    return {
        id: di.GetRandomUUID()
        name: ""
        baseUrl: ""
        go2rtcPort: 1984
        authType: "none"
        username: ""
        password: ""
        token: ""
    }
end function
```

- [ ] **Step 4: Run to verify pass**

Run: `./deploy.sh --test`
Expected: all `Test_ServerStore` asserts PASS, `[TESTS DONE]`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: server config persistence in registry"
```

---

### Task 4: URL builders + auth helpers (pure logic)

**Files:**
- Create: `source/FrigateUrls.brs`
- Create: `source/tests/Test_FrigateUrls.brs`
- Modify: `source/tests/TestRunner.brs` (add `Test_FrigateUrls(r)`)

**Interfaces:**
- Produces (all pure; `server` is a ServerStore AA):
  - `Frigate_NormalizeBaseUrl(url as string) as string` — trims, prepends `http://` if no scheme, strips trailing `/`
  - `Frigate_HostFromUrl(url as string) as string` — host only, no scheme/port/path
  - `Frigate_AuthHeaders(server as object) as object` — `{}` | `{Authorization: "Basic ..."}` | `{Authorization: "Bearer ..."}` (bearer only when `token <> ""`)
  - `Frigate_ParseTokenFromSetCookie(setCookieValue as string) as string` — value of `frigate_token`, `""` if absent
  - `Frigate_LiveHlsUrl(server, cameraName as string) as string`
  - `Frigate_SnapshotPath(cameraName as string, height as integer) as string` — `/api/<cam>/latest.jpg?height=<h>`
  - `Frigate_EventThumbPath(eventId as string) as string` — `/api/events/<id>/thumbnail.jpg`
  - `Frigate_EventClipPath(eventId as string) as string` — `/api/events/<id>/clip.mp4`
  - `Frigate_VodRangeUrl(server, cameraName, startTs as double, endTs as double) as string` — `<base>/vod/<cam>/start/<s>/end/<e>/master.m3u8` (timestamps as integer-seconds strings)
  - `Frigate_VodHourUrl(server, yearMonth as string, day as string, hour as string, cameraName as string, tz as string) as string` — `<base>/vod/<ym>/<dd>/<hh>/<cam>/<tz-with-slashes-as-commas>/master.m3u8`
  - `Frigate_UrlEncode(s as string) as string`
  - `TimeUtil_FormatEpoch(epoch as double) as string` — local `"Jul 29 11:04 PM"` style

- [ ] **Step 1: Write failing tests**

`source/tests/Test_FrigateUrls.brs`:

```brightscript
sub Test_FrigateUrls(r as object)
    print "Test_FrigateUrls"
    T("normalize adds scheme", Frigate_NormalizeBaseUrl("10.0.0.5:8971") = "http://10.0.0.5:8971", r)
    T("normalize strips slash", Frigate_NormalizeBaseUrl("https://nvr.lan:8971/") = "https://nvr.lan:8971", r)
    T("host from url", Frigate_HostFromUrl("http://10.0.0.5:8971") = "10.0.0.5", r)
    T("host no port", Frigate_HostFromUrl("https://nvr.lan") = "nvr.lan", r)

    s = ServerStore_NewServer()
    s.baseUrl = "http://10.0.0.5:8971"
    T("auth none empty", Frigate_AuthHeaders(s).Count() = 0, r)

    s.authType = "basic"
    s.username = "user"
    s.password = "pass"
    h = Frigate_AuthHeaders(s)
    T("basic header", h.Authorization = "Basic dXNlcjpwYXNz", r)

    s.authType = "frigate"
    s.token = ""
    T("frigate no token empty", Frigate_AuthHeaders(s).Count() = 0, r)
    s.token = "abc"
    T("bearer header", Frigate_AuthHeaders(s).Authorization = "Bearer abc", r)

    ck = "frigate_token=eyJx.y.z; expires=Sat, 01 Aug 2026 00:00:00 GMT; Path=/"
    T("parse cookie", Frigate_ParseTokenFromSetCookie(ck) = "eyJx.y.z", r)
    T("parse cookie miss", Frigate_ParseTokenFromSetCookie("other=1; Path=/") = "", r)

    T("live hls", Frigate_LiveHlsUrl(s, "front_door") = "http://10.0.0.5:1984/api/stream.m3u8?src=front_door&mp4", r)
    T("snapshot path", Frigate_SnapshotPath("front_door", 360) = "/api/front_door/latest.jpg?height=360", r)
    T("event thumb", Frigate_EventThumbPath("171234.5-abcd") = "/api/events/171234.5-abcd/thumbnail.jpg", r)
    T("event clip", Frigate_EventClipPath("171234.5-abcd") = "/api/events/171234.5-abcd/clip.mp4", r)
    T("vod range", Frigate_VodRangeUrl(s, "cam", 1753828000.4, 1753828060.9) = "http://10.0.0.5:8971/vod/cam/start/1753828000/end/1753828061/master.m3u8", r)
    T("vod hour tz commas", Frigate_VodHourUrl(s, "2026-07", "29", "23", "cam", "America/New_York") = "http://10.0.0.5:8971/vod/2026-07/29/23/cam/America,New_York/master.m3u8", r)
    T("urlencode", Frigate_UrlEncode("a b&c") = "a%20b%26c", r)
end sub
```

Add `Test_FrigateUrls(r)` to `RunAllTests`.

- [ ] **Step 2: Run to verify failure**

Run: `./deploy.sh --test`
Expected: compile error / FAILs.

- [ ] **Step 3: Implement**

`source/FrigateUrls.brs`:

```brightscript
function Frigate_NormalizeBaseUrl(url as string) as string
    u = url.Trim()
    if u = "" then return ""
    if Left(u, 7) <> "http://" and Left(u, 8) <> "https://"
        u = "http://" + u
    end if
    while Right(u, 1) = "/"
        u = Left(u, Len(u) - 1)
    end while
    return u
end function

function Frigate_HostFromUrl(url as string) as string
    u = Frigate_NormalizeBaseUrl(url)
    ' strip scheme
    p = Instr(1, u, "://")
    if p > 0 then u = Mid(u, p + 3)
    ' strip path
    p = Instr(1, u, "/")
    if p > 0 then u = Left(u, p - 1)
    ' strip port
    p = Instr(1, u, ":")
    if p > 0 then u = Left(u, p - 1)
    return u
end function

function Frigate_AuthHeaders(server as object) as object
    if server.authType = "basic"
        ba = CreateObject("roByteArray")
        ba.FromAsciiString(server.username + ":" + server.password)
        return { Authorization: "Basic " + ba.ToBase64String() }
    else if server.authType = "frigate" and server.token <> ""
        return { Authorization: "Bearer " + server.token }
    end if
    return {}
end function

function Frigate_ParseTokenFromSetCookie(setCookieValue as string) as string
    p = Instr(1, setCookieValue, "frigate_token=")
    if p = 0 then return ""
    rest = Mid(setCookieValue, p + Len("frigate_token="))
    semi = Instr(1, rest, ";")
    if semi > 0 then rest = Left(rest, semi - 1)
    return rest.Trim()
end function

function Frigate_LiveHlsUrl(server as object, cameraName as string) as string
    host = Frigate_HostFromUrl(server.baseUrl)
    return "http://" + host + ":" + StrI(server.go2rtcPort).Trim() + "/api/stream.m3u8?src=" + Frigate_UrlEncode(cameraName) + "&mp4"
end function

function Frigate_SnapshotPath(cameraName as string, height as integer) as string
    return "/api/" + cameraName + "/latest.jpg?height=" + StrI(height).Trim()
end function

function Frigate_EventThumbPath(eventId as string) as string
    return "/api/events/" + eventId + "/thumbnail.jpg"
end function

function Frigate_EventClipPath(eventId as string) as string
    return "/api/events/" + eventId + "/clip.mp4"
end function

function Frigate_VodRangeUrl(server as object, cameraName as string, startTs as double, endTs as double) as string
    s = StrI(Int(startTs)).Trim()
    e = StrI(Int(endTs + 0.999)).Trim()
    return server.baseUrl + "/vod/" + cameraName + "/start/" + s + "/end/" + e + "/master.m3u8"
end function

function Frigate_VodHourUrl(server as object, yearMonth as string, day as string, hour as string, cameraName as string, tz as string) as string
    tzSafe = tz.Replace("/", ",")
    return server.baseUrl + "/vod/" + yearMonth + "/" + day + "/" + hour + "/" + cameraName + "/" + tzSafe + "/master.m3u8"
end function

function Frigate_UrlEncode(s as string) as string
    x = CreateObject("roUrlTransfer")
    return x.Escape(s)
end function

function TimeUtil_FormatEpoch(epoch as double) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(Int(epoch))
    dt.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    hr = dt.GetHours()
    ampm = "AM"
    if hr >= 12 then ampm = "PM"
    if hr = 0 then hr = 12
    if hr > 12 then hr = hr - 12
    mins = StrI(dt.GetMinutes()).Trim()
    if Len(mins) = 1 then mins = "0" + mins
    return months[dt.GetMonth() - 1] + " " + StrI(dt.GetDayOfMonth()).Trim() + " " + StrI(hr).Trim() + ":" + mins + " " + ampm
end function
```

Note: `roUrlTransfer` cannot be created inside SceneGraph render-thread component scripts. `Frigate_UrlEncode` is only ever called from Task threads or `Main` (tests) — keep it that way.

- [ ] **Step 4: Run to verify pass**

Run: `./deploy.sh --test`
Expected: all `Test_FrigateUrls` asserts PASS, `[TESTS DONE]`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: frigate url builders and auth helpers"
```

---

### Task 5: ApiTask — synchronous HTTP with auth + auto re-login

**Files:**
- Create: `components/tasks/ApiTask.xml`
- Create: `components/tasks/ApiTask.brs`

**Interfaces:**
- Consumes: `Frigate_AuthHeaders`, `Frigate_ParseTokenFromSetCookie`, `Frigate_NormalizeBaseUrl` (Task 4); server AA shape (Task 3).
- Produces: Task node `ApiTask` used by every screen:
  - field `input` (assocarray): `{ server: <server AA>, path: "/api/..." or absolute "http..." URL, method: "GET"|"POST", body: string, savePath: string ("" → return body as string; else download to file), context: any }`
  - field `output` (assocarray, set once): `{ ok: boolean, status: integer, body: string, savePath: string, newToken: string, error: string, context: any }`
  - `newToken <> ""` means the task re-logged-in; the observer must persist it: `srv = ServerStore_GetById(server.id) : if srv <> invalid then srv.token = out.newToken : ServerStore_Upsert(srv)`.
  - Usage pattern from any component (render thread):
    ```brightscript
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/config", method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onConfigResponse")
    t.control = "RUN"
    m.pendingTask = t   ' keep a reference or the task may be GC'd
    ```

- [ ] **Step 1: Write the component**

`components/tasks/ApiTask.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ApiTask" extends="Task">
    <interface>
        <field id="input" type="assocarray" />
        <field id="output" type="assocarray" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/tasks/ApiTask.brs" />
    <script type="text/brightscript" uri="pkg:/source/FrigateUrls.brs" />
</component>
```

`components/tasks/ApiTask.brs`:

```brightscript
sub init()
    m.top.functionName = "run"
end sub

sub run()
    req = m.top.input
    server = req.server
    url = req.path
    if Left(url, 4) <> "http" then url = server.baseUrl + url

    headers = Frigate_AuthHeaders(server)
    res = doRequest(url, headers, req.method, req.body, req.savePath)

    newToken = ""
    if res.status = 401 and server.authType = "frigate" and server.username <> ""
        token = doLogin(server)
        if token <> ""
            newToken = token
            server2 = {}
            server2.Append(server)
            server2.token = token
            headers = Frigate_AuthHeaders(server2)
            res = doRequest(url, headers, req.method, req.body, req.savePath)
        end if
    end if

    out = {
        ok: (res.status >= 200 and res.status < 300)
        status: res.status
        body: res.body
        savePath: req.savePath
        newToken: newToken
        error: res.error
        context: req.context
    }
    m.top.output = out
end sub

' Synchronous request. Returns { status, body, headersArray, error }
function doRequest(url as string, headers as object, method as string, body as string, savePath as string) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.RetainBodyOnError(true)
    xfer.EnableEncodings(true)
    if Left(url, 8) = "https://"
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.InitClientCertificates()
    end if
    for each k in headers
        xfer.AddHeader(k, headers[k])
    end for

    started = false
    if method = "POST"
        xfer.AddHeader("Content-Type", "application/json")
        started = xfer.AsyncPostFromString(body)
    else if savePath <> ""
        started = xfer.AsyncGetToFile(savePath)
    else
        started = xfer.AsyncGetToString()
    end if
    if not started then return { status: 0, body: "", headersArray: [], error: "request failed to start" }

    msg = wait(15000, port)
    if msg = invalid
        xfer.AsyncCancel()
        return { status: 0, body: "", headersArray: [], error: "timeout" }
    end if
    if type(msg) = "roUrlEvent"
        status = msg.GetResponseCode()
        err = ""
        if status < 0 then err = msg.GetFailureReason()
        return { status: status, body: msg.GetString(), headersArray: msg.GetResponseHeadersArray(), error: err }
    end if
    return { status: 0, body: "", headersArray: [], error: "unexpected event" }
end function

' Returns JWT string or ""
function doLogin(server as object) as string
    body = FormatJson({ user: server.username, password: server.password })
    res = doRequest(server.baseUrl + "/api/login", {}, "POST", body, "")
    if res.status < 200 or res.status >= 300 then return ""
    for each entry in res.headersArray
        for each k in entry
            if LCase(k) = "set-cookie"
                token = Frigate_ParseTokenFromSetCookie(entry[k])
                if token <> "" then return token
            end if
        end for
    end for
    return ""
end function
```

- [ ] **Step 2: Compile check on device**

Run: `./deploy.sh --test`
Expected: install OK and existing tests still print `[TESTS DONE]` (a BrightScript compile error in the new component would abort launch — watch the console output for `Syntax Error` lines).

Functional verification of ApiTask against a real Frigate server happens in Task 6's Test Connection checklist (network behavior is not unit-testable on device without a live server).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: ApiTask with basic/bearer auth and auto re-login"
```

---

### Task 6: Navigation framework + Settings/Servers screens

**Files:**
- Modify: `components/AppScene.xml`, `components/AppScene.brs`
- Create: `components/screens/ServerListScreen.xml`, `components/screens/ServerListScreen.brs`
- Create: `components/screens/ServerEditScreen.xml`, `components/screens/ServerEditScreen.brs`

**Interfaces:**
- Consumes: `ServerStore_*` (Task 3), `ApiTask` (Task 5).
- Produces:
  - `AppScene` navigation: `PushScreen(screenNode)` / `PopScreen()` implemented via scene functions exposed on a scene interface function field. Screens are Group-based components; each gets `m.top.appScene` set before push; screens signal close by setting their own boolean field `closeMe = true` (AppScene observes it).
  - Every screen component has: field `closeMe` (bool), field `wasShown` (bool, set by AppScene on push/resume so screens can refresh).
  - `ServerListScreen` — entry point for settings; also the app's first screen when no servers exist.

- [ ] **Step 1: Navigation in AppScene**

`components/AppScene.xml` (replace placeholder children):

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="AppScene" extends="Scene">
    <script type="text/brightscript" uri="pkg:/components/AppScene.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Rectangle id="background" width="1920" height="1080" color="0x101418FF" />
        <Group id="screenHost" />
    </children>
</component>
```

`components/AppScene.brs`:

```brightscript
sub init()
    m.host = m.top.FindNode("screenHost")
    m.screens = []
    m.top.ObserveField("wasShown", "onSceneShown")
    ShowFirstScreen()
end sub

sub ShowFirstScreen()
    servers = ServerStore_Load()
    if servers.Count() = 0
        PushScreen(CreateObject("roSGNode", "ServerListScreen"))
    else
        ' HomeScreen exists from Task 7 onward; until then ServerListScreen is home
        if CreateObject("roSGNode", "HomeScreen") <> invalid
            PushScreen(CreateObject("roSGNode", "HomeScreen"))
        else
            PushScreen(CreateObject("roSGNode", "ServerListScreen"))
        end if
    end if
end sub

sub onSceneShown()
end sub

sub PushScreen(screen as object)
    if m.screens.Count() > 0
        top = m.screens[m.screens.Count() - 1]
        top.visible = false
    end if
    screen.ObserveFieldScoped("closeMe", "onScreenClose")
    m.screens.Push(screen)
    m.host.AppendChild(screen)
    screen.wasShown = true
    screen.SetFocus(true)
end sub

sub PopScreen()
    if m.screens.Count() <= 1 then return
    screen = m.screens.Pop()
    m.host.RemoveChild(screen)
    top = m.screens[m.screens.Count() - 1]
    top.visible = true
    top.wasShown = true
    top.SetFocus(true)
end sub

sub onScreenClose(ev as object)
    if ev.GetData() = true then PopScreen()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back"
        if m.screens.Count() > 1
            PopScreen()
            return true
        end if
    end if
    return false
end function
```

Screens navigate by calling functions on the scene via a callFunc-style pattern. To keep it simple, every screen does: `m.top.GetScene().CallFunc("pushScreen", node)`. Add to `AppScene.xml` interface:

```xml
    <interface>
        <function name="pushScreen" />
    </interface>
```

and in `AppScene.brs`:

```brightscript
function pushScreen(screen as object) as boolean
    PushScreen(screen)
    return true
end function
```

- [ ] **Step 2: ServerListScreen**

`components/screens/ServerListScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ServerListScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/ServerListScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Label id="title" text="Frigate Servers" translation="[120, 60]"
               color="0xE0E6EAFF" font="font:LargeBoldSystemFont" />
        <Label id="hint" text="OK: edit   *: not used   Back: return"
               translation="[120, 130]" color="0x8A959CFF" />
        <LabelList id="list" translation="[120, 190]" itemSize="[800, 64]"
                   numRows="10" focusBitmapUri="" color="0xE0E6EAFF" focusedColor="0x10545CFF" />
    </children>
</component>
```

`components/screens/ServerListScreen.brs`:

```brightscript
sub init()
    m.list = m.top.FindNode("list")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("wasShown", "refresh")
    refresh()
end sub

sub refresh()
    m.servers = ServerStore_Load()
    content = CreateObject("roSGNode", "ContentNode")
    for each s in m.servers
        item = content.CreateChild("ContentNode")
        item.title = s.name + "  (" + s.baseUrl + ")"
    end for
    addItem = content.CreateChild("ContentNode")
    addItem.title = "+ Add Server"
    m.list.content = content
    m.list.SetFocus(true)
end sub

sub onSelect()
    idx = m.list.itemSelected
    edit = CreateObject("roSGNode", "ServerEditScreen")
    if idx < m.servers.Count()
        edit.serverId = m.servers[idx].id
    end if
    m.top.GetScene().CallFunc("pushScreen", edit)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
```

- [ ] **Step 3: ServerEditScreen**

A vertical `LabelList` of editable fields; OK on a text field opens a `KeyboardDialog` (a `StandardKeyboardDialog` from `roSGNode`), OK on "Auth type" cycles the three values, and three action rows: Test Connection, Save, Delete.

`components/screens/ServerEditScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ServerEditScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
        <field id="serverId" type="string" value="" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/ServerEditScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Label id="title" text="Edit Server" translation="[120, 60]"
               color="0xE0E6EAFF" font="font:LargeBoldSystemFont" />
        <LabelList id="list" translation="[120, 160]" itemSize="[1000, 60]"
                   numRows="12" color="0xE0E6EAFF" focusedColor="0x10545CFF" />
        <Label id="status" translation="[120, 920]" color="0x8A959CFF" text="" width="1400" />
    </children>
</component>
```

`components/screens/ServerEditScreen.brs`:

```brightscript
sub init()
    m.list = m.top.FindNode("list")
    m.status = m.top.FindNode("status")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("serverId", "loadServer")
    m.top.ObserveField("wasShown", "onShown")
    m.server = ServerStore_NewServer()
    m.pendingTask = invalid
    m.dialog = invalid
    rebuild()
end sub

sub onShown()
    m.list.SetFocus(true)
end sub

sub loadServer()
    if m.top.serverId <> ""
        existing = ServerStore_GetById(m.top.serverId)
        if existing <> invalid then m.server = existing
    end if
    rebuild()
end sub

function rows() as object
    authLabel = m.server.authType
    return [
        { key: "name", title: "Name: " + m.server.name },
        { key: "baseUrl", title: "URL: " + m.server.baseUrl },
        { key: "go2rtcPort", title: "go2rtc port: " + StrI(m.server.go2rtcPort).Trim() },
        { key: "authType", title: "Auth type: " + authLabel + "  (OK cycles)" },
        { key: "username", title: "Username: " + m.server.username },
        { key: "password", title: "Password: " + String(Len(m.server.password), "*") },
        { key: "test", title: "▶ Test Connection" },
        { key: "save", title: "✔ Save" },
        { key: "delete", title: "✖ Delete Server" }
    ]
end function

sub rebuild()
    content = CreateObject("roSGNode", "ContentNode")
    for each row in rows()
        item = content.CreateChild("ContentNode")
        item.title = row.title
    end for
    m.list.content = content
end sub

sub onSelect()
    row = rows()[m.list.itemSelected]
    if row.key = "authType"
        order = ["none", "basic", "frigate"]
        for i = 0 to 2
            if order[i] = m.server.authType
                m.server.authType = order[(i + 1) mod 3]
                exit for
            end if
        end for
        rebuild()
    else if row.key = "test"
        testConnection()
    else if row.key = "save"
        m.server.baseUrl = Frigate_NormalizeBaseUrl_Render(m.server.baseUrl)
        ServerStore_Upsert(m.server)
        m.top.closeMe = true
    else if row.key = "delete"
        ServerStore_Delete(m.server.id)
        m.top.closeMe = true
    else
        openKeyboard(row.key)
    end if
end sub

' Render-thread-safe normalize (no roUrlTransfer): duplicate of trim logic
function Frigate_NormalizeBaseUrl_Render(url as string) as string
    u = url.Trim()
    if u = "" then return ""
    if Left(u, 7) <> "http://" and Left(u, 8) <> "https://" then u = "http://" + u
    while Right(u, 1) = "/"
        u = Left(u, Len(u) - 1)
    end while
    return u
end function

sub openKeyboard(fieldKey as string)
    m.editingKey = fieldKey
    d = CreateObject("roSGNode", "StandardKeyboardDialog")
    d.title = "Enter " + fieldKey
    current = m.server[fieldKey]
    if fieldKey = "go2rtcPort" then current = StrI(m.server.go2rtcPort).Trim()
    d.text = current
    d.buttons = ["OK", "Cancel"]
    d.ObserveFieldScoped("buttonSelected", "onKeyboardButton")
    m.dialog = d
    m.top.GetScene().dialog = d
end sub

sub onKeyboardButton()
    d = m.dialog
    if d.buttonSelected = 0
        value = d.text
        if m.editingKey = "go2rtcPort"
            m.server.go2rtcPort = Val(value)
            if m.server.go2rtcPort = 0 then m.server.go2rtcPort = 1984
        else
            m.server[m.editingKey] = value
        end if
        rebuild()
    end if
    d.close = true
    m.dialog = invalid
end sub

sub testConnection()
    m.status.text = "Testing " + m.server.baseUrl + " ..."
    m.server.baseUrl = Frigate_NormalizeBaseUrl_Render(m.server.baseUrl)
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/config", method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onTestResult")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onTestResult(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    if out.newToken <> ""
        m.server.token = out.newToken
    end if
    if out.ok
        cfg = ParseJson(out.body)
        if cfg <> invalid and cfg.cameras <> invalid
            names = []
            for each cam in cfg.cameras
                names.Push(cam)
            end for
            version = ""
            if cfg.version <> invalid then version = " v" + cfg.version
            m.status.text = "OK" + version + " — " + StrI(names.Count()).Trim() + " cameras found"
        else
            m.status.text = "Connected, but response is not a Frigate config"
        end if
    else if out.status = 401
        m.status.text = "Auth rejected (401) — check auth type / credentials"
    else if out.status = 0
        m.status.text = "Unreachable: " + out.error
    else
        m.status.text = "HTTP " + StrI(out.status).Trim()
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
```

- [ ] **Step 4: Deploy and run manual checklist**

Run: `./deploy.sh`, then on the TV:

1. Fresh install (no servers) opens Server list with only "+ Add Server".
2. Add a server: enter name, URL, auth settings for a REAL Frigate server on your LAN.
3. Test Connection with correct credentials → "OK v0.16.x — N cameras found".
4. Test Connection with wrong password (frigate auth) → "Auth rejected (401)".
5. Test Connection with wrong IP → "Unreachable: ..." within ~15 s.
6. Save; relaunch the channel (Home, reopen) → server persists.
7. Edit → Delete Server → list is empty again. Re-add and save for later tasks.

Expected: all 7 pass. Also confirms Task 5's ApiTask works, including Frigate-auth login (check the server's registry entry got a token by re-entering edit — Test Connection after save should succeed without re-login).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: navigation framework and server settings screens"
```

---

### Task 7: Home screen — server tabs, camera grid, snapshot loop

**Files:**
- Create: `source/HttpSync.brs` (extracted from ApiTask.brs)
- Modify: `components/tasks/ApiTask.brs`, `components/tasks/ApiTask.xml`
- Create: `components/tasks/SnapshotTask.xml`, `components/tasks/SnapshotTask.brs`
- Create: `components/CameraTileData.xml` (ContentNode subclass)
- Create: `components/CameraTile.xml`, `components/CameraTile.brs`
- Create: `components/screens/HomeScreen.xml`, `components/screens/HomeScreen.brs`

**Interfaces:**
- Consumes: `ApiTask`, `ServerStore_*`, `Frigate_SnapshotPath`, `Frigate_AuthHeaders`, navigation from Task 6.
- Produces:
  - `HttpSync.brs`: `doRequest(url, headers, method, body, savePath) as object`, `doLogin(server) as string` — shared by all Task components.
  - `SnapshotTask` fields: `server` (assocarray), `cameras` (array of strings), `result` (assocarray `{camera, path, ok}` — fires repeatedly), `newToken` (string), `quit` (boolean).
  - `CameraTileData` (extends ContentNode) fields: `cameraName` (string), `snapPath` (string), `offline` (boolean).
  - `HomeScreen` — reads ServerStore itself; pushes `LivePlayerScreen` (Task 8) with fields `server` (assocarray), `cameras` (array), `startIndex` (integer); pushes `ReviewScreen`/`ExploreScreen`/`RecordingsScreen` (Tasks 9–11) with field `server`; pushes `ServerListScreen` for Settings. Until those exist, menu items for missing screens are guarded with a "coming in a later task" status label.

- [ ] **Step 1: Extract shared sync HTTP into `source/HttpSync.brs`**

Move `doRequest` and `doLogin` (verbatim from Task 5) out of `components/tasks/ApiTask.brs` into new `source/HttpSync.brs`. In `ApiTask.xml` add:

```xml
    <script type="text/brightscript" uri="pkg:/source/HttpSync.brs" />
```

Run `./deploy.sh --test` — still `[TESTS DONE]` (compile check).

- [ ] **Step 2: SnapshotTask**

`components/tasks/SnapshotTask.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="SnapshotTask" extends="Task">
    <interface>
        <field id="server" type="assocarray" />
        <field id="cameras" type="array" />
        <field id="result" type="assocarray" alwaysNotify="true" />
        <field id="newToken" type="string" value="" />
        <field id="quit" type="boolean" value="false" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/tasks/SnapshotTask.brs" />
    <script type="text/brightscript" uri="pkg:/source/HttpSync.brs" />
    <script type="text/brightscript" uri="pkg:/source/FrigateUrls.brs" />
</component>
```

`components/tasks/SnapshotTask.brs`:

```brightscript
sub init()
    m.top.functionName = "run"
end sub

sub run()
    server = m.top.server
    fs = CreateObject("roFileSystem")
    seq = 0
    idShort = Left(server.id, 8)
    while not m.top.quit
        cameras = m.top.cameras
        headers = Frigate_AuthHeaders(server)
        for each cam in cameras
            if m.top.quit then exit for
            path = "tmp:/snap_" + idShort + "_" + cam + "_" + StrI(seq mod 4).Trim() + ".jpg"
            url = server.baseUrl + Frigate_SnapshotPath(cam, 360)
            res = doRequest(url, headers, "GET", "", path)
            if res.status = 401 and server.authType = "frigate" and server.username <> ""
                token = doLogin(server)
                if token <> ""
                    server.token = token
                    m.top.newToken = token
                    headers = Frigate_AuthHeaders(server)
                    res = doRequest(url, headers, "GET", "", path)
                end if
            end if
            ok = (res.status >= 200 and res.status < 300)
            m.top.result = { camera: cam, path: path, ok: ok }
            ' delete the file from 2 generations ago to cap tmp usage
            old = "tmp:/snap_" + idShort + "_" + cam + "_" + StrI((seq + 2) mod 4).Trim() + ".jpg"
            if fs.Exists(old) then fs.Delete(old)
        end for
        seq = seq + 1
        sleep(700)
    end while
end sub
```

- [ ] **Step 3: CameraTileData + CameraTile**

`components/CameraTileData.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="CameraTileData" extends="ContentNode">
    <interface>
        <field id="cameraName" type="string" value="" />
        <field id="snapPath" type="string" value="" />
        <field id="offline" type="boolean" value="false" />
    </interface>
</component>
```

`components/CameraTile.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="CameraTile" extends="Group">
    <interface>
        <field id="itemContent" type="node" onChange="onContentChange" />
        <field id="focusPercent" type="float" onChange="onFocus" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/CameraTile.brs" />
    <children>
        <Rectangle id="frame" width="580" height="362" color="0x1A2228FF" />
        <Poster id="snap" width="572" height="322" translation="[4, 4]" loadDisplayMode="scaleToFit" />
        <Label id="name" translation="[12, 330]" color="0xE0E6EAFF" font="font:MediumBoldSystemFont" />
        <Label id="badge" text="offline" translation="[480, 330]" color="0xFF6B6BFF" visible="false" />
        <Rectangle id="focusRing" width="580" height="362" color="0x00000000" visible="false">
            <Rectangle width="580" height="4" color="0x2BB3C0FF" />
            <Rectangle width="580" height="4" translation="[0, 358]" color="0x2BB3C0FF" />
            <Rectangle width="4" height="362" color="0x2BB3C0FF" />
            <Rectangle width="4" height="362" translation="[576, 0]" color="0x2BB3C0FF" />
        </Rectangle>
    </children>
</component>
```

`components/CameraTile.brs`:

```brightscript
sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    m.top.FindNode("name").text = c.cameraName
    if c.snapPath <> ""
        m.top.FindNode("snap").uri = c.snapPath
    end if
    m.top.FindNode("badge").visible = c.offline
end sub

sub onFocus()
    m.top.FindNode("focusRing").visible = (m.top.focusPercent > 0.5)
end sub
```

- [ ] **Step 4: HomeScreen**

`components/screens/HomeScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="HomeScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/HomeScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Group id="tabRow" translation="[60, 36]" />
        <Group id="menuRow" translation="[60, 104]" />
        <MarkupGrid id="grid" translation="[60, 170]" itemComponentName="CameraTile"
                    itemSize="[580, 362]" itemSpacing="[30, 30]" numColumns="3" numRows="2"
                    drawFocusFeedback="false" />
        <Label id="status" translation="[60, 1010]" color="0x8A959CFF" text="" width="1800" />
    </children>
</component>
```

`components/screens/HomeScreen.brs`:

```brightscript
sub init()
    m.grid = m.top.FindNode("grid")
    m.tabRow = m.top.FindNode("tabRow")
    m.menuRow = m.top.FindNode("menuRow")
    m.status = m.top.FindNode("status")
    m.grid.ObserveFieldScoped("itemSelected", "onTileSelected")
    m.top.ObserveField("wasShown", "onShown")

    m.menuItems = ["Review", "Explore", "Recordings", "Settings"]
    m.focusZone = "grid"   ' "tabs" | "menu" | "grid"
    m.tabIdx = 0
    m.menuIdx = 0
    m.servers = []
    m.cameras = []
    m.snapTask = invalid
    m.pendingTask = invalid
    reloadServers()
end sub

sub onShown()
    reloadServers()
end sub

sub reloadServers()
    stopSnapshots()
    m.servers = ServerStore_Load()
    if m.servers.Count() = 0
        m.top.GetScene().CallFunc("pushScreen", CreateObject("roSGNode", "ServerListScreen"))
        return
    end if
    if m.tabIdx >= m.servers.Count() then m.tabIdx = 0
    m.server = m.servers[m.tabIdx]
    renderTabs()
    renderMenu()
    fetchConfig()
end sub

sub renderTabs()
    while m.tabRow.GetChildCount() > 0
        m.tabRow.RemoveChildIndex(0)
    end while
    x = 0
    for i = 0 to m.servers.Count() - 1
        lbl = m.tabRow.CreateChild("Label")
        lbl.text = m.servers[i].name
        lbl.translation = [x, 0]
        lbl.font = "font:LargeBoldSystemFont"
        if i = m.tabIdx
            lbl.color = "0x2BB3C0FF"
        else
            lbl.color = "0x8A959CFF"
        end if
        if m.focusZone = "tabs" and i = m.tabIdx then lbl.color = "0xFFFFFFFF"
        x = x + 40 + Len(m.servers[i].name) * 22
    end for
end sub

sub renderMenu()
    while m.menuRow.GetChildCount() > 0
        m.menuRow.RemoveChildIndex(0)
    end while
    x = 0
    for i = 0 to m.menuItems.Count() - 1
        lbl = m.menuRow.CreateChild("Label")
        lbl.text = m.menuItems[i]
        lbl.translation = [x, 0]
        if m.focusZone = "menu" and i = m.menuIdx
            lbl.color = "0xFFFFFFFF"
        else
            lbl.color = "0x8A959CFF"
        end if
        x = x + 220
    end for
end sub

sub fetchConfig()
    m.status.text = "Loading cameras from " + m.server.name + " ..."
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/config", method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onConfig")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onConfig(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    persistToken(out.newToken)
    if not out.ok
        m.status.text = m.server.name + ": failed to load config (HTTP " + StrI(out.status).Trim() + " " + out.error + ")"
        return
    end if
    cfg = ParseJson(out.body)
    if cfg = invalid or cfg.cameras = invalid
        m.status.text = m.server.name + ": not a Frigate config response"
        return
    end if
    m.cameras = []
    for each cam in cfg.cameras
        camCfg = cfg.cameras[cam]
        enabled = true
        if camCfg <> invalid and camCfg.enabled <> invalid then enabled = camCfg.enabled
        if enabled then m.cameras.Push(cam)
    end for
    m.cameras.Sort()
    m.status.text = ""
    buildGrid()
    startSnapshots()
end sub

sub persistToken(newToken as string)
    if newToken <> ""
        srv = ServerStore_GetById(m.server.id)
        if srv <> invalid
            srv.token = newToken
            ServerStore_Upsert(srv)
            m.server.token = newToken
        end if
    end if
end sub

sub buildGrid()
    content = CreateObject("roSGNode", "ContentNode")
    for each cam in m.cameras
        tile = content.CreateChild("CameraTileData")
        tile.cameraName = cam
    end for
    m.grid.content = content
    if m.focusZone = "grid" then m.grid.SetFocus(true)
end sub

sub startSnapshots()
    stopSnapshots()
    if m.cameras.Count() = 0 then return
    t = CreateObject("roSGNode", "SnapshotTask")
    t.server = m.server
    t.cameras = m.cameras
    t.ObserveFieldScoped("result", "onSnapshot")
    t.ObserveFieldScoped("newToken", "onSnapToken")
    t.control = "RUN"
    m.snapTask = t
end sub

sub stopSnapshots()
    if m.snapTask <> invalid
        m.snapTask.UnobserveFieldScoped("result")
        m.snapTask.quit = true
        m.snapTask = invalid
    end if
end sub

sub onSnapToken(ev as object)
    persistToken(ev.GetData())
end sub

sub onSnapshot(ev as object)
    res = ev.GetData()
    if m.grid.content = invalid then return
    for i = 0 to m.grid.content.GetChildCount() - 1
        tile = m.grid.content.GetChild(i)
        if tile.cameraName = res.camera
            if res.ok
                tile.snapPath = res.path
                tile.offline = false
            else
                tile.offline = true
            end if
            exit for
        end if
    end for
end sub

sub onTileSelected()
    player = CreateObject("roSGNode", "LivePlayerScreen")
    if player <> invalid
        player.server = m.server
        player.cameras = m.cameras
        player.startIndex = m.grid.itemSelected
        m.top.GetScene().CallFunc("pushScreen", player)
    else
        m.status.text = "Live player arrives in the next task"
    end if
end sub

sub openMenuItem()
    name = m.menuItems[m.menuIdx]
    screenName = ""
    if name = "Review" then screenName = "ReviewScreen"
    if name = "Explore" then screenName = "ExploreScreen"
    if name = "Recordings" then screenName = "RecordingsScreen"
    if name = "Settings" then screenName = "ServerListScreen"
    node = CreateObject("roSGNode", screenName)
    if node = invalid
        m.status.text = name + " arrives in a later task"
        return
    end if
    if screenName <> "ServerListScreen" then node.server = m.server
    m.top.GetScene().CallFunc("pushScreen", node)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.focusZone = "grid"
        if key = "up" and m.grid.itemFocused < 3
            m.focusZone = "menu"
            m.top.SetFocus(true)
            renderMenu()
            return true
        end if
        return false
    else if m.focusZone = "menu"
        if key = "left" and m.menuIdx > 0
            m.menuIdx = m.menuIdx - 1 : renderMenu() : return true
        else if key = "right" and m.menuIdx < m.menuItems.Count() - 1
            m.menuIdx = m.menuIdx + 1 : renderMenu() : return true
        else if key = "down"
            m.focusZone = "grid" : renderMenu() : m.grid.SetFocus(true) : return true
        else if key = "up"
            m.focusZone = "tabs" : renderMenu() : renderTabs() : return true
        else if key = "OK"
            openMenuItem() : return true
        end if
    else if m.focusZone = "tabs"
        if key = "left" and m.tabIdx > 0
            m.tabIdx = m.tabIdx - 1 : reloadServers() : return true
        else if key = "right" and m.tabIdx < m.servers.Count() - 1
            m.tabIdx = m.tabIdx + 1 : reloadServers() : return true
        else if key = "down" or key = "OK"
            m.focusZone = "menu" : renderTabs() : renderMenu() : return true
        end if
    end if
    return false
end function
```

Note: when the tab zone has focus, the screen itself holds focus (`m.top.SetFocus(true)`) and arrows are handled in `onKeyEvent`; the grid re-takes focus when the zone returns to "grid".

Also update `AppScene.brs` `ShowFirstScreen` to drop the Task-6 fallback: always push `HomeScreen` when servers exist, `ServerListScreen` when none.

- [ ] **Step 5: Deploy and run manual checklist**

Run: `./deploy.sh`, then on the TV:

1. Home shows your server's name highlighted as a tab, menu row, and a grid tile per enabled camera (alphabetical).
2. Tiles fill with snapshots and visibly refresh (~1–2 s cadence; watch a camera with motion).
3. With a second server configured: Up to tabs, Left/Right switches server; grid reloads with that server's cameras.
4. Unplug/wrong-IP server tab shows the failure message in the status line; other tab still works.
5. Kill one camera (or use a disabled one) → its tile shows the red `offline` badge, others keep refreshing.
6. Up from top grid row reaches menu; OK on Settings opens the server list; Back returns and snapshots resume.
7. Let it run 10 minutes — no crash, no visible memory stutter (tmp files are capped by the 2-generation delete).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: home screen with server tabs, camera grid, live snapshots"
```

---

### Task 8: Live player — full-screen HLS with audio and camera switching

**Files:**
- Create: `components/screens/LivePlayerScreen.xml`, `components/screens/LivePlayerScreen.brs`

**Interfaces:**
- Consumes: `Frigate_LiveHlsUrl` (Task 4), `CameraTileData`/snapshot tmp files (Task 7), navigation (Task 6).
- Produces: `LivePlayerScreen` with fields `server` (assocarray), `cameras` (array of strings), `startIndex` (integer). Pushed by HomeScreen. Also `PlayerOverlay` behavior other tasks copy: none — self-contained.

- [ ] **Step 1: Write the screen**

`components/screens/LivePlayerScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="LivePlayerScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
        <field id="server" type="assocarray" />
        <field id="cameras" type="array" />
        <field id="startIndex" type="integer" value="0" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/LivePlayerScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/FrigateUrls.brs" />
    <children>
        <Video id="video" width="1920" height="1080" />
        <Label id="camName" translation="[60, 40]" color="0xFFFFFFFF"
               font="font:LargeBoldSystemFont" visible="false" />
        <Group id="errorPanel" visible="false">
            <Rectangle width="1920" height="1080" color="0x101418E0" />
            <Label id="errorTitle" text="Playback failed" translation="[660, 420]"
                   color="0xFF6B6BFF" font="font:LargeBoldSystemFont" />
            <Label id="errorDetail" translation="[400, 490]" width="1120" wrap="true" color="0xE0E6EAFF" />
            <Label id="errorHint" translation="[400, 600]" width="1120" wrap="true" color="0x8A959CFF"
                   text="Hint: Roku needs H.264 video and AAC audio. In Frigate's go2rtc config add '#video=h264#audio=aac' to this camera's stream, and confirm go2rtc port 1984 is reachable. Press OK to retry, Back to exit." />
        </Group>
        <Group id="switcher" visible="false" translation="[0, 830]">
            <Rectangle width="1920" height="250" color="0x101418D0" />
            <MarkupGrid id="switchGrid" translation="[60, 20]" itemComponentName="CameraTile"
                        itemSize="[290, 181]" itemSpacing="[20, 0]" numColumns="6" numRows="1"
                        drawFocusFeedback="false" />
        </Group>
        <Timer id="nameTimer" duration="3" repeat="false" />
    </children>
</component>
```

Note: `CameraTile` from Task 7 uses fixed 580x362 children; make it scale by adding to `CameraTile.brs` `onContentChange` nothing — instead MarkupGrid clips items. To keep this simple, `switchGrid` reuses CameraTile at full size scaled by the grid: set `itemSize="[290, 181]"` and in `CameraTile.xml` wrap children in a `<Group id="root">` and add a `scale` handler:

In `CameraTile.brs` `init` (add an init sub if absent):

```brightscript
sub init()
    m.top.ObserveField("width", "onSize")
end sub

sub onSize()
    ' MarkupGrid sets item width/height fields on item components
    w = m.top.width
    if w > 0 and w < 580
        m.top.FindNode("frame").scale = [w / 580, w / 580]
    end if
end sub
```

and scale the whole tile by putting all children inside the `frame` Rectangle's parent group — restructure `CameraTile.xml` children as one `<Group id="tileRoot">` containing everything, and scale `tileRoot` instead of `frame` in `onSize`.

`components/screens/LivePlayerScreen.brs`:

```brightscript
sub init()
    m.video = m.top.FindNode("video")
    m.camName = m.top.FindNode("camName")
    m.errorPanel = m.top.FindNode("errorPanel")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.switcher = m.top.FindNode("switcher")
    m.switchGrid = m.top.FindNode("switchGrid")
    m.nameTimer = m.top.FindNode("nameTimer")
    m.nameTimer.ObserveFieldScoped("fire", "hideName")
    m.video.ObserveFieldScoped("state", "onVideoState")
    m.switchGrid.ObserveFieldScoped("itemSelected", "onSwitchPick")
    m.top.ObserveField("wasShown", "onShown")
    m.idx = 0
    m.started = false
end sub

sub onShown()
    if not m.started
        m.started = true
        m.idx = m.top.startIndex
        buildSwitcher()
        playCurrent()
    end if
    m.top.SetFocus(true)
end sub

sub playCurrent()
    cam = m.top.cameras[m.idx]
    m.errorPanel.visible = false
    m.video.control = "stop"
    content = CreateObject("roSGNode", "ContentNode")
    content.url = Frigate_LiveHlsUrl_Render(m.top.server, cam)
    content.streamFormat = "hls"
    content.live = true
    content.title = cam
    m.video.content = content
    m.video.control = "play"
    showName(cam)
end sub

' Render-safe copy (Frigate_LiveHlsUrl calls roUrlTransfer via Frigate_UrlEncode)
function Frigate_LiveHlsUrl_Render(server as object, cameraName as string) as string
    host = Frigate_HostFromUrl(server.baseUrl)
    return "http://" + host + ":" + StrI(server.go2rtcPort).Trim() + "/api/stream.m3u8?src=" + cameraName + "&mp4"
end function

sub showName(cam as string)
    m.camName.text = cam
    m.camName.visible = true
    m.nameTimer.control = "start"
end sub

sub hideName()
    m.camName.visible = false
end sub

sub onVideoState()
    state = m.video.state
    if state = "error"
        m.errorDetail.text = "Camera: " + m.top.cameras[m.idx] + chr(10) + "Error: " + m.video.errorMsg + " (code " + StrI(m.video.errorCode).Trim() + ")" + chr(10) + "URL: " + Frigate_LiveHlsUrl_Render(m.top.server, m.top.cameras[m.idx])
        m.errorPanel.visible = true
    end if
end sub

sub buildSwitcher()
    content = CreateObject("roSGNode", "ContentNode")
    idShort = Left(m.top.server.id, 8)
    for each cam in m.top.cameras
        tile = content.CreateChild("CameraTileData")
        tile.cameraName = cam
        ' seed from the freshest snapshot files Task 7 wrote (any of the 4 generations)
        fs = CreateObject("roFileSystem")
        for g = 3 to 0 step -1
            p = "tmp:/snap_" + idShort + "_" + cam + "_" + StrI(g).Trim() + ".jpg"
            if fs.Exists(p)
                tile.snapPath = p
                exit for
            end if
        end for
    end for
    m.switchGrid.content = content
end sub

sub onSwitchPick()
    m.idx = m.switchGrid.itemSelected
    m.switcher.visible = false
    m.top.SetFocus(true)
    playCurrent()
end sub

sub switchBy(delta as integer)
    n = m.top.cameras.Count()
    m.idx = ((m.idx + delta) mod n + n) mod n
    playCurrent()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.switcher.visible
        if key = "back" or key = "up"
            m.switcher.visible = false
            m.top.SetFocus(true)
            return true
        end if
        return false
    end if
    if key = "left"
        switchBy(-1) : return true
    else if key = "right"
        switchBy(1) : return true
    else if key = "OK" or key = "down"
        if m.errorPanel.visible
            playCurrent()   ' OK = retry when error showing
        else
            m.switcher.visible = true
            m.switchGrid.SetFocus(true)
        end if
        return true
    end if
    return false
end function
```

Cleanup: when the screen is popped, AppScene removes it; add to `AppScene.brs` `PopScreen` before `RemoveChild`:

```brightscript
    if screen.HasField("stopPlayback") then screen.stopPlayback = true
```

and give LivePlayerScreen an interface field `stopPlayback` (boolean) observed to run `m.video.control = "stop"`. Add to the XML interface:

```xml
        <field id="stopPlayback" type="boolean" value="false" onChange="onStopPlayback" />
```

and in the .brs:

```brightscript
sub onStopPlayback()
    m.video.control = "stop"
end sub
```

- [ ] **Step 2: Deploy and run manual checklist**

Run: `./deploy.sh`, then on the TV:

1. OK on a grid tile → full-screen live video within ~3–6 s; camera name overlays then fades.
2. Audio is audible on a camera whose go2rtc stream has AAC audio (talk near the camera / check a doorbell).
3. Left/Right switches to prev/next camera; wraps at both ends.
4. Down/OK opens the bottom thumbnail strip; Left/Right moves; OK jumps to that camera; Back closes strip without switching.
5. Back from playback returns to the grid; snapshots still refreshing; enter a different camera — plays.
6. Point a server entry at a bogus go2rtc port → error panel with URL + codec hint; OK retries; Back exits.
7. No stutter after 5+ minutes on one camera.

If step 1 fails on all cameras: verify from a PC that `http://<host>:1984/api/stream.m3u8?src=<cam>&mp4` plays in VLC. If VLC works but Roku errors, check the camera's codec (`ffprobe` the stream) — H.265 on an older Roku is the usual cause; fix server-side per the hint text.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: full-screen live player with audio and camera switching"
```

---

### Task 9: VOD player + ThumbTask + Review screen

**Files:**
- Create: `components/screens/VodPlayerScreen.xml`, `components/screens/VodPlayerScreen.brs`
- Create: `components/tasks/ThumbTask.xml`, `components/tasks/ThumbTask.brs`
- Create: `components/ReviewRowData.xml`, `components/ReviewRow.xml`, `components/ReviewRow.brs`
- Create: `components/screens/ReviewScreen.xml`, `components/screens/ReviewScreen.brs`

**Interfaces:**
- Consumes: `ApiTask`, `HttpSync.brs`, `Frigate_VodRangeUrl`, `Frigate_EventThumbPath`, `TimeUtil_FormatEpoch`.
- Produces:
  - `VodPlayerScreen` fields: `server` (assocarray), `playlist` (array of `{url, title, format}` where format is `"hls"` or `"mp4"`), `startIndex` (integer). Plays items sequentially (auto-advance on finish), Left/Right seeks ±30 s, sends auth via content-node `HttpHeaders`. Reused by Tasks 10 and 11.
  - `ThumbTask` fields: `server` (assocarray), `items` (array of `{key, path, savePath}` — `path` is a Frigate API path), `result` (assocarray `{key, savePath, ok}`, fires per item), `newToken` (string), `quit` (boolean). Reused by Task 10.
  - `ReviewRowData` (extends ContentNode) fields: `reviewId`, `camera`, `caption`, `thumbPath` (all string), plus `startTime`, `endTime` (float).

- [ ] **Step 1: VodPlayerScreen**

`components/screens/VodPlayerScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="VodPlayerScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
        <field id="server" type="assocarray" />
        <field id="playlist" type="array" />
        <field id="startIndex" type="integer" value="0" />
        <field id="stopPlayback" type="boolean" value="false" onChange="onStopPlayback" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/VodPlayerScreen.brs" />
    <children>
        <Video id="video" width="1920" height="1080" />
        <Label id="titleLabel" translation="[60, 40]" color="0xFFFFFFFF"
               font="font:LargeBoldSystemFont" visible="false" />
        <Group id="errorPanel" visible="false">
            <Rectangle width="1920" height="1080" color="0x101418E0" />
            <Label id="errorTitle" text="Playback failed" translation="[660, 420]"
                   color="0xFF6B6BFF" font="font:LargeBoldSystemFont" />
            <Label id="errorDetail" translation="[400, 490]" width="1120" wrap="true" color="0xE0E6EAFF" />
            <Label id="errorHint" translation="[400, 620]" width="1120" wrap="true" color="0x8A959CFF"
                   text="OK to retry, Back to exit. If this recording exists in the Frigate web UI but fails here, the recording codec may be unsupported (Roku needs H.264 + AAC)." />
        </Group>
        <Timer id="nameTimer" duration="3" repeat="false" />
    </children>
</component>
```

`components/screens/VodPlayerScreen.brs`:

```brightscript
sub init()
    m.video = m.top.FindNode("video")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.errorPanel = m.top.FindNode("errorPanel")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.nameTimer = m.top.FindNode("nameTimer")
    m.nameTimer.ObserveFieldScoped("fire", "hideTitle")
    m.video.ObserveFieldScoped("state", "onVideoState")
    m.top.ObserveField("wasShown", "onShown")
    m.idx = 0
    m.started = false
end sub

sub onShown()
    if not m.started
        m.started = true
        m.idx = m.top.startIndex
        playCurrent()
    end if
    m.top.SetFocus(true)
end sub

sub playCurrent()
    item = m.top.playlist[m.idx]
    m.errorPanel.visible = false
    m.video.control = "stop"
    content = CreateObject("roSGNode", "ContentNode")
    content.url = item.url
    content.streamFormat = item.format
    content.title = item.title
    headers = authHeaderStrings()
    if headers.Count() > 0 then content.HttpHeaders = headers
    if Left(item.url, 8) = "https://" then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    m.video.content = content
    m.video.control = "play"
    m.titleLabel.text = item.title
    m.titleLabel.visible = true
    m.nameTimer.control = "start"
end sub

' ["Authorization: Bearer x"] / ["Authorization: Basic y"] / []
function authHeaderStrings() as object
    s = m.top.server
    if s = invalid then return []
    if s.authType = "basic"
        ba = CreateObject("roByteArray")
        ba.FromAsciiString(s.username + ":" + s.password)
        return ["Authorization: Basic " + ba.ToBase64String()]
    else if s.authType = "frigate" and s.token <> ""
        return ["Authorization: Bearer " + s.token]
    end if
    return []
end function

sub hideTitle()
    m.titleLabel.visible = false
end sub

sub onVideoState()
    state = m.video.state
    if state = "error"
        item = m.top.playlist[m.idx]
        m.errorDetail.text = item.title + chr(10) + "Error: " + m.video.errorMsg + " (code " + StrI(m.video.errorCode).Trim() + ")" + chr(10) + "URL: " + item.url
        m.errorPanel.visible = true
    else if state = "finished"
        if m.idx < m.top.playlist.Count() - 1
            m.idx = m.idx + 1
            playCurrent()
        else
            m.top.closeMe = true
        end if
    end if
end sub

sub onStopPlayback()
    m.video.control = "stop"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "OK" and m.errorPanel.visible
        playCurrent()
        return true
    else if key = "left"
        pos = m.video.position - 30
        if pos < 0 then pos = 0
        m.video.seek = pos
        return true
    else if key = "right"
        m.video.seek = m.video.position + 30
        return true
    end if
    return false
end function
```

If Bearer via `HttpHeaders` is rejected on device (check with a frigate-auth server), switch `authHeaderStrings` frigate branch to cookies instead: `content.HttpCookies = ["frigate_token=" + s.token]` — verify in the Step 5 checklist and keep whichever works.

- [ ] **Step 2: ThumbTask**

`components/tasks/ThumbTask.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ThumbTask" extends="Task">
    <interface>
        <field id="server" type="assocarray" />
        <field id="items" type="array" />
        <field id="result" type="assocarray" alwaysNotify="true" />
        <field id="newToken" type="string" value="" />
        <field id="quit" type="boolean" value="false" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/tasks/ThumbTask.brs" />
    <script type="text/brightscript" uri="pkg:/source/HttpSync.brs" />
    <script type="text/brightscript" uri="pkg:/source/FrigateUrls.brs" />
</component>
```

`components/tasks/ThumbTask.brs`:

```brightscript
sub init()
    m.top.functionName = "run"
end sub

sub run()
    server = m.top.server
    headers = Frigate_AuthHeaders(server)
    for each item in m.top.items
        if m.top.quit then exit for
        res = doRequest(server.baseUrl + item.path, headers, "GET", "", item.savePath)
        if res.status = 401 and server.authType = "frigate" and server.username <> ""
            token = doLogin(server)
            if token <> ""
                server.token = token
                m.top.newToken = token
                headers = Frigate_AuthHeaders(server)
                res = doRequest(server.baseUrl + item.path, headers, "GET", "", item.savePath)
            end if
        end if
        m.top.result = { key: item.key, savePath: item.savePath, ok: (res.status >= 200 and res.status < 300) }
    end for
end sub
```

- [ ] **Step 3: ReviewRow components**

`components/ReviewRowData.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ReviewRowData" extends="ContentNode">
    <interface>
        <field id="reviewId" type="string" value="" />
        <field id="camera" type="string" value="" />
        <field id="caption" type="string" value="" />
        <field id="thumbPath" type="string" value="" />
        <field id="startTime" type="float" value="0" />
        <field id="endTime" type="float" value="0" />
    </interface>
</component>
```

`components/ReviewRow.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ReviewRow" extends="Group">
    <interface>
        <field id="itemContent" type="node" onChange="onContentChange" />
        <field id="focusPercent" type="float" onChange="onFocus" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/ReviewRow.brs" />
    <children>
        <Rectangle id="bg" width="1700" height="130" color="0x1A2228FF" />
        <Poster id="thumb" width="200" height="112" translation="[10, 9]" loadDisplayMode="scaleToZoom" />
        <Label id="caption" translation="[230, 20]" color="0xE0E6EAFF" font="font:MediumBoldSystemFont" width="1400" />
        <Label id="sub" translation="[230, 70]" color="0x8A959CFF" width="1400" />
    </children>
</component>
```

`components/ReviewRow.brs`:

```brightscript
sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    if c.thumbPath <> "" then m.top.FindNode("thumb").uri = c.thumbPath
    m.top.FindNode("caption").text = c.caption
    m.top.FindNode("sub").text = c.camera
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.top.FindNode("bg").color = "0x10545CFF"
    else
        m.top.FindNode("bg").color = "0x1A2228FF"
    end if
end sub
```

- [ ] **Step 4: ReviewScreen**

`components/screens/ReviewScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ReviewScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
        <field id="server" type="assocarray" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/ReviewScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Label id="title" text="Review" translation="[120, 50]" color="0xE0E6EAFF" font="font:LargeBoldSystemFont" />
        <Label id="filterLabel" translation="[400, 58]" color="0x2BB3C0FF" text="Showing: Alerts  (press * to toggle)" />
        <MarkupGrid id="list" translation="[120, 130]" itemComponentName="ReviewRow"
                    itemSize="[1700, 130]" itemSpacing="[0, 12]" numColumns="1" numRows="6"
                    drawFocusFeedback="false" />
        <Label id="status" translation="[120, 1010]" color="0x8A959CFF" text="" width="1700" />
    </children>
</component>
```

`components/screens/ReviewScreen.brs`:

```brightscript
sub init()
    m.list = m.top.FindNode("list")
    m.status = m.top.FindNode("status")
    m.filterLabel = m.top.FindNode("filterLabel")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("wasShown", "onShown")
    m.severity = "alert"
    m.items = []
    m.pendingTask = invalid
    m.thumbTask = invalid
    m.loaded = false
end sub

sub onShown()
    if not m.loaded
        m.loaded = true
        fetchItems()
    end if
    m.list.SetFocus(true)
end sub

sub fetchItems()
    m.status.text = "Loading review items..."
    if m.thumbTask <> invalid then m.thumbTask.quit = true
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: "/api/review?limit=50&severity=" + m.severity, method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onItems")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub persistToken(newToken as string)
    if newToken <> "" and m.top.server <> invalid
        srv = ServerStore_GetById(m.top.server.id)
        if srv <> invalid
            srv.token = newToken
            ServerStore_Upsert(srv)
        end if
    end if
end sub

sub onItems(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    persistToken(out.newToken)
    if not out.ok
        m.status.text = "Failed to load review items (HTTP " + StrI(out.status).Trim() + ")"
        return
    end if
    m.items = ParseJson(out.body)
    if m.items = invalid
        m.status.text = "Bad response"
        m.items = []
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    thumbJobs = []
    for i = 0 to m.items.Count() - 1
        item = m.items[i]
        row = content.CreateChild("ReviewRowData")
        row.reviewId = item.id
        row.camera = item.camera
        row.startTime = item.start_time
        if item.end_time <> invalid then row.endTime = item.end_time
        labels = ""
        if item.data <> invalid and item.data.objects <> invalid
            for each obj in item.data.objects
                if labels <> "" then labels = labels + ", "
                labels = labels + obj
            end for
        end if
        if labels = "" then labels = m.severity
        row.caption = labels + " — " + TimeUtil_FormatEpoch(item.start_time)
        ' thumb: first detection event's jpg (guaranteed jpg, unlike webp thumb_path)
        if item.data <> invalid and item.data.detections <> invalid and item.data.detections.Count() > 0
            evId = item.data.detections[0]
            thumbJobs.Push({ key: item.id, path: "/api/events/" + evId + "/thumbnail.jpg", savePath: "tmp:/rev_" + item.id + ".jpg" })
        end if
    end for
    m.list.content = content
    m.status.text = StrI(m.items.Count()).Trim() + " items"
    if thumbJobs.Count() > 0
        tt = CreateObject("roSGNode", "ThumbTask")
        tt.server = m.top.server
        tt.items = thumbJobs
        tt.ObserveFieldScoped("result", "onThumb")
        tt.control = "RUN"
        m.thumbTask = tt
    end if
end sub

sub onThumb(ev as object)
    res = ev.GetData()
    if not res.ok then return
    if m.list.content = invalid then return
    for i = 0 to m.list.content.GetChildCount() - 1
        row = m.list.content.GetChild(i)
        if row.reviewId = res.key
            row.thumbPath = res.savePath
            exit for
        end if
    end for
end sub

sub onSelect()
    item = m.items[m.list.itemSelected]
    endTs = item.end_time
    if endTs = invalid then endTs = item.start_time + 60
    server = m.top.server
    url = server.baseUrl + "/vod/" + item.camera + "/start/" + StrI(Int(item.start_time)).Trim() + "/end/" + StrI(Int(endTs) + 1).Trim() + "/master.m3u8"
    player = CreateObject("roSGNode", "VodPlayerScreen")
    player.server = server
    player.playlist = [{ url: url, title: item.camera + " — " + TimeUtil_FormatEpoch(item.start_time), format: "hls" }]
    player.startIndex = 0
    m.top.GetScene().CallFunc("pushScreen", player)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options"   ' the * key
        if m.severity = "alert"
            m.severity = "detection"
            m.filterLabel.text = "Showing: Detections  (press * to toggle)"
        else
            m.severity = "alert"
            m.filterLabel.text = "Showing: Alerts  (press * to toggle)"
        end if
        fetchItems()
        return true
    end if
    return false
end function
```

- [ ] **Step 5: Deploy and run manual checklist**

Run: `./deploy.sh`, then on the TV:

1. Home → Review lists recent alerts with thumbnails, labels, and local times, newest first.
2. `*` toggles to Detections and back; list refetches.
3. OK on an item plays the recording of that segment; audio present if recorded; Left/Right seek ±30 s.
4. On a frigate-auth server: playback works (Bearer over `HttpHeaders`). If it 401s, apply the documented `HttpCookies` fallback in VodPlayerScreen and re-verify.
5. Back returns to the list, then to Home.
6. A server with no review items shows "0 items", no crash.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: review screen with VOD playback and thumbnails"
```

---

### Task 10: Explore screen (tracked objects with filters)

**Files:**
- Create: `components/EventTileData.xml`, `components/EventTile.xml`, `components/EventTile.brs`
- Create: `components/screens/ExploreScreen.xml`, `components/screens/ExploreScreen.brs`

**Interfaces:**
- Consumes: `ApiTask`, `ThumbTask`, `VodPlayerScreen`, `TimeUtil_FormatEpoch`, `Frigate_EventClipPath`.
- Produces: `ExploreScreen` with field `server` (assocarray). `EventTileData` (extends ContentNode) fields: `eventId`, `thumbPath`, `caption`, `subCaption` (strings), `hasClip` (boolean).

- [ ] **Step 1: EventTile components**

`components/EventTileData.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="EventTileData" extends="ContentNode">
    <interface>
        <field id="eventId" type="string" value="" />
        <field id="thumbPath" type="string" value="" />
        <field id="caption" type="string" value="" />
        <field id="subCaption" type="string" value="" />
        <field id="hasClip" type="boolean" value="false" />
    </interface>
</component>
```

`components/EventTile.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="EventTile" extends="Group">
    <interface>
        <field id="itemContent" type="node" onChange="onContentChange" />
        <field id="focusPercent" type="float" onChange="onFocus" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/EventTile.brs" />
    <children>
        <Rectangle id="bg" width="420" height="330" color="0x1A2228FF" />
        <Poster id="thumb" width="404" height="228" translation="[8, 8]" loadDisplayMode="scaleToZoom" />
        <Label id="caption" translation="[12, 244]" color="0xE0E6EAFF" font="font:MediumBoldSystemFont" width="400" />
        <Label id="sub" translation="[12, 284]" color="0x8A959CFF" width="400" />
    </children>
</component>
```

`components/EventTile.brs`:

```brightscript
sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    if c.thumbPath <> "" then m.top.FindNode("thumb").uri = c.thumbPath
    m.top.FindNode("caption").text = c.caption
    sub_ = c.subCaption
    if not c.hasClip then sub_ = sub_ + "  (no clip)"
    m.top.FindNode("sub").text = sub_
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.top.FindNode("bg").color = "0x10545CFF"
    else
        m.top.FindNode("bg").color = "0x1A2228FF"
    end if
end sub
```

- [ ] **Step 2: ExploreScreen**

`components/screens/ExploreScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="ExploreScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
        <field id="server" type="assocarray" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/ExploreScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Label id="title" text="Explore" translation="[120, 50]" color="0xE0E6EAFF" font="font:LargeBoldSystemFont" />
        <Label id="chips" translation="[420, 58]" color="0x2BB3C0FF" text="" width="1300" />
        <MarkupGrid id="grid" translation="[120, 130]" itemComponentName="EventTile"
                    itemSize="[420, 330]" itemSpacing="[24, 24]" numColumns="4" numRows="2"
                    drawFocusFeedback="false" />
        <Label id="status" translation="[120, 1010]" color="0x8A959CFF" text="" width="1700" />
    </children>
</component>
```

`components/screens/ExploreScreen.brs` — chip model: three filters cycled with dedicated keys shown in the chip bar (`*` = label, `replay`/`rewind` not used; keep it dead simple: Up from the grid's top row focuses the chip bar as one zone; Left/Right selects which chip; OK cycles that chip's value and refetches):

```brightscript
sub init()
    m.grid = m.top.FindNode("grid")
    m.status = m.top.FindNode("status")
    m.chips = m.top.FindNode("chips")
    m.grid.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("wasShown", "onShown")
    m.cameraOptions = ["all"]        ' filled from /api/config cameras via first fetch of events' cameras
    m.labelOptions = ["all"]         ' filled from /api/labels
    m.dateOptions = ["24h", "7d", "all"]
    m.cameraIdx = 0
    m.labelIdx = 0
    m.dateIdx = 0
    m.chipIdx = 0
    m.focusZone = "grid"
    m.events = []
    m.pendingTask = invalid
    m.thumbTask = invalid
    m.loaded = false
    renderChips()
end sub

sub onShown()
    if not m.loaded
        m.loaded = true
        fetchLabels()
        fetchCameras()
        fetchEvents()
    end if
    if m.focusZone = "grid" then m.grid.SetFocus(true) else m.top.SetFocus(true)
end sub

sub renderChips()
    names = ["Camera: " + m.cameraOptions[m.cameraIdx], "Label: " + m.labelOptions[m.labelIdx], "When: " + m.dateOptions[m.dateIdx]]
    text = ""
    for i = 0 to 2
        part = names[i]
        if m.focusZone = "chips" and i = m.chipIdx then part = "[ " + part + " ]"
        if text <> "" then text = text + "    "
        text = text + part
    end for
    m.chips.text = text
end sub

sub fetchLabels()
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: "/api/labels", method: "GET", body: "", savePath: "", context: "labels" }
    t.ObserveFieldScoped("output", "onAux")
    t.control = "RUN"
    m.labelsTask = t
end sub

sub fetchCameras()
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: "/api/config", method: "GET", body: "", savePath: "", context: "config" }
    t.ObserveFieldScoped("output", "onAux")
    t.control = "RUN"
    m.configTask = t
end sub

sub onAux(ev as object)
    out = ev.GetData()
    if not out.ok then return
    data = ParseJson(out.body)
    if data = invalid then return
    if out.context = "labels" and GetInterface(data, "ifArray") <> invalid
        m.labelOptions = ["all"]
        for each l in data
            m.labelOptions.Push(l)
        end for
    else if out.context = "config" and data.cameras <> invalid
        m.cameraOptions = ["all"]
        cams = []
        for each cam in data.cameras
            cams.Push(cam)
        end for
        cams.Sort()
        for each cam in cams
            m.cameraOptions.Push(cam)
        end for
    end if
    renderChips()
end sub

sub fetchEvents()
    m.status.text = "Loading events..."
    if m.thumbTask <> invalid then m.thumbTask.quit = true
    path = "/api/events?limit=60&include_thumbnails=0"
    if m.cameraOptions[m.cameraIdx] <> "all" then path = path + "&cameras=" + m.cameraOptions[m.cameraIdx]
    if m.labelOptions[m.labelIdx] <> "all" then path = path + "&labels=" + m.labelOptions[m.labelIdx]
    when = m.dateOptions[m.dateIdx]
    if when <> "all"
        now = CreateObject("roDateTime").AsSeconds()
        span = 24 * 3600
        if when = "7d" then span = 7 * 24 * 3600
        path = path + "&after=" + StrI(now - span).Trim()
    end if
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: path, method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onEvents")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onEvents(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    if out.newToken <> ""
        srv = ServerStore_GetById(m.top.server.id)
        if srv <> invalid
            srv.token = out.newToken
            ServerStore_Upsert(srv)
        end if
    end if
    if not out.ok
        m.status.text = "Failed to load events (HTTP " + StrI(out.status).Trim() + ")"
        return
    end if
    m.events = ParseJson(out.body)
    if m.events = invalid
        m.events = []
        m.status.text = "Bad response"
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    jobs = []
    for each item in m.events
        tile = content.CreateChild("EventTileData")
        tile.eventId = item.id
        tile.caption = item.label
        tile.subCaption = item.camera + " — " + TimeUtil_FormatEpoch(item.start_time)
        if item.has_clip <> invalid then tile.hasClip = item.has_clip
        jobs.Push({ key: item.id, path: "/api/events/" + item.id + "/thumbnail.jpg", savePath: "tmp:/evt_" + item.id + ".jpg" })
    end for
    m.grid.content = content
    m.status.text = StrI(m.events.Count()).Trim() + " events"
    if jobs.Count() > 0
        tt = CreateObject("roSGNode", "ThumbTask")
        tt.server = m.top.server
        tt.items = jobs
        tt.ObserveFieldScoped("result", "onThumb")
        tt.control = "RUN"
        m.thumbTask = tt
    end if
end sub

sub onThumb(ev as object)
    res = ev.GetData()
    if not res.ok or m.grid.content = invalid then return
    for i = 0 to m.grid.content.GetChildCount() - 1
        tile = m.grid.content.GetChild(i)
        if tile.eventId = res.key
            tile.thumbPath = res.savePath
            exit for
        end if
    end for
end sub

sub onSelect()
    item = m.events[m.grid.itemSelected]
    if item.has_clip <> invalid and item.has_clip = false
        m.status.text = "This event has no clip"
        return
    end if
    player = CreateObject("roSGNode", "VodPlayerScreen")
    player.server = m.top.server
    player.playlist = [{ url: m.top.server.baseUrl + "/api/events/" + item.id + "/clip.mp4", title: item.label + " — " + item.camera, format: "mp4" }]
    player.startIndex = 0
    m.top.GetScene().CallFunc("pushScreen", player)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.focusZone = "grid"
        if key = "up" and m.grid.itemFocused < 4
            m.focusZone = "chips"
            m.top.SetFocus(true)
            renderChips()
            return true
        end if
        return false
    end if
    ' chips zone
    if key = "left" and m.chipIdx > 0
        m.chipIdx = m.chipIdx - 1 : renderChips() : return true
    else if key = "right" and m.chipIdx < 2
        m.chipIdx = m.chipIdx + 1 : renderChips() : return true
    else if key = "OK"
        if m.chipIdx = 0
            m.cameraIdx = (m.cameraIdx + 1) mod m.cameraOptions.Count()
        else if m.chipIdx = 1
            m.labelIdx = (m.labelIdx + 1) mod m.labelOptions.Count()
        else
            m.dateIdx = (m.dateIdx + 1) mod m.dateOptions.Count()
        end if
        renderChips()
        fetchEvents()
        return true
    else if key = "down"
        m.focusZone = "grid" : renderChips() : m.grid.SetFocus(true) : return true
    end if
    return false
end function
```

- [ ] **Step 3: Deploy and run manual checklist**

1. Home → Explore shows a grid of recent tracked objects with thumbnails, label, camera, local time.
2. Up to chip bar; OK cycles Camera/Label/When values; grid refetches each time; combinations work (e.g. person + one camera + 7d).
3. OK on an event plays its clip (MP4); seek works; Back returns with filters intact.
4. An event without a clip shows "This event has no clip" instead of erroring.
5. Works on both servers (auth and no-auth).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: explore screen with camera/label/date filters"
```

---

### Task 11: Recordings screen (camera → day → hour)

**Files:**
- Create: `components/screens/RecordingsScreen.xml`, `components/screens/RecordingsScreen.brs`
- Modify: `components/screens/HomeScreen.brs` (`openMenuItem`: also pass `cameras`)

**Interfaces:**
- Consumes: `ApiTask`, `VodPlayerScreen`, `Frigate_VodHourUrl` (render-safe — no roUrlTransfer inside), recordings summary API.
- Produces: `RecordingsScreen` with fields `server` (assocarray), `cameras` (array of strings).

- [ ] **Step 1: Pass cameras from HomeScreen**

In `HomeScreen.brs` `openMenuItem`, after `if screenName <> "ServerListScreen" then node.server = m.server` add:

```brightscript
    if screenName = "RecordingsScreen" then node.cameras = m.cameras
```

- [ ] **Step 2: RecordingsScreen**

Three `LabelList`s side by side (Cameras / Days / Hours). Selecting a camera loads its recordings summary; selecting a day fills hours; selecting an hour plays that hour plus the rest of the day's hours as an auto-advancing playlist.

`components/screens/RecordingsScreen.xml`:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="RecordingsScreen" extends="Group">
    <interface>
        <field id="closeMe" type="boolean" value="false" />
        <field id="wasShown" type="boolean" value="false" />
        <field id="server" type="assocarray" />
        <field id="cameras" type="array" />
    </interface>
    <script type="text/brightscript" uri="pkg:/components/screens/RecordingsScreen.brs" />
    <script type="text/brightscript" uri="pkg:/source/ServerStore.brs" />
    <children>
        <Label id="title" text="Recordings" translation="[120, 50]" color="0xE0E6EAFF" font="font:LargeBoldSystemFont" />
        <Label text="Camera" translation="[120, 130]" color="0x8A959CFF" />
        <Label text="Day" translation="[720, 130]" color="0x8A959CFF" />
        <Label text="Hour" translation="[1320, 130]" color="0x8A959CFF" />
        <LabelList id="camList" translation="[120, 180]" itemSize="[540, 56]" numRows="12"
                   color="0xE0E6EAFF" focusedColor="0x10545CFF" />
        <LabelList id="dayList" translation="[720, 180]" itemSize="[540, 56]" numRows="12"
                   color="0xE0E6EAFF" focusedColor="0x10545CFF" />
        <LabelList id="hourList" translation="[1320, 180]" itemSize="[400, 56]" numRows="12"
                   color="0xE0E6EAFF" focusedColor="0x10545CFF" />
        <Label id="status" translation="[120, 1010]" color="0x8A959CFF" text="" width="1700" />
    </children>
</component>
```

`components/screens/RecordingsScreen.brs`:

```brightscript
sub init()
    m.camList = m.top.FindNode("camList")
    m.dayList = m.top.FindNode("dayList")
    m.hourList = m.top.FindNode("hourList")
    m.status = m.top.FindNode("status")
    m.camList.ObserveFieldScoped("itemSelected", "onCamSelect")
    m.dayList.ObserveFieldScoped("itemSelected", "onDaySelect")
    m.hourList.ObserveFieldScoped("itemSelected", "onHourSelect")
    m.top.ObserveField("wasShown", "onShown")
    m.summary = []
    m.dayIdx = 0
    m.camera = ""
    m.pendingTask = invalid
    m.loaded = false
end sub

sub onShown()
    if not m.loaded
        m.loaded = true
        content = CreateObject("roSGNode", "ContentNode")
        for each cam in m.top.cameras
            content.CreateChild("ContentNode").title = cam
        end for
        m.camList.content = content
    end if
    m.camList.SetFocus(true)
end sub

sub onCamSelect()
    m.camera = m.top.cameras[m.camList.itemSelected]
    m.status.text = "Loading recording days for " + m.camera + " ..."
    tz = CreateObject("roDeviceInfo").GetTimeZone()
    tzEnc = tz.Replace("/", "%2F")
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: "/api/" + m.camera + "/recordings/summary?timezone=" + tzEnc, method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onSummary")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onSummary(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    if out.newToken <> ""
        srv = ServerStore_GetById(m.top.server.id)
        if srv <> invalid
            srv.token = out.newToken
            ServerStore_Upsert(srv)
        end if
    end if
    if not out.ok
        m.status.text = "Failed to load summary (HTTP " + StrI(out.status).Trim() + ")"
        return
    end if
    m.summary = ParseJson(out.body)
    if m.summary = invalid or GetInterface(m.summary, "ifArray") = invalid
        m.summary = []
        m.status.text = "No recordings summary"
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    for each d in m.summary
        content.CreateChild("ContentNode").title = d.day
    end for
    m.dayList.content = content
    m.hourList.content = CreateObject("roSGNode", "ContentNode")
    m.status.text = StrI(m.summary.Count()).Trim() + " days with recordings"
    if m.summary.Count() > 0 then m.dayList.SetFocus(true)
end sub

sub onDaySelect()
    m.dayIdx = m.dayList.itemSelected
    d = m.summary[m.dayIdx]
    content = CreateObject("roSGNode", "ContentNode")
    if d.hours <> invalid
        for each h in d.hours
            content.CreateChild("ContentNode").title = hourLabel(h.hour)
        end for
    end if
    m.hourList.content = content
    m.hourList.SetFocus(true)
end sub

function hourLabel(hourVal as dynamic) as string
    h = Val(Str(hourVal).Trim())
    ampm = "AM"
    hr = h
    if hr >= 12 then ampm = "PM"
    if hr = 0 then hr = 12
    if hr > 12 then hr = hr - 12
    return StrI(hr).Trim() + ":00 " + ampm
end function

function pad2(v as dynamic) as string
    s = Str(Val(Str(v).Trim())).Trim()
    if Len(s) = 1 then s = "0" + s
    return s
end function

sub onHourSelect()
    d = m.summary[m.dayIdx]
    if d.hours = invalid then return
    tz = CreateObject("roDeviceInfo").GetTimeZone()
    ' day: "2026-07-29" -> yearMonth "2026-07", dd "29"
    parts = d.day.Split("-")
    if parts.Count() <> 3 then return
    ym = parts[0] + "-" + parts[1]
    dd = parts[2]
    playlist = []
    ' hours list may be newest-first; play selected hour then chronologically later hours
    hours = []
    for each h in d.hours
        hours.Push(pad2(h.hour))
    end for
    hours.Sort()
    selected = pad2(d.hours[m.hourList.itemSelected].hour)
    startAt = 0
    for i = 0 to hours.Count() - 1
        if hours[i] = selected then startAt = i
    end for
    for i = startAt to hours.Count() - 1
        url = Frigate_VodHourUrl(m.top.server, ym, dd, hours[i], m.camera, tz)
        playlist.Push({ url: url, title: m.camera + " — " + d.day + " " + hourLabel(hours[i]), format: "hls" })
    end for
    player = CreateObject("roSGNode", "VodPlayerScreen")
    player.server = m.top.server
    player.playlist = playlist
    player.startIndex = 0
    m.top.GetScene().CallFunc("pushScreen", player)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "left"
        if m.hourList.HasFocus()
            m.dayList.SetFocus(true) : return true
        else if m.dayList.HasFocus()
            m.camList.SetFocus(true) : return true
        end if
    else if key = "right"
        if m.camList.HasFocus() and m.dayList.content <> invalid and m.dayList.content.GetChildCount() > 0
            m.dayList.SetFocus(true) : return true
        else if m.dayList.HasFocus() and m.hourList.content <> invalid and m.hourList.content.GetChildCount() > 0
            m.hourList.SetFocus(true) : return true
        end if
    end if
    return false
end function
```

`Frigate_VodHourUrl` contains no `roUrlTransfer` use, so calling it from the render thread here is safe (see Task 4 note — only `Frigate_UrlEncode` is task-thread-only). `RecordingsScreen.xml` must also include `<script type="text/brightscript" uri="pkg:/source/FrigateUrls.brs" />`.

- [ ] **Step 3: Deploy and run manual checklist**

1. Home → Recordings lists cameras; OK loads days (only days that have recordings).
2. OK on a day lists its hours in local time; OK on an hour starts playback of that hour.
3. Left/Right seek ±30 s inside the hour; when an hour finishes, the next hour starts automatically; after the last hour the player closes.
4. Works on a frigate-auth server (VOD requests carry auth).
5. A camera with retention disabled shows "No recordings summary"/0 days, no crash.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: recordings browser with hour playback and auto-advance"
```

---

### Task 12: README + full regression pass

**Files:**
- Create: `README.md`
- Modify: `components/AppScene.xml` (remove any leftover placeholder label)

**Interfaces:** none — documentation and verification only.

- [ ] **Step 1: Write README.md**

Content must cover, in this order (write it out fully, not as bullets-of-bullets):

1. What it is: native Roku app for Frigate NVR 0.14+; camera grid with live snapshots, full-screen live HLS with audio, Review/Explore/Recordings playback, multiple servers.
2. Roku platform constraints (single decoder → snapshot grid; HLS-only live; H.264 + AAC).
3. Frigate server requirements:
   - Frigate 0.14+.
   - go2rtc restream configured for each camera you want live view on; go2rtc HTTP port (default 1984) reachable from the Roku.
   - Audio: go2rtc stream must carry AAC. Example config snippet:
     ```yaml
     go2rtc:
       streams:
         front_door:
           - rtsp://user:pass@10.0.0.20:554/stream1
           - "ffmpeg:front_door#audio=aac"
     ```
   - Auth modes: none (port 5000), Frigate login (port 8971), HTTP basic (reverse proxy). go2rtc port itself is unauthenticated on the LAN — note the implication.
4. Install: enable Roku developer mode, `cp .env.example .env` and fill in, `./deploy.sh`.
5. Usage: remote-key map per screen (grid: arrows/OK/up-to-menu; player: left/right switch, OK/down picker, `*` unused; review: `*` toggles severity; player seek ±30 s).
6. Troubleshooting table: live view errors (codec, port 1984, VLC test command), auth failures, empty review/explore, recordings gaps.
7. Development: `./deploy.sh --test` runs on-device tests; test output over telnet 8085.

- [ ] **Step 2: Full regression checklist**

Run `./deploy.sh --test` (expect `[TESTS DONE]`), then `./deploy.sh` and walk every checklist from Tasks 6–11 once more, on both an authenticated and an unauthenticated server. Record any failure as a bug to fix before finishing.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs: README with setup, server requirements, troubleshooting"
```

---

## Plan self-review notes

- Spec coverage: multi-server + per-server auth (Tasks 3–6), snapshot grid + tabs (7), live + audio + switching (8), Review (9), Explore (10), Recordings (11), errors surfaced per screen (6–11), README server-side codec guidance (12). Merged-grid and pre-0.14 support are explicitly out of scope per spec.
- Known on-device risks called out inline with fallbacks: Bearer-vs-cookie for Video auth (Task 9 step 5), `HttpHeaders` content field format, MarkupGrid item scaling in the player switcher (Task 8), recordings-summary response shape (Task 11 parses defensively).
- BrightScript thread rule threaded through: `roUrlTransfer` never on the render thread; render-safe duplicates are marked where needed.

