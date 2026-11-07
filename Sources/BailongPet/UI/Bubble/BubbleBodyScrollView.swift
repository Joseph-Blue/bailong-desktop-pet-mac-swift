import AppKit

// 一次分配正文边界和原生滚动条轨道；轨道使用右侧边距，不再额外压窄正文。
struct BubbleBodyLayout {
    let inset:CGFloat, contentWidth:CGFloat
    private let gutter:CGFloat

    init(width:CGFloat,scale:CGFloat) {
        gutter = GutterScrollView.gutter
        // 原默认正文起点为 16pt 外边距 + 5pt TextKit 行内留白。
        // 小比例下仍为系统尺寸的滚动条保留空间，两侧正文边界始终对称。
        inset = max(21*scale,gutter+2*scale)
        contentWidth = max(0,width-2*inset)
    }

    func viewport(y:CGFloat,height:CGFloat) -> NSRect {
        NSRect(x:inset,y:y,width:contentWidth+gutter,height:height)
    }
}

// 普通消息、审批、问卷、任务列表、额度与短进展共用的正文容器。
// 文档尺寸由内容提供，视口由气泡提供；滚动条只在真正溢出时存在。
final class BubbleBodyScrollView:GutterScrollView {
    private(set) var bodyHeight:CGFloat = 0
    var allowsScrolling = true {didSet {updateGeometry()}}
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
        let overflow = allowsScrolling && bodyHeight > bounds.height
        if hasVerticalScroller != overflow {hasVerticalScroller = overflow}
        let size = NSSize(width:documentLayoutWidth,height:allowsScrolling ? bodyHeight : min(bodyHeight,bounds.height))
        if document.frame.size != size {document.setFrameSize(size)}
        tile()
        reflectScrolledClipView(contentView)
    }

    func showTop() {restorePosition(.zero)}

    func restorePosition(_ origin:NSPoint) {
        // 本容器中的文档均按从上往下布局；不足一页时只存在顶部位置。
        let y = allowsScrolling ? min(max(0,origin.y),max(0,bodyHeight-contentView.bounds.height)) : 0
        let point = NSPoint(x:0,y:y)
        if contentView.bounds.origin != point {contentView.scroll(to:point)}
        reflectScrolledClipView(contentView)
    }
}
