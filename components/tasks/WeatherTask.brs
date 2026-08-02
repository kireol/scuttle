sub init()
    m.top.functionName = "execute"
end sub

' ZIP -> lat/lon (zippopotam.us, cached by the caller) -> current temperature
' and today's precipitation (open-meteo). Both APIs are free and keyless.
sub execute()
    lat = m.top.lat
    lon = m.top.lon
    if (lat = "" or lon = "") and m.top.zipcode <> ""
        res = doRequest("https://api.zippopotam.us/us/" + m.top.zipcode, {}, "GET", "", "")
        if res.status = 200
            j = ParseJson(res.body)
            if j <> invalid and j.places <> invalid and j.places.Count() > 0
                lat = j.places[0]["latitude"]
                lon = j.places[0]["longitude"]
            end if
        end if
    end if
    if lat = "" or lon = ""
        m.top.output = { ok: false }
        return
    end if
    tempUnit = "fahrenheit"
    precipUnit = "inch"
    if m.top.unit = "c"
        tempUnit = "celsius"
        precipUnit = "mm"
    end if
    url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
    url = url + "&current=temperature_2m&daily=precipitation_sum&forecast_days=1"
    url = url + "&temperature_unit=" + tempUnit + "&precipitation_unit=" + precipUnit + "&timezone=auto"
    res = doRequest(url, {}, "GET", "", "")
    if res.status <> 200
        m.top.output = { ok: false }
        return
    end if
    j = ParseJson(res.body)
    if j = invalid or j.current = invalid or j.current.temperature_2m = invalid
        m.top.output = { ok: false }
        return
    end if
    precip = 0.0
    if j.daily <> invalid and j.daily.precipitation_sum <> invalid and j.daily.precipitation_sum.Count() > 0
        if j.daily.precipitation_sum[0] <> invalid then precip = j.daily.precipitation_sum[0]
    end if
    m.top.output = { ok: true, tempF: j.current.temperature_2m, precipIn: precip, lat: lat, lon: lon }
end sub
