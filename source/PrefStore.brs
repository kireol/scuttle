' Small registry-backed preferences that don't belong on the server record:
' where a server's downgrade cascade last landed, and per-camera stream
' overrides. Kept separate from ServerStore so clearing one can't clobber
' server credentials.

function PrefStore_Section() as object
    return CreateObject("roRegistrySection", "scuttle_prefs")
end function

' --- Downgrade tier persistence -------------------------------------------
' Remember where a server's cascade landed so the next player session starts
' there instead of re-walking 10s per dead source. Entries expire so a
' transient outage doesn't pin a server at low quality forever.

function TierStore_TtlSecs() as integer
    return 6 * 3600
end function

' {tier: n, snapshot: bool} or invalid when nothing fresh is stored
function TierStore_Get(serverId as string) as dynamic
    sec = PrefStore_Section()
    if not sec.Exists("tiers") then return invalid
    all = ParseJson(sec.Read("tiers"))
    if all = invalid or not all.DoesExist(serverId) then return invalid
    entry = all[serverId]
    if entry.ts = invalid then return invalid
    now = CreateObject("roDateTime").AsSeconds()
    if now - entry.ts > TierStore_TtlSecs() then return invalid
    return entry
end function

sub TierStore_Set(serverId as string, tier as integer, snapshot as boolean)
    sec = PrefStore_Section()
    all = invalid
    if sec.Exists("tiers") then all = ParseJson(sec.Read("tiers"))
    if all = invalid then all = {}
    all[serverId] = { tier: tier, snapshot: snapshot, ts: CreateObject("roDateTime").AsSeconds() }
    sec.Write("tiers", FormatJson(all))
    sec.Flush()
end sub

' --- Per-camera stream override -------------------------------------------
' "" means no override (follow the server's streamType / auto chain)

function CamStream_Get(serverId as string, camera as string) as string
    sec = PrefStore_Section()
    if not sec.Exists("camstreams") then return ""
    data = ParseJson(sec.Read("camstreams"))
    if data = invalid then return ""
    key = serverId + "|" + camera
    if data.DoesExist(key) then return data[key]
    return ""
end function

sub CamStream_Set(serverId as string, camera as string, streamType as string)
    sec = PrefStore_Section()
    data = invalid
    if sec.Exists("camstreams") then data = ParseJson(sec.Read("camstreams"))
    if data = invalid then data = {}
    key = serverId + "|" + camera
    if streamType = "" or streamType = "auto"
        data.Delete(key)
    else
        data[key] = streamType
    end if
    sec.Write("camstreams", FormatJson(data))
    sec.Flush()
end sub
