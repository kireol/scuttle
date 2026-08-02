sub Test_PrefStore(r as object)
    print "Test_PrefStore"
    ' isolate: back up real prefs, wipe, restore at the end
    sec = CreateObject("roRegistrySection", "scuttle_prefs")
    backupTiers = ""
    backupCams = ""
    if sec.Exists("tiers") then backupTiers = sec.Read("tiers")
    if sec.Exists("camstreams") then backupCams = sec.Read("camstreams")
    sec.Delete("tiers")
    sec.Delete("camstreams")
    sec.Flush()

    T("tier miss is invalid", TierStore_Get("srv1") = invalid, r)
    TierStore_Set("srv1", 2, false)
    entry = TierStore_Get("srv1")
    T("tier roundtrip", entry <> invalid and entry.tier = 2 and entry.snapshot = false, r)
    TierStore_Set("srv1", 1, true)
    entry = TierStore_Get("srv1")
    T("tier overwrite", entry.tier = 1 and entry.snapshot = true, r)
    T("tier other server misses", TierStore_Get("srv2") = invalid, r)

    ' expired entries are ignored: write one with a timestamp past the TTL
    now = CreateObject("roDateTime").AsSeconds()
    stale = { srv3: { tier: 2, snapshot: false, ts: now - TierStore_TtlSecs() - 60 } }
    sec.Write("tiers", FormatJson(stale))
    sec.Flush()
    T("tier TTL expires", TierStore_Get("srv3") = invalid, r)

    T("camstream miss is empty", CamStream_Get("srv1", "cam") = "", r)
    CamStream_Set("srv1", "cam", "_sub")
    T("camstream roundtrip", CamStream_Get("srv1", "cam") = "_sub", r)
    T("camstream other camera misses", CamStream_Get("srv1", "other") = "", r)
    CamStream_Set("srv1", "cam", "auto")
    T("camstream auto clears", CamStream_Get("srv1", "cam") = "", r)

    ' prune removes everything for one server, leaves others alone
    TierStore_Set("srvA", 1, false)
    TierStore_Set("srvB", 2, true)
    CamStream_Set("srvA", "cam1", "_sub")
    CamStream_Set("srvB", "cam1", "_roku")
    PrefStore_PruneServer("srvA")
    T("prune drops tier", TierStore_Get("srvA") = invalid, r)
    T("prune keeps other tier", TierStore_Get("srvB") <> invalid, r)
    T("prune drops camstream", CamStream_Get("srvA", "cam1") = "", r)
    T("prune keeps other camstream", CamStream_Get("srvB", "cam1") = "_roku", r)

    if backupTiers <> "" then sec.Write("tiers", backupTiers) else sec.Delete("tiers")
    if backupCams <> "" then sec.Write("camstreams", backupCams) else sec.Delete("camstreams")
    sec.Flush()
end sub
