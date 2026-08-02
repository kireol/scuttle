sub Test_ServerStore(r as object)
    print "Test_ServerStore"
    ' isolate: back up real servers, wipe, restore at the end
    sec = CreateObject("roRegistrySection", "frigate_servers")
    backup = ""
    if sec.Exists("servers") then backup = sec.Read("servers")
    sec.Delete("servers")
    sec.Flush()

    T("load empty returns []", ServerStore_Load().Count() = 0, r)

    s = ServerStore_NewServer()
    T("new server has id", s.id <> "", r)
    T("new server defaults go2rtcPort", s.go2rtcPort = 1984, r)
    T("new server defaults authType", s.authType = "none", r)
    T("new server defaults cfProxied", s.cfProxied = false, r)
    T("new server defaults liveMode", s.liveMode = "video", r)
    T("new server defaults streamType", s.streamType = "auto", r)
    T("new server defaults verifyTls", s.verifyTls = false, r)

    s.name = "Home"
    s.baseUrl = "http://10.0.0.5:8971"
    ServerStore_Upsert(s)
    loaded = ServerStore_Load()
    T("upsert inserts", loaded.Count() = 1, r)
    T("fields persist", loaded[0].name = "Home" and loaded[0].baseUrl = "http://10.0.0.5:8971", r)

    s.name = "Home2"
    ServerStore_Upsert(s)
    loaded = ServerStore_Load()
    T("upsert replaces by id", loaded.Count() = 1 and loaded[0].name = "Home2", r)

    T("getById finds", ServerStore_GetById(s.id).name = "Home2", r)
    T("getById miss is invalid", ServerStore_GetById("nope") = invalid, r)

    ServerStore_Delete(s.id)
    T("delete removes", ServerStore_Load().Count() = 0, r)

    ' records saved before cfProxied existed get the field defaulted on load
    sec.Write("servers", FormatJson([{ id: "legacy1", name: "Old", baseUrl: "http://x" }]))
    sec.Flush()
    legacy = ServerStore_Load()
    T("load defaults cfProxied on legacy records", legacy[0].cfProxied = false, r)
    T("load defaults liveMode on legacy records", legacy[0].liveMode = "video", r)
    T("load defaults streamType on legacy records", legacy[0].streamType = "auto", r)
    T("load defaults verifyTls on legacy records", legacy[0].verifyTls = false, r)

    if backup <> ""
        sec.Write("servers", backup)
    else
        sec.Delete("servers")
    end if
    sec.Flush()
end sub
