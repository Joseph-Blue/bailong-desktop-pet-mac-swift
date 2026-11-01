import AppKit

// 只由用户点击文件链接触发。使用 Finder 自身字典，不控制 System Events 或请求辅助功能。
enum FinderFileReveal {
    private static let queue = DispatchQueue(label:"白龙桌宠 访达定位",qos:.userInitiated)
    static let script = """
    on run arguments
        set filePath to item 1 of arguments
        set folderPath to item 2 of arguments
        set targetItem to POSIX file filePath as alias
        set targetFolder to POSIX file folderPath as alias
        tell application id "com.apple.finder"
            with timeout of 15 seconds
                set chosenWindow to missing value
                repeat with candidate in Finder windows
                    if (target of candidate) is folder targetFolder then
                        set chosenWindow to candidate
                        exit repeat
                    end if
                end repeat
                if chosenWindow is missing value then
                    set chosenWindow to make new Finder window to targetFolder
                end if
                set collapsed of chosenWindow to false
                set index of chosenWindow to 1
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
                        ? "请在系统设置 → 隐私与安全性 → 自动化中，允许白龙桌宠Swift控制访达，然后重新点击文件链接。"
                        : "访达未完成文件定位。\n" + (detail.isEmpty ? "脚本退出码：\(process.terminationStatus)" : detail)
                    showError("无法在访达中显示",PetFailure(message:message))
                }
            } catch {
                DispatchQueue.main.async {showError("无法启动访达定位",error)}
            }
        }
    }
}
