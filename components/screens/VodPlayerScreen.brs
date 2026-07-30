sub init()
    m.video = m.top.FindNode("video")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.errorPanel = m.top.FindNode("errorPanel")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.nameTimer = m.top.FindNode("nameTimer")
    m.nameTimer.ObserveFieldScoped("fire", "hideTitle")
    m.video.ObserveFieldScoped("state", "onVideoState")
    m.top.ObserveField("wasShown", "onShown")
    m.idx = 0
    m.started = false
end sub

sub onShown()
    if not m.started
        m.started = true
        m.idx = m.top.startIndex
        playCurrent()
    end if
    m.top.SetFocus(true)
end sub

sub playCurrent()
    item = m.top.playlist[m.idx]
    m.errorPanel.visible = false
    m.video.control = "stop"
    content = CreateObject("roSGNode", "ContentNode")
    content.url = item.url
    content.streamFormat = item.format
    content.title = item.title
    headers = authHeaderStrings()
    if headers.Count() > 0 then content.HttpHeaders = headers
    if Left(item.url, 8) = "https://" then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    m.video.content = content
    m.video.control = "play"
    m.titleLabel.text = item.title
    m.titleLabel.visible = true
    m.nameTimer.control = "start"
end sub

' ["Authorization: Bearer x"] / ["Authorization: Basic y"] / []
function authHeaderStrings() as object
    s = m.top.server
    if s = invalid then return []
    if s.authType = "basic"
        ba = CreateObject("roByteArray")
        ba.FromAsciiString(s.username + ":" + s.password)
        return ["Authorization: Basic " + ba.ToBase64String()]
    else if s.authType = "frigate" and s.token <> ""
        return ["Authorization: Bearer " + s.token]
    end if
    return []
end function

sub hideTitle()
    m.titleLabel.visible = false
end sub

sub onVideoState()
    state = m.video.state
    if state = "error"
        item = m.top.playlist[m.idx]
        m.errorDetail.text = item.title + chr(10) + "Error: " + m.video.errorMsg + " (code " + StrI(m.video.errorCode).Trim() + ")" + chr(10) + "URL: " + item.url
        m.errorPanel.visible = true
    else if state = "finished"
        if m.idx < m.top.playlist.Count() - 1
            m.idx = m.idx + 1
            playCurrent()
        else
            m.top.closeMe = true
        end if
    end if
end sub

sub onStopPlayback()
    m.video.control = "stop"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "OK" and m.errorPanel.visible
        playCurrent()
        return true
    else if key = "left"
        seekPos = m.video.position - 30
        if seekPos < 0 then seekPos = 0
        m.video.seek = seekPos
        return true
    else if key = "right"
        m.video.seek = m.video.position + 30
        return true
    end if
    return false
end function
