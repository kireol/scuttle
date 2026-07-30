sub init()
    m.list = m.top.FindNode("list")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("wasShown", "refresh")
    refresh()
end sub

sub refresh()
    m.servers = ServerStore_Load()
    content = CreateObject("roSGNode", "ContentNode")
    for each s in m.servers
        item = content.CreateChild("ContentNode")
        item.title = s.name + "  (" + s.baseUrl + ")"
    end for
    addItem = content.CreateChild("ContentNode")
    addItem.title = "+ Add Server"
    m.list.content = content
    m.list.SetFocus(true)
end sub

sub onSelect()
    idx = m.list.itemSelected
    edit = CreateObject("roSGNode", "ServerEditScreen")
    if idx < m.servers.Count()
        edit.serverId = m.servers[idx].id
    end if
    m.top.GetScene().CallFunc("pushScreen", edit)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
