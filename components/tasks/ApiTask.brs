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
        headersArray: res.headersArray,
        savePath: req.savePath,
        newToken: newToken,
        error: res.error,
        context: req.context
    }
    m.top.output = out
end sub
