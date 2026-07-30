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

function Frigate_LiveHlsUrl(server as object, cameraName as string) as string
    host = Frigate_HostFromUrl(server.baseUrl)
    return "http://" + host + ":" + StrI(server.go2rtcPort).Trim() + "/api/stream.m3u8?src=" + Frigate_UrlEncode(cameraName) + "&mp4"
end function

function Frigate_SnapshotPath(cameraName as string, height as integer) as string
    return "/api/" + cameraName + "/latest.jpg?height=" + StrI(height).Trim()
end function

function Frigate_EventThumbPath(eventId as string) as string
    return "/api/events/" + eventId + "/thumbnail.jpg"
end function

function Frigate_EventClipPath(eventId as string) as string
    return "/api/events/" + eventId + "/clip.mp4"
end function

function Frigate_VodRangeUrl(server as object, cameraName as string, startTs as double, endTs as double) as string
    s = StrI(Int(startTs)).Trim()
    e = StrI(Int(endTs + 0.999)).Trim()
    return server.baseUrl + "/vod/" + cameraName + "/start/" + s + "/end/" + e + "/master.m3u8"
end function

function Frigate_VodHourUrl(server as object, yearMonth as string, day as string, hour as string, cameraName as string, tz as string) as string
    tzSafe = tz.Replace("/", ",")
    return server.baseUrl + "/vod/" + yearMonth + "/" + day + "/" + hour + "/" + cameraName + "/" + tzSafe + "/master.m3u8"
end function

function Frigate_UrlEncode(s as string) as string
    x = CreateObject("roUrlTransfer")
    return x.Escape(s)
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
