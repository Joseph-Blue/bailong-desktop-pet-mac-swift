import AppKit
import ObjectiveC

private var hoverHelpKey: UInt8 = 0

extension NSView {
    var hoverHelp: String? {
        get {(objc_getAssociatedObject(self,&hoverHelpKey) as? HoverHelpTarget)?.text}
        set {
            let old = objc_getAssociatedObject(self,&hoverHelpKey) as? HoverHelpTarget
            if old?.text == newValue {return}
            old?.detach()
            toolTip = nil
            setAccessibilityHelp(newValue)
            let target = newValue.flatMap {$0.isEmpty ? nil : HoverHelpTarget(view:self,text:$0)}
            objc_setAssociatedObject(self,&hoverHelpKey,target,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

extension NSToolbarItem {
    func installHoverHelp() {
        let button = NSButton(image:image ?? NSImage(),target:target,action:action)
        button.bezelStyle = .texturedRounded; button.imagePosition = .imageOnly
        button.setAccessibilityLabel(label); button.hoverHelp = label
        button.frame = NSRect(x:0,y:0,width:32,height:28)
        view = button; toolTip = nil
    }
}

private final class HoverHelpTarget: NSResponder {
    weak var view: NSView?
    let text: String
    private var area: NSTrackingArea!
    init(view:NSView,text:String) {
        self.view = view; self.text = text
        super.init()
        area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.inVisibleRect,.activeAlways],owner:self,userInfo:nil)
        view.addTrackingArea(area)
    }
    required init?(coder:NSCoder) {fatalError()}
    deinit {HoverHelpPresenter.shared.leave(self)}
    func detach() {
        if let area {view?.removeTrackingArea(area)}
        HoverHelpPresenter.shared.leave(self)
    }
    override func mouseEntered(with event:NSEvent) {HoverHelpPresenter.shared.enter(self)}
    override func mouseExited(with event:NSEvent) {HoverHelpPresenter.shared.leave(self)}
}

// 公开 AppKit panel／tracking API 控制应用自有提示的时长，不改系统 tooltip 私有参数。
private final class HoverHelpPresenter {
    static let shared = HoverHelpPresenter()
    private let panel = NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private let text = NSTextField(wrappingLabelWithString:"")
    private weak var target: HoverHelpTarget?
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var dismissMonitor: Any?
    private var notifications = [NSObjectProtocol]()
    private init() {
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.level = .statusBar
        panel.hidesOnDeactivate = true; panel.animationBehavior = .none
        let material = NSVisualEffectView(); material.material = .toolTip; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 6; material.layer?.masksToBounds = true
        panel.contentView = material
        text.font = .systemFont(ofSize:11); text.textColor = .labelColor
        text.maximumNumberOfLines = 0; text.lineBreakMode = .byCharWrapping
        text.cell?.wraps = true; text.cell?.isScrollable = false
        text.setAccessibilityElement(false); material.addSubview(text)
        dismissMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown,.keyDown,.scrollWheel,.leftMouseDragged]) { [weak self] event in
            self?.dismiss(); return event
        }
        for name in [NSWindow.willCloseNotification,NSWindow.didMiniaturizeNotification,NSWindow.didResignKeyNotification,NSApplication.didResignActiveNotification,NSMenu.didBeginTrackingNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.dismiss() })
        }
    }
    func enter(_ next:HoverHelpTarget) {
        dismiss(); target = next
        let job = DispatchWorkItem { [weak self,weak next] in
            guard let self,let next,self.target === next,let view = next.view,let window = view.window,
                  window.isVisible,!view.isHiddenOrHasHiddenAncestor else {return}
            let point = window.convertPoint(fromScreen:NSEvent.mouseLocation)
            guard view.visibleRect.contains(view.convert(point,from:nil)) else {return}
            self.show(next.text,window:window)
        }
        pending = job; DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:job)
    }
    func leave(_ previous:HoverHelpTarget) {if target === previous {dismiss()}}
    private func show(_ value:String,window:NSWindow) {
        generation += 1; pending = nil
        text.stringValue = value; panel.appearance = window.effectiveAppearance
        let mouse = NSEvent.mouseLocation
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let naturalWidth = (value as NSString).size(withAttributes:[.font:text.font!]).width.rounded(.up)+4
        var width = min(max(20,naturalWidth),min(520,screen.width-32))
        func textHeight(_ width:CGFloat) -> CGFloat {
            text.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up)
        }
        var height = max(14,textHeight(width))
        // 长标题按实际排版高度完整展开；接近屏幕高度时先增宽，不省略正文。
        if height > screen.height-32 {
            width = min(max(20,naturalWidth),screen.width-32); height = max(14,textHeight(width))
        }
        text.frame = NSRect(x:9,y:6,width:width,height:height)
        let size = NSSize(width:width+18,height:height+12)
        let origin = NSPoint(x:max(screen.minX,min(mouse.x+10,screen.maxX-size.width)),y:max(screen.minY,min(mouse.y-size.height-14,screen.maxY-size.height)))
        panel.setFrame(NSRect(origin:origin,size:size),display:true)
        panel.alphaValue = 1; panel.orderFrontRegardless()
    }
    private func dismiss() {
        pending?.cancel(); pending = nil; target = nil; generation += 1
        guard panel.isVisible else {return}
        let serial = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.08
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self,self.generation == serial else {return}
            self.panel.orderOut(nil)
            self.text.stringValue = ""
        }
    }
}
