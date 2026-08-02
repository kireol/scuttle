sub init()
    m.list = m.top.FindNode("list")
    m.status = m.top.FindNode("status")
    m.list.ObserveFieldScoped("itemSelected", "onSelect")
    m.top.ObserveField("serverId", "loadServer")
    m.top.ObserveField("wasShown", "onShown")
    m.server = ServerStore_NewServer()
    m.pendingTask = invalid
    m.dialog = invalid
    rebuild()
end sub

sub onShown()
    m.list.SetFocus(true)
end sub

sub loadServer()
    if m.top.serverId <> ""
        existing = ServerStore_GetById(m.top.serverId)
        if existing <> invalid then m.server = existing
    end if
    rebuild()
end sub

function rows() as object
    authLabel = m.server.authType
    return [
        { key: "name", title: "Name: " + m.server.name },
        { key: "baseUrl", title: "URL: " + m.server.baseUrl },
        { key: "go2rtcPort", title: "go2rtc port: " + StrI(m.server.go2rtcPort).Trim() },
        { key: "authType", title: "Auth type: " + authLabel + "  (OK cycles)" },
        { key: "username", title: "Username: " + m.server.username },
        { key: "password", title: "Password: " + String(Len(m.server.password), "*") },
        { key: "liveMode", title: "Live view: " + m.server.liveMode + "  (OK cycles)" },
        { key: "streamType", title: "Stream type: " + m.server.streamType + "  (OK picks from server)" },
        { key: "test", title: "▶ Test Connection" },
        { key: "save", title: "✔ Save" },
        { key: "delete", title: "✖ Delete Server" }
    ]
end function

sub rebuild()
    ' Replacing list content resets focus to row 0; restore it so
    ' cycling auth type or closing a keyboard keeps the user's place
    idx = m.list.itemFocused
    content = CreateObject("roSGNode", "ContentNode")
    for each row in rows()
        item = content.CreateChild("ContentNode")
        item.title = row.title
    end for
    m.list.content = content
    if idx > 0 then m.list.jumpToItem = idx
end sub

sub onSelect()
    row = rows()[m.list.itemSelected]
    print "[edit] selected row: "; row.key; " url="; m.server.baseUrl
    if row.key = "authType"
        order = ["none", "basic", "frigate"]
        for i = 0 to 2
            if order[i] = m.server.authType
                m.server.authType = order[(i + 1) mod 3]
                exit for
            end if
        end for
        rebuild()
    else if row.key = "liveMode"
        if m.server.liveMode = "video"
            m.server.liveMode = "snapshot"
        else
            m.server.liveMode = "video"
        end if
        rebuild()
    else if row.key = "streamType"
        fetchStreamTypes()
    else if row.key = "test"
        testConnection()
    else if row.key = "save"
        m.server.baseUrl = Frigate_NormalizeBaseUrl_Render(m.server.baseUrl)
        ServerStore_Upsert(m.server)
        showSavedDialog()
    else if row.key = "delete"
        ServerStore_Delete(m.server.id)
        m.top.closeMe = true
    else
        openKeyboard(row.key)
    end if
end sub

' Render-thread-safe normalize (no roUrlTransfer): duplicate of trim logic
function Frigate_NormalizeBaseUrl_Render(url as string) as string
    u = url.Trim()
    if u = "" then return ""
    if Left(u, 7) <> "http://" and Left(u, 8) <> "https://" then u = "http://" + u
    while Right(u, 1) = "/"
        u = Left(u, Len(u) - 1)
    end while
    return u
end function

sub openKeyboard(fieldKey as string)
    m.editingKey = fieldKey
    d = CreateObject("roSGNode", "StandardKeyboardDialog")
    d.title = "Enter " + fieldKey
    current = m.server[fieldKey]
    if fieldKey = "go2rtcPort" then current = StrI(m.server.go2rtcPort).Trim()
    d.text = current
    d.buttons = ["OK", "Cancel"]
    d.ObserveFieldScoped("buttonSelected", "onKeyboardButton")
    m.dialog = d
    m.top.GetScene().dialog = d
end sub

sub onKeyboardButton()
    d = m.dialog
    print "[edit] keyboard button "; d.buttonSelected; " text="; d.text
    if d.buttonSelected = 0
        value = d.text
        if m.editingKey = "go2rtcPort"
            m.server.go2rtcPort = Val(value)
            if m.server.go2rtcPort = 0 then m.server.go2rtcPort = 1984
        else
            m.server[m.editingKey] = value
        end if
        rebuild()
    end if
    d.close = true
    m.dialog = invalid
end sub

' Discover which go2rtc stream variants exist on this server, then offer a
' dialog pick — "auto" keeps the built-in main -> sub -> _roku fallback
sub fetchStreamTypes()
    m.status.text = "Looking up stream types on " + m.server.baseUrl + " ..."
    m.server.baseUrl = Frigate_NormalizeBaseUrl_Render(m.server.baseUrl)
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/go2rtc/api/streams", method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onStreamTypes")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onStreamTypes(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    if out.newToken <> "" then m.server.token = out.newToken
    if not out.ok
        m.status.text = Frigate_FriendlyError(out.status, out.error)
        return
    end if
    streams = ParseJson(out.body)
    names = []
    if streams <> invalid
        for each k in streams
            names.Push(k)
        end for
    end if
    m.typeOptions = ["auto"]
    m.typeOptions.Append(Frigate_StreamTypes(names))
    if m.typeOptions.Count() = 1
        m.status.text = "No stream variants found on the server — keeping auto"
        m.server.streamType = "auto"
        rebuild()
        return
    end if
    m.status.text = ""
    d = CreateObject("roSGNode", "Dialog")
    d.title = "Stream type"
    d.message = "Pick which go2rtc stream variant live view should use"
    d.buttons = m.typeOptions
    d.ObserveFieldScoped("buttonSelected", "onStreamTypeDialog")
    m.dialog = d
    m.top.GetScene().dialog = d
end sub

sub onStreamTypeDialog()
    d = m.dialog
    if d.buttonSelected >= 0 and d.buttonSelected < m.typeOptions.Count()
        m.server.streamType = m.typeOptions[d.buttonSelected]
    end if
    d.close = true
    m.dialog = invalid
    rebuild()
end sub

sub showSavedDialog()
    d = CreateObject("roSGNode", "Dialog")
    d.title = "Server saved"
    name = m.server.name
    if name = "" then name = "server"
    d.buttons = ["View " + name + " cameras", "Back to settings"]
    d.ObserveFieldScoped("buttonSelected", "onSavedDialog")
    m.dialog = d
    m.top.GetScene().dialog = d
end sub

sub onSavedDialog()
    d = m.dialog
    choice = d.buttonSelected
    d.close = true
    m.dialog = invalid
    if choice = 0
        ' land on this server's tab on the home screen
        scene = m.top.GetScene()
        scene.goToServerId = m.server.id
        scene.CallFunc("popToRoot")
    else
        m.top.closeMe = true
    end if
end sub

sub testConnection()
    m.status.text = "Testing " + m.server.baseUrl + " ..."
    m.server.baseUrl = Frigate_NormalizeBaseUrl_Render(m.server.baseUrl)
    t = CreateObject("roSGNode", "ApiTask")
    t.input = { server: m.server, path: "/api/config", method: "GET", body: "", savePath: "", context: invalid }
    t.ObserveFieldScoped("output", "onTestResult")
    t.control = "RUN"
    m.pendingTask = t
end sub

sub onTestResult(ev as object)
    out = ev.GetData()
    m.pendingTask = invalid
    if out.newToken <> ""
        m.server.token = out.newToken
    end if
    if out.ok
        cfg = ParseJson(out.body)
        if cfg <> invalid and cfg.cameras <> invalid
            names = []
            for each cam in cfg.cameras
                names.Push(cam)
            end for
            version = ""
            if cfg.version <> invalid then version = " v" + cfg.version
            okMsg = "OK" + version + " — " + StrI(names.Count()).Trim() + " cameras found"
            m.status.text = okMsg
            ' Detect Frigate versions older than 0.14 (string like "0.16.1-abc"); guard
            ' defensively so a missing/odd version string just keeps the OK message.
            if cfg.version <> invalid and GetInterface(cfg.version, "ifString") <> invalid
                verStr = cfg.version
                dashPos = Instr(1, verStr, "-")
                if dashPos > 0 then verStr = Left(verStr, dashPos - 1)
                verParts = verStr.Split(".")
                if verParts.Count() >= 2
                    majorStr = verParts[0]
                    minorStr = verParts[1]
                    if majorStr = "0" and Val(minorStr) < 14
                        m.status.text = "Frigate version too old (needs 0.14+): v" + cfg.version
                    end if
                end if
            end if
        else
            m.status.text = "Connected, but response is not a Frigate config"
        end if
    else
        m.status.text = Frigate_FriendlyError(out.status, out.error)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
