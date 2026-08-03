' Small preferences that don't belong on the server record: where a server's
' downgrade cascade last landed, and per-camera stream overrides. Kept
' separate from ServerStore so clearing one can't clobber server credentials.
' Dual-written (registry + cachefs mirror with revision counter) for the same
' reason as ServerStore — registry flushes don't reliably reach disk on every
' fleet TV.

function PrefStore_Section() as object
    return CreateObject("roRegistrySection", "scuttle_prefs")
end function

function PrefStore_CachePath() as string
    return "cachefs:/scuttle_prefs.json"
end function

' {rev, tiers: {}, camstreams: {}} — merges the legacy two-key registry
' layout into one wrapper
function PrefStore_LoadAll() as object
    regRaw = ""
    sec = PrefStore_Section()
    if sec.Exists("all")
        regRaw = sec.Read("all")
    else if sec.Exists("tiers") or sec.Exists("camstreams")
        ' legacy layout: two separate keys, counts as revision 0
        legacy = { rev: 0, tiers: {}, camstreams: {} }
        if sec.Exists("tiers")
            tiersParsed = ParseJson(sec.Read("tiers"))
            if tiersParsed <> invalid then legacy.tiers = tiersParsed
        end if
        if sec.Exists("camstreams")
            camsParsed = ParseJson(sec.Read("camstreams"))
            if camsParsed <> invalid then legacy.camstreams = camsParsed
        end if
        regRaw = FormatJson(legacy)
    end if
    fileRaw = ""
    if MatchFiles("cachefs:/", "scuttle_prefs.json").Count() > 0
        fileRaw = ReadAsciiFile(PrefStore_CachePath())
    end if
    reg = invalid
    if regRaw <> "" then reg = ParseJson(regRaw)
    fil = invalid
    if fileRaw <> "" then fil = ParseJson(fileRaw)
    best = invalid
    if fil <> invalid and fil.tiers <> invalid
        best = fil
    end if
    if reg <> invalid and reg.tiers <> invalid
        if best = invalid then best = reg
        if best.rev = invalid or (reg.rev <> invalid and reg.rev > best.rev) then best = reg
    end if
    if best = invalid then best = { rev: 0, tiers: {}, camstreams: {} }
    if best.rev = invalid then best.rev = 0
    if best.tiers = invalid then best.tiers = {}
    if best.camstreams = invalid then best.camstreams = {}
    return best
end function

sub PrefStore_SaveAll(all as object)
    if all.rev = invalid then all.rev = 0
    all.rev = all.rev + 1
    json = FormatJson(all)
    sec = PrefStore_Section()
    sec.Write("all", json)
    sec.Flush()
    WriteAsciiFile(PrefStore_CachePath(), json)
end sub

' --- Downgrade tier persistence -------------------------------------------
' Remember where a server's cascade landed so the next player session starts
' there instead of re-walking 10s per dead source. Entries expire so a
' transient outage doesn't pin a server at low quality forever.

function TierStore_TtlSecs() as integer
    return 6 * 3600
end function

' {tier: n, snapshot: bool} or invalid when nothing fresh is stored
function TierStore_Get(serverId as string) as dynamic
    all = PrefStore_LoadAll()
    if not all.tiers.DoesExist(serverId) then return invalid
    entry = all.tiers[serverId]
    if entry.ts = invalid then return invalid
    now = CreateObject("roDateTime").AsSeconds()
    if now - entry.ts > TierStore_TtlSecs() then return invalid
    return entry
end function

sub TierStore_Set(serverId as string, tier as integer, snapshot as boolean)
    all = PrefStore_LoadAll()
    all.tiers[serverId] = { tier: tier, snapshot: snapshot, ts: CreateObject("roDateTime").AsSeconds() }
    PrefStore_SaveAll(all)
end sub

' --- Per-camera stream override -------------------------------------------
' "" means no override (follow the server's streamType / auto chain)

function CamStream_Get(serverId as string, camera as string) as string
    all = PrefStore_LoadAll()
    key = serverId + "|" + camera
    if all.camstreams.DoesExist(key) then return all.camstreams[key]
    return ""
end function

sub CamStream_Set(serverId as string, camera as string, streamType as string)
    all = PrefStore_LoadAll()
    key = serverId + "|" + camera
    if streamType = "" or streamType = "auto"
        all.camstreams.Delete(key)
    else
        all.camstreams[key] = streamType
    end if
    PrefStore_SaveAll(all)
end sub

' Drop everything stored for a server that is being deleted
sub PrefStore_PruneServer(serverId as string)
    all = PrefStore_LoadAll()
    changed = false
    if all.tiers.DoesExist(serverId)
        all.tiers.Delete(serverId)
        changed = true
    end if
    doomed = []
    for each k in all.camstreams
        if Left(k, Len(serverId) + 1) = serverId + "|" then doomed.Push(k)
    end for
    for each k in doomed
        all.camstreams.Delete(k)
        changed = true
    end for
    if changed then PrefStore_SaveAll(all)
end sub
