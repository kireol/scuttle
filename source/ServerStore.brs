' Storage note: the registry is the traditional home for these records, but
' on several fleet TVs registry flushes stopped reaching disk — writes read
' back fine in-process, then vanish on relaunch, and mid-session reads can
' resync from the stale disk copy, silently reverting fresh writes. Every
' save therefore also goes to a cachefs file with a revision counter, and
' loads use whichever copy is newer. cachefs survives restarts and reboots
' (it is evictable, but only under storage pressure — and then the registry
' copy is still there as a fallback).

function ServerStore_Section() as object
    return CreateObject("roRegistrySection", "frigate_servers")
end function

function ServerStore_CachePath() as string
    return "cachefs:/scuttle_servers.json"
end function

' Accepts either the wrapped {rev, servers} payload or a legacy plain array
' (which counts as revision 0). rev -1 = unusable.
function ServerStore_ParseWrapper(raw as string) as object
    parsed = ParseJson(raw)
    if parsed = invalid then return { rev: -1, servers: invalid }
    if GetInterface(parsed, "ifArray") <> invalid then return { rev: 0, servers: parsed }
    if parsed.servers <> invalid and GetInterface(parsed.servers, "ifArray") <> invalid
        rev = 0
        if parsed.rev <> invalid then rev = parsed.rev
        return { rev: rev, servers: parsed.servers }
    end if
    return { rev: -1, servers: invalid }
end function

function ServerStore_BestWrapper() as object
    regRaw = ""
    sec = ServerStore_Section()
    if sec.Exists("servers") then regRaw = sec.Read("servers")
    ' ReadAsciiFile returns "" for a missing file; roFileSystem must not be
    ' used here — it is a main/task-thread-only component and hard-crashes
    ' the render thread
    fileRaw = ReadAsciiFile(ServerStore_CachePath())
    reg = ServerStore_ParseWrapper(regRaw)
    fil = ServerStore_ParseWrapper(fileRaw)
    ' ties go to the file: when the registry disk copy is stale it keeps an
    ' old rev, so an equal-or-higher file rev is the trustworthy one
    if fil.servers <> invalid and (reg.servers = invalid or fil.rev >= reg.rev) then return fil
    return reg
end function

function ServerStore_Load() as object
    data = ServerStore_BestWrapper().servers
    if data <> invalid
        ' default fields added after records were first saved
        for each s in data
            if not s.DoesExist("cfProxied") then s.cfProxied = false
            if not s.DoesExist("liveMode") then s.liveMode = "video"
            if not s.DoesExist("streamType") then s.streamType = "auto"
            if not s.DoesExist("verifyTls") then s.verifyTls = false
            if not s.DoesExist("mediamtxPort") then s.mediamtxPort = 8888
            if not s.DoesExist("mediamtxOk") then s.mediamtxOk = false
            if not s.DoesExist("cycleCams") then s.cycleCams = []
            if not s.DoesExist("zipcode") then s.zipcode = ""
            if not s.DoesExist("tempUnit") then s.tempUnit = "f"
            if not s.DoesExist("zipLat") then s.zipLat = ""
            if not s.DoesExist("zipLon") then s.zipLon = ""
        end for
        return data
    end if
    return []
end function

sub ServerStore_SaveAll(servers as object, tag = "?" as string)
    rev = ServerStore_BestWrapper().rev + 1
    json = FormatJson({ rev: rev, servers: servers })
    sec = ServerStore_Section()
    sec.Write("servers", json)
    if not sec.Flush()
        print "[store] WARNING: registry flush failed (cachefs copy still saved)"
    end if
    if not WriteAsciiFile(ServerStore_CachePath(), json)
        print "[store] WARNING: cachefs write failed (registry copy still saved)"
    end if
    print "[store] saved rev "; rev; " ("; tag; ")"
end sub

sub ServerStore_Upsert(server as object, tag = "?" as string)
    servers = ServerStore_Load()
    replaced = false
    for i = 0 to servers.Count() - 1
        if servers[i].id = server.id
            servers[i] = server
            replaced = true
            exit for
        end if
    end for
    if not replaced then servers.Push(server)
    ServerStore_SaveAll(servers, tag)
end sub

sub ServerStore_Delete(id as string)
    servers = ServerStore_Load()
    kept = []
    for each s in servers
        if s.id <> id then kept.Push(s)
    end for
    ServerStore_SaveAll(kept, "delete")
end sub

function ServerStore_GetById(id as string) as dynamic
    for each s in ServerStore_Load()
        if s.id = id then return s
    end for
    return invalid
end function

function ServerStore_NewServer() as object
    di = CreateObject("roDeviceInfo")
    return {
        id: di.GetRandomUUID()
        name: ""
        baseUrl: ""
        go2rtcPort: 1984
        authType: "none"
        username: ""
        password: ""
        token: ""
        cfProxied: false
        liveMode: "video"
        streamType: "auto"
        verifyTls: false
        mediamtxPort: 8888
        mediamtxOk: false
        cycleCams: []
        zipcode: ""
        tempUnit: "f"
        zipLat: ""
        zipLon: ""
    }
end function

' Duplicate of Frigate_NormalizeBaseUrl: every component that imports this
' file would otherwise also have to import FrigateUrls.brs
function ServerStore_NormalizeUrl(url as string) as string
    u = url.Trim()
    if u = "" then return ""
    if Left(u, 7) <> "http://" and Left(u, 8) <> "https://"
        u = "http://" + u
    end if
    while Right(u, 1) = "/"
        u = Left(u, Len(u) - 1)
    end while
    return u
end function

sub HandleAddServer(info as object)
    ' Upsert by name so re-running an add-server script updates in place
    ' instead of stacking duplicates
    srv = invalid
    if info.name <> invalid
        for each s in ServerStore_Load()
            if s.name = info.name
                srv = s
                exit for
            end if
        end for
    end if
    if srv = invalid then srv = ServerStore_NewServer()
    if info.name <> invalid then srv.name = info.name
    if info.url <> invalid
        newUrl = ServerStore_NormalizeUrl(info.url)
        ' a different address means the Cloudflare detection must start over
        if srv.DoesExist("cfProxied") and newUrl <> srv.baseUrl then srv.cfProxied = false
        srv.baseUrl = newUrl
    end if
    if info.username <> invalid then srv.username = info.username
    if info.password <> invalid then srv.password = info.password
    if info.authtype <> invalid then srv.authType = info.authtype
    if info.go2rtcport <> invalid
        srv.go2rtcPort = Val(info.go2rtcport)
        if srv.go2rtcPort = 0 then srv.go2rtcPort = 1984
    end if
    if info.zipcode <> invalid
        srv.zipcode = info.zipcode
        srv.zipLat = ""
        srv.zipLon = ""
    end if
    if info.tempunit <> invalid and (info.tempunit = "f" or info.tempunit = "c")
        srv.tempUnit = info.tempunit
    end if
    print "[store] addserver via ECP input: "; srv.name; " "; srv.baseUrl
    ServerStore_Upsert(srv, "ecp")
end sub
