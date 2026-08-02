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
    m.grid.ObserveFieldScoped("itemSelected", "onTileSelected")
    m.top.ObserveField("wasShown", "onShown")
    m.top.ObserveField("visible", "onVisibleChange")

    m.menuItems = ["Review", "Explore", "Recordings", "Cycle Cameras", "Settings"]
    m.settingsIdx = 4   ' index of "Settings" in m.menuItems
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
    if not m.top.visible then stopSnapshots()
end sub

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
    m.grid.content = CreateObject("roSGNode", "ContentNode")
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
    m.cameras = []
    m.liveStreams = {}
    m.liveStreamsSub = {}
    for each cam in cfg.cameras
        camCfg = cfg.cameras[cam]
        enabled = true
        if camCfg <> invalid and camCfg.enabled <> invalid then enabled = camCfg.enabled
        if enabled then m.cameras.Push(cam)
        ' go2rtc restream names for live view: prefer the main/high-res entry,
        ' and keep a low-res pick for fallback (7680-wide panoramic mains
        ' exceed Roku's 3840x2160 decoder limit)
        if camCfg <> invalid and camCfg.live <> invalid and camCfg.live.streams <> invalid
            pick = ""
            subPick = ""
            for each label in camCfg.live.streams
                name = camCfg.live.streams[label]
                if pick = "" then pick = name
                if Right(name, 5) = "_main" then pick = name
                if Right(name, 4) = "_sub" then subPick = name
            end for
            if subPick = "" then
                for each label in camCfg.live.streams
                    name = camCfg.live.streams[label]
                    if name <> pick then subPick = name
                end for
            end if
            if pick <> "" then m.liveStreams[cam] = pick
            if subPick <> "" and subPick <> pick then m.liveStreamsSub[cam] = subPick
        end if
    end for
    m.cameras.Sort()
    m.status.text = ""
    buildGrid()
    startSnapshots()
    m.actTimer.control = "start"
    fetchActivity()
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
    for each item in items
        if item.camera <> invalid then active[item.camera] = true
    end for
    if m.grid.content = invalid then return
    for i = 0 to m.grid.content.GetChildCount() - 1
        tile = m.grid.content.GetChild(i)
        tile.hasActivity = active.DoesExist(tile.cameraName)
    end for
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
            else
                tile.offline = true
            end if
            exit for
        end if
    end for
end sub

sub onTileSelected()
    st = AppSettings_Load()
    if st.lastGridIdx <> m.grid.itemSelected
        st.lastGridIdx = m.grid.itemSelected
        AppSettings_Save(st)
    end if
    openPlayer(m.grid.itemSelected, false)
end sub

sub openPlayer(startIndex as integer, cycleMode as boolean)
    player = CreateObject("roSGNode", "LivePlayerScreen")
    player.server = m.server
    player.cameras = m.cameras
    player.startIndex = startIndex
    player.cycleMode = cycleMode
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
    if m.servers.Count() = 0 and m.menuItems[m.menuIdx] <> "Settings"
        m.status.text = "Add a server first (Settings)"
        return
    end if
    name = m.menuItems[m.menuIdx]
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
