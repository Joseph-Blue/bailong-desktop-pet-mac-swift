import AppKit

// 文字以原生第一行基线对齐；图标以相邻文字的大写字高中心对齐。
enum InlineStatusLayout {
    static func baseline(of field:NSTextField) -> CGFloat {
        field.alignmentRect(forFrame:field.frame).maxY-field.firstBaselineOffsetFromTop
    }
    static func align(_ field:NSTextField,to baseline:CGFloat) {
        field.frame.size.height = field.fittingSize.height
        field.frame.origin.y += baseline-Self.baseline(of:field)
    }
    static func align(_ icon:NSImageView,to field:NSTextField,side:CGFloat) {
        let center = baseline(of:field)+(field.font?.capHeight ?? 0)/2
        icon.frame.origin.y = center-side/2
        icon.frame.size = NSSize(width:side,height:side)
    }
}
