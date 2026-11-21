import AppKit

extension NSAttributedString.Key {
    static let fileEditSection = NSAttributedString.Key("BailongFileEditSection")
    static let fileEditDisclosure = NSAttributedString.Key("BailongFileEditDisclosure")
    static let fileEditRow = NSAttributedString.Key("BailongFileEditRow")
}

// 显示层元数据，保留完整列表供展开和搜索；不写入历史或助手正文。
final class FileEditSection:NSObject {
    let id:String, edits:[FileEditSummary], font:NSFont
    init(id:String,edits:[FileEditSummary],font:NSFont) {self.id = id; self.edits = edits; self.font = font}
    override func isEqual(_ object:Any?) -> Bool {
        guard let other = object as? FileEditSection else {return false}
        return id == other.id && edits == other.edits && font == other.font
    }
    override var hash:Int {id.hashValue ^ font.hash}
}

// 气泡与历史共用 TextKit 表格，不增加嵌套滚动视图或独立文件操作路径。
enum FileEditRendering {
    static let previewCount = 3
    static func counts(_ lines:FileEditSummary.Lines,font:NSFont) -> NSAttributedString {
        let value = NSMutableAttributedString(attributedString:count(lines.added,added:true,font:font))
        value.append(NSAttributedString(string:" ",attributes:[.font:NSFont.monospacedSystemFont(ofSize:font.pointSize,weight:.semibold)]))
        value.append(count(lines.removed,added:false,font:font))
        return value
    }
    static func count(_ number:Int,added:Bool,font:NSFont) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize:font.pointSize,weight:.semibold)
        let color = added ? StatusTextColor.green : StatusTextColor.red
        let value = NSMutableAttributedString(attributedString:InlineStatusLayout.centeredSymbol(added ? "+" : "-",font:font,color:color))
        value.append(NSAttributedString(string:String(number),attributes:[.font:font,.foregroundColor:color]))
        return value
    }
    private static func symbol(_ name:String,description:String,font:NSFont,side:CGFloat) -> NSAttributedString? {
        guard let symbol = NSImage(systemSymbolName:name,accessibilityDescription:description)?.withSymbolConfiguration(.init(pointSize:side,weight:.regular)) else {return nil}
        return InlineStatusLayout.imageAttachment(symbol,description:description,font:font,side:side,color:.labelColor)
    }
    static func render(_ edits:[FileEditSummary],font:NSFont,id:String) -> NSAttributedString {
        render(FileEditSection(id:id,edits:edits,font:font),expanded:false)
    }
    static func render(_ section:FileEditSection,expanded:Bool) -> NSAttributedString {
        let edits = section.edits, font = section.font
        let result = NSMutableAttributedString()
        guard !edits.isEmpty else {return result}
        let table = NSTextTable(); table.numberOfColumns = 2; table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.setContentWidth(100,type:.percentageValueType); table.collapsesBorders = true
        let base:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        func counts(_ lines:FileEditSummary.Lines) -> NSAttributedString {
            Self.counts(lines,font:font)
        }
        let total = edits.allSatisfy {$0.lines != nil} ? edits.reduce(FileEditSummary.Lines(added:0,removed:0)) {sum,edit in
            FileEditSummary.Lines(added:sum.added+edit.lines!.added,removed:sum.removed+edit.lines!.removed)
        } : nil
        let countWidth = ceil((edits.compactMap(\.lines)+[total].compactMap {$0}).map {counts($0).size().width}.max() ?? 0)+8
        func cell(_ content:NSAttributedString,row:Int,column:Int) {
            let block = NSTextTableBlock(table:table,startingRow:row,rowSpan:1,startingColumn:column,columnSpan:1)
            if column == 1 {block.setContentWidth(countWidth,type:.absoluteValueType)}
            block.setWidth(5,type:.absoluteValueType,for:.padding)
            // 顶部对齐在 SDK 26/27 中的 Swift 名称不同，原始值均为 0。
            block.verticalAlignment = NSTextBlock.VerticalAlignment(rawValue:0)!
            if row == 1 {
                block.setWidth(0.5,type:.absoluteValueType,for:.border,edge:.minY)
                block.setBorderColor(.separatorColor)
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.textBlocks = [block]
            paragraph.alignment = column == 0 ? .left : .right; paragraph.lineBreakMode = column == 0 ? .byCharWrapping : .byClipping
            paragraph.paragraphSpacing = 0; paragraph.lineSpacing = 2
            let value = NSMutableAttributedString(attributedString:content); value.append(NSAttributedString(string:"\n",attributes:base))
            value.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:value.length)); result.append(value)
        }
        let header = NSMutableAttributedString(string:"已编辑 \(edits.count) 个文件",attributes:[.font:NSFont.systemFont(ofSize:font.pointSize,weight:.semibold),.foregroundColor:NSColor.labelColor])
        if let icon = symbol("doc.badge.plus",description:"文件修改",font:font,side:font.pointSize) {
            header.insert(NSAttributedString(string:"  ",attributes:base),at:0)
            header.insert(icon,at:0)
        }
        cell(header,row:0,column:0)
        cell(total.map(counts) ?? NSAttributedString(string:""),row:0,column:1)
        let visible = expanded ? edits[...] : edits.prefix(previewCount)
        for (index,edit) in visible.enumerated() {
            let start = result.length
            let path = NSMutableAttributedString(string:edit.path,attributes:[.font:font,.foregroundColor:NSColor.secondaryLabelColor])
            let name = (edit.path as NSString).lastPathComponent
            let nameRange = NSRange(location:path.length-(name as NSString).length,length:(name as NSString).length)
            path.addAttribute(.font,value:NSFont.systemFont(ofSize:font.pointSize,weight:.medium),range:nameRange)
            path.addAttribute(.foregroundColor,value:NSColor.labelColor,range:nameRange)
            cell(path,row:index+1,column:0)
            cell(edit.lines.map(counts) ?? NSAttributedString(string:""),row:index+1,column:1)
            result.addAttribute(.fileEditRow,value:index,range:NSRange(location:start,length:result.length-start))
        }
        if edits.count > previewCount {
            let style = NSMutableParagraphStyle(); style.paragraphSpacing = 4
            result.append(NSAttributedString(string:"\u{200B}\n",attributes:[.font:font,.paragraphStyle:style,.fileEditDisclosure:expanded]))
        }
        result.addAttribute(.fileEditSection,value:section,range:NSRange(location:0,length:result.length))
        result.append(NSAttributedString(string:"\n",attributes:base))
        return result
    }
}
