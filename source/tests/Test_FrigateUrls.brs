sub Test_FrigateUrls(r as object)
    print "Test_FrigateUrls"
    T("normalize adds scheme", Frigate_NormalizeBaseUrl("10.0.0.5:8971") = "http://10.0.0.5:8971", r)
    T("normalize strips slash", Frigate_NormalizeBaseUrl("https://nvr.lan:8971/") = "https://nvr.lan:8971", r)
    T("host from url", Frigate_HostFromUrl("http://10.0.0.5:8971") = "10.0.0.5", r)
    T("host no port", Frigate_HostFromUrl("https://nvr.lan") = "nvr.lan", r)

    s = ServerStore_NewServer()
    s.baseUrl = "http://10.0.0.5:8971"
    T("auth none empty", Frigate_AuthHeaders(s).Count() = 0, r)

    s.authType = "basic"
    s.username = "user"
    s.password = "pass"
    h = Frigate_AuthHeaders(s)
    T("basic header", h.Authorization = "Basic dXNlcjpwYXNz", r)

    s.authType = "frigate"
    s.token = ""
    T("frigate no token empty", Frigate_AuthHeaders(s).Count() = 0, r)
    s.token = "abc"
    T("bearer header", Frigate_AuthHeaders(s).Authorization = "Bearer abc", r)

    ck = "frigate_token=eyJx.y.z; expires=Sat, 01 Aug 2026 00:00:00 GMT; Path=/"
    T("parse cookie", Frigate_ParseTokenFromSetCookie(ck) = "eyJx.y.z", r)
    T("parse cookie miss", Frigate_ParseTokenFromSetCookie("other=1; Path=/") = "", r)

    T("live hls", Frigate_LiveHlsUrl(s, "front_door") = "http://10.0.0.5:1984/api/stream.m3u8?src=front_door&mp4", r)
    T("snapshot path", Frigate_SnapshotPath("front_door", 360) = "/api/front_door/latest.jpg?height=360", r)
    T("event thumb", Frigate_EventThumbPath("171234.5-abcd") = "/api/events/171234.5-abcd/thumbnail.jpg", r)
    T("event clip", Frigate_EventClipPath("171234.5-abcd") = "/api/events/171234.5-abcd/clip.mp4", r)
    T("vod range", Frigate_VodRangeUrl(s, "cam", 1753828000.4, 1753828060.9) = "http://10.0.0.5:8971/vod/cam/start/1753828000/end/1753828061/master.m3u8", r)
    T("vod hour tz commas", Frigate_VodHourUrl(s, "2026-07", "29", "23", "cam", "America/New_York") = "http://10.0.0.5:8971/vod/2026-07/29/23/cam/America,New_York/master.m3u8", r)
    T("urlencode", Frigate_UrlEncode("a b&c") = "a%20b%26c", r)
end sub
