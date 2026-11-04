import AppKit

// 每个正文视图拥有自己的展开状态。渲染器只输出快照，会话层不持有 UI 状态。
final class FileEditPresentation {
    private var source = NSAttributedString()
    private var expanded = Set<String>()

    func content(_ value:NSAttributedString) -> NSAttributedString {
        source = value
        let ids = Set(sections.map { $0.section.id })
        expanded.formIntersection(ids)
        return projected()
    }
    func toggle(_ id:String) -> NSAttributedString {
        if !expanded.insert(id).inserted {expanded.remove(id)}
        return projected()
    }
    func revealMatches(_ query:String) -> NSAttributedString? {
        guard !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return nil}
        var changed = false
        for entry in sections where !expanded.contains(entry.section.id) {
            if entry.section.edits.dropFirst(FileEditRendering.previewCount).contains(where:{!HistorySearch.ranges(in:$0.path,query:query).isEmpty}) {
                expanded.insert(entry.section.id); changed = true
            }
        }
        return changed ? projected() : nil
    }
    private var sections:[(section:FileEditSection,range:NSRange)] {
        var result = [(section:FileEditSection,range:NSRange)]()
        source.enumerateAttribute(.fileEditSection,in:NSRange(location:0,length:source.length)) {value,range,_ in
            if let section = value as? FileEditSection {result.append((section,range))}
        }
        return result
    }
    private func projected() -> NSAttributedString {
        guard !expanded.isEmpty else {return source}
        let result = NSMutableAttributedString(attributedString:source)
        for entry in sections.reversed() where expanded.contains(entry.section.id) {
            // 原快照保留区域外的分隔换行；替换时只取带 section 属性的部分。
            let full = FileEditRendering.render(entry.section,expanded:true)
            result.replaceCharacters(in:entry.range,with:full.attributedSubstring(from:NSRange(location:0,length:full.length-1)))
        }
        return result
    }
}
