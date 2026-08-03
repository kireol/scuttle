' One-time hint dialogs. Each hint has a key; "Don't show this again"
' persists the key in AppSettings.hintsSeen. Import alongside
' AppSettings.brs — the dialog callback must live in the component scope,
' which importing this file provides.

function Hints_Seen(key as string) as boolean
    st = AppSettings_Load()
    return st.hintsSeen <> invalid and st.hintsSeen.DoesExist(key)
end function

' Shows the hint unless dismissed for good. Returns true if it was shown,
' so callers can avoid stacking a second dialog on the same screen-show.
function Hints_Show(key as string, title as string, message as string) as boolean
    if Hints_Seen(key) then return false
    d = CreateObject("roSGNode", "Dialog")
    d.title = title
    d.message = message
    d.buttons = ["Got it", "Don't show this again"]
    d.ObserveFieldScoped("buttonSelected", "Hints_OnButton")
    m.hintDialog = d
    m.hintKey = key
    m.top.GetScene().dialog = d
    return true
end function

sub Hints_OnButton()
    d = m.hintDialog
    if d = invalid then return
    if d.buttonSelected = 1
        st = AppSettings_Load()
        if st.hintsSeen = invalid then st.hintsSeen = {}
        st.hintsSeen[m.hintKey] = true
        AppSettings_Save(st)
    end if
    d.close = true
    m.hintDialog = invalid
end sub
