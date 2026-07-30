sub Test_ServerStore(r as object)
    print "Test_ServerStore"
    ' isolate: wipe section first
    sec = CreateObject("roRegistrySection", "frigate_servers")
    sec.Delete("servers")
    sec.Flush()

    T("load empty returns []", ServerStore_Load().Count() = 0, r)

    s = ServerStore_NewServer()
    T("new server has id", s.id <> "", r)
    T("new server defaults go2rtcPort", s.go2rtcPort = 1984, r)
    T("new server defaults authType", s.authType = "none", r)

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
end sub
