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
        m.snapTask.UnobserveFieldScoped("newToken")
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
