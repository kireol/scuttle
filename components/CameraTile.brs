sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    m.top.FindNode("name").text = c.cameraName
    if c.snapPath <> ""
        m.top.FindNode("snap").uri = c.snapPath
    end if
    m.top.FindNode("badge").visible = c.offline
end sub

sub onFocus()
    m.top.FindNode("focusRing").visible = (m.top.focusPercent > 0.5)
end sub
