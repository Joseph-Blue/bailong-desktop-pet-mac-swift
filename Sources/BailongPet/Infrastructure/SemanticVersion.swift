import Foundation

/// SemVer precedence; build metadata does not affect comparison.
struct SemanticVersion: Comparable {
    let core: [String]
    let prerelease: [String]

    init?(_ text: String) {
        let pattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#
        guard text.range(of:pattern,options:.regularExpression) == text.startIndex..<text.endIndex else {return nil}
        let precedence = text.split(separator:"+",maxSplits:1)[0]
        let pieces = precedence.split(separator:"-",maxSplits:1)
        core = pieces[0].split(separator:".").map(String.init)
        prerelease = pieces.count == 2 ? pieces[1].split(separator:".").map(String.init) : []
        guard !prerelease.contains(where:{Self.numeric($0) && $0.count > 1 && $0.first == "0"}) else {return nil}
    }

    static func releaseTag(_ tag: String) -> SemanticVersion? {
        for prefix in ["白龙娘桌宠v","v"] where tag.hasPrefix(prefix) {
            return SemanticVersion(String(tag.dropFirst(prefix.count)))
        }
        return SemanticVersion(tag)
    }
    private static func numeric(_ value: String) -> Bool {value.utf8.allSatisfy{(48...57).contains($0)}}
    private static func numberLess(_ a: String,_ b: String) -> Bool {
        a.count == b.count ? a < b : a.count < b.count
    }
    static func == (a: Self,b: Self) -> Bool {a.core == b.core && a.prerelease == b.prerelease}
    static func < (a: Self,b: Self) -> Bool {
        for (left,right) in zip(a.core,b.core) where left != right {return numberLess(left,right)}
        if a.prerelease.isEmpty {return false}
        if b.prerelease.isEmpty {return true}
        for (left,right) in zip(a.prerelease,b.prerelease) where left != right {
            let ln = numeric(left), rn = numeric(right)
            if ln && rn {return numberLess(left,right)}
            if ln != rn {return ln}
            return left < right
        }
        return a.prerelease.count < b.prerelease.count
    }
}
