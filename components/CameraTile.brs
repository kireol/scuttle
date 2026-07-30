sub init()
    m.boundContent = invalid
end sub

sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    if m.boundContent <> invalid
        m.boundContent.UnobserveFieldScoped("snapPath")
        m.boundContent.UnobserveFieldScoped("offline")
    end if
    m.boundContent = c
    c.ObserveFieldScoped("snapPath", "onSnapChanged")
    c.ObserveFieldScoped("offline", "onOfflineChanged")
    m.top.FindNode("name").text = c.cameraName
    applySnap()
    applyOffline()
end sub

sub onSnapChanged()
    applySnap()
end sub

sub onOfflineChanged()
    applyOffline()
end sub

sub applySnap()
    c = m.top.itemContent
    if c <> invalid and c.snapPath <> "" then m.top.FindNode("snap").uri = c.snapPath
end sub

sub applyOffline()
    c = m.top.itemContent
    if c <> invalid then m.top.FindNode("badge").visible = c.offline
end sub

sub onFocus()
    m.top.FindNode("focusRing").visible = (m.top.focusPercent > 0.5)
end sub
