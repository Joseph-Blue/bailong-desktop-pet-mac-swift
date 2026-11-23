on run argv
    set volumePath to item 1 of argv
    set volumeFolder to POSIX file volumePath as alias
    set backgroundFile to POSIX file (volumePath & "/.background/background.tiff") as alias
    tell application "Finder"
        set installWindow to make new Finder window to volumeFolder
        set current view of installWindow to icon view
        set toolbar visible of installWindow to false
        set statusbar visible of installWindow to false
        set pathbar visible of installWindow to false
        set bounds of installWindow to {100, 100, 1020, 558}
        set options to icon view options of installWindow
        set arrangement of options to not arranged
        set icon size of options to 80
        set text size of options to 12
        set label position of options to bottom
        set shows item info of options to false
        set shows icon preview of options to true
        set background picture of options to backgroundFile
        set position of item "白龙桌宠Swift.app" of volumeFolder to {180, 190}
        set position of item "应用程序" of volumeFolder to {647, 190}
        update volumeFolder without registering applications
        delay 2
        close installWindow
    end tell
end run
