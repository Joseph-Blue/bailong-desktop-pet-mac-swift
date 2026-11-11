import AppKit
import QuartzCore

final class SpriteView: NSView {
    weak var pet: PetController?
    private let imageLayer = CALayer()
    private struct RenderState: Equatable {
        let image: CGImage
        let rect: CGRect
        let bounds: CGRect
        let transform: CGAffineTransform
        let clipped: Bool
        let backingScale: CGFloat
        static func == (a: Self, b: Self) -> Bool {
            a.image === b.image && a.rect == b.rect && a.bounds == b.bounds && a.transform == b.transform &&
                a.clipped == b.clipped && a.backingScale == b.backingScale
        }
    }
    private var displayedState: RenderState?
    private var shadowState: RenderState?

    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        imageLayer.anchorPoint = .zero
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .linear
        imageLayer.magnificationFilter = .linear
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        wantsLayer = true
    }
    required init?(coder: NSCoder) {fatalError("init(coder:) has not been implemented")}
    override var isFlipped: Bool {true}
    override var wantsUpdateLayer: Bool {true}
    override func makeBackingLayer() -> CALayer {
        let backing = CALayer()
        backing.isGeometryFlipped = true
        backing.addSublayer(imageLayer)
        return backing
    }
    // 根图层只承载图像子层，内容和几何在原选帧／位置回调中一起更新。
    override func updateLayer() {}
    override func layout() {super.layout(); refreshFrame()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); refreshFrame()}
    override func viewDidChangeBackingProperties() {super.viewDidChangeBackingProperties(); refreshFrame()}

    func refreshFrame() {
        guard let pet, !pet.hidden, let frame = pet.currentFrame, let layer else {return}
        let state = RenderState(image:frame.image,rect:pet.drawRect,bounds:bounds,transform:pet.transform,
                                clipped:pet.dock == "notch",backingScale:window?.backingScaleFactor ?? 1)
        if state != displayedState {
            let t = state.transform
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.masksToBounds = state.clipped
            imageLayer.bounds = CGRect(origin:.zero,size:state.rect.size)
            // 与原 drawRect → transform 相同：先把图像放进动作矩形，再绕画布变换。
            imageLayer.position = state.rect.origin.applying(t)
            imageLayer.setAffineTransform(CGAffineTransform(a:t.a,b:t.b,c:t.c,d:t.d,tx:0,ty:0))
            imageLayer.contentsScale = state.backingScale
            if displayedState?.image !== frame.image {imageLayer.contents = frame.image}
            CATransaction.commit()
            displayedState = state
            pet.diagnostics?.record(frame.image)
        }
        // 起播首帧已提交时，最终 Animation 交接仍要登记这次加载的就绪时间。
        if let animation = pet.animation, animation.loadTiming?.submittedAt == nil {
            animation.loadTiming?.submittedAt = ProcessInfo.processInfo.systemUptime
        }
        if window?.hasShadow == true {
            if shadowState != state {window?.invalidateShadow(); shadowState = state}
        } else {shadowState = nil}
    }
    func releaseDisplayTracking() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        CATransaction.commit()
        displayedState = nil; shadowState = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {true}
    override func shouldDelayWindowOrdering(for event:NSEvent) -> Bool {true}
    override func mouseDown(with event: NSEvent) {
        NSApp.preventWindowOrdering(); pet?.mouseDown(event)
    }
    override func mouseDragged(with event: NSEvent) {pet?.mouseDragged(event)}
    override func mouseUp(with event: NSEvent) {pet?.mouseUp(event)}
    override func rightMouseDown(with event: NSEvent) {
        NSApp.preventWindowOrdering(); pet?.rightMouseDown(event)
    }
    override func rightMouseUp(with event: NSEvent) {}
}
