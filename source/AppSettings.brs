function AppSettings_Load() as object
    settings = { refreshSecs: 10, gridColumns: 3, livePortFirst: true }
    s = CreateObject("roRegistrySection", "scuttle_settings")
    if s.Exists("json")
        parsed = ParseJson(s.Read("json"))
        if parsed <> invalid then settings.Append(parsed)
    end if
    return settings
end function

sub AppSettings_Save(settings as object)
    s = CreateObject("roRegistrySection", "scuttle_settings")
    s.Write("json", FormatJson(settings))
    s.Flush()
end sub
