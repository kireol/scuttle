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
    ' # suffix forces double literals: these values overflow float (32-bit) precision
    print "DEBUG vod range actual: "; Frigate_VodRangeUrl(s, "cam", 1753828000.4#, 1753828060.9#)
    T("vod range", Frigate_VodRangeUrl(s, "cam", 1753828000.4#, 1753828060.9#) = "http://10.0.0.5:8971/vod/cam/start/1753828000/end/1753828061/master.m3u8", r)
    T("vod hour tz commas", Frigate_VodHourUrl(s, "2026-07", "29", "23", "cam", "America/New_York") = "http://10.0.0.5:8971/vod/2026-07/29/23/cam/America,New_York/master.m3u8", r)
    T("urlencode", Frigate_UrlEncode("a b&c") = "a%20b%26c", r)

    n = Frigate_LiveStreamNames("front_door_main", "front_door_sub")
    T("live names main first", n.Count() = 3 and n[0] = "front_door_main" and n[1] = "front_door_sub" and n[2] = "front_door_roku", r)
    n = Frigate_LiveStreamNames("cam", "")
    T("live names no sub", n.Count() = 2 and n[0] = "cam" and n[1] = "cam_roku", r)
    n = Frigate_LiveStreamNames("cam", "cam")
    T("live names dup sub skipped", n.Count() = 2 and n[0] = "cam" and n[1] = "cam_roku", r)

    ty = Frigate_StreamTypes(["front_main", "front_sub", "back_main", "back_roku"])
    T("stream types known ordered", ty.Count() = 3 and ty[0] = "_main" and ty[1] = "_sub" and ty[2] = "_roku", r)
    ty = Frigate_StreamTypes(["front_door"])
    T("stream types lone suffix ignored", ty.Count() = 0, r)
    ty = Frigate_StreamTypes(["front_hd", "back_hd", "front_main"])
    T("stream types repeated custom kept", ty.Count() = 2 and ty[0] = "_main" and ty[1] = "_hd", r)
    T("stream types no underscores", Frigate_StreamTypes(["cam1", "cam2"]).Count() = 0, r)

    clk = TimeUtil_FormatClock()
    T("clock has colon", Instr(1, clk, ":") > 0, r)
    T("clock has am/pm", Instr(1, clk, "am") > 0 or Instr(1, clk, "pm") > 0, r)

    T("stream name replaces main", Frigate_StreamNameForType("cam_main", "_sub") = "cam_sub", r)
    T("stream name replaces sub", Frigate_StreamNameForType("cam_sub", "_roku") = "cam_roku", r)
    T("stream name bare appends", Frigate_StreamNameForType("cam", "_sub") = "cam_sub", r)
    T("stream name keeps unknown suffix", Frigate_StreamNameForType("front_door", "_main") = "front_door_main", r)

    body = "#EXTM3U" + chr(10) + "#EXT-X-STREAM-INF:BANDWIDTH=192000" + chr(10) + "hls/playlist.m3u8?id=Ab12" + chr(10)
    e = Frigate_PlaylistEntries(body)
    T("playlist entries master", e.Count() = 1 and e[0] = "hls/playlist.m3u8?id=Ab12", r)
    body = "#EXTM3U" + chr(10) + "#EXTINF:0.500," + chr(10) + "segment.m4s?id=x&n=0" + chr(10) + chr(10) + "#EXTINF:0.500," + chr(10) + "segment.m4s?id=x&n=1"
    e = Frigate_PlaylistEntries(body)
    T("playlist entries segments", e.Count() = 2 and e[0] = "segment.m4s?id=x&n=0" and e[1] = "segment.m4s?id=x&n=1", r)
    T("playlist entries empty", Frigate_PlaylistEntries("#EXTM3U" + chr(10) + "#EXT-X-VERSION:6").Count() = 0, r)

    T("hls base strips query+file", Frigate_HlsBaseUrl("http://10.0.0.5:1984/api/stream.m3u8?src=a&mp4") = "http://10.0.0.5:1984/api/", r)
    T("hls base nested", Frigate_HlsBaseUrl("https://nvr:8971/api/go2rtc/api/hls/playlist.m3u8?id=Z") = "https://nvr:8971/api/go2rtc/api/hls/", r)

    T("cf via server header", Frigate_IsCloudflare([{ "server": "cloudflare" }]) = true, r)
    T("cf case insensitive", Frigate_IsCloudflare([{ "Server": "Cloudflare" }]) = true, r)
    T("cf via cf-ray", Frigate_IsCloudflare([{ "CF-RAY": "8c9-DTW" }]) = true, r)
    T("cf nginx is false", Frigate_IsCloudflare([{ "server": "nginx/1.27.4" }, { "content-type": "text/html" }]) = false, r)
    T("cf empty is false", Frigate_IsCloudflare([]) = false, r)
    T("cf invalid is false", Frigate_IsCloudflare(invalid) = false, r)
end sub
