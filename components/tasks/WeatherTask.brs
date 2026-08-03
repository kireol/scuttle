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
    if m.top.unit = "c" then tempUnit = "celsius"
    url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
    url = url + "&current=temperature_2m&daily=rain_sum,showers_sum,snowfall_sum&forecast_days=1"
    url = url + "&temperature_unit=" + tempUnit + "&timezone=auto"
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
    ' report what kind of precipitation today's forecast expects
    rain = 0.0
    snow = 0.0
    if j.daily <> invalid
        rain = rain + DailyFirst(j.daily.rain_sum) + DailyFirst(j.daily.showers_sum)
        snow = snow + DailyFirst(j.daily.snowfall_sum)
    end if
    precipType = ""
    if rain > 0 and snow > 0
        precipType = "rain/snow"
    else if rain > 0
        precipType = "rain"
    else if snow > 0
        precipType = "snow"
    end if
    m.top.output = { ok: true, tempF: j.current.temperature_2m, precip: precipType, lat: lat, lon: lon }
end sub

function DailyFirst(arr as dynamic) as float
    if arr = invalid or arr.Count() = 0 or arr[0] = invalid then return 0.0
    return arr[0]
end function
