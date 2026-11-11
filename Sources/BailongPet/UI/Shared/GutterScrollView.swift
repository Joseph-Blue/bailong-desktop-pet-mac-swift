import AppKit

// 正文按宽度换行，只允许纵向阅读；排版、选择及恢复位置不能横移正文。
private class VerticalReadingClipView:NSClipView {
    override func scroll(to newOrigin:NSPoint) {
        super.scroll(to:NSPoint(x:documentView?.frame.minX ?? 0,y:newOrigin.y))
    }
    override func constrainBoundsRect(_ proposedBounds:NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        result.origin.x = documentView?.frame.minX ?? 0
        return result
    }
}

// 跟随系统滚动条样式；覆盖式滚动条也占用独立的正文留白。
class GutterScrollView:NSScrollView {
    static var gutter:CGFloat {NSScroller.scrollerWidth(for:.regular,scrollerStyle:.legacy)+4}
    static func documentWidth(for width:CGFloat) -> CGFloat {max(0,width-gutter)}
    var documentLayoutWidth:CGFloat {hasVerticalScroller ? Self.documentWidth(for:bounds.width) : bounds.width}
    override var documentView:NSView? {
        didSet {
            // 文本换行按容器宽度计算，滚动条显隐只改变视口，不拉伸正文。
            if let text = documentView as? NSTextView {
                text.autoresizingMask.remove(.width)
                layoutTextWidth(text)
            }
        }
    }
    private func layoutTextWidth(_ text:NSTextView) {
        let width = documentLayoutWidth
        if text.frame.width != width {text.frame.size.width = width}
    }
    override init(frame:NSRect) {
        super.init(frame:frame)
        let clip = VerticalReadingClipView()
        clip.drawsBackground = false; contentView = clip
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        contentInsets = .init(); scrollerInsets = .init()
        hasHorizontalScroller = false; horizontalScrollElasticity = .none
        verticalScrollElasticity = .allowed
    }
    required init?(coder:NSCoder) {fatalError()}
    override func tile() {
        if let text = documentView as? NSTextView {layoutTextWidth(text)}
        // 正文宽度只减一次 gutter；原生滚动条位于滚动视图最右缘。
        // contentInsets 再预留右边距会将滚动条一起向内推，形成重复留白。
        super.tile()
    }
}
