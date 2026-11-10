import AppKit
import CoreText

// 文字以原生第一行基线对齐；图标以相邻文字的大写字高中心对齐。
enum InlineStatusLayout {
    static func lineBaseline(font:NSFont,height:CGFloat) -> CGFloat {
        (height-font.ascender+font.descender)/2-font.descender
    }
    static func align(_ icon:NSImageView,toLineIn view:NSView,font:NSFont,side:CGFloat) {
        let center = view.frame.minY+lineBaseline(font:font,height:view.frame.height)+font.capHeight/2
        icon.frame.origin.y = center-side/2
        icon.frame.size = NSSize(width:side,height:side)
    }
    static func braille(_ frame:String,font:NSFont,color:NSColor) -> NSAttributedString {
        // 用完整盲文单元测量，所有动画帧保持同一中心，避免随亮点上下跳动。
        let cell = CTLineCreateWithAttributedString(NSAttributedString(string:"⣿",attributes:[.font:font]))
        let bounds = CTLineGetBoundsWithOptions(cell,.useGlyphPathBounds)
        return NSAttributedString(string:frame,attributes:[.font:font,.foregroundColor:color,
            .baselineOffset:font.capHeight/2-bounds.midY])
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
    static func align(_ icon:NSView,to field:NSTextField,side:CGFloat) {
        let direction:CGFloat = field.superview?.isFlipped == true ? -1 : 1
        let center = baseline(of:field)+direction*(field.font?.capHeight ?? 0)/2
        icon.frame.origin.y = center-side/2
        icon.frame.size = NSSize(width:side,height:side)
    }
}
