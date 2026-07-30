sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    if c.thumbPath <> "" then m.top.FindNode("thumb").uri = c.thumbPath
    m.top.FindNode("caption").text = c.caption
    m.top.FindNode("sub").text = c.camera
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.top.FindNode("bg").color = "0x10545CFF"
    else
        m.top.FindNode("bg").color = "0x1A2228FF"
    end if
end sub
