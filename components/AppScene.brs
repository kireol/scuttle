sub init()
    m.host = m.top.FindNode("screenHost")
    m.screens = []
    m.top.ObserveField("wasShown", "onSceneShown")
    ShowFirstScreen()
end sub

sub ShowFirstScreen()
    servers = ServerStore_Load()
    if servers.Count() = 0
        DoPushScreen(CreateObject("roSGNode", "ServerListScreen"))
    else
        DoPushScreen(CreateObject("roSGNode", "HomeScreen"))
    end if
end sub

sub onSceneShown()
end sub

' Renamed from PushScreen: BrightScript identifiers are case-insensitive, so this
' name would collide with the interface function `pushScreen` below.
sub DoPushScreen(screen as object)
    if m.screens.Count() > 0
        top = m.screens[m.screens.Count() - 1]
        top.visible = false
    end if
    screen.ObserveFieldScoped("closeMe", "onScreenClose")
    m.screens.Push(screen)
    m.host.AppendChild(screen)
    screen.wasShown = true
    screen.SetFocus(true)
end sub

sub PopScreen()
    if m.screens.Count() <= 1 then return
    screen = m.screens.Pop()
    if screen.HasField("stopPlayback") then screen.stopPlayback = true
    m.host.RemoveChild(screen)
    top = m.screens[m.screens.Count() - 1]
    top.visible = true
    top.wasShown = true
    top.SetFocus(true)
end sub

sub onScreenClose(ev as object)
    if ev.GetData() = true then PopScreen()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back"
        if m.screens.Count() > 1
            PopScreen()
            return true
        end if
    end if
    return false
end function

function pushScreen(screen as object) as boolean
    DoPushScreen(screen)
    return true
end function
