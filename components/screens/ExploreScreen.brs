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

sub persistToken(newToken as string)
    if newToken <> "" and m.top.server <> invalid
        srv = ServerStore_GetById(m.top.server.id)
        if srv <> invalid
            srv.token = newToken
            ServerStore_Upsert(srv)
        end if
    end if
end sub

sub fetchEvents()
    m.status.text = "Loading events..."
    if m.thumbTask <> invalid
        m.thumbTask.UnobserveFieldScoped("result")
        m.thumbTask.UnobserveFieldScoped("newToken")
        m.thumbTask.quit = true
    end if
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
    persistToken(out.newToken)
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
        jobs.Push({ key: item.id, path: Frigate_EventThumbPath(item.id), savePath: "tmp:/evt_" + item.id + ".jpg" })
    end for
    m.grid.content = content
    m.status.text = StrI(m.events.Count()).Trim() + " events"
    if jobs.Count() > 0
        tt = CreateObject("roSGNode", "ThumbTask")
        tt.server = m.top.server
        tt.items = jobs
        tt.ObserveFieldScoped("result", "onThumb")
        tt.ObserveFieldScoped("newToken", "onThumbToken")
        tt.control = "RUN"
        m.thumbTask = tt
    end if
end sub

sub onThumbToken(ev as object)
    persistToken(ev.GetData())
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
    player.playlist = [{ url: m.top.server.baseUrl + Frigate_EventClipPath(item.id), title: item.label + " — " + item.camera, format: "mp4" }]
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
