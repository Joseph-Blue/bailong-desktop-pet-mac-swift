import AppKit

// 跟随系统滚动条样式；覆盖式滚动条也占用独立的正文留白。
final class GutterScrollView:NSScrollView {
    static var gutter:CGFloat {NSScroller.scrollerWidth(for:.regular,scrollerStyle:.legacy)+4}
    static func documentWidth(for width:CGFloat) -> CGFloat {max(0,width-gutter)}
    override func tile() {
        super.tile()
        guard hasVerticalScroller else {return}
        var frame = contentView.frame
        let reserved = bounds.maxX-frame.maxX
        frame.size.width = max(0,frame.width-max(0,Self.gutter-reserved))
        if contentView.frame != frame {contentView.frame = frame}
    }
}
