sub init()
    m.boundContent = invalid
end sub

sub onContentChange()
    c = m.top.itemContent
    if c = invalid then return
    if m.boundContent <> invalid
        m.boundContent.UnobserveFieldScoped("thumbPath")
    end if
    m.boundContent = c
    c.ObserveFieldScoped("thumbPath", "onThumbChanged")
    m.top.FindNode("caption").text = c.caption
    m.top.FindNode("sub").text = c.camera
    applyThumb()
end sub

sub onThumbChanged()
    applyThumb()
end sub

sub applyThumb()
    c = m.top.itemContent
    if c <> invalid and c.thumbPath <> "" then m.top.FindNode("thumb").uri = c.thumbPath
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.top.FindNode("bg").color = "0x10545CFF"
    else
        m.top.FindNode("bg").color = "0x1A2228FF"
    end if
end sub
