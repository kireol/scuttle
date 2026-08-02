sub init()
    m.grid = m.top.FindNode("grid")
    m.tabRow = m.top.FindNode("tabRow")
    m.menuRow = m.top.FindNode("menuRow")
    m.status = m.top.FindNode("status")
    m.clockLabel = m.top.FindNode("clock")
    m.clockTimer = m.top.FindNode("clockTimer")
    m.clockTimer.ObserveFieldScoped("fire", "onClockTick")
    m.actTimer = m.top.FindNode("actTimer")
    m.actTimer.ObserveFieldScoped("fire", "fetchActivity")
    m.staleTimer = m.top.FindNode("staleTimer")
    m.staleTimer.ObserveFieldScoped("fire", "onStaleTick")
    m.lastSnapAt = {}
    m.toast = m.top.FindNode("toast")
    m.toastText = m.top.FindNode("toastText")
    m.toastTimer = m.top.FindNode("toastTimer")
    m.toastTimer.ObserveFieldScoped("fire", "hideToast")
    m.toastCamera = ""
    m.seenReviewIds = {}
    m.seenSeeded = false
    m.bgVideo = m.top.FindNode("bgVideo")
    m.bgVideo.ObserveFieldScoped("state", "onBgState")
    m.bgPlaying = false
    m.kickTimer = m.top.FindNode("kickTimer")
    m.kickTimer.ObserveFieldScoped("fire", "startBgKeepalive")
    m.grid.ObserveFieldScoped("itemSelected", "onTileSelected")
    m.grid.ObserveFieldScoped("itemFocused", "updateScrollbar")
    m.scrollTrack = m.top.FindNode("scrollTrack")
    m.scrollThumb = m.top.FindNode("scrollThumb")
    m.gridTotalRows = 0
    m.gridVisibleRows = 1
    m.top.ObserveField("wasShown", "onShown")
    m.top.ObserveField("visible", "onVisibleChange")

    m.menuItems = ["Live", "Review", "Explore", "Recordings", "Cycle Cameras", "Settings"]
    m.settingsIdx = 5   ' index of "Settings" in m.menuItems
    m.focusZone = "grid"   ' "tabs" | "menu" | "grid"
    m.tabIdx = 0
    m.menuIdx = 0
    m.servers = []
    m.cameras = []
    m.liveStreams = {}
    m.liveStreamsSub = {}
    m.loadedServerId = ""
    ' land on the server (and roughly the tile) the user last used
    m.pendingServerId = AppSettings_Load().lastServerId
    m.snapTasks = []
    m.actTask = invalid
    m.pendingTask = invalid
    m.redirectedToSettings = false
end sub

sub onClockTick()
    m.clockLabel.text = TimeUtil_FormatClock()
end sub

sub applyClockSetting()
    show = AppSettings_Load().showClock = true
    m.clockLabel.visible = show
    if show
        onClockTick()
        m.clockTimer.control = "start"
    else
        m.clockTimer.control = "stop"
    end if
end sub

sub onShown()
    ' keepalive start is deferred: playing during scene construction wedges
    ' the Video node with state stuck on "playing" and no actual session
    m.kickTimer.control = "start"
    m.staleTimer.control = "start"
    if m.sceneObserved = invalid
        ' react to servers added externally via the ECP input API
        m.sceneObserved = true
        m.top.GetScene().ObserveFieldScoped("serversChanged", "onServersChangedExternally")
        m.top.GetScene().ObserveFieldScoped("goToServerId", "onGoToServer")
    end if
    reloadServers()
end sub

' A pushed screen (server edit "View cameras") asked to land on this server's
' tab; remember it — reloadServers applies it when this screen is shown next
sub onGoToServer()
    id = m.top.GetScene().goToServerId
    if id <> "" then m.pendingServerId = id
end sub

sub onServersChangedExternally()
    if m.top.visible then reloadServers()
end sub

sub onVisibleChange()
    if not m.top.visible
        stopSnapshots()
        stopBgKeepalive()
        hideToast()
    else
        startBgKeepalive()
    end if
end sub

' --- screensaver guard for the dashboard grid: same trick as the player's
' --- snapshot mode — a tiny offscreen looping clip keeps "video playing"
' --- true so the OS screensaver never interrupts the wall display
sub startBgKeepalive()
    ' only trust "playing": a play issued during cold launch can wedge in
    ' buffering (or vanish), so onStaleTick re-kicks with a stop+play until
    ' it actually sticks
    if m.bgVideo.state = "playing" then return
    m.bgPlaying = true
    m.bgVideo.control = "stop"
    c = CreateObject("roSGNode", "ContentNode")
    c.url = "pkg:/images/keepalive.mp4"
    c.streamFormat = "mp4"
    m.bgVideo.loop = true
    m.bgVideo.content = c
    m.bgVideo.control = "play"
end sub

sub stopBgKeepalive()
    if not m.bgPlaying then return
    m.bgPlaying = false
    m.bgVideo.control = "stop"
end sub

sub onBgState()
    if m.bgVideo.state = "error"
        print "[home] bg keepalive errorCode="; m.bgVideo.errorCode; " msg="; m.bgVideo.errorMsg
    end if
end sub

' --- stale tiles: when refreshes stop arriving (server down, task wedged,
' --- network gone) the tile shows the image age instead of posing as live
sub onStaleTick()
    if not m.top.visible or m.grid.content = invalid then return
    print "[home] staleTick bgState="; m.bgVideo.state
    startBgKeepalive()   ' self-heal: cold-launch play can be dropped
    threshold = AppSettings_Load().refreshSecs * 2
    if threshold < 30 then threshold = 30
    now = CreateObject("roDateTime").AsSeconds()
    for i = 0 to m.grid.content.GetChildCount() - 1
        tile = m.grid.content.GetChild(i)
        if m.lastSnapAt.DoesExist(tile.cameraName)
            age = now - m.lastSnapAt[tile.cameraName]
            if age > threshold
                tile.staleText = fmtAge(age)
            else
                tile.staleText = ""
            end if
        end if
    end for
end sub

function fmtAge(secs as integer) as string
    if secs < 120 then return StrI(secs).Trim() + "s ago"
    if secs < 7200 then return StrI(Int(secs / 60)).Trim() + "m ago"
    return StrI(Int(secs / 3600)).Trim() + "h ago"
end function

sub hideToast()
    m.toast.visible = false
    m.toastCamera = ""
end sub

' OK while a toast is up jumps to the alerting camera instead of the
' focused tile / menu item; returns true when it consumed the press
function tryToastJump() as boolean
    if not m.toast.visible or m.toastCamera = "" then return false
    cam = m.toastCamera
    hideToast()
    for i = 0 to m.cameras.Count() - 1
        if m.cameras[i] = cam
            openPlayer(i, false)
            return true
        end if
    end for
    return false
end function

sub reloadServers()
    stopSnapshots()
    m.servers = ServerStore_Load()
    if m.servers.Count() = 0
        renderTabsEmpty()
        m.grid.content = CreateObject("roSGNode", "ContentNode")
        if not m.redirectedToSettings
            m.redirectedToSettings = true
            m.top.GetScene().CallFunc("pushScreen", CreateObject("roSGNode", "ServerListScreen"))
        else
            m.status.text = "No servers configured — select Settings to add one"
            m.focusZone = "menu"
            m.menuIdx = m.settingsIdx
            m.top.SetFocus(true)
            renderMenu()
        end if
        return
    end if
    if m.pendingServerId <> ""
        for i = 0 to m.servers.Count() - 1
            if m.servers[i].id = m.pendingServerId then m.tabIdx = i : exit for
        end for
        m.pendingServerId = ""
    end if
    if m.tabIdx >= m.servers.Count() then m.tabIdx = 0
    m.server = m.servers[m.tabIdx]
    ' switching servers: drop the old server's grid entirely so stale
    ' cameras never linger while (or if) the new config loads
    if m.loadedServerId <> m.server.id then clearCameras()
    st = AppSettings_Load()
    if st.lastServerId <> m.server.id
        st.lastServerId = m.server.id
        AppSettings_Save(st)
    end if
    applyClockSetting()
    renderTabs()
    renderMenu()
    fetchConfig()
end sub

sub clearCameras()
    m.cameras = []
    m.liveStreams = {}
    m.liveStreamsSub = {}
    m.lastSnapAt = {}
    m.grid.content = CreateObject("roSGNode", "ContentNode")
    m.gridTotalRows = 0
    updateScrollbar()
end sub

sub renderTabsEmpty()
    while m.tabRow.GetChildCount() > 0
        m.tabRow.RemoveChildIndex(0)
    end while
    while m.menuRow.GetChildCount() > 0
        m.menuRow.RemoveChildIndex(0)
    end while
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
        if m.focusZone = "tabs" and i = m.tabIdx
            lbl.color = "0xFFFFFFFF"
            drawFocusOutline(m.tabRow, x, Len(m.servers[i].name) * 22, 60)
        end if
        x = x + 40 + Len(m.servers[i].name) * 22
    end for
end sub

' White outline (4 thin rectangles) around a focused row item; Rectangle
' has no border support, so build it like CameraTile's focusRing
sub drawFocusOutline(parent as object, labelX as integer, textWidth as integer, h as integer)
    ox = labelX - 14
    oy = -8
    w = textWidth + 28
    t = 3
    sides = [[ox, oy, w, t], [ox, oy + h - t, w, t], [ox, oy, t, h], [ox + w - t, oy, t, h]]
    for each s in sides
        r = parent.CreateChild("Rectangle")
        r.color = "0xFFFFFFFF"
        r.translation = [s[0], s[1]]
        r.width = s[2]
        r.height = s[3]
    end for
end sub

sub renderMenu()
    ' Dim the grid when focus is on the menu/tabs: the tiles' focus ring cannot
    ' reliably be cleared (itemHasFocus is not reset when the grid blurs).
    ' Also make the grid unfocusable there: SetFocus(true) on m.top otherwise
    ' bounces focus straight back into the grid (Group focus redirects to a
    ' focusable descendant), leaving left/right silently moving grid tiles
    ' while the menu highlight never moves
    if m.focusZone = "grid"
        m.grid.opacity = 1.0
    else
        m.grid.opacity = 0.45
        ' Focus the menuRow Group, NOT m.top: focusing an ancestor of the grid
        ' bounces focus back into the grid. menuRow has no focusable children,
        ' so it holds focus and keys bubble to this component's onKeyEvent.
        m.menuRow.SetFocus(true)
    end if
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
            drawFocusOutline(m.menuRow, x, Len(m.menuItems[i]) * 17, 52)
        else
            lbl.color = "0x8A959CFF"
        end if
        x = x + Len(m.menuItems[i]) * 17 + 70
    end for
end sub

sub fetchConfig()
    m.status.text = "Loading cameras from " + m.server.name + " ..."
    if m.pendingTask <> invalid then m.pendingTask.UnobserveFieldScoped("output")
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/config", method: "GET", body: "", savePath: "", context: m.server.id }
    t.ObserveFieldScoped("output", "onConfig")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onConfig(ev as object)
    out = ev.GetData()
    print "[home] onConfig ok="; out.ok; " status="; out.status; " server="; m.server.baseUrl
    if out.context <> invalid and out.context <> m.server.id then return
    m.pendingTask = invalid
    persistToken(out.newToken)
    if not out.ok
        m.status.text = m.server.name + ": " + Frigate_FriendlyError(out.status, out.error)
        return
    end if
    cfg = ParseJson(out.body)
    if cfg = invalid or cfg.cameras = invalid
        m.status.text = m.server.name + ": not a Frigate config response"
        return
    end if
    ' Cloudflare blackholes the raw go2rtc port, so remember whether this
    ' server sits behind it and skip those attempts (re-checked every
    ' connect: the flag clears if the entry moves to a direct address)
    cf = Frigate_IsCloudflare(out.headersArray)
    if m.server.cfProxied <> cf
        print "[home] cfProxied="; cf; " for "; m.server.name
        m.server.cfProxied = cf
        srv = ServerStore_GetById(m.server.id)
        if srv <> invalid
            srv.cfProxied = cf
            ServerStore_Upsert(srv)
        end if
    end if
    m.loadedServerId = m.server.id
    parsed = Frigate_ParseCameraConfig(cfg)
    m.cameras = parsed.cameras
    m.liveStreams = parsed.liveStreams
    m.liveStreamsSub = parsed.liveStreamsSub
    m.status.text = ""
    buildGrid()
    startSnapshots()
    m.actTimer.control = "start"
    fetchActivity()
    probeMediamtx()
end sub

' --- MediaMTX detection: if a spec-compliant HLS packager answers on the
' --- server's MediaMTX port, the live player prefers it (go2rtc's own HLS
' --- window is too small for Roku). Re-checked on every connect.
sub probeMediamtx()
    if m.mtxTask <> invalid then return
    port = m.server.mediamtxPort
    if port = invalid or port = 0 then port = 8888
    url = "http://" + Frigate_HostFromUrl(m.server.baseUrl) + ":" + StrI(port).Trim() + "/"
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: url, method: "GET", body: "", savePath: "", context: "mtx" + m.server.id }
    t.ObserveFieldScoped("output", "onMtxProbe")
    t.control = "RUN"
    m.mtxTask = t
end sub

sub onMtxProbe(ev as object)
    out = ev.GetData()
    m.mtxTask = invalid
    if out.context <> "mtx" + m.server.id then return   ' stale (server switched)
    present = out.status <> 0   ' any HTTP answer (even 404) means it's there
    if m.server.mediamtxOk = present then return
    print "[home] mediamtx detected="; present; " for "; m.server.name
    m.server.mediamtxOk = present
    srv = ServerStore_GetById(m.server.id)
    if srv <> invalid
        srv.mediamtxOk = present
        ServerStore_Upsert(srv)
    end if
    ' a newly appeared packager means video may work now — forget the old
    ' downgrade so the next camera open tries video immediately
    if present then TierStore_Set(m.server.id, 0, false)
end sub

' --- activity badges: cameras with review items (motion/objects) in the
' --- last 15 minutes get a marker on their grid tile
sub fetchActivity()
    if not m.top.visible or m.cameras.Count() = 0 then return
    if m.actTask <> invalid then return   ' previous poll still in flight
    now = CreateObject("roDateTime").AsSeconds()
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/review?limit=100&after=" + StrI(now - 900).Trim(), method: "GET", body: "", savePath: "", context: m.server.id }
    t.ObserveFieldScoped("output", "onActivity")
    t.control = "RUN"
    m.actTask = t
end sub

sub onActivity(ev as object)
    out = ev.GetData()
    m.actTask = invalid
    if out.context <> m.server.id then return   ' stale (server switched)
    if not out.ok then return
    items = ParseJson(out.body)
    if items = invalid or GetInterface(items, "ifArray") = invalid then return
    active = {}
    newest = invalid
    for each item in items
        if item.camera <> invalid then active[item.camera] = true
        if item.id <> invalid and not m.seenReviewIds.DoesExist(item.id)
            m.seenReviewIds[item.id] = true
            ' toast only fresh high-severity items, and only after the first
            ' poll has seeded what already existed (no storm on entry)
            if m.seenSeeded and item.severity = "alert" then newest = item
        end if
    end for
    m.seenSeeded = true
    if newest <> invalid and m.top.visible then showToast(newest)
    if m.grid.content = invalid then return
    for i = 0 to m.grid.content.GetChildCount() - 1
        tile = m.grid.content.GetChild(i)
        tile.hasActivity = active.DoesExist(tile.cameraName)
    end for
end sub

sub showToast(item as object)
    labels = ""
    if item.data <> invalid and item.data.objects <> invalid
        for each obj in item.data.objects
            if labels <> "" then labels = labels + ", "
            labels = labels + obj
        end for
    end if
    if labels = "" then labels = "Alert"
    m.toastText.text = labels + " — " + item.camera + "   (OK to view)"
    m.toastCamera = item.camera
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
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
    st = AppSettings_Load()
    cols = st.gridColumns
    if cols < 1 then cols = 1
    if cols > 6 then cols = 6
    tileW = Int((1800 - 30 * (cols - 1)) / cols)
    tileH = Int(tileW * 362 / 580)
    ' 1-2 columns: a full-width tile would be taller than the grid area
    if tileH > 850
        tileH = 850
        tileW = Int(tileH * 580 / 362)
    end if
    print "[home] buildGrid cols="; cols; " tileW="; tileW; " tileH="; tileH
    m.grid.numColumns = cols
    rows = Int(880 / (tileH + 30))
    if rows < 1 then rows = 1
    m.grid.numRows = rows
    m.gridVisibleRows = rows
    m.gridTotalRows = Int((m.cameras.Count() + cols - 1) / cols)
    m.grid.itemSize = [tileW, tileH]
    content = CreateObject("roSGNode", "ContentNode")
    for each cam in m.cameras
        tile = content.CreateChild("CameraTileData")
        tile.cameraName = cam
        tile.tileW = tileW
        tile.tileH = tileH
    end for
    m.grid.content = content
    ' restore the last-used tile (persisted across launches); ignore when the
    ' saved index belongs to a server with fewer cameras
    lastIdx = st.lastGridIdx
    if lastIdx > 0 and lastIdx < content.GetChildCount() then m.grid.jumpToItem = lastIdx
    if m.focusZone = "grid" then m.grid.SetFocus(true)
    updateScrollbar()
end sub

' Right-edge scroll indicator: thumb height shows how much of the grid fits,
' thumb position tracks the focused row. Hidden when everything fits.
sub updateScrollbar()
    if m.gridTotalRows <= m.gridVisibleRows or m.cameras.Count() = 0
        m.scrollTrack.visible = false
        m.scrollThumb.visible = false
        return
    end if
    trackH = 880
    thumbH = Int(trackH * m.gridVisibleRows / m.gridTotalRows)
    if thumbH < 40 then thumbH = 40
    row = 0
    if m.grid.itemFocused >= 0 and m.grid.numColumns > 0
        row = Int(m.grid.itemFocused / m.grid.numColumns)
    end if
    y = 170
    maxRow = m.gridTotalRows - 1
    if maxRow > 0 then y = 170 + Int((trackH - thumbH) * row / maxRow)
    m.scrollThumb.height = thumbH
    m.scrollThumb.translation = [1872, y]
    m.scrollTrack.visible = true
    m.scrollThumb.visible = true
end sub

' Up to 3 workers, cameras split round-robin: one slow camera (or server)
' no longer stretches the refresh interval for every tile
sub startSnapshots()
    stopSnapshots()
    if m.cameras.Count() = 0 then return
    workers = 3
    if m.cameras.Count() < workers then workers = m.cameras.Count()
    refreshMs = AppSettings_Load().refreshSecs * 1000
    for w = 0 to workers - 1
        chunk = []
        for i = w to m.cameras.Count() - 1 step workers
            chunk.Push(m.cameras[i])
        end for
        t = CreateObject("roSGNode", "SnapshotTask")
        t.server = m.server
        t.cameras = chunk
        t.refreshMs = refreshMs
        t.bbox = AppSettings_Load().showBoxes = true
        t.tag = "w" + StrI(w).Trim() + "_"
        t.ObserveFieldScoped("result", "onSnapshot")
        t.ObserveFieldScoped("newToken", "onSnapToken")
        t.control = "RUN"
        m.snapTasks.Push(t)
    end for
end sub

sub stopSnapshots()
    for each t in m.snapTasks
        t.UnobserveFieldScoped("result")
        t.UnobserveFieldScoped("newToken")
        t.quit = true
    end for
    m.snapTasks = []
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
                tile.staleText = ""
                m.lastSnapAt[res.camera] = CreateObject("roDateTime").AsSeconds()
            else
                tile.offline = true
            end if
            exit for
        end if
    end for
end sub

sub onTileSelected()
    if tryToastJump() then return
    st = AppSettings_Load()
    if st.lastGridIdx <> m.grid.itemSelected
        st.lastGridIdx = m.grid.itemSelected
        AppSettings_Save(st)
    end if
    openPlayer(m.grid.itemSelected, false)
end sub

sub openPlayer(startIndex as integer, cycleMode as boolean, openInfo = false as boolean)
    player = CreateObject("roSGNode", "LivePlayerScreen")
    player.server = m.server
    player.cameras = m.cameras
    player.startIndex = startIndex
    player.cycleMode = cycleMode
    player.openInfo = openInfo
    ' "cycle all servers": the tour visits every server, starting from this one
    if cycleMode and AppSettings_Load().cycleScope = "all" and m.servers.Count() > 1
        player.tourServers = m.servers
    end if
    player.liveStreams = m.liveStreams
    player.liveStreamsSub = m.liveStreamsSub
    player.portFirst = AppSettings_Load().livePortFirst
    paths = []
    if m.grid.content <> invalid
        for i = 0 to m.grid.content.GetChildCount() - 1
            paths.Push(m.grid.content.GetChild(i).snapPath)
        end for
    end if
    player.snapPaths = paths
    m.top.GetScene().CallFunc("pushScreen", player)
end sub

sub openMenuItem()
    if tryToastJump() then return
    if m.servers.Count() = 0 and m.menuItems[m.menuIdx] <> "Settings"
        m.status.text = "Add a server first (Settings)"
        return
    end if
    name = m.menuItems[m.menuIdx]
    if name = "Live"
        ' the home grid IS the live view — just hand focus back to it
        m.focusZone = "grid"
        renderMenu()
        m.grid.SetFocus(true)
        return
    end if
    if name = "Cycle Cameras"
        if m.cameras.Count() = 0
            m.status.text = "No cameras loaded yet"
        else
            openPlayer(0, true)
        end if
        return
    end if
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
    if screenName = "RecordingsScreen" then node.cameras = m.cameras
    m.top.GetScene().CallFunc("pushScreen", node)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options"
        ' consume * everywhere — unhandled it opens the Roku TV settings
        ' sidebar; on a focused tile it means "show me this camera's info"
        if m.focusZone = "grid" and m.cameras.Count() > 0 and m.grid.itemFocused >= 0
            openPlayer(m.grid.itemFocused, false, true)
        end if
        return true
    end if
    if m.focusZone = "grid"
        if key = "back" or (key = "up" and m.grid.itemFocused < m.grid.numColumns)
            m.focusZone = "menu"
            renderMenu()   ' focuses menuRow
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
        else if key = "back"
            confirmExit() : return true
        end if
    else if m.focusZone = "tabs"
        if key = "left" and m.tabIdx > 0
            m.tabIdx = m.tabIdx - 1 : reloadServers() : return true
        else if key = "right" and m.tabIdx < m.servers.Count() - 1
            m.tabIdx = m.tabIdx + 1 : reloadServers() : return true
        else if key = "down" or key = "OK"
            m.focusZone = "menu" : renderTabs() : renderMenu() : return true
        else if key = "up"
            ' consume: nothing above the tabs, and the key must never bubble
            ' out of the app without the exit dialog
            return true
        else if key = "back"
            confirmExit() : return true
        end if
    end if
    return false
end function

' Back at the root would otherwise silently exit the app; confirm first
sub confirmExit()
    d = CreateObject("roSGNode", "Dialog")
    d.title = "Exit Scuttle?"
    d.message = "Do you want to close the app?"
    d.buttons = ["Exit", "Stay"]
    d.ObserveFieldScoped("buttonSelected", "onExitDialog")
    m.exitDialog = d
    m.top.GetScene().dialog = d
end sub

sub onExitDialog()
    choice = m.exitDialog.buttonSelected
    m.exitDialog.close = true
    m.exitDialog = invalid
    if choice = 0 then m.top.GetScene().exitApp = true
end sub
