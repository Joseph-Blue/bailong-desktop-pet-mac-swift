import AppKit

// 本地消息附件只定位文件；网页等链接仍由 NSTextView 交给系统处理。
enum MessageFileLink {
    static func url(forPath path:String) -> URL? {
        if path.hasPrefix("/") {return URL(fileURLWithPath:path)}
        var components = URLComponents(); components.path = path
        return components.url
    }
    static func reveal(_ link: Any, relativeTo directory: URL?) -> Bool {
        let url: URL
        if let value = link as? URL {url = value}
        else if let value = link as? String, let parsed = URL(string:value) {url = parsed}
        else {return false}
        let scheme = url.scheme?.lowercased()
        guard scheme == nil || scheme == "file" || scheme == "sandbox" else {return false}
        if scheme == nil && url.path.isEmpty {return false}
        if scheme == "sandbox" {
            showError("此文件不在本机",PetFailure(message:"请在 Codex 中下载文件后，再到访达查看。"))
            return true
        }
        guard url.host == nil || url.host == "" || url.host == "localhost" else {
            showError("无法定位文件",PetFailure(message:"此链接不是本机文件地址。")); return true
        }
        let path = (url.path as NSString).expandingTildeInPath
        let file: URL
        if path.hasPrefix("/") {file = URL(fileURLWithPath:path)}
        else if let directory {file = directory.appendingPathComponent(path)}
        else {
            showError("无法定位文件",PetFailure(message:"此链接使用相对路径，但这条消息没有任务文件夹信息。")); return true
        }
        let target = existingFile(file.standardizedFileURL)
        guard let target else {
            showError("文件不存在",PetFailure(message:file.path)); return true
        }
        FinderFileReveal.reveal(target)
        return true
    }

    private static func existingFile(_ url: URL) -> URL? {
        // 优先匹配完整文件名，避免把名称中的冒号和数字当成行号。
        if FileManager.default.fileExists(atPath:url.path) {return url}
        let path = url.path.replacingOccurrences(of:":\\d+(?::\\d+)?$",with:"",options:.regularExpression)
        guard path != url.path, FileManager.default.fileExists(atPath:path) else {return nil}
        return URL(fileURLWithPath:path)
    }
}
