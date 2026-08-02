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
                ' registry writes must happen on the render thread (see
                ' AppScene.addServerInfo) — main-thread flushes are not
                ' reliably visible to render-thread readers
                scene.addServerInfo = info
            else if info <> invalid and info.cmd <> invalid and info.cmd = "listservers"
                ' debug aid: enumerate registry servers on the console, e.g.
                ' curl -d '' "http://<roku>:8060/input?cmd=listservers"
                for each s in ServerStore_Load()
                    print "[main] server name='"; s.name; "' unit="; s.tempUnit; " zip="; s.zipcode; " url="; s.baseUrl
                end for
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
