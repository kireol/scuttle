sub T(name as string, cond as boolean, r as object)
    if cond
        r.passed = r.passed + 1
        print "  PASS: "; name
    else
        r.failed = r.failed + 1
        print "  FAIL: "; name
    end if
end sub

sub RunAllTests()
    print "[TESTS START]"
    r = {passed: 0, failed: 0}
    Test_Sanity(r)
    Test_ServerStore(r)
    Test_FrigateUrls(r)
    print "passed: "; r.passed; " failed: "; r.failed
    if r.failed > 0
        print "[TESTS FAILED]"
    else
        print "[TESTS DONE]"
    end if
end sub

sub Test_Sanity(r as object)
    print "Test_Sanity"
    T("math works", 1 + 1 = 2, r)
end sub
