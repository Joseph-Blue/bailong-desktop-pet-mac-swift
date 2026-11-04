import Foundation

// Codex 产物引用只在显示层转换为普通文件链接，继续走既有的点击／访达路径。
enum CodexFileCitation {
    static let marker = ":codex-file-citation{"
    private static let directive = try! NSRegularExpression(pattern:#"(?<![:\\]):codex-file-citation\{((?:\s*[A-Za-z_][A-Za-z_0-9]*\s*=\s*"(?:\\.|[^"\\])*"\s*)+)\}"#)
    private static let attribute = try! NSRegularExpression(pattern:#"([A-Za-z_][A-Za-z_0-9]*)\s*=\s*("(?:\\.|[^"\\])*")"#)

    static func markdown(_ source:String,parsed:AttributedString) -> String {
        let text = source as NSString
        let matches = directive.matches(in:source,range:NSRange(location:0,length:text.length))
        guard !matches.isEmpty else {return source}
        // 用 Foundation 的源码位置识别代码与已有链接，不另写一套 Markdown 围栏解析。
        let literals:[NSRange] = parsed.runs.compactMap {run in
            let codeBlock = run.presentationIntent?.components.contains {
                if case .codeBlock = $0.kind {return true}; return false
            } == true
            guard codeBlock || run.inlinePresentationIntent?.contains(.code) == true || run.link != nil || run.imageURL != nil,
                  let position = run.markdownSourcePosition else {return nil}
            return NSRange(position,in:source)
        }
        let result = NSMutableString(string:source)
        for match in matches.reversed() {
            guard !literals.contains(where:{NSIntersectionRange($0,match.range).length > 0}) else {continue}
            let fields = attribute.matches(in:source,range:match.range(at:1))
            let paths = fields.filter {text.substring(with:$0.range(at:1)) == "path"}
            guard paths.count == 1,
                  let path = try? JSONDecoder().decode(String.self,from:Data(text.substring(with:paths[0].range(at:2)).utf8)),
                  path.hasPrefix("/"),!path.hasSuffix("/") else {continue}
            guard let file = MessageFileLink.url(forPath:path) else {continue}
            let name = file.lastPathComponent
            var label = ""
            for character in name {
                if "\\`*_{}[]<>|".contains(character) {label.append("\\")}
                label.append(character.isWhitespace ? " " : character)
            }
            result.replaceCharacters(in:match.range,with:"[\(label)](<\(file.absoluteString)>)")
        }
        return result as String
    }
}
