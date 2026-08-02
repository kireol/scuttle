sub init()
    m.list = m.top.FindNode("list")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.list.ObserveFieldScoped("itemFocused", "updateScrollbar")
    m.scrollTrack = m.top.FindNode("scrollTrack")
    m.scrollThumb = m.top.FindNode("scrollThumb")
    m.top.ObserveField("wasShown", "onShownList")
    ' version comes from the manifest so this label can never drift from it
    m.top.FindNode("version").text = "v" + CreateObject("roAppInfo").GetVersion()
    refresh()
end sub

sub updateScrollbar()
    total = 0
    if m.list.content <> invalid then total = m.list.content.GetChildCount()
    vis = 12
    if total <= vis
        m.scrollTrack.visible = false
        m.scrollThumb.visible = false
        return
    end if
    trackH = 768
    thumbH = Int(trackH * vis / total)
    if thumbH < 40 then thumbH = 40
    y = 240
    if total > 1 and m.list.itemFocused > 0
        y = 240 + Int((trackH - thumbH) * m.list.itemFocused / (total - 1))
    end if
    m.scrollThumb.height = thumbH
    m.scrollThumb.translation = [1250, y]
    m.scrollTrack.visible = true
    m.scrollThumb.visible = true
end sub

sub onShownList()
    if m.sceneObserved = invalid
        ' react to servers added externally via the ECP input API
        m.sceneObserved = true
        m.top.GetScene().ObserveFieldScoped("serversChanged", "refresh")
    end if
    refresh()
end sub

' Typed row model so servers and app settings stay visually separated;
' header rows are inert
function buildRows() as object
    rows = []
    rows.Push({ kind: "header", title: "SERVERS" })
    for each s in m.servers
        rows.Push({ kind: "server", id: s.id, title: "  " + s.name + "  (" + s.baseUrl + ")" })
    end for
    rows.Push({ kind: "add", title: "  + Add Server" })
    rows.Push({ kind: "header", title: "APP SETTINGS" })
    liveMode = "try go2rtc port first, then Frigate proxy"
    if not m.settings.livePortFirst then liveMode = "Frigate proxy only"
    clockLabel = "off"
    if m.settings.showClock = true then clockLabel = "on"
    rows.Push({ kind: "refresh", title: "  Snapshot refresh: " + StrI(m.settings.refreshSecs).Trim() + "s" })
    rows.Push({ kind: "columns", title: "  Home screen columns: " + StrI(m.settings.gridColumns).Trim() })
    rows.Push({ kind: "portFirst", title: "  Live streaming: " + liveMode })
    rows.Push({ kind: "clock", title: "  Show clock: " + clockLabel })
    boxesLabel = "off"
    if m.settings.showBoxes = true then boxesLabel = "on"
    rows.Push({ kind: "boxes", title: "  Motion boxes on snapshots: " + boxesLabel })
    rows.Push({ kind: "cycle", title: "  Camera cycle time: " + StrI(m.settings.cycleSecs).Trim() + "s" })
    scopeLabel = "single server"
    if m.settings.cycleScope = "all" then scopeLabel = "cycle all servers"
    rows.Push({ kind: "cycleScope", title: "  Cycle camera mode: " + scopeLabel })
    return rows
end function

sub refresh()
    m.servers = ServerStore_Load()
    m.settings = AppSettings_Load()
    m.rows = buildRows()
    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        item = content.CreateChild("ContentNode")
        item.title = row.title
    end for
    idx = m.list.itemFocused
    m.list.content = content
    if idx > 0 and idx < content.GetChildCount() then m.list.jumpToItem = idx
    m.list.SetFocus(true)
    updateScrollbar()
end sub

sub onSelect()
    row = m.rows[m.list.itemSelected]
    print "[settings] selected idx="; m.list.itemSelected; " kind="; row.kind
    if row.kind = "server" or row.kind = "add"
        edit = CreateObject("roSGNode", "ServerEditScreen")
        if row.kind = "server" then edit.serverId = row.id
        m.top.GetScene().CallFunc("pushScreen", edit)
        return
    end if
    if row.kind = "refresh"
        cycle = [5, 10, 15, 30, 60]
        cur = 0
        for i = 0 to cycle.Count() - 1
            if cycle[i] = m.settings.refreshSecs then cur = i
        end for
        m.settings.refreshSecs = cycle[(cur + 1) mod cycle.Count()]
    else if row.kind = "columns"
        cols = m.settings.gridColumns + 1
        if cols > 6 then cols = 1
        m.settings.gridColumns = cols
    else if row.kind = "portFirst"
        m.settings.livePortFirst = not m.settings.livePortFirst
    else if row.kind = "clock"
        m.settings.showClock = not (m.settings.showClock = true)
    else if row.kind = "boxes"
        m.settings.showBoxes = not (m.settings.showBoxes = true)
    else if row.kind = "cycle"
        cycle = [5, 10, 15, 30, 60]
        cur = 1   ' default 10s
        for i = 0 to cycle.Count() - 1
            if cycle[i] = m.settings.cycleSecs then cur = i
        end for
        m.settings.cycleSecs = cycle[(cur + 1) mod cycle.Count()]
    else if row.kind = "cycleScope"
        if m.settings.cycleScope = "all"
            m.settings.cycleScope = "single"
        else
            m.settings.cycleScope = "all"
        end if
    else
        return   ' header row — nothing to do
    end if
    AppSettings_Save(m.settings)
    refresh()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
