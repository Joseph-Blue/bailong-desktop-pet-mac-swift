import Foundation

struct FileEditSummary:Codable,Equatable {
    struct Patch:Codable,Equatable,Hashable {
        let kind:String?, originalPath:String?
        var text:String?
        let exceedsLimit:Bool
    }
    static let patchBudget = 512 * 1024
    struct Lines:Codable,Equatable {
        var added:Int, removed:Int
    }
    let path:String
    var lines:Lines?
    var patches:[Patch]? = nil
    var patchBytes:Int {patches?.reduce(0) {$0+($1.text?.utf8.count ?? 0)} ?? 0}
    var cost:Int {path.utf8.count+patchBytes+(patches?.reduce(0) {$0+($1.originalPath?.utf8.count ?? 0)+32} ?? 0)}
    var signature:[String] {[path,lines.map {String($0.added)} ?? "",lines.map {String($0.removed)} ?? "",String(patches.hashValue)]}

    // 仅统计 Codex 已完成的 fileChange，不从命令输出或助手叙述推测文件修改。
    static func read(_ item:[String:Any],patchBudget:Int = Self.patchBudget) -> [Self] {
        guard item["type"] as? String == "fileChange",item["status"] as? String == "completed" else {return []}
        var remaining = patchBudget
        return (item["changes"] as? [[String:Any]] ?? []).compactMap {change in
            guard let path = change["path"] as? String,!path.isEmpty else {return nil}
            let kind = change["kind"] as? [String:Any] ?? [:]
            let destination = kind["move_path"] as? String ?? path
            let type = kind["type"] as? String, diff = change["diff"] as? String
            let bytes = diff?.utf8.count ?? 0
            let exceedsLimit = bytes > min(remaining,256 * 1024)
            if !exceedsLimit {remaining -= bytes}
            let patch = Patch(kind:type,originalPath:destination == path ? nil : path,text:exceedsLimit ? nil : diff,exceedsLimit:exceedsLimit)
            return Self(path:destination,lines:diff.flatMap {count($0,kind:type)},patches:[patch])
        }
    }
    static func merged(_ edits:[Self]) -> [Self] {
        var result = [Self](), positions = [String:Int]()
        for edit in edits {
            if let index = positions[edit.path] {
                if let a = result[index].lines,let b = edit.lines {result[index].lines = Lines(added:a.added+b.added,removed:a.removed+b.removed)}
                else {result[index].lines = nil}
                if let patches = edit.patches {
                    if result[index].patches == nil {result[index].patches = patches}
                    else {result[index].patches?.append(contentsOf:patches)}
                }
            } else {positions[edit.path] = result.count; result.append(edit)}
        }
        return result
    }
    private static func count(_ diff:String,kind:String?) -> Lines? {
        var rows = diff.components(separatedBy:"\n")
        if rows.last == "" {rows.removeLast()}
        if kind == "add" {return Lines(added:rows.count,removed:0)}
        if kind == "delete" {return Lines(added:0,removed:rows.count)}
        guard kind == "update" else {return nil}
        var inHunk = false, result = Lines(added:0,removed:0)
        for row in rows {
            if row.hasPrefix("@@ ") {inHunk = true; continue}
            guard inHunk else {continue}
            if row.hasPrefix("+") {result.added += 1}
            else if row.hasPrefix("-") {result.removed += 1}
        }
        return inHunk || diff.isEmpty ? result : nil
    }
}
