import AppKit

extension NSMenu {
    func showProvidedImages() {
        for item in items {
            #if BAILONG_SDK_MENU_IMAGES
            if #available(macOS 27.0, *), item.image != nil {item.preferredImageVisibility = .visible}
            #endif
            item.submenu?.showProvidedImages()
        }
    }
}

func showError(_ title: String, _ error: Error) {
    let alert = NSAlert(); alert.messageText = title; alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning; alert.addButton(withTitle: "好")
    alert.applyAccent(); NSApp.activate(ignoringOtherApps: true); alert.runModal()
}
func label(_ text: String, bold: Bool = false) -> NSTextField {
    let view = NSTextField(wrappingLabelWithString: text)
    view.isSelectable = false
    view.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
    return view
}
func materialView() -> NSVisualEffectView {
    let view = NSVisualEffectView(); view.material = .popover
    view.blendingMode = .behindWindow; view.state = .active; return view
}
final class ActionButton: NSButton {
    var callback: () -> Void
    var acceptsKeyboardActivation = true
    override var acceptsFirstResponder: Bool {acceptsKeyboardActivation && super.acceptsFirstResponder}
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        acceptsKeyboardActivation && super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        if acceptsKeyboardActivation {super.keyDown(with:event)}
    }
    private var prominent = false
    private var hovering = false
    private var hoverTracking:NSTrackingArea?
    private var flexibleLayout = false
    var extraHorizontalPadding:CGFloat = 0 {didSet {invalidateIntrinsicContentSize()}}
    var semanticColor:NSColor? {didSet {updateAccent()}}
    var keepsAccentWhenInactive = false {didSet {updateAccent()}}
    init(_ title: String, _ callback: @escaping () -> Void) {
        self.callback = callback; super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; target = self; action = #selector(invokeCallback)
        NotificationCenter.default.addObserver(self,selector:#selector(updateAccent),name:AppAccent.didChange,object:nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        if let hoverTracking {removeTrackingArea(hoverTracking)}
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        hoverTracking = area; addTrackingArea(area); super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) {super.mouseEntered(with:event); hovering = true; needsDisplay = true}
    override func mouseExited(with event:NSEvent) {super.mouseExited(with:event); hovering = false; needsDisplay = true}
    func configureFlexible(font:NSFont) {
        flexibleLayout = true; bezelStyle = .flexiblePush; self.font = font
        symbolConfiguration = .init(pointSize:font.pointSize,weight:.regular)
        if let image,image.size != NSSize(width:iconSide,height:iconSide),let copy = image.copy() as? NSImage {
            copy.size = NSSize(width:iconSide,height:iconSide); self.image = copy
        }
        invalidateIntrinsicContentSize()
    }
    private var iconSide:CGFloat {image == nil ? 0 : (font?.pointSize ?? 13)+3}
    override var intrinsicContentSize:NSSize {
        guard flexibleLayout || (prominent && keepsAccentWhenInactive) else {return super.intrinsicContentSize}
        let font = font ?? .systemFont(ofSize:13), ratio = font.pointSize/13
        let text = imagePosition == .imageOnly ? NSSize.zero : (title as NSString).size(withAttributes:[.font:font])
        let gap:CGFloat = image != nil && text.width > 0 ? 6*ratio : 0
        return NSSize(width:ceil(text.width+iconSide+gap+(24+extraHorizontalPadding)*ratio),height:ceil(max(28*ratio,max(text.height,iconSide)+10*ratio)))
    }
    func emphasize(_ enabled: Bool = true) {prominent = enabled; updateAccent()}
    @objc private func updateAccent() {
        bezelColor = prominent ? AppAccent.color : nil
        isBordered = semanticColor == nil && !(prominent && keepsAccentWhenInactive); invalidateIntrinsicContentSize(); needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
    override func draw(_ dirtyRect: NSRect) {
        guard semanticColor != nil || prominent && keepsAccentWhenInactive else {super.draw(dirtyRect); return}
        let color:NSColor, foreground:NSColor
        if let semanticColor {
            // 实色浅底，文字随系统外观提高对比；不依赖背景玻璃或仅靠颜色区分。
            color = NSColor.controlBackgroundColor.blended(withFraction:isHighlighted ? 0.26 : isEnabled && hovering ? 0.20 : 0.13,of:semanticColor) ?? .controlBackgroundColor
            foreground = isEnabled ? semanticColor.blended(withFraction:0.35,of:.labelColor) ?? .labelColor : .disabledControlTextColor
        } else {
            color = isHighlighted ? AppAccent.color.blended(withFraction:0.15,of:.black) ?? AppAccent.color : isEnabled && hovering ? AppAccent.color.blended(withFraction:0.08,of:.white) ?? AppAccent.color : AppAccent.color
            foreground = .white
        }
        color.withAlphaComponent(isEnabled ? 1 : 0.45).setFill()
        let ratio = (font?.pointSize ?? 13)/13
        NSBezierPath(roundedRect:bounds.insetBy(dx:0,dy:1),xRadius:7*ratio,yRadius:7*ratio).fill()
        let attributes: [NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:foreground]
        let size = (title as NSString).size(withAttributes:attributes)
        let iconSize = iconSide
        let iconSpace = iconSize > 0 ? iconSize+6*ratio : 0
        let start = (bounds.width-size.width-iconSpace)/2
        if let image {
            let natural = image.size
            let scale = natural.width > 0 && natural.height > 0 ? min(iconSize/natural.width,iconSize/natural.height) : 1
            let target = NSSize(width:natural.width*scale,height:natural.height*scale)
            let rect = NSRect(x:start+(iconSize-target.width)/2,y:(bounds.height-target.height)/2,width:target.width,height:target.height)
            let tinted = NSImage(size:rect.size,flipped:false) { bounds in
                image.draw(in:bounds)
                foreground.setFill(); bounds.fill(using:.sourceIn); return true
            }
            tinted.draw(in:rect)
        }
        (title as NSString).draw(at:NSPoint(x:start+iconSpace,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
    @objc func invokeCallback() { callback() }
}
class HoverIconButton: NSButton {
    var hoverCornerRadius:CGFloat?
    var horizontalPadding:CGFloat = 0
    private var tracking: NSTrackingArea?
    private var hovering = false
    init(symbol:String,label:String) {
        super.init(frame:.zero)
        title = ""; image = NSImage(systemSymbolName:symbol,accessibilityDescription:label)
        imagePosition = .imageOnly; isBordered = false; contentTintColor = .secondaryLabelColor
        setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) {fatalError()}
    override var intrinsicContentSize:NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width:size.width+2*horizontalPadding,height:size.height)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {true}
    override func updateTrackingAreas() {
        if let tracking {removeTrackingArea(tracking)}
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); tracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {hovering = true; needsDisplay = true}
    override func mouseExited(with event: NSEvent) {hovering = false; needsDisplay = true}
    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.secondaryLabelColor.withAlphaComponent(isHighlighted ? 0.24 : 0.14).setFill()
            let rect = bounds.insetBy(dx:1,dy:1)
            if let radius = hoverCornerRadius {NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill()}
            else {NSBezierPath(ovalIn:rect).fill()}
        }
        super.draw(dirtyRect)
    }
}
final class BubbleCloseButton: HoverIconButton {
    var onClose:() -> Void = {}
    init() {
        super.init(symbol:"xmark",label:"关闭气泡")
        target = self; action = #selector(closeBubble)
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func closeBubble() {onClose()}
}
final class TopDownView: NSView {override var isFlipped: Bool {true}}
class ContentCursorPanel:NSPanel {
    var tracksContentCursor = false
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        TextContextMenu.performKeyEquivalent(event,in:self) || super.performKeyEquivalent(with:event)
    }
    override func sendEvent(_ event:NSEvent) {
        super.sendEvent(event)
        guard [.mouseMoved,.mouseEntered,.cursorUpdate,.scrollWheel,.leftMouseUp].contains(event.type) else {return}
        // AppKit 分发完成后再确定光标，输入能力与链接悬停互不依赖。
        refreshContentCursor()
    }
    func refreshContentCursor() {
        guard tracksContentCursor,isVisible,let contentView,
              NSWindow.windowNumber(at:NSEvent.mouseLocation,belowWindowWithWindowNumber:0) == windowNumber else {return}
        let point = contentView.convert(convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
        let interior = styleMask.contains(.resizable) ? contentView.bounds.insetBy(dx:6,dy:6) : contentView.bounds
        guard interior.contains(point) else {return}
        LinkAppearance.cursor(at:point,in:contentView).set()
    }
}
final class PetWindow:ContentCursorPanel {
    var allowsInput = false
    override var canBecomeKey:Bool {allowsInput}
    override var canBecomeMain:Bool {false}
}
// 正文与衬底保持同一视图树；玻璃通过 contentView 为其中的内容提供原生适配。
private final class BubbleBackingView: NSView {
    var opacity: CGFloat = 1 {didSet {needsDisplay = true}}
    override var isOpaque: Bool {false}
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:BubbleBackgroundView.cornerRadius,yRadius:BubbleBackgroundView.cornerRadius).fill()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
final class BubbleBackgroundView: NSView {
    static let cornerRadius:CGFloat = 14
    let body = NSView()
    private let surface = NSView()
    private let edge = GlassEdgeHighlight()
    private let ordinary = BubbleBackingView(), glassBacking = BubbleBackingView()
    private var glass: NSView?
    private var usesGlassContent = false
    private var fade: Timer?
    private var targetOpacity: CGFloat = 1
    private var cursorTracking:NSTrackingArea?
    private let preferences: PetPreferences
    init(preferences: PetPreferences = .shared) {
        self.preferences = preferences
        super.init(frame:.zero)
        addSubview(surface)
        for view in [glassBacking,ordinary,body] {
            surface.addSubview(view); view.autoresizingMask = [.width,.height]
        }
        surface.autoresizingMask = [.width,.height]
        edge.cornerRadius = Self.cornerRadius; edge.autoresizingMask = [.width,.height]
        edge.isHidden = true; addSubview(edge)
        NotificationCenter.default.addObserver(self,selector:#selector(preferencesChanged(_:)),name:PetPreferences.didChange,object:preferences)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(updateMaterial),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        updateMaterial()
    }
    required init?(coder:NSCoder) {fatalError()}
    private func setGlassContent(_ enabled:Bool) {
        guard enabled != usesGlassContent else {return}
        #if BAILONG_SDK_GLASS
        if #available(macOS 26.0, *),let effect = glass as? NSGlassEffectView {
            let host = window
            let responder = host?.firstResponder as? NSView
            let contentResponder = responder.flatMap {$0.isDescendant(of:surface) ? $0 : nil}
            if enabled {
                effect.isHidden = false
                effect.contentView = surface
            } else {
                effect.contentView = nil
                surface.translatesAutoresizingMaskIntoConstraints = true
                addSubview(surface)
                effect.isHidden = true
            }
            usesGlassContent = enabled
            surface.frame = bounds
            // 只恢复本窗原有的内容焦点，不激活应用或把窗口变为 key。
            if let host,let contentResponder,host.firstResponder !== contentResponder {
                host.makeFirstResponder(contentResponder)
            }
        }
        #endif
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking {removeTrackingArea(cursorTracking); self.cursorTracking = nil}
        guard let panel = window as? ContentCursorPanel,panel.tracksContentCursor else {return}
        // 非激活气泡仍接收移动事件；activeAlways 不会发送 cursorUpdate。
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.mouseMoved,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); cursorTracking = area
        panel.refreshContentCursor()
    }
    override func mouseExited(with event:NSEvent) {
        super.mouseExited(with:event)
        if let cursorTracking,event.trackingArea === cursorTracking {NSCursor.arrow.set()}
    }
    override var isOpaque: Bool {false}
    @objc private func preferencesChanged(_ note: Notification) {
        let keys = note.userInfo?["keys"] as? [String] ?? []
        if !Set(keys).isDisjoint(with:["bubbleMaterial","glassFollowsSystem","glassOpacity","bubbleMotion"]) {updateMaterial()}
    }
    @objc private func updateMaterial() {
        let enabled = preferences.usesGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let next: CGFloat = enabled ? 0 : 1
        // 高光仅参与绘制，不跟随 key 状态，也不获取鼠标或键盘焦点。
        edge.isHidden = !enabled
        #if BAILONG_SDK_GLASS
        if #available(macOS 26.0, *), enabled {
            if glass == nil {
                let effect = NSGlassEffectView(frame:bounds)
                effect.autoresizingMask = [.width,.height]; effect.cornerRadius = Self.cornerRadius
                addSubview(effect,positioned:.below,relativeTo:surface); glass = effect
            }
            let effect = glass as! NSGlassEffectView
            effect.style = preferences.bool("glassFollowsSystem") ? .regular : .clear
            glassBacking.opacity = preferences.bool("glassFollowsSystem") ? 0 : CGFloat(preferences.number("glassOpacity"))
            setGlassContent(true)
        }
        #endif
        let animate = preferences.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && window?.isVisible == true
        if next == targetOpacity && fade != nil && animate {return}
        fade?.invalidate(); fade = nil; targetOpacity = next
        guard animate, ordinary.opacity != next else {ordinary.opacity = next; finishMaterial(); return}
        let from = ordinary.opacity, started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:1.0/60,repeats:true) { [weak self] timer in
            guard let self else {timer.invalidate(); return}
            let t = min(1,(ProcessInfo.processInfo.systemUptime-started)/0.16)
            let eased = 1-pow(1-t,3)
            self.ordinary.opacity = from+(next-from)*eased
            if t >= 1 {timer.invalidate(); self.fade = nil; self.finishMaterial()}
        }
        fade = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func finishMaterial() {
        // 实色衬底先铺满，再把同一内容容器移回普通根视图。
        ordinary.opacity = targetOpacity; ordinary.displayIfNeeded()
        if targetOpacity == 1 {setGlassContent(false)}
        window?.invalidateShadow()
    }
    override func layout() {
        super.layout(); glass?.frame = bounds; surface.frame = bounds; edge.frame = bounds
        for view in [glassBacking,ordinary,body] {view.frame = surface.bounds}
    }
    deinit {fade?.invalidate(); NotificationCenter.default.removeObserver(self); NSWorkspace.shared.notificationCenter.removeObserver(self)}
}
// 选项是静态信息，不使用 NSButton，也不注册点击、悬停或键盘焦点。
private final class TaskQuestionOptionView: NSView {
    let scale: CGFloat
    init(frame:NSRect,scale:CGFloat) {self.scale = scale; super.init(frame:frame)}
    required init?(coder:NSCoder) {fatalError()}
    override var isFlipped: Bool {true}
    override func draw(_ dirtyRect:NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.045)).setFill()
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8*scale,yRadius:8*scale)
        shape.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {NSColor.separatorColor.setStroke(); shape.lineWidth = 1; shape.stroke()}
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
enum TaskQuestionLayout {
    static func document(_ questions:[TaskQuestion],width:CGFloat,scale:CGFloat,fontSize:CGFloat) -> NSView {
        let document = TopDownView(frame:NSRect(x:0,y:0,width:width,height:0))
        let bodyFont = NSFont.systemFont(ofSize:fontSize,weight:.medium)
        let detailFont = NSFont.systemFont(ofSize:max(10*scale,fontSize-2*scale))
        func text(_ value:String,_ font:NSFont,_ width:CGFloat,color:NSColor = .labelColor) -> NSTextField {
            let view = label(value); view.font = font; view.textColor = color
            view.maximumNumberOfLines = 0; view.lineBreakMode = .byWordWrapping
            view.frame.size = NSSize(width:width,height:view.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up))
            return view
        }
        var y:CGFloat = 0
        for (questionIndex,question) in questions.enumerated() {
            if questionIndex > 0 {y += 16*scale}
            let prompt = text(question.prompt,bodyFont,width)
            prompt.frame.origin.y = y; document.addSubview(prompt); y += prompt.frame.height
            for (index,option) in question.options.enumerated() {
                y += 8*scale
                let padding = 10*scale, numberWidth = 18*scale, gap = 6*scale
                let contentX = padding+numberWidth+gap, contentWidth = width-contentX-padding
                let badge = option.recommended ? text("推荐",detailFont,34*scale,color:AppAccent.foregroundColor) : nil
                let titleWidth = contentWidth-(badge.map {$0.frame.width+gap} ?? 0)
                let name = text(option.title,bodyFont,titleWidth)
                name.frame.origin = NSPoint(x:contentX,y:padding)
                let number = text(String(index+1),detailFont,numberWidth,color:.secondaryLabelColor)
                number.frame.origin = NSPoint(x:padding,y:padding)
                // 行容器使用向下坐标；按标题首行基线对齐不同字号，而非对齐文本框顶边。
                let baseline = name.alignmentRect(forFrame:name.frame).minY+name.firstBaselineOffsetFromTop
                func alignFirstBaseline(_ view:NSTextField) {
                    let current = view.alignmentRect(forFrame:view.frame).minY+view.firstBaselineOffsetFromTop
                    view.frame.origin.y += baseline-current
                }
                alignFirstBaseline(number)
                if let badge {
                    badge.frame.origin = NSPoint(x:width-padding-badge.frame.width,y:padding)
                    alignFirstBaseline(badge)
                }
                var rowHeight = max(name.frame.maxY,number.frame.maxY,badge?.frame.maxY ?? 0)
                let detail = option.detail.flatMap {$0.isEmpty ? nil : text($0,detailFont,contentWidth,color:.secondaryLabelColor)}
                if let detail {detail.frame.origin = NSPoint(x:contentX,y:rowHeight+4*scale); rowHeight += 4*scale+detail.frame.height}
                rowHeight += padding
                let row = TaskQuestionOptionView(frame:NSRect(x:0,y:y,width:width,height:rowHeight),scale:scale)
                row.addSubview(number); row.addSubview(name)
                if let badge {row.addSubview(badge)}
                if let detail {row.addSubview(detail)}
                document.addSubview(row); y += rowHeight
            }
        }
        document.frame.size.height = y
        return document
    }
}
