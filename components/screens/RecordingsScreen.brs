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
    if m.pendingTask <> invalid then m.pendingTask.UnobserveFieldScoped("output")
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
