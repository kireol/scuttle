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
    Hints_Show("browseDetails", "Browsing tips", "OK opens an entry's snapshot and details. Left/Right move between camera, day and hour lists.")
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
            ServerStore_Upsert(srv, "tokRec")
        end if
    end if
    if not out.ok
        m.status.text = Frigate_FriendlyError(out.status, out.error)
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

' Frigate may return hour as "07" (string) or 7 (number); normalize safely
function HourToInt(v as dynamic) as integer
    if v = invalid then return 0
    if GetInterface(v, "ifString") <> invalid then return Int(Val(v))
    if GetInterface(v, "ifInt") <> invalid then return v
    if GetInterface(v, "ifFloat") <> invalid or GetInterface(v, "ifDouble") <> invalid then return Int(v)
    return 0
end function

function hourLabel(hourVal as dynamic) as string
    hr = HourToInt(hourVal)
    ampm = "AM"
    if hr >= 12 then ampm = "PM"
    if hr = 0 then hr = 12
    if hr > 12 then hr = hr - 12
    return StrI(hr).Trim() + ":00 " + ampm
end function

function pad2(v as dynamic) as string
    s = StrI(HourToInt(v)).Trim()
    if Len(s) = 1 then s = "0" + s
    return s
end function

sub onHourSelect()
    d = m.summary[m.dayIdx]
    if d.hours = invalid then return
    h = d.hours[m.hourList.itemSelected]
    hr = HourToInt(h.hour)
    ' local wall time -> epoch: parse day+hour as if UTC, then remove the
    ' device's UTC offset
    probe = CreateObject("roDateTime")
    utcNow = probe.AsSeconds()
    probe.ToLocalTime()
    offset = probe.AsSeconds() - utcNow
    parser = CreateObject("roDateTime")
    parser.FromISO8601String(d.day + "T" + pad2(hr) + ":00:00")
    hourStart& = parser.AsSeconds()
    hourStart& = hourStart& - offset
    snapTs& = hourStart& + 1800
    now& = utcNow
    if snapTs& > now& - 120 then snapTs& = now& - 120
    if snapTs& < hourStart& then snapTs& = hourStart& + 30
    srv = ServerStore_GetById(m.top.server.id)
    if srv = invalid then srv = m.top.server
    lines = []
    lines.Push("Camera: " + m.camera)
    lines.Push("Hour: " + d.day + "  " + hourLabel(hr))
    if h.duration <> invalid then lines.Push("Recorded: " + StrI(Int(h.duration / 60)).Trim() + " min")
    if h.events <> invalid then lines.Push("Events: " + StrI(HourToInt(h.events)).Trim())
    lines.Push("Snapshot from mid-hour")
    detail = CreateObject("roSGNode", "DetailScreen")
    detail.server = srv
    detail.titleText = m.camera + " — " + d.day + " " + hourLabel(hr)
    detail.imagePaths = ["/api/" + m.camera + "/recordings/" + snapTs&.ToStr() + "/snapshot.jpg"]
    detail.infoLines = lines
    m.top.GetScene().CallFunc("pushScreen", detail)
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
