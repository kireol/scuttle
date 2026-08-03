' Dual-written like ServerStore: registry plus a cachefs mirror with a
' revision counter, because registry flushes don't reliably reach disk on
' every fleet TV (see ServerStore.brs for the full story).

function AppSettings_CachePath() as string
    return "cachefs:/scuttle_settings.json"
end function

function AppSettings_ParseWrapper(raw as string) as object
    if raw = "" then return { rev: -1, settings: invalid }
    parsed = ParseJson(raw)
    if parsed = invalid then return { rev: -1, settings: invalid }
    if parsed.settings <> invalid then
        rev = 0
        if parsed.rev <> invalid then rev = parsed.rev
        return { rev: rev, settings: parsed.settings }
    end if
    ' legacy payload: the settings AA itself
    return { rev: 0, settings: parsed }
end function

function AppSettings_BestWrapper() as object
    regRaw = ""
    s = CreateObject("roRegistrySection", "scuttle_settings")
    if s.Exists("json") then regRaw = s.Read("json")
    fileRaw = ""
    if MatchFiles("cachefs:/", "scuttle_settings.json").Count() > 0
        fileRaw = ReadAsciiFile(AppSettings_CachePath())
    end if
    reg = AppSettings_ParseWrapper(regRaw)
    fil = AppSettings_ParseWrapper(fileRaw)
    if fil.settings <> invalid and (reg.settings = invalid or fil.rev >= reg.rev) then return fil
    return reg
end function

function AppSettings_Load() as object
    settings = {
        refreshSecs: 10
        gridColumns: 3
        livePortFirst: true
        showClock: true
        showBoxes: false
        cycleSecs: 10
        cycleScope: "single"
        lastServerId: ""
        lastGridIdx: 0
        launchCount: 0
        hintsSeen: {}
    }
    stored = AppSettings_BestWrapper().settings
    if stored <> invalid then settings.Append(stored)
    return settings
end function

sub AppSettings_Save(settings as object)
    rev = AppSettings_BestWrapper().rev + 1
    json = FormatJson({ rev: rev, settings: settings })
    s = CreateObject("roRegistrySection", "scuttle_settings")
    s.Write("json", json)
    s.Flush()
    WriteAsciiFile(AppSettings_CachePath(), json)
end sub
