import AppKit

// 跟随系统滚动条样式；覆盖式滚动条也占用独立的正文留白。
class GutterScrollView:NSScrollView {
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

// 新审批持续锚定顶部；原生文本排版和窗口高度动画不能把首段移出视口。
private final class InitialReadingClipView:NSClipView {
    var holdsTop = false
    override func scroll(to newOrigin:NSPoint) {
        var proposed = bounds; proposed.origin = newOrigin
        super.scroll(to:holdsTop ? constrainBoundsRect(proposed).origin : newOrigin)
    }
    override func constrainBoundsRect(_ proposedBounds:NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        if holdsTop {
            result.origin.y = documentView?.isFlipped == false
                ? max(documentRect.minY,documentRect.maxY-result.height) : documentRect.minY
        }
        return result
    }
}

private final class ReadingScroller:NSScroller {
    var onUserScroll:() -> Void = {}
    override class var isCompatibleWithOverlayScrollers:Bool {true}
    override func mouseDown(with event:NSEvent) {onUserScroll(); super.mouseDown(with:event)}
    override func accessibilityPerformIncrement() -> Bool {onUserScroll(); return super.accessibilityPerformIncrement()}
    override func accessibilityPerformDecrement() -> Bool {onUserScroll(); return super.accessibilityPerformDecrement()}
}

final class InitialReadingScrollView:GutterScrollView {
    private let readingClip = InitialReadingClipView()
    override init(frame:NSRect) {
        super.init(frame:frame)
        readingClip.drawsBackground = false; contentView = readingClip
        let scroller = ReadingScroller()
        scroller.onUserScroll = { [weak self] in self?.releaseInitialTop() }
        verticalScroller = scroller
    }
    required init?(coder:NSCoder) {fatalError()}
    func holdInitialTop() {
        readingClip.holdsTop = true
        readingClip.scroll(to:readingClip.constrainBoundsRect(readingClip.bounds).origin)
        reflectScrolledClipView(readingClip)
    }
    func releaseInitialTop() {readingClip.holdsTop = false}
    override func scrollWheel(with event:NSEvent) {releaseInitialTop(); super.scrollWheel(with:event)}
}
