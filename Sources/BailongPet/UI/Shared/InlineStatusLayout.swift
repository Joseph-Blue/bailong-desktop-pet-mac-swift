import AppKit
import CoreText

// 文字以原生第一行基线对齐；图标以相邻文字的大写字高中心对齐。
enum InlineStatusLayout {
    static let brailleFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private struct FontKey:Hashable {
        let name:String
        let size:CGFloat
    }
    private struct BrailleStyleKey:Hashable {
        let font:FontKey
        let colorID:ObjectIdentifier
    }
    private struct BrailleStyleEntry {
        let attributes:[NSAttributedString.Key:Any]
        let prototype:NSAttributedString
    }
    private static var brailleOffsets = [FontKey:CGFloat]()
    private static var brailleOffsetOrder = [FontKey]()
    private static var brailleStyles = [BrailleStyleKey:BrailleStyleEntry]()
    private static var brailleStyleOrder = [BrailleStyleKey]()

    private static func brailleBaselineOffset(for font:NSFont) -> CGFloat {
        let key = FontKey(name:font.fontName,size:font.pointSize)
        if let cached = brailleOffsets[key] {return cached}
        // 用完整盲文单元测量，所有动画帧保持同一中心，避免随亮点上下跳动。
        let cell = CTLineCreateWithAttributedString(NSAttributedString(string:"⣿",attributes:[.font:font]))
        let bounds = CTLineGetBoundsWithOptions(cell,.useGlyphPathBounds)
        let offset = font.capHeight/2-bounds.midY
        if brailleOffsetOrder.count >= 16,let oldest = brailleOffsetOrder.first {
            brailleOffsetOrder.removeFirst(); brailleOffsets.removeValue(forKey:oldest)
        }
        brailleOffsetOrder.append(key); brailleOffsets[key] = offset
        return offset
    }

    static func tabbedRows(_ rows:[[NSAttributedString]],font:NSFont,columnGap:CGFloat = 10,paragraphSpacing:CGFloat = 0) -> NSAttributedString {
        var columnWidths = [CGFloat]()
        for row in rows {
            for (index,cell) in row.dropLast().enumerated() {
                let width = cell.size().width
                if index == columnWidths.count {columnWidths.append(width)}
                else {columnWidths[index] = max(columnWidths[index],width)}
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping; paragraph.paragraphSpacing = paragraphSpacing
        var position:CGFloat = 0
        paragraph.tabStops = columnWidths.map {width in
            position += ceil(width)+columnGap
            return NSTextTab(textAlignment:.left,location:position)
        }
        let result = NSMutableAttributedString()
        for (rowIndex,row) in rows.enumerated() {
            if rowIndex > 0 {result.append(NSAttributedString(string:"\n",attributes:[.font:font]))}
            for (column,cell) in row.enumerated() {
                if column > 0 {result.append(NSAttributedString(string:"\t",attributes:[.font:font]))}
                result.append(cell)
            }
        }
        result.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:result.length))
        return result
    }

    static func centeredSymbol(_ symbol:String,font:NSFont,color:NSColor) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string:symbol,attributes:attributes))
        let bounds = CTLineGetBoundsWithOptions(line,.useGlyphPathBounds)
        return NSAttributedString(string:symbol,attributes:attributes.merging([.baselineOffset:font.capHeight/2-bounds.midY]) {_,new in new})
    }
    static func imageAttachment(_ source:NSImage,description:String,font:NSFont,side:CGFloat,color:NSColor) -> NSAttributedString {
        // 文本附件每次绘制解析动态色，避免缓存上一次外观。
        let image = NSImage(size:source.size,flipped:false) {rect in
            source.draw(in:rect)
            color.setFill(); rect.fill(using:.sourceIn)
            return true
        }
        image.cacheMode = .never; image.accessibilityDescription = description
        let attachment = NSTextAttachment(); attachment.image = image
        let factor = side/max(source.size.width,source.size.height)
        let width = source.size.width*factor, height = source.size.height*factor
        attachment.bounds = NSRect(x:0,y:(font.capHeight-height)/2,width:width,height:height)
        return NSAttributedString(attachment:attachment)
    }
    static func lineBaseline(font:NSFont,height:CGFloat) -> CGFloat {
        (height-font.ascender+font.descender)/2-font.descender
    }
    static func align(_ icon:NSView,toLineIn view:NSView,font:NSFont,side:CGFloat,width:CGFloat? = nil) {
        let center = view.frame.minY+lineBaseline(font:font,height:view.frame.height)+font.capHeight/2
        icon.frame.origin.y = center-side/2
        icon.frame.size = NSSize(width:width ?? side,height:side)
    }
    static func braille(_ frame:String,font:NSFont,color:NSColor) -> NSAttributedString {
        let offset = brailleBaselineOffset(for:font)
        if color === AppAccent.foregroundColor || color === NSColor.labelColor || color === StatusTextColor.secondary {
            let key = BrailleStyleKey(font:FontKey(name:font.fontName,size:font.pointSize),colorID:ObjectIdentifier(color))
            if let entry = brailleStyles[key] {
                return NSAttributedString(string:frame,attributes:entry.attributes)
            }
            let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color,.baselineOffset:offset]
            let entry = BrailleStyleEntry(attributes:attributes,prototype:NSAttributedString(string:"⣿",attributes:attributes))
            if brailleStyleOrder.count >= 16,let oldest = brailleStyleOrder.first {
                brailleStyleOrder.removeFirst(); brailleStyles.removeValue(forKey:oldest)
            }
            brailleStyleOrder.append(key); brailleStyles[key] = entry
            return NSAttributedString(string:frame,attributes:entry.attributes)
        }
        return NSAttributedString(string:frame,attributes:[.font:font,.foregroundColor:color,.baselineOffset:offset])
    }
    static func brailleFieldSize(font:NSFont) -> NSSize {
        let cell = NSTextFieldCell(textCell:"")
        cell.isBordered = false; cell.isBezeled = false; cell.drawsBackground = false
        cell.font = font
        cell.attributedStringValue = braille("⣿",font:font,color:.labelColor)
        let size = cell.cellSize
        return NSSize(width:ceil(size.width),height:ceil(size.height))
    }
    static func alignBraille(_ field:NSTextField,to baseline:CGFloat) {
        field.frame.size = brailleFieldSize(font:field.font!)
        field.frame.origin.y += baseline-Self.baseline(of:field)
    }
    static func baseline(of field:NSTextField) -> CGFloat {
        let rect = field.alignmentRect(forFrame:field.frame)
        return field.superview?.isFlipped == true ? rect.minY+field.firstBaselineOffsetFromTop : rect.maxY-field.firstBaselineOffsetFromTop
    }
    static func align(_ field:NSTextField,to baseline:CGFloat) {
        field.frame.size.height = field.fittingSize.height
        field.frame.origin.y += baseline-Self.baseline(of:field)
    }
    static func align(_ icon:NSView,to field:NSTextField,side:CGFloat,width:CGFloat? = nil) {
        let direction:CGFloat = field.superview?.isFlipped == true ? -1 : 1
        let center = baseline(of:field)+direction*(field.font?.capHeight ?? 0)/2
        icon.frame.origin.y = center-side/2
        icon.frame.size = NSSize(width:width ?? side,height:side)
    }
}
