import Foundation

struct WorkspaceDiffReview {
    struct Code {
        let line:WorkspaceDiffPatch.Line, text:String, emphasis:NSRange?
    }
    struct Pair {
        let before:Code?, after:Code?
    }
    enum Row {
        case code(Code)
        case change([Pair])
        case fold(id:Int,count:Int,expanded:Bool)
        case gap(Int)
        case detail(String)
    }
    let rows:[Row]

    init(patch:WorkspaceDiffPatch,expanded:Set<Int>) {
        let source = patch.lines
        var rows = [Row](), index = 0, oldEnd = 0, newEnd = 0
        while index < source.count {
            let line = source[index]
            if let hunk = line.hunk {
                let missing = min(hunk.oldBefore-oldEnd,hunk.newBefore-newEnd)
                if missing > 0 {rows.append(.gap(missing))}
                oldEnd = hunk.oldBefore+hunk.oldCount
                newEnd = hunk.newBefore+hunk.newCount
                index += 1
            } else if line.kind == .context {
                let start = index
                while index < source.count,source[index].kind == .context {index += 1}
                let count = index-start
                if count <= 6 {
                    rows += source[start..<index].map {.code(Self.code($0))}
                } else {
                    let foldStart = start+2, foldEnd = index-2
                    let isExpanded = expanded.contains(start)
                    rows += source[start..<foldStart].map {.code(Self.code($0))}
                    rows.append(.fold(id:start,count:foldEnd-foldStart,expanded:isExpanded))
                    if isExpanded {rows += source[foldStart..<foldEnd].map {.code(Self.code($0))}}
                    rows += source[foldEnd..<index].map {.code(Self.code($0))}
                }
            } else if line.kind == .addition || line.kind == .deletion {
                var missingNewline = false
                func take(_ kind:WorkspaceDiffPatch.Kind) -> [WorkspaceDiffPatch.Line] {
                    var lines = [WorkspaceDiffPatch.Line]()
                    while index < source.count {
                        if source[index].kind == kind {lines.append(source[index])}
                        else if source[index].text.hasPrefix("\\ No newline") {missingNewline = true}
                        else {break}
                        index += 1
                    }
                    return lines
                }
                let removed = take(.deletion), added = take(.addition)
                rows.append(.change(Self.align(removed,added)))
                if missingNewline {rows.append(.detail(L10n.text(.workspace,"workspaceDiff.noNewline")))}
            } else {
                if let detail = Self.detail(line.text) {rows.append(.detail(detail))}
                index += 1
            }
        }
        self.rows = rows
    }

    private static func code(_ line:WorkspaceDiffPatch.Line,emphasis:NSRange? = nil) -> Code {
        Code(line:line,text:String(line.text.dropFirst()),emphasis:emphasis)
    }

    private static func match(_ left:String,_ right:String) -> (score:Int,before:NSRange,after:NSRange)? {
        let before = left.dropFirst(), after = right.dropFirst()
        guard before.utf16.count <= 2048,after.utf16.count <= 2048 else {return nil}
        let prefix = zip(before,after).prefix(while:{$0.0 == $0.1}).count
        let lhs = before.dropFirst(prefix), rhs = after.dropFirst(prefix)
        let suffix = zip(lhs.reversed(),rhs.reversed()).prefix(while:{$0.0 == $0.1}).count
        let shared = before.prefix(prefix).filter {!$0.isWhitespace}.count+lhs.suffix(suffix).filter {!$0.isWhitespace}.count
        guard shared >= 2 || prefix+suffix >= 1 && min(lhs.count,rhs.count) == suffix else {return nil}
        let start = before.prefix(prefix).utf16.count
        return (max(1,shared),NSRange(location:start,length:lhs.dropLast(suffix).utf16.count),
                NSRange(location:start,length:rhs.dropLast(suffix).utf16.count))
    }

    // Preserve source order on both sides, preferring pairs with shared code over insertions above a replacement.
    private static func align(_ before:[WorkspaceDiffPatch.Line],_ after:[WorkspaceDiffPatch.Line]) -> [Pair] {
        let columns = after.count+1
        var anchors = [(Int,Int)]()
        if !before.isEmpty,!after.isEmpty,before.count <= 4096/after.count {
            var scores = [Int](repeating:0,count:(before.count+1)*columns)
            var paired = [Bool](repeating:false,count:scores.count)
            for left in before.indices.reversed() {
                for right in after.indices.reversed() {
                    let cell = left*columns+right
                    let skip = max(scores[cell+columns],scores[cell+1])
                    let matchScore = match(before[left].text,after[right].text)?.score ?? 0
                    let together = scores[cell+columns+1]+matchScore
                    paired[cell] = matchScore > 0 && together >= skip
                    scores[cell] = paired[cell] ? together : skip
                }
            }
            var left = 0, right = 0
            while left < before.count,right < after.count {
                let cell = left*columns+right
                if paired[cell] {anchors.append((left,right)); left += 1; right += 1}
                else if scores[cell+columns] > scores[cell+1] {left += 1}
                else {right += 1}
            }
        }
        var result = [Pair](), left = 0, right = 0
        func append(through endLeft:Int,_ endRight:Int) {
            while left < endLeft || right < endRight {
                let old = left < endLeft ? before[left] : nil
                let new = right < endRight ? after[right] : nil
                let emphasis = old.flatMap {old in new.flatMap {match(old.text,$0.text)}}
                result.append(Pair(before:old.map {code($0,emphasis:emphasis?.before)},
                                   after:new.map {code($0,emphasis:emphasis?.after)}))
                if old != nil {left += 1}
                if new != nil {right += 1}
            }
        }
        for (anchorLeft,anchorRight) in anchors {
            append(through:anchorLeft,anchorRight)
            append(through:anchorLeft+1,anchorRight+1)
        }
        append(through:before.count,after.count)
        return result
    }

    private static func detail(_ text:String) -> String? {
        if text.hasPrefix("\\ No newline") {return L10n.text(.workspace,"workspaceDiff.noNewline")}
        let keys = [("rename from ","renameFrom"),("rename to ","renameTo"),
                    ("copy from ","copyFrom"),("copy to ","copyTo"),
                    ("old mode ","oldMode"),("new mode ","newMode")]
        for (prefix,key) in keys where text.hasPrefix(prefix) {
            return L10n.format(.workspace,"workspaceDiff."+key,String(text.dropFirst(prefix.count)))
        }
        if text.hasPrefix("new file mode ") {return L10n.text(.workspace,"workspaceDiff.fileAdded")}
        if text.hasPrefix("deleted file mode ") {return L10n.text(.workspace,"workspaceDiff.fileDeleted")}
        return nil
    }
}
