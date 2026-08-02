sub init()
    m.host = m.top.FindNode("screenHost")
    m.screens = []
end sub

sub onReady()
    if m.top.ready and m.screens.Count() = 0 then ShowFirstScreen()
end sub

sub onAddServerInfo()
    info = m.top.addServerInfo
    if info = invalid then return
    HandleAddServer(info)
    m.top.serversChanged = true
end sub

sub ShowFirstScreen()
    DoPushScreen(CreateObject("roSGNode", "HomeScreen"))
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
    ' Focus the screen first so its wasShown handler can hand focus to an inner widget
    screen.SetFocus(true)
    screen.wasShown = true
end sub

sub PopScreen()
    if m.screens.Count() <= 1 then return
    screen = m.screens.Pop()
    if screen.HasField("stopPlayback") then screen.stopPlayback = true
    m.host.RemoveChild(screen)
    top = m.screens[m.screens.Count() - 1]
    top.visible = true
    top.SetFocus(true)
    top.wasShown = true
end sub

sub onScreenClose(ev as object)
    if ev.GetData() = true then PopScreen()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back"
        if m.screens.Count() > 1
            PopScreen()
        end if
        ' Always swallow back at the scene: during screen transitions focus can
        ' be in limbo, and an unhandled back here silently exits the app
        ' (EXIT_USER_NAV) — HomeScreen owns the confirm-exit dialog instead.
        return true
    end if
    return false
end function

function pushScreen(screen as object) as boolean
    DoPushScreen(screen)
    return true
end function

' Close every pushed screen, landing back on the home screen
function popToRoot() as boolean
    while m.screens.Count() > 1
        PopScreen()
    end while
    return true
end function
