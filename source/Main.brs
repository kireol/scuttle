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
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        end if
    end while
end sub

' Replaced by the real runner in Task 2; needed so RunTests launches compile.
sub RunAllTests()
    print "[TESTS START]"
    print "[TESTS DONE]"
end sub
