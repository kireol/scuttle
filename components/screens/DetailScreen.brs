' Still image + metadata for a review item, event, or recorded hour.
' Deliberately no video playback: recorded streams are not reliably
' decodable on Roku (panoramic/HEVC mains), so details show a snapshot.

sub init()
    m.still = m.top.FindNode("still")
    m.title = m.top.FindNode("title")
    m.info = m.top.FindNode("info")
    m.status = m.top.FindNode("status")
    m.top.ObserveField("wasShown", "onShown")
    m.thumbTask = invalid
    m.pathIdx = 0
    m.started = false
end sub

sub onShown()
    m.top.SetFocus(true)
    if m.started then return
    m.started = true
    m.title.text = m.top.titleText
    lines = ""
    if m.top.infoLines <> invalid
        for each l in m.top.infoLines
            if lines <> "" then lines = lines + Chr(10)
            lines = lines + l
        end for
    end if
    m.info.text = lines
    tryNextImage()
end sub

sub tryNextImage()
    paths = m.top.imagePaths
    if paths = invalid or m.pathIdx >= paths.Count()
        m.status.text = "No image available for this entry"
        return
    end if
    m.status.text = "Loading image ..."
    t = CreateObject("roSGNode", "ThumbTask")
    t.server = m.top.server
    ' unique tmp name per attempt: Roku's texture cache is keyed by uri
    dt = CreateObject("roDateTime")
    t.items = [{ key: "still", path: paths[m.pathIdx], savePath: "tmp:/detail_" + StrI(dt.AsSeconds()).Trim() + "_" + StrI(m.pathIdx).Trim() + ".jpg" }]
    t.ObserveFieldScoped("result", "onImage")
    t.control = "RUN"
    m.thumbTask = t
end sub

sub onImage(ev as object)
    res = ev.GetData()
    m.thumbTask = invalid
    if res.ok
        m.still.uri = res.savePath
        m.status.text = ""
    else
        m.pathIdx = m.pathIdx + 1
        tryNextImage()
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false   ' back bubbles to AppScene, which pops this screen
end function
