sub init()
    m.video = m.top.FindNode("video")
    m.snapA = m.top.FindNode("snapA")
    m.snapB = m.top.FindNode("snapB")
    m.snapFront = m.snapA
    m.snapBack = m.snapB
    m.snapA.ObserveFieldScoped("loadStatus", "onSnapLoaded")
    m.snapB.ObserveFieldScoped("loadStatus", "onSnapLoaded")
    m.snapTask = invalid
    m.warmTask = invalid
    m.snapMode = false
    m.snapFails = 0
    m.camName = m.top.FindNode("camName")
    m.modeIcon = m.top.FindNode("modeIcon")
    m.fpsTimer = m.top.FindNode("fpsTimer")
    m.fpsTimer.ObserveFieldScoped("fire", "onFpsTick")
    m.fpsTask = invalid
    m.lastFps = ""
    m.loadingLabel = m.top.FindNode("loadingLabel")
    m.hintLabel = m.top.FindNode("hintLabel")
    m.hintTimer = m.top.FindNode("hintTimer")
    m.hintTimer.ObserveFieldScoped("fire", "hideHint")
    ' contrast strip tracks whichever bottom text is showing
    m.bottomBar = m.top.FindNode("bottomBar")
    m.clockBg = m.top.FindNode("clockBg")
    m.loadingLabel.ObserveFieldScoped("visible", "updateBottomBar")
    m.hintLabel.ObserveFieldScoped("visible", "updateBottomBar")
    m.hintShown = false
    m.infoPanel = m.top.FindNode("infoPanel")
    m.infoText = m.top.FindNode("infoText")
    m.infoBg = m.top.FindNode("infoBg")
    m.playUrl = ""
    ' advertised feed resolution, parsed from the master playlist
    m.streamRes = ""
    ' next-camera snapshot prefetch for seamless cycle hops
    m.prefetch = invalid
    m.prefetchTask = invalid
    m.placeholder = m.top.FindNode("placeholder")
    m.videoCover = m.top.FindNode("videoCover")
    m.clockLabel = m.top.FindNode("clock")
    m.clockLabel.ObserveFieldScoped("visible", "updateBottomBar")
    m.clockTimer = m.top.FindNode("clockTimer")
    m.clockTimer.ObserveFieldScoped("fire", "onClockTick")
    m.weatherTimer = m.top.FindNode("weatherTimer")
    m.weatherTimer.ObserveFieldScoped("fire", "fetchWeather")
    m.weatherText = ""
    m.weatherTask = invalid
    m.retryTimer = m.top.FindNode("retryTimer")
    m.retryTimer.ObserveFieldScoped("fire", "onRetryTick")
    m.masterRetryTimer = m.top.FindNode("masterRetryTimer")
    m.masterRetryTimer.ObserveFieldScoped("fire", "onMasterRetry")
    m.masterTries = 0
    m.warmupTimer = m.top.FindNode("warmupTimer")
    m.warmupTimer.ObserveFieldScoped("fire", "fetchWarmup")
    ' The startup watchdog retires once playback begins, so a live stream
    ' that stalls mid-play would otherwise buffer forever with no fallback
    m.stallTimer = m.top.FindNode("stallTimer")
    m.stallTimer.ObserveFieldScoped("fire", "onStallTick")
    m.lastPos = -1
    m.stallCount = 0
    m.stallRestarted = false
    m.cycleTimer = m.top.FindNode("cycleTimer")
    m.cycleTimer.ObserveFieldScoped("fire", "onCycleTick")
    ' true while the tiny bundled clip plays under the snapshot posters to
    ' hold off the OS screensaver (video playback suppresses it; refreshing
    ' Posters do not)
    m.keepalive = false
    ' true while a background video retry runs behind live snapshots
    m.quietRetry = false
    ' set when go2rtc's "zero length playlist" error is seen — the * overlay
    ' then points at the server-side fix
    m.sawZeroLen = false
    ' fallback trail for the info overlay
    m.attemptLog = []
    ' cycle-all-servers tour state
    m.tourIdx = 0
    m.tourHops = 0
    m.tourTask = invalid
    m.errorPanel = m.top.FindNode("errorPanel")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.switcher = m.top.FindNode("switcher")
    m.switchGrid = m.top.FindNode("switchGrid")
    m.nameTimer = m.top.FindNode("nameTimer")
    m.nameTimer.ObserveFieldScoped("fire", "hideName")
    m.video.ObserveFieldScoped("state", "onVideoState")
    ' no built-in spinner/UI: video buffers invisibly behind the snapshots
    m.video.enableUI = false
    m.switchGrid.ObserveFieldScoped("itemSelected", "onSwitchPick")
    m.top.ObserveField("wasShown", "onShown")
    m.idx = 0
    m.started = false
    m.tiers = []
    m.tierNames = []
    m.tierIdx = 0
    m.attemptIdx = 0
    ' Downgrades are server-wide: once one camera drops to a lower stream
    ' tier (or all the way to snapshots), every camera in this player
    ' session starts there too. OK resets to full quality.
    m.serverTier = 0
    m.serverSnapshot = false
    ' A dead stream source (e.g. port 1984 behind Cloudflare, which silently
    ' drops the connection) buffers forever without ever raising an error, so
    ' a watchdog forces the next attempt when playback doesn't start in time.
    ' 10s is the max wait per source before downgrading; note a cold
    ' ffmpeg-transcoded _roku stream needs ~7-8s before its master playlist
    ' even answers, so it only just fits.
    m.watchdog = CreateObject("roSGNode", "Timer")
    m.watchdog.duration = 10
    m.watchdog.repeat = false
    m.watchdog.ObserveFieldScoped("fire", "onWatchdog")
end sub

' URL of the attempt currently being tried
function currentUrl() as string
    if m.tierIdx >= m.tiers.Count() then return ""
    return m.tiers[m.tierIdx][m.attemptIdx]
end function

sub onWatchdog()
    if m.video.state = "playing" then return
    print "[live] watchdog: no playback after 10s on "; currentUrl()
    advanceAttempt()
end sub

sub onShown()
    Hints_Show("playerKeys", "Camera view keys", "Up: stream info and quality" + Chr(10) + "Left / Right: switch cameras" + Chr(10) + "OK: stop camera cycling" + Chr(10) + "Down: retry video from full quality")
    if not m.started
        m.started = true
        m.idx = m.top.startIndex
        ' resume at the tier this server last landed on (6h TTL) instead of
        ' re-walking the full 10s-per-source cascade
        stored = TierStore_Get(m.top.server.id)
        if stored <> invalid and m.top.server.liveMode <> "snapshot"
            m.serverTier = stored.tier
            m.serverSnapshot = (stored.snapshot = true)
            print "[live] resuming stored tier="; m.serverTier; " snapshot="; m.serverSnapshot
        end if
        st = AppSettings_Load()
        if st.showClock = true
            onClockTick()
            m.clockLabel.visible = true
            m.modeIcon.visible = true
            m.clockTimer.control = "start"
            fetchWeather()
        end if
        if m.top.cycleMode
            m.cycleTimer.duration = st.cycleSecs
            m.cycleTimer.control = "start"
        end if
        if m.top.tourServers <> invalid
            for i = 0 to m.top.tourServers.Count() - 1
                if m.top.tourServers[i].id = m.top.server.id then m.tourIdx = i
            end for
        end if
        buildSwitcher()
        startCam()
        ' * on a home tile lands here with the info overlay requested
        if m.top.openInfo then toggleInfoPanel()
    end if
    m.top.SetFocus(true)
end sub

sub onClockTick()
    txt = TimeUtil_FormatClock()
    if m.weatherText <> "" then txt = m.weatherText + "   " + txt
    m.clockLabel.text = txt
    layoutClockBox()
end sub

' Size the snug clock backdrop to its content (weather makes it wider).
' The extra 150px leaves room for the LIVE/● mode tag plus a real gap
' before the right-aligned text — 90px let "LIVE" overlap the time.
sub layoutClockBox()
    w = Len(m.clockLabel.text) * 17 + 150
    if w < 240 then w = 240
    x = 1880 - w
    m.clockBg.width = w
    m.clockBg.translation = [x, 990]
    m.modeIcon.translation = [x + 14, 1000]
end sub

' Per-server weather for the clock box (see HomeScreen for the same flow)
sub fetchWeather()
    srv = m.top.server
    if srv = invalid or srv.zipcode = invalid or srv.zipcode = ""
        m.weatherText = ""
        onClockTick()
        return
    end if
    if m.weatherTask <> invalid then return
    t = CreateObject("roSGNode", "WeatherTask")
    t.zipcode = srv.zipcode
    if srv.tempUnit <> invalid then t.unit = srv.tempUnit
    if srv.zipLat <> invalid then t.lat = srv.zipLat
    if srv.zipLon <> invalid then t.lon = srv.zipLon
    t.ObserveFieldScoped("output", "onWeather")
    t.control = "RUN"
    m.weatherTask = t
    m.weatherTimer.control = "start"
end sub

sub onWeather(ev as object)
    out = ev.GetData()
    m.weatherTask = invalid
    if out.ok <> true then return
    unit = "f"
    srv = m.top.server
    if srv <> invalid and srv.tempUnit <> invalid and srv.tempUnit = "c" then unit = "c"
    m.weatherText = Weather_Format(out.tempF, out.precip, unit)
    onClockTick()
end sub

sub updateBottomBar()
    ' full-width strip only when loading/hint text is up; a clock alone gets
    ' a snug box with a little margin instead of a screen-wide bar
    others = m.loadingLabel.visible or m.hintLabel.visible
    m.bottomBar.visible = others
    m.clockBg.visible = m.clockLabel.visible and not others
end sub

sub onCycleTick()
    ' don't yank the screen away while the user is interacting
    if m.switcher.visible or m.infoPanel.visible then return
    ' at the end of this server's cameras, an all-servers tour hops on
    if m.top.tourServers <> invalid and m.top.tourServers.Count() > 1 and m.idx >= m.top.cameras.Count() - 1
        advanceTourServer()
    else
        switchBy(1)
    end if
end sub

' Move the tour to the next server: fetch its config, swap the player's
' server context, and start at its first camera. Dead or camera-less
' servers are skipped; if every other server fails, wrap locally.
sub advanceTourServer()
    if m.tourTask <> invalid then return   ' fetch already in flight
    m.tourHops = m.tourHops + 1
    if m.tourHops > m.top.tourServers.Count()
        m.tourHops = 0
        switchBy(1)
        return
    end if
    m.tourIdx = (m.tourIdx + 1) mod m.top.tourServers.Count()
    srv = m.top.tourServers[m.tourIdx]
    print "[live] tour: fetching config for "; srv.name
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: srv, path: "/api/config", method: "GET", body: "", savePath: "", context: "tour" + srv.id }
    t.ObserveFieldScoped("output", "onTourConfig")
    t.control = "RUN"
    m.tourTask = t
end sub

sub onTourConfig(ev as object)
    out = ev.GetData()
    m.tourTask = invalid
    srv = m.top.tourServers[m.tourIdx]
    if out.context <> "tour" + srv.id then return
    parsed = invalid
    if out.ok then parsed = Frigate_ParseCameraConfig(ParseJson(out.body))
    if parsed = invalid or parsed.cameras.Count() = 0
        advanceTourServer()
        return
    end if
    m.tourHops = 0
    cams = parsed.cameras
    filtered = Frigate_FilterCycleCams(cams, [], srv.cycleCams)
    if filtered <> invalid then cams = filtered.cameras
    print "[live] tour: now on "; srv.name; " ("; cams.Count(); " cameras)"
    m.top.server = srv
    m.top.cameras = cams
    m.top.liveStreams = parsed.liveStreams
    m.top.liveStreamsSub = parsed.liveStreamsSub
    m.top.snapPaths = []
    m.serverTier = 0
    m.serverSnapshot = false
    stored = TierStore_Get(srv.id)
    if stored <> invalid and srv.liveMode <> "snapshot"
        m.serverTier = stored.tier
        m.serverSnapshot = (stored.snapshot = true)
    end if
    m.sawZeroLen = false
    m.weatherText = ""
    fetchWeather()
    m.idx = 0
    buildSwitcher()
    startCam()
end sub

' Fresh camera: rebuild the URL attempt chain, starting at the tier the
' server has already been downgraded to
' Snapshots first, always: an instant picture while video sources are tried
' in the background; the first one to reach "playing" swaps in seamlessly
sub startCam()
    leaveSnapshotMode()
    m.quietRetry = false
    m.attemptLog = []
    cam = m.top.cameras[m.idx]
    showPlaceholder(cam)
    enterSnapshotMode()
    showName(cam)
    if m.top.server.liveMode <> "snapshot" then startBgVideoAttempt()
    prefetchNextCam()
end sub

' During a tour, quietly fetch the NEXT camera's snapshot so the hop swaps
' straight to a fresh full-opacity image instead of a "Loading..." screen
sub prefetchNextCam()
    if not m.top.cycleMode then return
    cnt = m.top.cameras.Count()
    if cnt < 2 then return
    if m.prefetchTask <> invalid then m.prefetchTask.UnobserveFieldScoped("result")
    nxt = (m.idx + 1) mod cnt
    cam = m.top.cameras[nxt]
    t = CreateObject("roSGNode", "ThumbTask")
    t.server = m.top.server
    t.items = [{ key: cam, path: Frigate_SnapshotPath(cam, 1080), savePath: "tmp:/cyc_" + cam + ".jpg" }]
    t.ObserveFieldScoped("result", "onPrefetch")
    t.control = "RUN"
    m.prefetchTask = t
end sub

sub onPrefetch(ev as object)
    res = ev.GetData()
    m.prefetch = { cam: res.key, path: res.savePath, ok: res.ok = true }
end sub

' Background video cascade behind the live snapshots. fromTier -1 = start
' at the tier this server last worked at; 0 = retry from full quality.
sub startBgVideoAttempt(fromTier = -1 as integer)
    m.quietRetry = true
    stopKeepalive()
    buildTiers(m.top.cameras[m.idx])
    if fromTier >= 0
        m.tierIdx = fromTier
    else
        m.tierIdx = m.serverTier
    end if
    if m.tierIdx >= m.tiers.Count() then m.tierIdx = m.tiers.Count() - 1
    if m.tierIdx < 0 then m.tierIdx = 0
    m.attemptIdx = 0
    playCurrent()
end sub

' Last grid snapshot for this camera, dimmed, so the cascade never runs
' against a black screen (snapPaths is index-aligned with cameras)
sub showPlaceholder(cam as string)
    m.placeholder.visible = false
    m.placeholder.uri = ""
    m.placeholder.opacity = 0.45
    ' a prefetched tour snapshot is seconds old — show it full strength
    if m.prefetch <> invalid and m.prefetch.ok and m.prefetch.cam = cam
        m.placeholder.uri = m.prefetch.path
        m.placeholder.opacity = 1.0
        m.placeholder.visible = true
        return
    end if
    paths = m.top.snapPaths
    if paths <> invalid and m.idx < paths.Count() and paths[m.idx] <> ""
        m.placeholder.uri = paths[m.idx]
        m.placeholder.visible = true
    end if
end sub

sub hidePlaceholder()
    m.placeholder.visible = false
end sub

' --- snapshot-mode fallback: full-screen refreshing stills when no video
' --- source will play (works on any Roku regardless of codec/OS quirks)
sub enterSnapshotMode()
    cam = m.top.cameras[m.idx]
    print "[live] snapshot mode for "; cam
    m.watchdog.control = "stop"
    stopWarmTask()
    stopFpsPolling()
    m.video.control = "stop"
    m.errorPanel.visible = false
    m.snapMode = true
    m.snapFails = 0
    m.modeIcon.text = "●"   ' ● = snapshots, "LIVE" = video (▶/■ lack glyphs here)
    m.videoCover.visible = true
    m.loadingLabel.text = "Loading..."
    ' skip the label when a fresh prefetched image is already on screen
    m.loadingLabel.visible = not m.placeholder.visible
    startKeepalive()
    ' downgraded here (vs. snapshot by configuration): quietly retry video
    ' every few minutes so a transient failure recovers on its own
    if m.top.server.liveMode <> "snapshot" then m.retryTimer.control = "start"
    if m.infoPanel.visible then updateInfoPanel()
    ' Snapshot sources in preference order: go2rtc frame.jpeg gives FULL
    ' resolution frames from the main stream (Frigate's latest.jpg only has
    ' the low-res detect stream); raw port first, then the authenticated
    ' proxy, then latest.jpg as a last resort.
    main = cam
    streams = m.top.liveStreams
    if streams <> invalid and streams.DoesExist(cam) then main = streams[cam]
    host = Frigate_HostFromUrl(m.top.server.baseUrl)
    m.snapUrls = []
    if m.top.server.cfProxied <> true
        m.snapUrls.Push("http://" + host + ":" + StrI(m.top.server.go2rtcPort).Trim() + "/api/frame.jpeg?src=" + main)
    end if
    m.snapUrls.Push(m.top.server.baseUrl + "/api/go2rtc/api/frame.jpeg?src=" + main)
    m.snapUrls.Push("")
    m.snapUrlIdx = 0
    startSnapTask()
end sub

sub startSnapTask()
    stopSnapTask()
    t = CreateObject("roSGNode", "SnapshotTask")
    t.server = m.top.server
    t.cameras = [m.top.cameras[m.idx]]
    t.fullUrl = m.snapUrls[m.snapUrlIdx]
    ' frame.jpeg takes ~2-3s server-side, so a short pause suffices; the
    ' latest.jpg fallback is instant and needs a real interval
    if t.fullUrl = ""
        t.refreshMs = 1000
    else
        t.refreshMs = 1000
    end if
    t.height = 1080
    dt = CreateObject("roDateTime")
    t.tag = "lv" + StrI(dt.AsSeconds()).Trim() + "_"
    t.ObserveFieldScoped("result", "onLiveSnap")
    t.control = "RUN"
    m.snapTask = t
end sub

sub stopSnapTask()
    if m.snapTask <> invalid
        m.snapTask.UnobserveFieldScoped("result")
        m.snapTask.quit = true
        m.snapTask = invalid
    end if
end sub

sub leaveSnapshotMode()
    stopSnapTask()
    stopKeepalive()
    m.retryTimer.control = "stop"
    m.snapMode = false
    m.videoCover.visible = false
    m.snapA.visible = false
    m.snapB.visible = false
    m.snapA.uri = ""
    m.snapB.uri = ""
end sub

sub onLiveSnap(ev as object)
    res = ev.GetData()
    if not m.snapMode then return
    if not res.ok
        m.snapFails = m.snapFails + 1
        if m.snapFails >= 3
            if m.snapUrlIdx < m.snapUrls.Count() - 1
                ' this snapshot source doesn't work; try the next one
                m.snapFails = 0
                m.snapUrlIdx = m.snapUrlIdx + 1
                startSnapTask()
            else
                showFinalError("no video source works and snapshots are unavailable")
            end if
        end if
        return
    end if
    m.snapFails = 0
    m.loadingLabel.visible = false
    hidePlaceholder()
    if m.snapFront.uri = ""
        m.snapFront.uri = res.path
        m.snapFront.visible = true
    else
        m.snapBack.uri = res.path
    end if
end sub

sub onSnapLoaded()
    if not m.snapMode then return
    if m.snapBack.loadStatus = "ready" and m.snapBack.uri <> ""
        m.snapBack.visible = true
        m.snapFront.visible = false
        tmp = m.snapFront
        m.snapFront = m.snapBack
        m.snapBack = tmp
    end if
end sub

sub stopWarmTask()
    if m.warmTask <> invalid
        m.warmTask.quit = true
        m.warmTask = invalid
    end if
end sub

' --- screensaver guard: play a bundled clip on loop underneath the snapshot
' --- posters; video playback is the only thing that reliably holds off the
' --- OS screensaver, which otherwise interrupts a wall dashboard. The clip
' --- is 10 minutes of mid-gray: TVs drive their backlight from the video
' --- plane, so a black clip (or frequent loop restarts) made the whole
' --- screen pulse dark and bright in snapshot mode.
sub startKeepalive()
    if m.keepalive then return
    m.keepalive = true
    content = CreateObject("roSGNode", "ContentNode")
    content.url = "pkg:/images/keepalive.mp4"
    content.streamFormat = "mp4"
    m.video.loop = true
    m.video.content = content
    m.video.control = "play"
end sub

sub stopKeepalive()
    if not m.keepalive then return
    m.keepalive = false
    m.video.loop = false
    m.video.control = "stop"
end sub

' Frozen position after playback started (live edge lost, dead session):
' restart the same attempt once, cascade if it stalls again
sub onStallTick()
    if m.keepalive or m.snapMode
        m.stallTimer.control = "stop"
        return
    end if
    state = m.video.state
    if state <> "playing" and state <> "buffering" then return
    curPos = m.video.position
    if curPos = m.lastPos
        m.stallCount = m.stallCount + 1
    else
        m.stallCount = 0
        m.stallRestarted = false
    end if
    m.lastPos = curPos
    if m.stallCount >= 2
        m.stallCount = 0
        m.stallTimer.control = "stop"
        if not m.stallRestarted
            print "[live] stall: position frozen 20s — restarting attempt"
            m.stallRestarted = true
            playCurrent()
        else
            print "[live] stall: repeated — advancing"
            advanceAttempt()
        end if
    end if
end sub

' Every few minutes while on snapshots: retry video from full quality
sub onRetryTick()
    if not m.snapMode or m.quietRetry then return
    if m.top.server.liveMode = "snapshot" then return
    print "[live] periodic video retry"
    startBgVideoAttempt(0)
end sub

sub playCurrent()
    cam = m.top.cameras[m.idx]
    m.errorPanel.visible = false
    stopWarmTask()
    stopFpsPolling()
    m.stallTimer.control = "stop"
    m.video.control = "stop"
    m.masterTries = 0
    fetchMaster()
    ' MediaMTX starts its go2rtc pull on demand — a cold ffmpeg chain needs
    ' ~10s before the playlist exists, so give that route a longer leash
    if isMtxUrl(currentUrl())
        m.watchdog.duration = 15
    else
        m.watchdog.duration = 10
    end if
    m.watchdog.control = "stop"
    m.watchdog.control = "start"
    tname = ""
    if m.tierIdx < m.tierNames.Count() then tname = m.tierNames[m.tierIdx]
    logAttempt(tname + " via " + routeName(currentUrl()))
    ' background attempts are silent on screen — the Up overlay's trail is
    ' where the cascade shows its work
    if m.infoPanel.visible then updateInfoPanel()
end sub

' Fetch the master playlist ourselves and hand the Video node the MEDIA
' playlist directly: newer Roku OS (seen on 15.3) refuses go2rtc's master
' when it declares an hvc1 codec — it never even opens a connection, just
' buffers forever. The media playlist carries no codec declaration, so the
' decoder sniffs the init segment instead and HEVC plays fine.
sub fetchMaster()
    if m.masterTask <> invalid then m.masterTask.UnobserveFieldScoped("output")
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: currentUrl(), method: "GET", body: "", savePath: "", context: currentUrl() }
    t.ObserveFieldScoped("output", "onMaster")
    t.control = "RUN"
    m.masterTask = t
end sub

' MediaMTX 404s while its on-demand source spins up; re-poll the master on a
' 1s cadence and let the watchdog cap the total wait
sub onMasterRetry()
    if m.masterTries = 0 then return   ' attempt changed since scheduling
    fetchMaster()
end sub


sub onMaster(ev as object)
    out = ev.GetData()
    if out.context <> currentUrl() then return   ' stale response
    m.masterTask = invalid
    mediaUrl = ""
    if out.ok
        entries = Frigate_PlaylistEntries(out.body)
        if entries.Count() > 0 then mediaUrl = entries[entries.Count() - 1]
    end if
    if mediaUrl = ""
        if isMtxUrl(out.context) and m.masterTries < 12
            ' on-demand source still warming — keep polling under the watchdog
            m.masterTries = m.masterTries + 1
            m.masterRetryTimer.control = "start"
            return
        end if
        print "[live] master fetch failed/empty for "; out.context
        advanceAttempt()
        return
    end if
    m.masterTries = 0
    ' resolve relative to the master URL's directory
    if Left(mediaUrl, 4) <> "http" then mediaUrl = Frigate_HlsBaseUrl(out.context) + mediaUrl
    print "[live] media playlist: "; mediaUrl
    ' remember the advertised resolution (e.g. RESOLUTION=1280x720) for the
    ' info overlay; go2rtc masters omit it, MediaMTX/Frigate include it
    m.streamRes = ""
    p = Instr(1, out.body, "RESOLUTION=")
    if p > 0
        i = p + 11
        while i <= Len(out.body)
            c = Mid(out.body, i, 1)
            if (c >= "0" and c <= "9") or c = "x"
                m.streamRes = m.streamRes + c
            else
                exit while
            end if
            i = i + 1
        end while
    end if
    ' Always hand Roku the MEDIA playlist. Handing the master was tried for
    ' audio (MediaMTX fmp4 keeps audio in a separate rendition) but Roku's
    ' demuxer corrupts video on that layout — audio must instead come muxed
    ' into the segments (MediaMTX hlsVariant: mpegts).
    m.playUrl = mediaUrl
    ' Warm the session up before handing it to Roku: a freshly created go2rtc
    ' HLS session has no segments for the first moments, and OS 15.3 treats an
    ' empty media playlist as fatal ("mpr zero length playlist") instead of
    ' re-polling. Poll it ourselves until segments exist.
    m.mediaUrl = mediaUrl
    m.warmupTries = 0
    fetchWarmup()
end sub

sub fetchWarmup()
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: m.mediaUrl, method: "GET", body: "", savePath: "", context: m.mediaUrl }
    t.ObserveFieldScoped("output", "onWarmup")
    t.control = "RUN"
    m.warmupTask = t
end sub

sub onWarmup(ev as object)
    out = ev.GetData()
    if out.context <> m.mediaUrl then return   ' stale
    m.warmupTask = invalid
    segs = 0
    if out.ok then segs = Frigate_PlaylistEntries(out.body).Count()
    ' MediaMTX: wait for real runway (3 segments) before attaching Roku's
    ' player — attaching at 1-2 segments strands it at the live edge and it
    ' stalls to death. Paced retries; the watchdog caps the total wait.
    need = 1
    maxTries = 5
    if isMtxUrl(currentUrl())
        need = 3
        maxTries = 15
    end if
    if segs < need
        m.warmupTries = m.warmupTries + 1
        if m.warmupTries < maxTries
            if need > 1
                m.warmupTimer.control = "start"
            else
                fetchWarmup()
            end if
        else
            print "[live] warmup: playlist never gained enough segments (got "; segs; ")"
            advanceAttempt()
        end if
        return
    end if
    print "[live] warmup ok after "; m.warmupTries; " retries"
    ' Keep the go2rtc session alive until the player takes over — see
    ' StreamWarmTask. Without this, remote/proxied streams die before the
    ' Video node's first fetch and every attempt fails with -3.
    stopWarmTask()
    wt = CreateObject("roSGNode", "StreamWarmTask")
    wt.server = m.top.server
    wt.playlistUrl = m.mediaUrl
    wt.control = "RUN"
    m.warmTask = wt
    ' HLS, not progressive stream.mp4: Roku's mp4 reader issues byte-range
    ' requests an endless live stream can't satisfy, and only supports HEVC
    ' inside HLS/DASH. No content.title: Roku overlays its own title UI on top
    ' of our camName label, showing the name twice.
    content = CreateObject("roSGNode", "ContentNode")
    content.url = m.playUrl
    content.streamFormat = "hls"
    content.live = true
    headers = authHeaderStrings()
    if headers.Count() > 0 then content.HttpHeaders = headers
    ' The Video node only verifies TLS when a CA bundle is set; Frigate's
    ' built-in cert is self-signed, so verification is opt-in per server
    if m.top.server.verifyTls = true then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    m.video.content = content
    m.video.control = "play"
end sub

sub advanceAttempt()
    if m.attemptIdx < m.tiers[m.tierIdx].Count() - 1
        ' same stream, next route (raw port -> proxy): not a downgrade
        m.attemptIdx = m.attemptIdx + 1
        playCurrent()
    else if m.tierIdx < m.tiers.Count() - 1
        m.tierIdx = m.tierIdx + 1
        m.attemptIdx = 0
        if not m.quietRetry and m.tierIdx > m.serverTier
            ' downgrade the whole server: other cameras skip the tiers above
            m.serverTier = m.tierIdx
            TierStore_Set(m.top.server.id, m.serverTier, false)
            print "[live] server downgraded to tier "; m.serverTier
        end if
        playCurrent()
    else if m.quietRetry
        ' background cascade exhausted every source — stay on the snapshots
        ' the user is already watching; the retry timer tries again later
        print "[live] background video attempts exhausted; staying on snapshots"
        m.quietRetry = false
        m.watchdog.control = "stop"
        m.video.control = "stop"
        logAttempt("snapshots")
        m.loadingLabel.visible = false
        if m.infoPanel.visible then updateInfoPanel()
        startKeepalive()
    else
        ' out of video sources — fall back to refreshing snapshots, and take
        ' every camera on this server along
        m.serverSnapshot = true
        TierStore_Set(m.top.server.id, m.serverTier, true)
        enterSnapshotMode()
    end if
end sub

sub showFinalError(reason as string)
    m.watchdog.control = "stop"
    stopWarmTask()
    m.loadingLabel.visible = false
    m.video.control = "stop"
    m.errorDetail.text = m.top.cameras[m.idx] + " won't play: " + reason
    m.errorPanel.visible = true
end sub

' URL candidates for a camera, grouped into quality tiers. Each tier is one
' stream name reached by up to two routes: the raw go2rtc port when enabled
' (best on the LAN), then Frigate's authenticated go2rtc proxy (works
' remotely / through Cloudflare where port 1984 is unreachable). Tier order:
' full-res main, then the sub when the main won't decode (panoramic mains
' exceed Roku's 3840x2160 decoder cap), then an optional "<name>_roku"
' transcode (e.g. cam_roku: ffmpeg:cam_main#video=h264#width=1280) as the
' last resort — see Frigate_LiveStreamNames. A fixed server streamType
' collapses this to a single tier of just that variant. If a name doesn't
' exist the master fetch 404s instantly and we move on.
' Sets m.tiers plus m.tierNames (stream name per tier, for the UI).
sub buildTiers(cam as string)
    main = cam
    streams = m.top.liveStreams
    if streams <> invalid and streams.DoesExist(cam) then main = streams[cam]
    pref = m.top.server.streamType
    ' a per-camera override (set from the * overlay) beats the server default
    override = CamStream_Get(m.top.server.id, cam)
    if override <> "" then pref = override
    if pref <> invalid and pref <> "" and pref <> "auto"
        names = [Frigate_StreamNameForType(main, pref)]
    else
        subName = ""
        subs = m.top.liveStreamsSub
        if subs <> invalid and subs.DoesExist(cam) then subName = subs[cam]
        names = Frigate_LiveStreamNames(main, subName)
    end if
    host = Frigate_HostFromUrl(m.top.server.baseUrl)
    rawBase = "http://" + host + ":" + StrI(m.top.server.go2rtcPort).Trim() + "/api/stream.m3u8?src="
    proxyBase = m.top.server.baseUrl + "/api/go2rtc/api/stream.m3u8?src="
    ' MediaMTX (when detected) is the preferred route: it serves the same
    ' streams with a real multi-second HLS window, which go2rtc's ~1s window
    ' never provides — that window is why go2rtc HLS always dies on Roku
    useMtx = m.top.server.mediamtxOk = true
    mtxPort = m.top.server.mediamtxPort
    if mtxPort = invalid or mtxPort = 0 then mtxPort = 8888
    mtxBase = "http://" + host + ":" + StrI(mtxPort).Trim() + "/"
    ' Cloudflare-fronted servers: the raw port is blackholed (connections
    ' hang, costing a full watchdog cycle each), so don't even try it
    useRaw = m.top.portFirst and m.top.server.cfProxied <> true
    if useMtx
        ' via MediaMTX prefer the h264 _roku restream: HEVC mains stall (huge
        ' GOP segments, PCMU audio that fMP4 can't carry); _roku is built for this
        reordered = []
        for each n in names
            if Right(n, 5) = "_roku" then reordered.Push(n)
        end for
        for each n in names
            if Right(n, 5) <> "_roku" then reordered.Push(n)
        end for
        names = reordered
    end if
    print "[live] buildTiers "; cam; " mtx="; useMtx; " cfProxied="; m.top.server.cfProxied; " names="; FormatJson(names)
    tiers = []
    for each n in names
        urls = []
        if useMtx then urls.Push(mtxBase + n + "/index.m3u8")
        if useRaw then urls.Push(rawBase + n + "&mp4")
        urls.Push(proxyBase + n + "&mp4")
        tiers.Push(urls)
    end for
    m.tiers = tiers
    m.tierNames = names
end sub

' True when an attempt URL goes through MediaMTX rather than go2rtc
function isMtxUrl(url as string) as boolean
    return Instr(1, url, "/index.m3u8") > 0
end function

' Short route name for the current attempt URL
function routeName(url as string) as string
    if isMtxUrl(url) then return "MediaMTX"
    if Instr(1, url, "/api/go2rtc/") > 0 then return "proxy"
    return "direct"
end function

' Fallback trail shown in the info overlay: mark the previous attempt
' failed and note what is being tried now
sub logAttempt(entry as string)
    n = m.attemptLog.Count()
    if n > 0 then m.attemptLog[n - 1] = "x " + Mid(m.attemptLog[n - 1], 3)
    if n >= 8 then m.attemptLog.Shift()
    m.attemptLog.Push("> " + entry)
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
    if m.keepalive then return   ' the screensaver-guard clip is not a stream
    state = m.video.state
    print "[live] state="; state
    if state = "playing"
        if m.quietRetry
            ' background retry succeeded — swap the snapshots out for video
            print "[live] quiet retry recovered video at tier "; m.tierIdx
            m.quietRetry = false
            m.serverSnapshot = false
            m.serverTier = m.tierIdx
            TierStore_Set(m.top.server.id, m.serverTier, false)
            leaveSnapshotMode()
        end if
        m.watchdog.control = "stop"
        stopWarmTask()
        startFpsPolling()
        m.modeIcon.text = "LIVE"
        ' the winning attempt gets an explicit verdict in the trail
        n = m.attemptLog.Count()
        if n > 0 and Left(m.attemptLog[n - 1], 2) = "> "
            m.attemptLog[n - 1] = "OK " + Mid(m.attemptLog[n - 1], 3)
        end if
        m.lastPos = -1
        m.stallCount = 0
        m.stallTimer.control = "start"
        m.loadingLabel.visible = false
        hidePlaceholder()
        if not m.hintShown
            ' once per player session, on the first camera that plays
            m.hintShown = true
            m.hintLabel.visible = true
            m.hintTimer.control = "start"
        end if
    end if
    if m.infoPanel.visible then updateInfoPanel()
    if state = "error"
        stopFpsPolling()
        print "[live] errorCode="; m.video.errorCode; " errorMsg="; m.video.errorMsg; " url="; currentUrl()
        info = m.video.errorInfo
        if info <> invalid then print "[live] errorInfo: "; FormatJson(info)
        if info <> invalid and info.dbgmsg <> invalid and Instr(1, info.dbgmsg, "zero length playlist") > 0
            m.sawZeroLen = true
        end if
        ' advanceAttempt falls back to snapshot mode once every video source
        ' is exhausted — never strand the user on an error panel here
        advanceAttempt()
    end if
end sub

sub buildSwitcher()
    ' Snapshot paths come from HomeScreen's grid (index-aligned with cameras):
    ' roFileSystem is unavailable on the render thread, so no probing here
    content = CreateObject("roSGNode", "ContentNode")
    paths = m.top.snapPaths
    i = 0
    for each cam in m.top.cameras
        tile = content.CreateChild("CameraTileData")
        tile.cameraName = cam
        if paths <> invalid and i < paths.Count() and paths[i] <> "" then tile.snapPath = paths[i]
        i = i + 1
    end for
    m.switchGrid.content = content
end sub

sub onSwitchPick()
    m.idx = m.switchGrid.itemSelected
    m.switcher.visible = false
    m.top.SetFocus(true)
    startCam()
end sub

sub switchBy(delta as integer)
    n = m.top.cameras.Count()
    m.idx = ((m.idx + delta) mod n + n) mod n
    startCam()
end sub

' Manual left/right during a tour gives the chosen camera a full dwell
sub restartCycleDwell()
    if m.top.cycleMode
        m.cycleTimer.control = "stop"
        m.cycleTimer.control = "start"
    end if
end sub

sub onStopPlayback()
    m.watchdog.control = "stop"
    m.stallTimer.control = "stop"
    m.cycleTimer.control = "stop"
    m.clockTimer.control = "stop"
    stopWarmTask()
    stopFpsPolling()
    leaveSnapshotMode()   ' also stops the retry timer and keepalive clip
    m.video.control = "stop"
    hidePlaceholder()
end sub

' OK inside the * overlay: cycle this camera's stream override through
' auto + the variants that exist for it, then restart with the new pick
sub cycleCamOverride()
    cam = m.top.cameras[m.idx]
    main = cam
    streams = m.top.liveStreams
    if streams <> invalid and streams.DoesExist(cam) then main = streams[cam]
    subName = ""
    subs = m.top.liveStreamsSub
    if subs <> invalid and subs.DoesExist(cam) then subName = subs[cam]
    options = ["auto"]
    options.Append(Frigate_StreamTypes(Frigate_LiveStreamNames(main, subName)))
    cur = CamStream_Get(m.top.server.id, cam)
    if cur = "" then cur = "auto"
    idx = 0
    for i = 0 to options.Count() - 1
        if options[i] = cur then idx = i
    end for
    choice = options[(idx + 1) mod options.Count()]
    CamStream_Set(m.top.server.id, cam, choice)
    print "[live] stream override for "; cam; ": "; choice
    ' picking a stream implies the user wants video — retry even if downgraded
    m.serverSnapshot = false
    startCam()
    updateInfoPanel()
end sub

' --- FPS overlay: Roku's Video node doesn't expose decoder frame rate, so
' --- poll Frigate's /api/stats for the camera's real FPS while playing
sub startFpsPolling()
    m.fpsTimer.control = "start"
    fetchFps()
end sub

sub stopFpsPolling()
    m.fpsTimer.control = "stop"
end sub

sub onFpsTick()
    fetchFps()
end sub

sub fetchFps()
    if m.fpsTask <> invalid then return   ' one request in flight is plenty
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: "/api/stats", method: "GET", body: "", savePath: "", context: "stats" }
    t.ObserveFieldScoped("output", "onFpsStats")
    t.control = "RUN"
    m.fpsTask = t
end sub

sub onFpsStats(ev as object)
    m.fpsTask = invalid
    out = ev.GetData()
    if not out.ok then return
    stats = ParseJson(out.body)
    cam = m.top.cameras[m.idx]
    if stats = invalid or stats.cameras = invalid or stats.cameras[cam] = invalid then return
    fps = stats.cameras[cam].camera_fps
    if fps = invalid then return
    ' one decimal is enough ("5.1 fps"); Str() of a float pads a leading space
    rounded = Int(fps * 10 + 0.5) / 10.0
    m.lastFps = Str(rounded).Trim() + " fps"
    if m.infoPanel.visible then updateInfoPanel()
end sub

sub hideHint()
    m.hintLabel.visible = false
end sub

' * key overlay: everything worth knowing about the current stream
sub toggleInfoPanel()
    m.infoPanel.visible = not m.infoPanel.visible
    if m.infoPanel.visible
        updateInfoPanel()
        ' keep FPS fresh while the overlay is up, even in snapshot mode
        m.fpsTimer.control = "start"
        fetchFps()
    else if m.video.state <> "playing"
        m.fpsTimer.control = "stop"
    end if
end sub

sub updateInfoPanel()
    nl = chr(10)
    cam = m.top.cameras[m.idx]
    txt = "Camera: " + cam
    if m.top.server <> invalid and m.top.server.name <> invalid
        txt = txt + nl + "Server: " + m.top.server.name
    end if
    if m.snapMode
        txt = txt + nl + "Mode: snapshot (refreshing stills)"
        if m.snapFront.bitmapWidth > 0
            txt = txt + nl + "Snapshot resolution: " + StrI(m.snapFront.bitmapWidth).Trim() + "x" + StrI(m.snapFront.bitmapHeight).Trim()
        end if
        if m.quietRetry
            txt = txt + nl + "Video: being tried in the background"
        else
            txt = txt + nl + "Video: not available — retries periodically"
        end if
    else
        name = ""
        if m.tierIdx < m.tierNames.Count() then name = m.tierNames[m.tierIdx]
        txt = txt + nl + "Stream: " + name
        route = "go2rtc port (direct)"
        if isMtxUrl(currentUrl()) then route = "MediaMTX"
        if Instr(1, currentUrl(), "/api/go2rtc/") > 0 then route = "Frigate proxy"
        txt = txt + nl + "Route: " + route
        txt = txt + nl + "State: " + m.video.state
        ' decoder-reported size when available, else the playlist's advertised one
        resTxt = ""
        seg = m.video.streamingSegment
        if seg <> invalid and seg.width <> invalid and seg.width > 0
            resTxt = StrI(seg.width).Trim() + "x" + StrI(seg.height).Trim()
        else if m.streamRes <> ""
            resTxt = m.streamRes
        end if
        if resTxt <> "" then txt = txt + nl + "Resolution: " + resTxt
        if seg <> invalid and seg.segBitrateBps <> invalid and seg.segBitrateBps > 0
            txt = txt + nl + "Stream bitrate: " + fmtBitrate(seg.segBitrateBps)
        end if
        si = m.video.streamInfo
        if si <> invalid and si.measuredBitrate <> invalid and si.measuredBitrate > 0
            txt = txt + nl + "Measured bandwidth: " + fmtBitrate(si.measuredBitrate)
        end if
    end if
    if m.lastFps <> "" then txt = txt + nl + "Camera FPS: " + m.lastFps
    if m.tiers.Count() > 0
        txt = txt + nl + "Quality: " + tierLabel(m.tierIdx, m.tiers.Count())
    end if
    ov = CamStream_Get(m.top.server.id, cam)
    if ov = "" then ov = "auto"
    txt = txt + nl + "Stream override: " + ov + "  (OK cycles)"
    ' the fallback trail; last 4 attempts shown (background sized after)
    if m.attemptLog <> invalid and m.attemptLog.Count() > 0
        txt = txt + nl + "Tried  (x failed, > trying, OK playing):"
        first = m.attemptLog.Count() - 4
        if first < 0 then first = 0
        for i = first to m.attemptLog.Count() - 1
            txt = txt + nl + "  " + m.attemptLog[i]
        end for
    end if
    if m.sawZeroLen
        txt = txt + nl + "Tip: go2rtc's HLS window is too small for Roku —"
        txt = txt + nl + "see README, 'Live video reliability'"
    end if
    m.infoText.text = txt
    ' size the dark backdrop to the text so long trails never overflow it
    r = m.infoText.boundingRect()
    m.infoBg.height = r.height + 48
end sub

' Friendly name for a spot in the downgrade chain: the first choice is
' "Best", the last fallback before snapshots is "Good"
function tierLabel(idx as integer, count as integer) as string
    if idx <= 0 or count <= 1 then return "Best"
    if idx = 1 and count >= 3 then return "Better"
    return "Good"
end function

function fmtBitrate(bps as integer) as string
    if bps >= 1000000
        tenths = Int(bps / 100000)
        return Str(tenths / 10.0).Trim() + " Mbps"
    end if
    return StrI(Int(bps / 1000)).Trim() + " kbps"
end function

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
    if m.infoPanel.visible and key = "OK"
        cycleCamOverride() : return true
    else if m.infoPanel.visible and (key = "back" or key = "up")
        toggleInfoPanel() : return true
    else if key = "options" or key = "up"
        ' up mirrors * because Roku TVs reserve * for their own picture
        ' settings sidebar during video playback
        toggleInfoPanel() : return true
    else if key = "OK" and m.top.cycleMode
        ' OK during a tour: stop cycling and stay on this camera
        m.top.cycleMode = false
        m.cycleTimer.control = "stop"
        m.hintLabel.text = "Cycling stopped"
        m.hintLabel.visible = true
        m.hintTimer.control = "start"
        return true
    else if key = "left"
        switchBy(-1)
        restartCycleDwell()
        return true
    else if key = "right"
        switchBy(1)
        restartCycleDwell()
        return true
    else if key = "OK" or key = "down"
        if (m.errorPanel.visible or (m.snapMode and key = "OK")) and m.top.server.liveMode <> "snapshot"
            ' retry real video from full quality — undo the server-wide downgrade
            m.serverSnapshot = false
            m.serverTier = 0
            TierStore_Set(m.top.server.id, 0, false)
            startCam()
        else
            m.switcher.visible = true
            m.switchGrid.SetFocus(true)
        end if
        return true
    end if
    return false
end function
