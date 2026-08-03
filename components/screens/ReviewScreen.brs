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
    Hints_Show("browseDetails", "Browsing tips", "OK opens an entry's snapshot and details. Press * to switch between alerts and detections.")
end sub

sub fetchItems()
    m.status.text = "Loading review items..."
    if m.pendingTask <> invalid then m.pendingTask.UnobserveFieldScoped("output")
    if m.thumbTask <> invalid
        m.thumbTask.UnobserveFieldScoped("result")
        m.thumbTask.UnobserveFieldScoped("newToken")
        m.thumbTask.quit = true
    end if
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
            ServerStore_Upsert(srv, "tokRev")
        end if
    end if
end sub

sub onItems(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    persistToken(out.newToken)
    if not out.ok
        m.status.text = Frigate_FriendlyError(out.status, out.error)
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
    srv = ServerStore_GetById(m.top.server.id)
    if srv = invalid then srv = m.top.server
    labels = ""
    if item.data <> invalid and item.data.objects <> invalid
        for each obj in item.data.objects
            if labels <> "" then labels = labels + ", "
            labels = labels + obj
        end for
    end if
    zones = ""
    if item.data <> invalid and item.data.zones <> invalid
        for each z in item.data.zones
            if zones <> "" then zones = zones + ", "
            zones = zones + z
        end for
    end if
    endTs = item.end_time
    if endTs = invalid then endTs = item.start_time
    lines = []
    lines.Push("Type: " + m.severity)
    if labels <> "" then lines.Push("Objects: " + labels)
    if zones <> "" then lines.Push("Zones: " + zones)
    lines.Push("Start: " + TimeUtil_FormatEpoch(item.start_time))
    if endTs > item.start_time then lines.Push("Duration: " + StrI(Int(endTs - item.start_time)).Trim() + "s")
    imgs = []
    if item.data <> invalid and item.data.detections <> invalid and item.data.detections.Count() > 0
        evId = item.data.detections[0]
        imgs.Push("/api/events/" + evId + "/snapshot.jpg?bbox=1")
        imgs.Push("/api/events/" + evId + "/thumbnail.jpg")
    end if
    detail = CreateObject("roSGNode", "DetailScreen")
    detail.server = srv
    detail.titleText = item.camera + " — " + TimeUtil_FormatEpoch(item.start_time)
    detail.imagePaths = imgs
    detail.infoLines = lines
    m.top.GetScene().CallFunc("pushScreen", detail)
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
