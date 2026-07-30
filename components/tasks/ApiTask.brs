sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.input
    server = req.server
    url = req.path
    if Left(url, 4) <> "http" then url = server.baseUrl + url

    headers = Frigate_AuthHeaders(server)
    res = doRequest(url, headers, req.method, req.body, req.savePath)

    newToken = ""
    if res.status = 401 and server.authType = "frigate" and server.username <> ""
        token = doLogin(server)
        if token <> ""
            newToken = token
            server2 = {}
            server2.Append(server)
            server2.token = token
            headers = Frigate_AuthHeaders(server2)
            res = doRequest(url, headers, req.method, req.body, req.savePath)
        end if
    end if

    out = {
        ok: (res.status >= 200 and res.status < 300),
        status: res.status,
        body: res.body,
        savePath: req.savePath,
        newToken: newToken,
        error: res.error,
        context: req.context
    }
    m.top.output = out
end sub

' Synchronous request. Returns { status, body, headersArray, error }
function doRequest(url as string, headers as object, method as string, body as string, savePath as string) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.RetainBodyOnError(true)
    xfer.EnableEncodings(true)
    if Left(url, 8) = "https://"
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.InitClientCertificates()
    end if
    for each k in headers
        xfer.AddHeader(k, headers[k])
    end for

    started = false
    if method = "POST"
        xfer.AddHeader("Content-Type", "application/json")
        started = xfer.AsyncPostFromString(body)
    else if savePath <> ""
        started = xfer.AsyncGetToFile(savePath)
    else
        started = xfer.AsyncGetToString()
    end if
    if not started then return { status: 0, body: "", headersArray: [], error: "request failed to start" }

    msg = wait(15000, port)
    if msg = invalid
        xfer.AsyncCancel()
        return { status: 0, body: "", headersArray: [], error: "timeout" }
    end if
    if type(msg) = "roUrlEvent"
        status = msg.GetResponseCode()
        err = ""
        if status < 0 then err = msg.GetFailureReason()
        return { status: status, body: msg.GetString(), headersArray: msg.GetResponseHeadersArray(), error: err }
    end if
    return { status: 0, body: "", headersArray: [], error: "unexpected event" }
end function

' Returns JWT string or ""
function doLogin(server as object) as string
    body = FormatJson({ user: server.username, password: server.password })
    res = doRequest(server.baseUrl + "/api/login", {}, "POST", body, "")
    if res.status < 200 or res.status >= 300 then return ""
    for each entry in res.headersArray
        for each k in entry
            if LCase(k) = "set-cookie"
                token = Frigate_ParseTokenFromSetCookie(entry[k])
                if token <> "" then return token
            end if
        end for
    end for
    return ""
end function
