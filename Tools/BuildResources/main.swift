import Foundation

struct Failure: Error, CustomStringConvertible { let description: String; init(_ text: String) { description = text } }
struct Manifest: Decodable {
    let version: String
    let archive: String
    let published: Bool
    let url: String
    let bytes: Int64
    let runtime: [String]
    let development: [String]
}
let fm = FileManager.default
let catalogPath = "native-hevc/catalog/素材清单.json"
let args = Array(CommandLine.arguments.dropFirst())
func relative(_ path: String) throws -> String {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
        throw Failure("资源路径无效：\(path)")
    }
    return path
}
func json(_ url: URL) throws -> Any { try JSONSerialization.jsonObject(with: Data(contentsOf: url)) }
func animationFiles(_ root: URL) throws -> [String] {
    guard let catalog = try json(root.appendingPathComponent(catalogPath)) as? [String: Any] else { throw Failure("素材清单不是 JSON 对象") }
    let singles = ["idle", "dragAnimation", "landingAnimation", "quotaAnimation"]
    let arrays = ["additionalIdleAnimations", "variants", "workAnimations", "movementAnimations"]
    var clips = [[String: Any]]()
    for key in singles {
        guard let clip = catalog[key] as? [String: Any] else { throw Failure("素材清单缺少动作：\(key)") }
        clips.append(clip)
    }
    for key in arrays {
        guard let items = catalog[key] as? [Any] else { throw Failure("素材清单缺少动作组：\(key)") }
        for item in items {
            if key == "workAnimations", item is NSNull { continue }
            guard let clip = item as? [String: Any] else { throw Failure("素材清单动作格式错误：\(key)") }
            clips.append(clip)
        }
    }
    return try Array(Set(clips.map { clip in
        guard let file = (clip["playbackFile"] as? String) ?? (clip["file"] as? String) else { throw Failure("素材清单动作缺少文件路径") }
        return "native-hevc/catalog/" + (try relative(file))
    })).sorted()
}
func files(_ manifest: Manifest, _ root: URL, development: Bool) throws -> [String] {
    try (manifest.runtime + [catalogPath] + animationFiles(root) + (development ? manifest.development : [])).map(relative)
}
func check(_ manifest: Manifest, _ root: URL, development: Bool) throws -> [String] {
    var problems = [String]()
    var required = manifest.runtime + [catalogPath] + (development ? manifest.development : [])
    if fm.fileExists(atPath: root.appendingPathComponent(catalogPath).path) {
        do { required += try animationFiles(root) } catch { problems.append("素材清单：\(error)") }
    }
    for path in required {
        let url = root.appendingPathComponent(try relative(path))
        if !fm.fileExists(atPath: url.path) { problems.append("缺少：\(path)"); continue }
        do {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if info.isRegularFile != true || (info.fileSize ?? 0) == 0 { problems.append("空文件或非普通文件：\(path)") }
        } catch { problems.append("无法读取：\(path)（\(error.localizedDescription)）") }
    }
    if development, fm.fileExists(atPath: root.appendingPathComponent("native-hevc/catalog/samples.json").path) {
        do { _ = try json(root.appendingPathComponent("native-hevc/catalog/samples.json")) }
        catch { problems.append("samples.json：\(error.localizedDescription)") }
    }
    guard problems.isEmpty else { throw Failure(problems.joined(separator: "\n")) }
    return try files(manifest, root, development: development)
}
func copy(_ source: URL, _ target: URL) throws {
    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.copyItem(at: source, to: target)
}
// 发布包仅改写来源字段，不改动作参数或本地原件。
func portable(_ value: Any) -> Any {
    if var dict = value as? [String: Any] {
        for (key, item) in dict {
            if key == "sourceFile", let text = item as? String, text.hasPrefix("/"), let range = text.range(of: "/local-assets/") {
                dict[key] = "local-assets/" + text[range.upperBound...]
            } else { dict[key] = portable(item) }
        }
        return dict
    }
    if let array = value as? [Any] { return array.map(portable) }
    return value
}
func run() throws {
    guard args.count >= 2 else { throw Failure("用法：BuildResources <info|check|copy-app|stage|import> <manifest> [参数]") }
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    if args[0] == "info" {
        print(manifest.version); print(manifest.archive); print(manifest.published ? "yes" : "no"); print(manifest.url); print(manifest.bytes)
        return
    }
    if args[0] == "record-size" {
        guard args.count == 3 else { throw Failure("缺少 ZIP 路径") }
        let archive = URL(fileURLWithPath: args[2])
        guard archive.lastPathComponent == manifest.archive, !manifest.published else { throw Failure("仅记录未发布的指定资源包大小") }
        let url = URL(fileURLWithPath: args[1])
        guard var metadata = try json(url) as? [String: Any], let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw Failure("无法读取资源包大小") }
        metadata["bytes"] = size
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
        return
    }
    guard args.count >= 3 else { throw Failure("缺少资源目录") }
    let root = URL(fileURLWithPath: args[2], isDirectory: true)
    if args[0] == "check" {
        let list = try check(manifest, root, development: args.contains("--development"))
        print("资源齐全 · \(list.count) 个文件")
        return
    }
    guard args.count >= 4 else { throw Failure("缺少目标目录") }
    let target = URL(fileURLWithPath: args[3], isDirectory: true)
    switch args[0] {
    case "copy-app", "stage":
        let development = args[0] == "stage"
        let list = try check(manifest, root, development: development)
        for path in list {
            let destination = development ? path : path.replacingOccurrences(of: "native-hevc/catalog/", with: "outputs/白龙桌宠素材/", options: .anchored)
            try copy(root.appendingPathComponent(path), target.appendingPathComponent(destination))
        }
        if development {
            let metadata: [String: Any] = ["version": manifest.version, "runtime": manifest.runtime, "development": manifest.development]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: target.deletingLastPathComponent().appendingPathComponent("RESOURCE-MANIFEST.json"))
            for path in [catalogPath, "native-hevc/catalog/samples.json"] {
                let url = target.appendingPathComponent(path)
                let data = try JSONSerialization.data(withJSONObject: portable(json(url)), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                try data.write(to: url, options: .atomic)
            }
        }
    case "import":
        guard args.count == 5, ["missing", "replace"].contains(args[4]) else { throw Failure("导入模式：missing 或 replace") }
        let list = try check(manifest, root, development: true)
        // 解压目录不接受符号链接，复制范围由受版本控制的清单决定。
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { throw Failure("无法读取解压目录") }
        for case let url as URL in entries {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw Failure("资源包包含符号链接：\(url.lastPathComponent)") }
        }
        let workspace = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/resource-import")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        let staging = workspace.appendingPathComponent("staging-" + UUID().uuidString)
        let backup = workspace.appendingPathComponent("backup-" + UUID().uuidString)
        defer { if fm.fileExists(atPath: staging.path) { do { try fm.removeItem(at: staging) } catch { fputs("清理导入副本失败：\(error)\n", stderr) } } }
        var selected = list
        if args[4] == "missing", fm.fileExists(atPath: target.appendingPathComponent(catalogPath).path) {
            selected = Array(Set(list + (try animationFiles(target)))).sorted()
        }
        var changed = [String]()
        for path in selected {
            let existing = target.appendingPathComponent(path)
            // 不通过已有目录链接覆盖外部文件。
            var ancestor = existing
            while ancestor.path.count >= target.path.count {
                if fm.fileExists(atPath: ancestor.path), try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw Failure("目标包含符号链接：\(ancestor.path)")
                }
                ancestor.deleteLastPathComponent()
            }
            let keep = args[4] == "missing" && fm.fileExists(atPath: existing.path)
            try copy(keep ? existing : root.appendingPathComponent(path), staging.appendingPathComponent(path))
            if !keep { changed.append(path) }
        }
        _ = try check(manifest, staging, development: true)
        var installed = [String]()
        var saved = [String]()
        do {
            for path in changed {
                let destination = target.appendingPathComponent(path)
                if fm.fileExists(atPath: destination.path) {
                    try copy(destination, backup.appendingPathComponent(path))
                    saved.append(path)
                    try fm.removeItem(at: destination)
                }
                try copy(staging.appendingPathComponent(path), destination)
                installed.append(path)
            }
        } catch {
            for path in installed { try fm.removeItem(at: target.appendingPathComponent(path)) }
            for path in saved {
                let destination = target.appendingPathComponent(path)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try copy(backup.appendingPathComponent(path), destination)
            }
            throw error
        }
        if !saved.isEmpty { print("原资源备份：\(backup.path)") }
        print("资源已导入")
    default: throw Failure("未知操作：\(args[0])")
    }
}
do { try run() }
catch { fputs("\(error)\n", stderr); exit(1) }
