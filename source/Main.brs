sub Main(args as dynamic)
    if args <> invalid and args.RunTests <> invalid
        RunAllTests()
        return
    end if
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("AppScene")
    screen.Show()
    ' Focus set before Show() does not stick; tell the scene to build its UI now
    scene.ready = true
    scene.ObserveField("exitApp", port)
    ' ECP input API: lets scripts add a server without driving the on-screen
    ' keyboard, e.g. curl -d '' "http://<roku>:8060/input?cmd=addserver&name=..&url=.."
    ecpInput = CreateObject("roInput")
    ecpInput.SetMessagePort(port)
    ' throttle for input?cmd=runtests: deploy.sh retries the trigger when the
    ' debug console is mute, and overlapping suite runs race the registry
    ' backup/wipe/restore in Test_ServerStore — that has eaten real servers
    testClock = CreateObject("roTimespan")
    lastTestMs = -60000
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        else if type(msg) = "roSGNodeEvent"
            if msg.GetField() = "exitApp" and msg.GetData() = true then return
        else if type(msg) = "roInputEvent"
            info = msg.GetInfo()
            if info <> invalid and info.cmd <> invalid and info.cmd = "addserver"
                HandleAddServer(info)
                scene.serversChanged = true
            else if info <> invalid and info.cmd <> invalid and info.cmd = "runtests"
                ' Instant-Resume devices only RESUME on ECP launch, so the
                ' RunTests launch arg is unreliable — this input command runs
                ' the suite in the live app instead (see deploy.sh --test)
                if testClock.TotalMilliseconds() - lastTestMs >= 60000
                    lastTestMs = testClock.TotalMilliseconds()
                    RunAllTests()
                end if
            end if
        end if
    end while
end sub

sub HandleAddServer(info as object)
    ' Upsert by name so re-running an add-server script updates in place
    ' instead of stacking duplicates
    srv = invalid
    if info.name <> invalid
        for each s in ServerStore_Load()
            if s.name = info.name
                srv = s
                exit for
            end if
        end for
    end if
    if srv = invalid then srv = ServerStore_NewServer()
    if info.name <> invalid then srv.name = info.name
    if info.url <> invalid
        newUrl = Frigate_NormalizeBaseUrl(info.url)
        ' a different address means the Cloudflare detection must start over
        if srv.DoesExist("cfProxied") and newUrl <> srv.baseUrl then srv.cfProxied = false
        srv.baseUrl = newUrl
    end if
    if info.username <> invalid then srv.username = info.username
    if info.password <> invalid then srv.password = info.password
    if info.authtype <> invalid then srv.authType = info.authtype
    if info.go2rtcport <> invalid
        srv.go2rtcPort = Val(info.go2rtcport)
        if srv.go2rtcPort = 0 then srv.go2rtcPort = 1984
    end if
    if info.zipcode <> invalid
        srv.zipcode = info.zipcode
        srv.zipLat = ""
        srv.zipLon = ""
    end if
    print "[main] addserver via ECP input: "; srv.name; " "; srv.baseUrl
    ServerStore_Upsert(srv)
end sub

