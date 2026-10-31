import AppKit

// Foundation 负责 Markdown 解析，AppKit 负责文字显示；原始历史仍保存原文。
enum MarkdownText {
    private struct TableContent {
        let columns: [PresentationIntent.TableColumn]
        var rows = [Int]()
        var headers = Set<Int>()
        var cells = [Int:[Int:NSMutableAttributedString]]()
    }
    private struct Fragment {
        let block: Int?
        let table: Int?
        let text: NSAttributedString
    }
    static func render(_ source: String, font: NSFont = .systemFont(ofSize:14), color: NSColor = .labelColor,
                       lineSpacing: CGFloat = 4, paragraphSpacing: CGFloat = 12) -> NSAttributedString {
        // 生成中的 Markdown 可能尚未闭合，此时保留可解析内容或原文。
        let parsed = (try? AttributedString(markdown:source,options:.init(interpretedSyntax:.full,failurePolicy:.returnPartiallyParsedIfPossible))) ?? AttributedString(source)
        var fragments = [Fragment](), tables = [Int:TableContent]()
        var previousItem: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            var level: Int?, ordinal: Int?, itemID: Int?, tableRow: Int?, tableID: Int?, column: Int?
            var listDepth = 0, ordered = false, codeBlock = false, quote = false, header = false
            for component in components {
                switch component.kind {
                case .header(let value): level = value
                case .listItem(let value): if itemID == nil {ordinal = value; itemID = component.identity}
                case .orderedList: if listDepth == 0 {ordered = true}; listDepth += 1
                case .unorderedList: listDepth += 1
                case .codeBlock: codeBlock = true
                case .blockQuote: quote = true
                case .table(let columns):
                    tableID = component.identity
                    if tables[component.identity] == nil {tables[component.identity] = TableContent(columns:columns)}
                case .tableRow: tableRow = component.identity
                case .tableHeaderRow: tableRow = component.identity; header = true
                case .tableCell(let value): column = value
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
            let inline = run.inlinePresentationIntent ?? []
            let code = codeBlock || inline.contains(.code)
            var runFont = code ? NSFont.monospacedSystemFont(ofSize:max(10,font.pointSize-1),weight:.regular) : font
            if let level {runFont = .systemFont(ofSize:font.pointSize+CGFloat(max(1,7-level)),weight:.semibold)}
            if header || inline.contains(.stronglyEmphasized) {runFont = NSFontManager.shared.convert(runFont,toHaveTrait:.boldFontMask)}
            if inline.contains(.emphasized) {runFont = NSFontManager.shared.convert(runFont,toHaveTrait:.italicFontMask)}
            var attributes: [NSAttributedString.Key:Any] = [.font:runFont,.foregroundColor:quote ? NSColor.secondaryLabelColor : color,.paragraphStyle:paragraph]
            if code {attributes[.backgroundColor] = NSColor.quaternaryLabelColor}
            if inline.contains(.strikethrough) {attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue}
            if let link = run.link {attributes[.link] = link; attributes[.foregroundColor] = AppAccent.color}
            var value = String(parsed[run.range].characters)
            if let image = run.imageURL {
                // 保留图片入口，不再丢弃 Markdown 图片地址；不把远程图片下载到本机。
                attributes[.link] = image; attributes[.foregroundColor] = AppAccent.color
                let description = value.replacingOccurrences(of:"\u{FFFC}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
                let name = image.lastPathComponent.isEmpty ? "查看图片" : image.lastPathComponent
                value = "图片：" + (description.isEmpty ? name : description)
            }
            let text = NSAttributedString(string:prefix+value,attributes:attributes)
            fragments.append(Fragment(block:block,table:tableID,text:text))
            if let id = tableID, let row = tableRow, let column, var table = tables[id] {
                if table.cells[row] == nil {table.rows.append(row); table.cells[row] = [:]}
                if header {table.headers.insert(row)}
                let cell = table.cells[row]?[column] ?? NSMutableAttributedString(string:"")
                cell.append(text); table.cells[row]?[column] = cell; tables[id] = table
            }
            previousItem = itemID
        }
        let result = NSMutableAttributedString()
        let plain = NSMutableParagraphStyle(); plain.lineSpacing = lineSpacing; plain.paragraphSpacing = paragraphSpacing
        let base: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color,.paragraphStyle:plain]
        var previousBlock: Int?, emittedTables = Set<Int>()
        for fragment in fragments {
            if let id = fragment.table, let table = tables[id] {
                guard emittedTables.insert(id).inserted else {continue}
                if result.length > 0 && !result.string.hasSuffix("\n") {result.append(NSAttributedString(string:"\n",attributes:base))}
                result.append(renderTable(table,font:font,color:color,lineSpacing:lineSpacing))
                // 单元格必须以自己的段落样式结束，随后恢复普通段落，避免后文落入最后一格。
                result.append(NSAttributedString(string:"\n",attributes:base))
                previousBlock = nil
            } else {
                if fragment.block != previousBlock && result.length > 0 && !result.string.hasSuffix("\n") {
                    let attributes = result.attributes(at:result.length-1,effectiveRange:nil)
                    result.append(NSAttributedString(string:"\n",attributes:attributes))
                }
                result.append(fragment.text); previousBlock = fragment.block
            }
        }
        return result
    }

    private static func renderTable(_ content: TableContent, font: NSFont, color: NSColor, lineSpacing: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        guard !content.columns.isEmpty else {return result}
        let table = NSTextTable()
        table.numberOfColumns = content.columns.count; table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true; table.hidesEmptyCells = false
        table.setContentWidth(100,type:.percentageValueType)
        for (rowIndex,rowID) in content.rows.enumerated() {
            for (columnIndex,column) in content.columns.enumerated() {
                let block = NSTextTableBlock(table:table,startingRow:rowIndex,rowSpan:1,startingColumn:columnIndex,columnSpan:1)
                block.setContentWidth(100/CGFloat(content.columns.count),type:.percentageValueType)
                block.setWidth(6,type:.absoluteValueType,for:.padding)
                block.setWidth(0.5,type:.absoluteValueType,for:.border)
                block.setBorderColor(.separatorColor)
                block.verticalAlignment = .top
                if content.headers.contains(rowID) {block.backgroundColor = .quaternaryLabelColor}
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]; paragraph.lineSpacing = lineSpacing; paragraph.paragraphSpacing = 0
                paragraph.lineBreakMode = .byWordWrapping
                switch column.alignment {
                case .left: paragraph.alignment = .left
                case .center: paragraph.alignment = .center
                case .right: paragraph.alignment = .right
                @unknown default: paragraph.alignment = .left
                }
                let cell = NSMutableAttributedString(string:"")
                if let value = content.cells[rowID]?[columnIndex] {cell.append(value)}
                cell.append(NSAttributedString(string:"\n",attributes:[.font:font,.foregroundColor:color]))
                cell.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:cell.length))
                result.append(cell)
            }
        }
        return result
    }
}
