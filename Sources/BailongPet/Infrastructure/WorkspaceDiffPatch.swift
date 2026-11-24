import Foundation

struct WorkspaceDiffPatch {
    static let byteLimit = 1024 * 1024
    enum Kind {case context, addition, deletion, hunk, metadata}
    struct Hunk {
        let oldBefore:Int, newBefore:Int, oldCount:Int, newCount:Int
    }
    struct Line {
        let text:String, kind:Kind
        var old:Int? = nil, new:Int? = nil
        var hunk:Hunk? = nil
    }
    let text:String, lines:[Line], binary:Bool

    init(_ text:String) throws {
        let lineLimit = 20_000
        let newlineLimit = lineLimit+(text.utf8.last == 10 ? 0 : -1)
        guard text.utf8.lazy.filter({$0 == 10}).prefix(newlineLimit+1).count <= newlineLimit else {
            throw GitWorkspaceFailure(L10n.text(.workspace,"workspaceDiff.tooLarge"))
        }
        var source = text.components(separatedBy:"\n")
        if source.last == "" {source.removeLast()}
        self.text = text
        var old = 0, new = 0, oldLeft = 0, newLeft = 0, binary = false
        lines = source.map {line in
            if let (before,after) = Self.hunk(line) {
                (old,oldLeft) = before; (new,newLeft) = after
                return Line(text:line,kind:.hunk,hunk:Hunk(oldBefore:oldLeft == 0 ? old : max(0,old-1),
                    newBefore:newLeft == 0 ? new : max(0,new-1),oldCount:oldLeft,newCount:newLeft))
            }
            if oldLeft > 0,line.hasPrefix("-") {
                defer {old += 1; oldLeft -= 1}
                return Line(text:line,kind:.deletion,old:old)
            }
            if newLeft > 0,line.hasPrefix("+") {
                defer {new += 1; newLeft -= 1}
                return Line(text:line,kind:.addition,new:new)
            }
            if oldLeft > 0,newLeft > 0,line.hasPrefix(" ") {
                defer {old += 1; new += 1; oldLeft -= 1; newLeft -= 1}
                return Line(text:line,kind:.context,old:old,new:new)
            }
            if line.hasPrefix("Binary files "),line.hasSuffix(" differ") {binary = true}
            return Line(text:line,kind:.metadata)
        }
        self.binary = binary
    }

    init?(edit:FileEditSummary.Patch,path:String,directory:URL?) throws {
        guard let text = edit.text else {return nil}
        func relative(_ path:String) -> String {
            guard let directory else {return path}
            let prefix = directory.standardizedFileURL.path.hasSuffix("/") ? directory.standardizedFileURL.path : directory.standardizedFileURL.path+"/"
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }
        let before = relative(edit.originalPath ?? path), after = relative(path)
        let oldPath = Self.quote("a/"+before), newPath = Self.quote("b/"+after)
        let rename = edit.originalPath != nil ? "rename from "+Self.quote(before)+"\nrename to "+Self.quote(after)+"\n" : ""
        let header = "diff --git \(oldPath) \(newPath)\n"+rename
        switch edit.kind {
        case "add","delete":
            let add = edit.kind == "add"
            let files = "--- \(add ? "/dev/null" : oldPath)\n+++ \(add ? newPath : "/dev/null")\n"
            guard !text.isEmpty else {try self.init(header+files); return}
            var rows = text.components(separatedBy:"\n")
            let endsWithNewline = text.utf8.last == 10
            if endsWithNewline {rows.removeLast()}
            let count = rows.count
            let hunk = add ? "@@ -0,0 +1,\(count) @@\n" : "@@ -1,\(count) +0,0 @@\n"
            let body = rows.map {(add ? "+" : "-")+$0+"\n"}.joined()
            let marker = endsWithNewline ? "" : "\\ No newline at end of file\n"
            try self.init(header+files+hunk+body+marker)
        default:
            if text.hasPrefix("@@ ") {
                try self.init(header+"--- \(oldPath)\n+++ \(newPath)\n"+text+(text.utf8.last == 10 ? "" : "\n"))
            } else {
                try self.init(text.isEmpty && !rename.isEmpty ? header : text)
            }
        }
    }

    private static func hunk(_ line:String) -> ((Int,Int),(Int,Int))? {
        guard line.hasPrefix("@@ ") else {return nil}
        let fields = line.split(separator:" ",maxSplits:4)
        guard fields.count >= 4,fields[1].hasPrefix("-"),fields[2].hasPrefix("+") else {return nil}
        func range(_ value:Substring) -> (Int,Int)? {
            let parts = value.dropFirst().split(separator:",",maxSplits:1)
            guard let first = parts.first,let start = Int(first),start >= 0,
                  let count = parts.count == 1 ? 1 : Int(parts[1]),count >= 0,start <= Int.max-count else {return nil}
            return (start,count)
        }
        guard let before = range(fields[1]),let after = range(fields[2]) else {return nil}
        return (before,after)
    }

    private static func quote(_ path:String) -> String {
        let escaped = path.utf8.map {byte -> String in
            switch byte {
            case 34:return "\\\""
            case 92:return "\\\\"
            case 33...126:return String(UnicodeScalar(byte))
            case 32:return " "
            default:return "\\"+String((byte >> 6) & 7)+String((byte >> 3) & 7)+String(byte & 7)
            }
        }.joined()
        return escaped == path && !path.contains(" ") ? path : "\""+escaped+"\""
    }
}
