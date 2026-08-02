sub init()
    m.list = m.top.FindNode("list")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("wasShown", "onShownList")
    refresh()
end sub

sub onShownList()
    if m.sceneObserved = invalid
        ' react to servers added externally via the ECP input API
        m.sceneObserved = true
        m.top.GetScene().ObserveFieldScoped("serversChanged", "refresh")
    end if
    refresh()
end sub

sub refresh()
    m.servers = ServerStore_Load()
    m.settings = AppSettings_Load()
    content = CreateObject("roSGNode", "ContentNode")
    for each s in m.servers
        item = content.CreateChild("ContentNode")
        item.title = s.name + "  (" + s.baseUrl + ")"
    end for
    addItem = content.CreateChild("ContentNode")
    addItem.title = "+ Add Server"
    liveMode = "try go2rtc port first, then Frigate proxy"
    if not m.settings.livePortFirst then liveMode = "Frigate proxy only"
    for each t in [
        "Snapshot refresh: " + StrI(m.settings.refreshSecs).Trim() + "s",
        "Home screen columns: " + StrI(m.settings.gridColumns).Trim(),
        "Live streaming: " + liveMode]
        item = content.CreateChild("ContentNode")
        item.title = t
    end for
    idx = m.list.itemFocused
    m.list.content = content
    if idx > 0 and idx < content.GetChildCount() then m.list.jumpToItem = idx
    m.list.SetFocus(true)
end sub

sub onSelect()
    idx = m.list.itemSelected
    if idx <= m.servers.Count()
        edit = CreateObject("roSGNode", "ServerEditScreen")
        if idx < m.servers.Count()
            edit.serverId = m.servers[idx].id
        end if
        m.top.GetScene().CallFunc("pushScreen", edit)
        return
    end if
    setting = idx - m.servers.Count() - 1
    if setting = 0
        cycle = [5, 10, 15, 30, 60]
        cur = 0
        for i = 0 to cycle.Count() - 1
            if cycle[i] = m.settings.refreshSecs then cur = i
        end for
        m.settings.refreshSecs = cycle[(cur + 1) mod cycle.Count()]
    else if setting = 1
        cols = m.settings.gridColumns + 1
        if cols > 4 then cols = 2
        m.settings.gridColumns = cols
    else if setting = 2
        m.settings.livePortFirst = not m.settings.livePortFirst
    end if
    AppSettings_Save(m.settings)
    refresh()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
