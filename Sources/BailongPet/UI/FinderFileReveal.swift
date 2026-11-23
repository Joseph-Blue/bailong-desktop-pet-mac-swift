import AppKit

// 只由用户点击文件链接触发。使用 Finder 自身字典，不控制 System Events 或请求辅助功能。
enum FinderFileReveal {
    // 目录入口沿用历史工具栏行为；不走文件定位脚本，不枚举访达窗口。
    static func openDirectory(_ directory:URL) {
        if !NSWorkspace.shared.open(directory) {
            showError(L10n.text(.workspace,"finderFileReveal.openDirectory.error"),PetFailure(message:L10n.text(.workspace,"finderFileReveal.openDirectory.message")+directory.path))
        }
    }

    private static let queue = DispatchQueue(label:L10n.text(.workspace,"finderFileReveal.queue.label"),qos:.userInitiated)
    // 先取得窗口 ID 列表；直接 repeat ... in Finder windows 会把 item 引用交给 Finder，读到窗口内文件。
    static let script = """
    on run arguments
        set filePath to item 1 of arguments
        set folderPath to item 2 of arguments
        set targetItem to POSIX file filePath as alias
        set targetFolder to POSIX file folderPath as alias
        tell application id "com.apple.finder"
            with timeout of 15 seconds
                set chosenWindowID to missing value
                set windowIDs to get id of every Finder window
                repeat with windowID in windowIDs
                    set candidateID to contents of windowID
                    if (target of Finder window id candidateID) is folder targetFolder then
                        set chosenWindowID to candidateID
                        exit repeat
                    end if
                end repeat
                if chosenWindowID is missing value then
                    set createdWindow to make new Finder window to targetFolder
                    set chosenWindowID to id of createdWindow
                end if
                set collapsed of Finder window id chosenWindowID to false
                set index of Finder window id chosenWindowID to 1
                set selection to {targetItem}
                set frontmost to true
            end timeout
        end tell
    end run
    """

    static func reveal(_ target:URL) {
        // 固定脚本与路径参数分离，文件名中的引号、换行及反斜杠不成为脚本代码。
        queue.async {
            let process = Process(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/osascript")
            process.arguments = ["-e",script,"--",target.path,target.deletingLastPathComponent().path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = errors
            do {
                try process.run()
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus != 0 else {return}
                let detail = String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
                DispatchQueue.main.async {
                    let message = detail.contains("(-1743)")
                        ? L10n.text(.workspace,"finderFileReveal.reveal.text")
                        : L10n.text(.workspace,"finderFileReveal.reveal.text.2") + (detail.isEmpty ? L10n.format(.workspace,"finderFileReveal.reveal.text.3",String(describing:process.terminationStatus)) : detail)
                    showError(L10n.text(.workspace,"finderFileReveal.reveal.error"),PetFailure(message:message))
                }
            } catch {
                DispatchQueue.main.async {showError(L10n.text(.workspace,"finderFileReveal.reveal.error.2"),error)}
            }
        }
    }
}
