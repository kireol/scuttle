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
            ServerStore_Upsert(srv)
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
    print "[review] select idx="; m.list.itemSelected; " item: "; FormatJson(item)
    endTs = item.end_time
    if endTs = invalid then endTs = item.start_time + 60
    ' Pad the range: alerts can be 1-2s long while Frigate's VOD segments run
    ' ~12s, so an unpadded window is often an empty playlist that Roku kills
    ' with "zero length playlist". Padding also gives useful context.
    startTs = item.start_time - 10
    endTs = endTs + 15
    if endTs - startTs < 40 then endTs = startTs + 40
    srv = ServerStore_GetById(m.top.server.id)
    if srv = invalid then srv = m.top.server
    ' Frigate_VodRangeUrl keeps LongInteger precision; StrI(Int(epoch)) mangles
    ' epochs through 32-bit float
    url = Frigate_VodRangeUrl(srv, item.camera, startTs, endTs)
    player = CreateObject("roSGNode", "VodPlayerScreen")
    player.server = srv
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
