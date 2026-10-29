import AppKit

// Foundation 负责 Markdown 解析，AppKit 负责文字显示；原始历史仍保存原文。
enum MarkdownText {
    static func render(_ source: String, font: NSFont = .systemFont(ofSize:14), color: NSColor = .labelColor,
                       lineSpacing: CGFloat = 4, paragraphSpacing: CGFloat = 12) -> NSAttributedString {
        // 生成中的 Markdown 可能尚未闭合，此时保留可解析内容或原文。
        let parsed = (try? AttributedString(markdown:source,options:.init(interpretedSyntax:.full,failurePolicy:.returnPartiallyParsedIfPossible))) ?? AttributedString(source)
        let result = NSMutableAttributedString()
        var previousBlock: Int?, previousItem: Int?, previousTableRow: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            var level: Int?, ordinal: Int?, itemID: Int?, tableRow: Int?
            var listDepth = 0, ordered = false, codeBlock = false, quote = false, tableCell = false
            for component in components {
                switch component.kind {
                case .header(let value): level = value
                case .listItem(let value): if itemID == nil {ordinal = value; itemID = component.identity}
                case .orderedList: if listDepth == 0 {ordered = true}; listDepth += 1
                case .unorderedList: listDepth += 1
                case .codeBlock: codeBlock = true
                case .blockQuote: quote = true
                case .tableRow, .tableHeaderRow: tableRow = component.identity
                case .tableCell: tableCell = true
                default: break
                }
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = lineSpacing; paragraph.paragraphSpacing = paragraphSpacing
            var prefix = ""
            if itemID != nil {
                paragraph.firstLineHeadIndent = CGFloat(max(0,listDepth-1))*20
                paragraph.headIndent = paragraph.firstLineHeadIndent+24
                paragraph.tabStops = [NSTextTab(textAlignment:.left,location:paragraph.headIndent)]
                if itemID != previousItem {prefix = ordered ? "\(ordinal ?? 1).\t" : "•\t"}
            } else if quote {paragraph.headIndent = 12; paragraph.firstLineHeadIndent = 12}
            if tableCell {paragraph.defaultTabInterval = 140}
            let inline = run.inlinePresentationIntent ?? []
            let code = codeBlock || inline.contains(.code)
            var runFont = code ? NSFont.monospacedSystemFont(ofSize:max(10,font.pointSize-1),weight:.regular) : font
            if let level {runFont = .systemFont(ofSize:font.pointSize+CGFloat(max(1,7-level)),weight:.semibold)}
            if inline.contains(.stronglyEmphasized) {runFont = NSFontManager.shared.convert(runFont,toHaveTrait:.boldFontMask)}
            if inline.contains(.emphasized) {runFont = NSFontManager.shared.convert(runFont,toHaveTrait:.italicFontMask)}
            var attributes: [NSAttributedString.Key:Any] = [.font:runFont,.foregroundColor:quote ? NSColor.secondaryLabelColor : color,.paragraphStyle:paragraph]
            if code {attributes[.backgroundColor] = NSColor.quaternaryLabelColor}
            if inline.contains(.strikethrough) {attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue}
            if let link = run.link {attributes[.link] = link; attributes[.foregroundColor] = AppAccent.color}
            if block != previousBlock && result.length > 0 {
                let separator = tableCell && tableRow == previousTableRow ? "\t" : result.string.hasSuffix("\n") ? "" : "\n"
                result.append(NSAttributedString(string:separator,attributes:attributes))
            }
            result.append(NSAttributedString(string:prefix+String(parsed[run.range].characters),attributes:attributes))
            previousBlock = block; previousItem = itemID; previousTableRow = tableRow
        }
        return result
    }
}
