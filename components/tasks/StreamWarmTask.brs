sub init()
    m.top.functionName = "execute"
end sub

' Keeps a go2rtc HLS session alive while the Video node starts up. go2rtc
' drops a session ~5s after the last segment download (playlist polls alone
' don't count), and over a remote HTTPS proxy the player's first fetch easily
' arrives later than that — it then sees a dead session ("mpr zero length
' playlist"). Poll the media playlist and pull the newest segment until the
' screen sets quit (player reached "playing", attempt abandoned) or a safety
' cap. Downloaded bytes are discarded; this is purely a keepalive.
sub execute()
    headers = Frigate_AuthHeaders(m.top.server)
    base = Frigate_HlsBaseUrl(m.top.playlistUrl)
    clock = CreateObject("roTimespan")
    lastSeg = ""
    while (not m.top.quit) and clock.TotalMilliseconds() < 25000
        res = doRequest(m.top.playlistUrl, headers, "GET", "", "")
        if res.status <> 200 then exit while
        entries = Frigate_PlaylistEntries(res.body)
        if entries.Count() > 0
            seg = entries[entries.Count() - 1]
            if seg <> lastSeg
                lastSeg = seg
                doRequest(base + seg, headers, "GET", "", "")
            end if
        end if
        sleep(700)
    end while
end sub
