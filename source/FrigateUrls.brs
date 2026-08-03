function Frigate_NormalizeBaseUrl(url as string) as string
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

function Frigate_HostFromUrl(url as string) as string
    u = Frigate_NormalizeBaseUrl(url)
    ' strip scheme
    p = Instr(1, u, "://")
    if p > 0 then u = Mid(u, p + 3)
    ' strip path
    p = Instr(1, u, "/")
    if p > 0 then u = Left(u, p - 1)
    ' strip port
    p = Instr(1, u, ":")
    if p > 0 then u = Left(u, p - 1)
    return u
end function

function Frigate_AuthHeaders(server as object) as object
    if server.authType = "basic"
        ba = CreateObject("roByteArray")
        ba.FromAsciiString(server.username + ":" + server.password)
        return { Authorization: "Basic " + ba.ToBase64String() }
    else if server.authType = "frigate" and server.token <> ""
        return { Authorization: "Bearer " + server.token }
    end if
    return {}
end function

function Frigate_ParseTokenFromSetCookie(setCookieValue as string) as string
    p = Instr(1, setCookieValue, "frigate_token=")
    if p = 0 then return ""
    rest = Mid(setCookieValue, p + Len("frigate_token="))
    semi = Instr(1, rest, ";")
    if semi > 0 then rest = Left(rest, semi - 1)
    return rest.Trim()
end function

' TASK-THREAD ONLY: creates roUrlTransfer, which crashes on the SceneGraph render thread — use the _Render copies in screens
function Frigate_LiveHlsUrl(server as object, cameraName as string) as string
    host = Frigate_HostFromUrl(server.baseUrl)
    return "http://" + host + ":" + StrI(server.go2rtcPort).Trim() + "/api/stream.m3u8?src=" + Frigate_UrlEncode(cameraName) + "&mp4"
end function

' Ordered go2rtc stream names for live view: full-res main first (its master
' answers instantly), the sub as a decode fallback, and the optional
' "<name>_roku" ffmpeg transcode last — it is capped at 1280 wide and a cold
' start takes ~8s before the master playlist even responds.
function Frigate_LiveStreamNames(mainName as string, subName as string) as object
    rokuName = mainName + "_roku"
    if Right(mainName, 5) = "_main" then rokuName = Left(mainName, Len(mainName) - 5) + "_roku"
    names = [mainName]
    if subName <> "" and subName <> mainName then names.Push(subName)
    names.Push(rokuName)
    return names
end function

' Enabled cameras plus go2rtc live-stream picks from a parsed /api/config
' response: prefer the main/high-res entry per camera and keep a low-res
' fallback (panoramic mains exceed Roku's 3840x2160 decoder limit)
function Frigate_ParseCameraConfig(cfg as object) as object
    out = { cameras: [], liveStreams: {}, liveStreamsSub: {} }
    if cfg = invalid or cfg.cameras = invalid then return out
    for each cam in cfg.cameras
        camCfg = cfg.cameras[cam]
        enabled = true
        if camCfg <> invalid and camCfg.enabled <> invalid then enabled = camCfg.enabled
        if enabled then out.cameras.Push(cam)
        if camCfg <> invalid and camCfg.live <> invalid and camCfg.live.streams <> invalid
            pick = ""
            subPick = ""
            for each label in camCfg.live.streams
                name = camCfg.live.streams[label]
                if pick = "" then pick = name
                if Right(name, 5) = "_main" then pick = name
                if Right(name, 4) = "_sub" then subPick = name
            end for
            if subPick = "" then
                for each label in camCfg.live.streams
                    name = camCfg.live.streams[label]
                    if name <> pick then subPick = name
                end for
            end if
            if pick <> "" then out.liveStreams[cam] = pick
            if subPick <> "" and subPick <> pick then out.liveStreamsSub[cam] = subPick
        end if
    end for
    out.cameras.Sort()
    return out
end function

' Cycle-camera selection filter: keep only the wanted cameras (with their
' index-aligned snapshot paths). Returns invalid when there is nothing to
' filter or the filter would leave no cameras (fall back to all).
function Frigate_FilterCycleCams(cameras as object, paths as object, wanted as dynamic) as dynamic
    if wanted = invalid or wanted.Count() = 0 then return invalid
    want = {}
    for each c in wanted
        want[c] = true
    end for
    fc = []
    fp = []
    for i = 0 to cameras.Count() - 1
        if want.DoesExist(cameras[i])
            fc.Push(cameras[i])
            if i < paths.Count() then fp.Push(paths[i]) else fp.Push("")
        end if
    end for
    if fc.Count() = 0 then return invalid
    return { cameras: fc, paths: fp }
end function

' Distinct stream-type suffixes present in a list of go2rtc stream names,
' e.g. ["front_main","front_sub","back_main"] -> ["_main","_sub"]. A suffix
' counts as a type when it is a known convention (_main/_sub/_roku) or
' appears on at least two names (so a lone camera called "front_door"
' doesn't invent a "_door" type). Known types come first, in quality order.
function Frigate_StreamTypes(streamNames as object) as object
    counts = {}
    for each n in streamNames
        p = 0
        for i = Len(n) to 1 step -1
            if Mid(n, i, 1) = "_" then p = i : exit for
        end for
        if p > 1 and p < Len(n)
            suffix = Mid(n, p)
            if counts.DoesExist(suffix)
                counts[suffix] = counts[suffix] + 1
            else
                counts[suffix] = 1
            end if
        end if
    end for
    types = []
    for each k in ["_main", "_sub", "_roku"]
        if counts.DoesExist(k) then types.Push(k)
    end for
    known = { "_main": true, "_sub": true, "_roku": true }
    others = []
    for each suffix in counts
        if not known.DoesExist(suffix) and counts[suffix] >= 2 then others.Push(suffix)
    end for
    others.Sort()
    for each o in others
        types.Push(o)
    end for
    return types
end function

' Stream name for a camera at a chosen type: a known variant suffix on the
' main stream name is replaced ("cam_main" + "_sub" -> "cam_sub"); a bare
' name just gets the suffix appended ("cam" + "_sub" -> "cam_sub").
function Frigate_StreamNameForType(mainName as string, streamType as string) as string
    base = mainName
    for each suffix in ["_main", "_sub", "_roku"]
        if Len(base) > Len(suffix) and Right(base, Len(suffix)) = suffix
            base = Left(base, Len(base) - Len(suffix))
            exit for
        end if
    end for
    return base + streamType
end function

' True when response headers show the server is behind Cloudflare, which
' silently drops non-web ports — the raw go2rtc port can never work there.
' headersArray is roUrlEvent.GetResponseHeadersArray() format: [{name: value}]
function Frigate_IsCloudflare(headersArray as dynamic) as boolean
    if headersArray = invalid then return false
    for each entry in headersArray
        for each k in entry
            key = LCase(k)
            if key = "cf-ray" then return true
            if key = "server" and Instr(1, LCase(entry[k]), "cloudflare") > 0 then return true
        end for
    end for
    return false
end function

' Non-comment entries of an m3u8 playlist (variant names or segment files)
function Frigate_PlaylistEntries(body as string) as object
    entries = []
    for each ln in body.Split(chr(10))
        l = ln.Trim()
        if l <> "" and Left(l, 1) <> "#" then entries.Push(l)
    end for
    return entries
end function

' Directory of a playlist URL, for resolving relative entries: query and
' filename stripped, trailing slash kept
function Frigate_HlsBaseUrl(url as string) as string
    u = url
    p = Instr(1, u, "?")
    if p > 0 then u = Left(u, p - 1)
    for i = Len(u) to 1 step -1
        if Mid(u, i, 1) = "/" then return Left(u, i)
    end for
    return u
end function

' bbox draws Frigate's detection bounding boxes onto the JPEG
function Frigate_SnapshotPath(cameraName as string, height as integer, bbox = false as boolean) as string
    path = "/api/" + cameraName + "/latest.jpg?height=" + StrI(height).Trim()
    if bbox then path = path + "&bbox=1"
    return path
end function

function Frigate_EventThumbPath(eventId as string) as string
    return "/api/events/" + eventId + "/thumbnail.jpg"
end function

function Frigate_EventClipPath(eventId as string) as string
    return "/api/events/" + eventId + "/clip.mp4"
end function

function Frigate_VodRangeUrl(server as object, cameraName as string, startTs as double, endTs as double) as string
    ' Int()/StrI()/Str() coerce through 32-bit float and mangle epoch timestamps;
    ' LongInteger + ToStr() keeps full precision (floor start, ceil end)
    s& = startTs
    if s& > startTs then s& = s& - 1
    e& = endTs
    if e& < endTs then e& = e& + 1
    return server.baseUrl + "/vod/" + cameraName + "/start/" + s&.ToStr() + "/end/" + e&.ToStr() + "/master.m3u8"
end function

function Frigate_VodHourUrl(server as object, yearMonth as string, day as string, hour as string, cameraName as string, tz as string) as string
    tzSafe = tz.Replace("/", ",")
    return server.baseUrl + "/vod/" + yearMonth + "/" + day + "/" + hour + "/" + cameraName + "/" + tzSafe + "/master.m3u8"
end function

' TASK-THREAD ONLY: creates roUrlTransfer, which crashes on the SceneGraph render thread — use the _Render copies in screens
function Frigate_UrlEncode(s as string) as string
    x = CreateObject("roUrlTransfer")
    return x.Escape(s)
end function

' Human-readable message for an HTTP-level failure (status 0 = no connection)
function Frigate_FriendlyError(status as integer, err as string) as string
    if status = 401 then return "Login failed — check username and password"
    if status = 403 then return "The server refused access (403)"
    if status = 404 then return "Not found on the server (404)"
    if status = 0
        msg = "Can't reach the server — check the URL and your network"
        if err <> "" then msg = msg + " (" + err + ")"
        return msg
    end if
    if status >= 500 then return "The server hit an internal error (" + StrI(status).Trim() + ")"
    return "Request failed (HTTP " + StrI(status).Trim() + ")"
end function

' Human-readable message for a Video node error code
function Frigate_FriendlyVideoError(code as integer, msg as string) as string
    if code = -1 then return "Couldn't connect to the video stream"
    if code = -2 then return "The video stream timed out"
    if code = -3 then return "This video format isn't supported by your Roku"
    if code = -4 then return "The video is unavailable right now"
    if code = -5 then return "The video couldn't be decoded"
    if msg <> "" then return msg
    return "Playback failed"
end function

' "72°F 0.12in" (imperial) / "21°C 3.2mm" (metric); precip omitted when zero
function Weather_Format(temp as dynamic, precipType as dynamic, unit = "f" as string) as string
    if temp = invalid then return ""
    s = StrI(Int(temp + 0.5)).Trim() + "°" + UCase(unit)
    ' precipType is "rain", "snow", "rain/snow" or "" — what today's
    ' forecast expects, not a measured amount
    if precipType <> invalid and precipType <> "" then s = s + " " + precipType
    return s
end function

' Current local time as "7:24 pm" for the on-screen clock
function TimeUtil_FormatClock() as string
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    hr = dt.GetHours()
    ampm = "am"
    if hr >= 12 then ampm = "pm"
    if hr = 0 then hr = 12
    if hr > 12 then hr = hr - 12
    mins = StrI(dt.GetMinutes()).Trim()
    if Len(mins) = 1 then mins = "0" + mins
    return StrI(hr).Trim() + ":" + mins + " " + ampm
end function

function TimeUtil_FormatEpoch(epoch as double) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(Int(epoch))
    dt.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    hr = dt.GetHours()
    ampm = "AM"
    if hr >= 12 then ampm = "PM"
    if hr = 0 then hr = 12
    if hr > 12 then hr = hr - 12
    mins = StrI(dt.GetMinutes()).Trim()
    if Len(mins) = 1 then mins = "0" + mins
    return months[dt.GetMonth() - 1] + " " + StrI(dt.GetDayOfMonth()).Trim() + " " + StrI(hr).Trim() + ":" + mins + " " + ampm
end function
