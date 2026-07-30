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
            path = "tmp:/snap_" + idShort + "_" + cam + "_" + StrI(seq mod 4).Trim() + ".jpg"
            url = server.baseUrl + Frigate_SnapshotPath(cam, 360)
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
            old = "tmp:/snap_" + idShort + "_" + cam + "_" + StrI((seq + 2) mod 4).Trim() + ".jpg"
            if fs.Exists(old) then fs.Delete(old)
        end for
        seq = seq + 1
        sleep(700)
    end while
end sub
