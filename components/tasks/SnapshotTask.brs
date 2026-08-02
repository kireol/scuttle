sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    server = m.top.server
    fs = CreateObject("roFileSystem")
    seq = 0
    idShort = Left(server.id, 8)
    while not m.top.quit
        cameras = m.top.cameras
        headers = Frigate_AuthHeaders(server)
        for each cam in cameras
            if m.top.quit then exit for
            ' Unique filename every round: Roku's texture cache is keyed by uri,
            ' so reusing names serves the stale cached image instead of the new file
            path = "tmp:/snap_" + m.top.tag + idShort + "_" + cam + "_" + StrI(seq).Trim() + ".jpg"
            ' fullUrl overrides the default Frigate latest.jpg (e.g. go2rtc
            ' frame.jpeg for full-resolution frames from the main stream)
            if m.top.fullUrl <> ""
                url = m.top.fullUrl
            else
                url = server.baseUrl + Frigate_SnapshotPath(cam, m.top.height)
            end if
            res = doRequest(url, headers, "GET", "", path)
            if res.status = 401 and server.authType = "frigate" and server.username <> ""
                token = doLogin(server)
                if token <> ""
                    server.token = token
                    m.top.newToken = token
                    headers = Frigate_AuthHeaders(server)
                    res = doRequest(url, headers, "GET", "", path)
                end if
            end if
            ok = (res.status >= 200 and res.status < 300)
            m.top.result = { camera: cam, path: path, ok: ok }
            ' delete the file from 2 generations ago to cap tmp usage
            if seq >= 2
                old = "tmp:/snap_" + m.top.tag + idShort + "_" + cam + "_" + StrI(seq - 2).Trim() + ".jpg"
                if fs.Exists(old) then fs.Delete(old)
            end if
        end for
        seq = seq + 1
        ' wait out the configured refresh interval, staying responsive to quit
        waitMs = m.top.refreshMs
        if waitMs < 1000 then waitMs = 10000
        elapsed = 0
        while elapsed < waitMs and not m.top.quit
            sleep(250)
            elapsed = elapsed + 250
        end while
    end while
end sub
