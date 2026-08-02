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
    m.fpsLabel = m.top.FindNode("fpsLabel")
    m.fpsTimer = m.top.FindNode("fpsTimer")
    m.fpsTimer.ObserveFieldScoped("fire", "onFpsTick")
    m.fpsTask = invalid
    m.lastFps = ""
    m.loadingLabel = m.top.FindNode("loadingLabel")
    m.hintLabel = m.top.FindNode("hintLabel")
    m.hintTimer = m.top.FindNode("hintTimer")
    m.hintTimer.ObserveFieldScoped("fire", "hideHint")
    m.hintShown = false
    m.infoPanel = m.top.FindNode("infoPanel")
    m.infoText = m.top.FindNode("infoText")
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
    if not m.started
        m.started = true
        m.idx = m.top.startIndex
        buildSwitcher()
        startCam()
    end if
    m.top.SetFocus(true)
end sub

' Fresh camera: rebuild the URL attempt chain, starting at the tier the
' server has already been downgraded to
sub startCam()
    leaveSnapshotMode()
    cam = m.top.cameras[m.idx]
    if m.top.server.liveMode = "snapshot" or m.serverSnapshot
        ' snapshots by configuration, or video already proved hopeless for
        ' this server this session
        enterSnapshotMode()
        showName(cam)
        return
    end if
    buildTiers(cam)
    m.tierIdx = m.serverTier
    if m.tierIdx >= m.tiers.Count() then m.tierIdx = m.tiers.Count() - 1
    m.attemptIdx = 0
    playCurrent()
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
    m.loadingLabel.text = "Loading snapshot mode ..."
    m.loadingLabel.visible = true
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
    m.snapMode = false
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

sub playCurrent()
    cam = m.top.cameras[m.idx]
    m.errorPanel.visible = false
    stopWarmTask()
    stopFpsPolling()
    m.video.control = "stop"
    ' Fetch the master playlist ourselves and hand the Video node the MEDIA
    ' playlist directly: newer Roku OS (seen on 15.3) refuses go2rtc's master
    ' when it declares an hvc1 codec — it never even opens a connection, just
    ' buffers forever. The media playlist carries no codec declaration, so the
    ' decoder sniffs the init segment instead and HEVC plays fine.
    if m.masterTask <> invalid then m.masterTask.UnobserveFieldScoped("output")
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.top.server, path: currentUrl(), method: "GET", body: "", savePath: "", context: currentUrl() }
    t.ObserveFieldScoped("output", "onMaster")
    t.control = "RUN"
    m.masterTask = t
    m.watchdog.control = "stop"
    m.watchdog.control = "start"
    showLoading()
    showName(cam)
end sub

' "Loading back_garage_sub (proxy) ..." while a source is being tried
sub showLoading()
    name = ""
    if m.tierIdx < m.tierNames.Count() then name = m.tierNames[m.tierIdx]
    route = "direct"
    if Instr(1, currentUrl(), "/api/go2rtc/") > 0 then route = "proxy"
    m.loadingLabel.text = "Loading " + name + " (" + route + ") ..."
    m.loadingLabel.visible = true
    if m.infoPanel.visible then updateInfoPanel()
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
        print "[live] master fetch failed/empty for "; out.context
        advanceAttempt()
        return
    end if
    ' resolve relative to the master URL's directory
    if Left(mediaUrl, 4) <> "http" then mediaUrl = Frigate_HlsBaseUrl(out.context) + mediaUrl
    print "[live] media playlist: "; mediaUrl
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
    hasSegment = false
    if out.ok and Frigate_PlaylistEntries(out.body).Count() > 0 then hasSegment = true
    if not hasSegment
        m.warmupTries = m.warmupTries + 1
        if m.warmupTries < 5
            fetchWarmup()
        else
            print "[live] warmup: playlist never gained segments"
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
    content.url = m.mediaUrl
    content.streamFormat = "hls"
    content.live = true
    headers = authHeaderStrings()
    if headers.Count() > 0 then content.HttpHeaders = headers
    ' No HttpCertificatesFile: the Video node only verifies TLS when a CA bundle
    ' is set, and Frigate's built-in cert is self-signed
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
        if m.tierIdx > m.serverTier
            ' downgrade the whole server: other cameras skip the tiers above
            m.serverTier = m.tierIdx
            print "[live] server downgraded to tier "; m.serverTier
        end if
        playCurrent()
    else
        ' out of video sources — fall back to refreshing snapshots, and take
        ' every camera on this server along
        m.serverSnapshot = true
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
    ' Cloudflare-fronted servers: the raw port is blackholed (connections
    ' hang, costing a full watchdog cycle each), so don't even try it
    useRaw = m.top.portFirst and m.top.server.cfProxied <> true
    print "[live] buildTiers "; cam; " portFirst="; m.top.portFirst; " cfProxied="; m.top.server.cfProxied; " names="; FormatJson(names)
    tiers = []
    for each n in names
        urls = []
        if useRaw then urls.Push(rawBase + n + "&mp4")
        urls.Push(proxyBase + n + "&mp4")
        tiers.Push(urls)
    end for
    m.tiers = tiers
    m.tierNames = names
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
    state = m.video.state
    print "[live] state="; state
    if state = "playing"
        m.watchdog.control = "stop"
        stopWarmTask()
        startFpsPolling()
        m.loadingLabel.visible = false
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

sub onStopPlayback()
    m.watchdog.control = "stop"
    stopWarmTask()
    stopFpsPolling()
    m.video.control = "stop"
    leaveSnapshotMode()
end sub

' --- FPS overlay: Roku's Video node doesn't expose decoder frame rate, so
' --- poll Frigate's /api/stats for the camera's real FPS while playing
sub startFpsPolling()
    m.fpsTimer.control = "start"
    fetchFps()
end sub

sub stopFpsPolling()
    m.fpsTimer.control = "stop"
    m.fpsLabel.visible = false
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
    if m.video.state = "playing"
        m.fpsLabel.text = m.lastFps
        m.fpsLabel.visible = true
    end if
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
    else
        name = ""
        if m.tierIdx < m.tierNames.Count() then name = m.tierNames[m.tierIdx]
        txt = txt + nl + "Stream: " + name
        route = "go2rtc port (direct)"
        if Instr(1, currentUrl(), "/api/go2rtc/") > 0 then route = "Frigate proxy"
        txt = txt + nl + "Route: " + route
        txt = txt + nl + "State: " + m.video.state
        seg = m.video.streamingSegment
        if seg <> invalid and seg.width <> invalid and seg.width > 0
            txt = txt + nl + "Resolution: " + StrI(seg.width).Trim() + " x " + StrI(seg.height).Trim()
        end if
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
        txt = txt + nl + "Quality tier: " + StrI(m.serverTier + 1).Trim() + " of " + StrI(m.tiers.Count()).Trim()
    end if
    m.infoText.text = txt
end sub

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
    if key = "options"
        toggleInfoPanel() : return true
    else if key = "left"
        switchBy(-1) : return true
    else if key = "right"
        switchBy(1) : return true
    else if key = "OK" or key = "down"
        if (m.errorPanel.visible or (m.snapMode and key = "OK")) and m.top.server.liveMode <> "snapshot"
            ' retry real video from full quality — undo the server-wide downgrade
            m.serverSnapshot = false
            m.serverTier = 0
            startCam()
        else
            m.switcher.visible = true
            m.switchGrid.SetFocus(true)
        end if
        return true
    end if
    return false
end function
