sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    server = m.top.server
    headers = Frigate_AuthHeaders(server)
    for each item in m.top.items
        if m.top.quit then exit for
        res = doRequest(server.baseUrl + item.path, headers, "GET", "", item.savePath)
        if res.status = 401 and server.authType = "frigate" and server.username <> ""
            token = doLogin(server)
            if token <> ""
                server.token = token
                m.top.newToken = token
                headers = Frigate_AuthHeaders(server)
                res = doRequest(server.baseUrl + item.path, headers, "GET", "", item.savePath)
            end if
        end if
        m.top.result = { key: item.key, savePath: item.savePath, ok: (res.status >= 200 and res.status < 300) }
    end for
end sub
