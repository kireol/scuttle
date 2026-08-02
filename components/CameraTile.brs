sub init()
    m.boundContent = invalid
    m.snapA = m.top.FindNode("snapA")
    m.snapB = m.top.FindNode("snapB")
    m.front = m.snapA
    m.back = m.snapB
    m.back.ObserveFieldScoped("loadStatus", "onBackLoad")
    m.snapA.ObserveFieldScoped("loadStatus", "onBackLoad")
end sub

sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    if m.boundContent <> invalid
        m.boundContent.UnobserveFieldScoped("snapPath")
        m.boundContent.UnobserveFieldScoped("offline")
        m.boundContent.UnobserveFieldScoped("hasActivity")
    end if
    m.boundContent = c
    c.ObserveFieldScoped("snapPath", "onSnapChanged")
    c.ObserveFieldScoped("offline", "onOfflineChanged")
    c.ObserveFieldScoped("hasActivity", "onActivityChanged")
    m.top.FindNode("name").text = c.cameraName
    if c.tileW > 0 then applySize(c.tileW, c.tileH)
    applySnap()
    applyOffline()
    onActivityChanged()
end sub

sub onActivityChanged()
    c = m.top.itemContent
    if c <> invalid then m.top.FindNode("actBadge").visible = c.hasActivity
end sub

' Resize all children for the configured grid tile size (defaults are 580x362)
sub applySize(w as integer, h as integer)
    frame = m.top.FindNode("frame")
    frame.width = w
    frame.height = h
    for each p in [m.snapA, m.snapB]
        p.width = w - 8
        p.height = h - 40
    end for
    name = m.top.FindNode("name")
    name.width = w
    name.translation = [0, h - 32]
    m.top.FindNode("badge").translation = [w - 100, h - 32]
    ring = m.top.FindNode("focusRing")
    ring.width = w
    ring.height = h
    m.top.FindNode("frTop").width = w
    b = m.top.FindNode("frBottom")
    b.width = w
    b.translation = [0, h - 4]
    m.top.FindNode("frLeft").height = h
    r = m.top.FindNode("frRight")
    r.height = h
    r.translation = [w - 4, 0]
end sub

sub onSnapChanged()
    applySnap()
end sub

sub onOfflineChanged()
    applyOffline()
end sub

' Load the new snapshot into the hidden poster; onBackLoad swaps it in when
' ready so the visible image is never blanked mid-load (no flicker)
sub applySnap()
    c = m.top.itemContent
    if c = invalid or c.snapPath = "" then return
    if m.front.uri = "" then
        m.front.uri = c.snapPath
    else if c.snapPath <> m.front.uri
        m.back.uri = c.snapPath
    end if
end sub

sub onBackLoad()
    if m.back.loadStatus = "ready" and m.back.uri <> ""
        m.back.visible = true
        m.front.visible = false
        tmp = m.front
        m.front = m.back
        m.back = tmp
    end if
end sub

sub applyOffline()
    c = m.top.itemContent
    if c <> invalid then m.top.FindNode("badge").visible = c.offline
end sub

sub onFocus()
    ' focusPercent alone is not enough: it keeps its last value when the grid
    ' itself loses focus (e.g. focus moves to the menu row), leaving the ring lit
    m.top.FindNode("focusRing").visible = m.top.itemHasFocus and (m.top.focusPercent > 0.5)
end sub
