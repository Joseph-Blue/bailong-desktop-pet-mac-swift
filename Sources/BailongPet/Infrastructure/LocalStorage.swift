import AppKit

struct LocalStorageUsage {
    let data: Int64, workspace: Int64, cache: Int64
    var total: Int64 {data + workspace + cache}
    func description(_ bytes:Int64) -> String {
        let amount = ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)
        return amount + " · " + String(format:"%.1f%%",total > 0 ? Double(bytes)/Double(total)*100 : 0)
    }
}

enum LocalStorage {
    static let bundleID = "com.bailongpet.appkit"
    static var cache: URL {FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent(bundleID,isDirectory:true)}
    static var workspace: URL {Paths.data.appendingPathComponent("Workspace",isDirectory:true)}
    static var preferences: URL {URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Preferences/"+bundleID+".plist")}
    static func size(_ url:URL) throws -> Int64 {
        let manager = FileManager.default
        guard manager.fileExists(atPath:url.path) else {return 0}
        let keys:Set<URLResourceKey> = [.isSymbolicLinkKey,.isDirectoryKey,.fileSizeKey]
        let own = try url.resourceValues(forKeys:keys)
        if own.isSymbolicLink == true {return 0}
        if own.isDirectory != true {return Int64(own.fileSize ?? 0)}
        var failure: Error?, bytes:Int64 = 0
        guard let files = manager.enumerator(at:url,includingPropertiesForKeys:Array(keys),options:[],errorHandler:{_,error in failure = error; return false}) else {throw PetFailure(message:"无法读取目录："+url.path)}
        for case let child as URL in files {
            let values = try child.resourceValues(forKeys:keys)
            if values.isSymbolicLink == true {files.skipDescendants(); continue}
            if values.isDirectory != true {bytes += Int64(values.fileSize ?? 0)}
        }
        if let failure {throw failure}
        return bytes
    }
    static func usage() throws -> LocalStorageUsage {
        let work = try size(workspace)
        return try LocalStorageUsage(data:max(0,size(Paths.data)-work)+size(preferences),workspace:work,cache:size(cache))
    }
    static func clearCache() throws {
        // 仅处理本应用的缓存目录，不追随符号链接、不扫描其他应用。
        if FileManager.default.fileExists(atPath:cache.path) {try FileManager.default.removeItem(at:cache)}
        URLCache.shared.removeAllCachedResponses()
    }
    static func clearBuiltInWorkspace(moveToTrash:(URL) throws -> Void = {try FileManager.default.trashItem(at:$0,resultingItemURL:nil)}) throws {
        let manager = FileManager.default, directory = workspace
        guard manager.fileExists(atPath:directory.path) else {return}
        let values = try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true,values.isSymbolicLink != true else {throw PetFailure(message:"内置 Workspace 已被替换，未执行清理。")}
        for child in try manager.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) {
            try moveToTrash(child)
        }
    }
}
