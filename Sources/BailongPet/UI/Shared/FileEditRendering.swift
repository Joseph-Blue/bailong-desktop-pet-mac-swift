import AppKit

extension NSAttributedString.Key {
    static let fileEditSection = NSAttributedString.Key("BailongFileEditSection")
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
    static let disclosureLink = URL(string:"bailong-file-edits:toggle")!
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
            let text = NSMutableAttributedString(string:"+\(lines.added)",attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:font.pointSize,weight:.regular),.foregroundColor:NSColor.systemGreen])
            text.append(NSAttributedString(string:"  −\(lines.removed)",attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:font.pointSize,weight:.regular),.foregroundColor:NSColor.systemRed]))
            return text
        }
        let total = edits.allSatisfy {$0.lines != nil} ? edits.reduce(FileEditSummary.Lines(added:0,removed:0)) {sum,edit in
            FileEditSummary.Lines(added:sum.added+edit.lines!.added,removed:sum.removed+edit.lines!.removed)
        } : nil
        // 首行总计和文件计数共用右列，以两者最大文字宽度分配空间。
        let countWidth = ceil((edits.compactMap(\.lines)+[total].compactMap {$0}).map {counts($0).size().width}.max() ?? 0)+8
        func cell(_ content:NSAttributedString,row:Int,column:Int) {
            let block = NSTextTableBlock(table:table,startingRow:row,rowSpan:1,startingColumn:column,columnSpan:1)
            if column == 1 {block.setContentWidth(countWidth,type:.absoluteValueType)}
            block.setWidth(5,type:.absoluteValueType,for:.padding); block.verticalAlignment = .top
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
        func paragraph(_ content:NSAttributedString) {
            let style = NSMutableParagraphStyle(); style.lineSpacing = 4; style.paragraphSpacing = 8
            let value = NSMutableAttributedString(attributedString:content)
            value.append(NSAttributedString(string:"\n",attributes:base))
            value.addAttribute(.paragraphStyle,value:style,range:NSRange(location:0,length:value.length))
            result.append(value)
        }
        let header = NSMutableAttributedString(string:"已编辑 \(edits.count) 个文件",attributes:[.font:NSFont.systemFont(ofSize:font.pointSize,weight:.semibold),.foregroundColor:NSColor.labelColor])
        if let image = NSImage(systemSymbolName:"doc.badge.plus",accessibilityDescription:"文件修改") {
            let attachment = NSTextAttachment(); attachment.image = image
            attachment.bounds = NSRect(x:0,y:(font.capHeight-font.pointSize)/2,width:font.pointSize,height:font.pointSize)
            header.insert(NSAttributedString(string:"  ",attributes:base),at:0)
            header.insert(NSAttributedString(attachment:attachment),at:0)
        }
        cell(header,row:0,column:0)
        cell(total.map(counts) ?? NSAttributedString(string:""),row:0,column:1)
        let visible = expanded ? edits[...] : edits.prefix(previewCount)
        for (index,edit) in visible.enumerated() {
            let path = NSMutableAttributedString(string:edit.path,attributes:[.font:font,.foregroundColor:NSColor.secondaryLabelColor])
            let name = (edit.path as NSString).lastPathComponent
            let nameRange = NSRange(location:path.length-(name as NSString).length,length:(name as NSString).length)
            path.addAttribute(.font,value:NSFont.systemFont(ofSize:font.pointSize,weight:.medium),range:nameRange)
            path.addAttribute(.foregroundColor,value:NSColor.labelColor,range:nameRange)
            if let link = MessageFileLink.url(forPath:edit.path) {path.addAttributes([.link:link,.cursor:NSCursor.pointingHand],range:NSRange(location:0,length:path.length))}
            cell(path,row:index+1,column:0)
            cell(edit.lines.map(counts) ?? NSAttributedString(string:""),row:index+1,column:1)
        }
        if edits.count > previewCount {
            let label = expanded ? "收起文件列表  ⌃" : "再显示 \(edits.count-previewCount) 个文件  ⌄"
            let attributes:[NSAttributedString.Key:Any] = [.link:disclosureLink,.cursor:NSCursor.pointingHand,.foregroundColor:NSColor.labelColor,.font:font]
            paragraph(NSAttributedString(string:label,attributes:attributes))
        }
        result.addAttribute(.fileEditSection,value:section,range:NSRange(location:0,length:result.length))
        result.append(NSAttributedString(string:"\n",attributes:base))
        return result
    }
}
