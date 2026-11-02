import AppKit

// 普通消息、审批、问卷、任务列表、额度与短进展共用的正文容器。
// 文档尺寸由内容提供，视口由气泡提供；滚动条只在真正溢出时存在。
final class BubbleBodyScrollView:GutterScrollView {
    private(set) var bodyHeight:CGFloat = 0
    override var documentLayoutWidth:CGFloat {Self.documentWidth(for:bounds.width)}

    override init(frame:NSRect) {
        super.init(frame:frame)
        drawsBackground = false
        autohidesScrollers = false
        hasVerticalScroller = false
        verticalScrollElasticity = .none
    }
    required init?(coder:NSCoder) {fatalError()}

    func setBody(_ document:NSView,height:CGFloat) {
        bodyHeight = max(0,ceil(height))
        if documentView !== document {documentView = document}
        updateGeometry()
    }

    func setViewport(_ viewport:NSRect) {
        let origin = contentView.bounds.origin
        if frame != viewport {frame = viewport}
        updateGeometry()
        restorePosition(origin)
    }

    private func updateGeometry() {
        guard let document = documentView else {return}
        let overflow = bodyHeight > bounds.height
        if hasVerticalScroller != overflow {hasVerticalScroller = overflow}
        let size = NSSize(width:documentLayoutWidth,height:bodyHeight)
        if document.frame.size != size {document.setFrameSize(size)}
        tile()
        reflectScrolledClipView(contentView)
    }

    func showTop() {restorePosition(.zero)}

    func restorePosition(_ origin:NSPoint) {
        // 本容器中的文档均按从上往下布局；不足一页时只存在顶部位置。
        let y = min(max(0,origin.y),max(0,bodyHeight-contentView.bounds.height))
        let point = NSPoint(x:0,y:y)
        if contentView.bounds.origin != point {contentView.scroll(to:point)}
        reflectScrolledClipView(contentView)
    }
}
