sub init()
    m.video = m.top.FindNode("video")
    m.camName = m.top.FindNode("camName")
    m.errorPanel = m.top.FindNode("errorPanel")
    m.errorDetail = m.top.FindNode("errorDetail")
    m.switcher = m.top.FindNode("switcher")
    m.switchGrid = m.top.FindNode("switchGrid")
    m.nameTimer = m.top.FindNode("nameTimer")
    m.nameTimer.ObserveFieldScoped("fire", "hideName")
    m.video.ObserveFieldScoped("state", "onVideoState")
    m.switchGrid.ObserveFieldScoped("itemSelected", "onSwitchPick")
    m.top.ObserveField("wasShown", "onShown")
    m.idx = 0
    m.started = false
end sub

sub onShown()
    if not m.started
        m.started = true
        m.idx = m.top.startIndex
        buildSwitcher()
        playCurrent()
    end if
    m.top.SetFocus(true)
end sub

sub playCurrent()
    cam = m.top.cameras[m.idx]
    m.errorPanel.visible = false
    m.video.control = "stop"
    content = CreateObject("roSGNode", "ContentNode")
    content.url = Frigate_LiveHlsUrl_Render(m.top.server, cam)
    content.streamFormat = "hls"
    content.live = true
    content.title = cam
    m.video.content = content
    m.video.control = "play"
    showName(cam)
end sub

' Render-safe copy (Frigate_LiveHlsUrl calls roUrlTransfer via Frigate_UrlEncode)
function Frigate_LiveHlsUrl_Render(server as object, cameraName as string) as string
    host = Frigate_HostFromUrl(server.baseUrl)
    return "http://" + host + ":" + StrI(server.go2rtcPort).Trim() + "/api/stream.m3u8?src=" + cameraName + "&mp4"
end function

sub showName(cam as string)
    m.camName.text = cam
    m.camName.visible = true
    m.nameTimer.control = "start"
end sub

sub hideName()
    m.camName.visible = false
end sub

sub onVideoState()
    state = m.video.state
    if state = "error"
        m.errorDetail.text = "Camera: " + m.top.cameras[m.idx] + chr(10) + "Error: " + m.video.errorMsg + " (code " + StrI(m.video.errorCode).Trim() + ")" + chr(10) + "URL: " + Frigate_LiveHlsUrl_Render(m.top.server, m.top.cameras[m.idx])
        m.errorPanel.visible = true
    end if
end sub

sub buildSwitcher()
    content = CreateObject("roSGNode", "ContentNode")
    idShort = Left(m.top.server.id, 8)
    for each cam in m.top.cameras
        tile = content.CreateChild("CameraTileData")
        tile.cameraName = cam
        ' seed from the freshest snapshot files Task 7 wrote (any of the 4 generations)
        fs = CreateObject("roFileSystem")
        for g = 3 to 0 step -1
            p = "tmp:/snap_" + idShort + "_" + cam + "_" + StrI(g).Trim() + ".jpg"
            if fs.Exists(p)
                tile.snapPath = p
                exit for
            end if
        end for
    end for
    m.switchGrid.content = content
end sub

sub onSwitchPick()
    m.idx = m.switchGrid.itemSelected
    m.switcher.visible = false
    m.top.SetFocus(true)
    playCurrent()
end sub

sub switchBy(delta as integer)
    n = m.top.cameras.Count()
    m.idx = ((m.idx + delta) mod n + n) mod n
    playCurrent()
end sub

sub onStopPlayback()
    m.video.control = "stop"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.switcher.visible
        if key = "back" or key = "up"
            m.switcher.visible = false
            m.top.SetFocus(true)
            return true
        end if
        return false
    end if
    if key = "left"
        switchBy(-1) : return true
    else if key = "right"
        switchBy(1) : return true
    else if key = "OK" or key = "down"
        if m.errorPanel.visible
            playCurrent()   ' OK = retry when error showing
        else
            m.switcher.visible = true
            m.switchGrid.SetFocus(true)
        end if
        return true
    end if
    return false
end function
