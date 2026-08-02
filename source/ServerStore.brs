function ServerStore_Section() as object
    return CreateObject("roRegistrySection", "frigate_servers")
end function

function ServerStore_Load() as object
    sec = ServerStore_Section()
    if sec.Exists("servers")
        data = ParseJson(sec.Read("servers"))
        if data <> invalid and GetInterface(data, "ifArray") <> invalid
            ' default fields added after records were first saved
            for each s in data
                if not s.DoesExist("cfProxied") then s.cfProxied = false
                if not s.DoesExist("liveMode") then s.liveMode = "video"
                if not s.DoesExist("streamType") then s.streamType = "auto"
            end for
            return data
        end if
    end if
    return []
end function

sub ServerStore_SaveAll(servers as object)
    sec = ServerStore_Section()
    sec.Write("servers", FormatJson(servers))
    sec.Flush()
end sub

sub ServerStore_Upsert(server as object)
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
    ServerStore_SaveAll(servers)
end sub

sub ServerStore_Delete(id as string)
    servers = ServerStore_Load()
    kept = []
    for each s in servers
        if s.id <> id then kept.Push(s)
    end for
    ServerStore_SaveAll(kept)
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
    }
end function
