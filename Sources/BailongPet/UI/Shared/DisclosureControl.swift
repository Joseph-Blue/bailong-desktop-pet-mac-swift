import AppKit

// 共用的展开触发控件，内容、展开状态与视口行为由调用方管理。
final class DisclosureControl:NSControl {
    private static let inlineTitleColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .white : .black}
    override var isFlipped:Bool {true}
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size:NSSize(width:10000,height:10000))
    private var tracking:NSTrackingArea?
    private var hovering = false
    private var pressed = false

    var onToggle:(() -> Void)?
    var scale:CGFloat = 1 {didSet {invalidateIntrinsicContentSize(); needsDisplay = true}}
    var expandable = true {
        didSet {
            if !expandable {hovering = false; pressed = false}
            isEnabled = expandable
            invalidateIntrinsicContentSize(); needsDisplay = true
        }
    }
    var expanded = false {didSet {updateAccessibility(); needsDisplay = true}}
    var baseFont:NSFont = .monospacedDigitSystemFont(ofSize:12,weight:.regular) {
        didSet {invalidateIntrinsicContentSize(); needsDisplay = true}
    }
    var chevronTint:NSColor = .labelColor {didSet {needsDisplay = true}}
    var accessibilityTitle = "明细" {didSet {updateAccessibility()}}

    // 仅供测试或外部模拟悬停验证，不参与业务逻辑。
    var isShowingHoverHighlight:Bool {expandable && (hovering || pressed)}
    func setSimulatedHover(_ active:Bool) {
        hovering = expandable && active
        needsDisplay = true
    }

    var textLeadingInset:CGFloat {expandable ? round(6*scale) : 0}
    private var verticalInset:CGFloat {round(4*scale)}
    private var chevronGap:CGFloat {expandable ? round(5*scale) : 0}
    private var chevronSlot:CGFloat {expandable ? ceil(baseFont.pointSize*0.95) : 0}

    var attributedTitle:NSAttributedString {
        get {storage}
        set {
            if !storage.isEqual(to:newValue) {
                storage.setAttributedString(newValue)
                invalidateIntrinsicContentSize()
                needsDisplay = true
            }
        }
    }

    func setInlineTitle(_ title:String,font:NSFont) {
        let scale = max(0.85,font.pointSize/12)
        if self.scale != scale {self.scale = scale}
        if baseFont != font {baseFont = font}
        chevronTint = .secondaryLabelColor
        attributedTitle = NSAttributedString(string:title,attributes:[.font:font,.foregroundColor:Self.inlineTitleColor])
    }

    override init(frame:NSRect) {
        super.init(frame:frame)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        setAccessibilityElement(true)
        updateAccessibility()
    }
    required init?(coder:NSCoder) {fatalError()}

    private func updateAccessibility() {
        setAccessibilityRole(expandable ? .button : .staticText)
        setAccessibilityLabel(expandable ? (expanded ? "收起"+accessibilityTitle : "展开"+accessibilityTitle) : storage.string)
    }

    override func acceptsFirstMouse(for event:NSEvent?) -> Bool {expandable}
    override var acceptsFirstResponder:Bool {expandable}

    func preferredSize(maxWidth:CGFloat = 10000) -> NSSize {
        let chrome = textLeadingInset*2+chevronGap+chevronSlot
        let availableText = max(1,maxWidth-chrome)
        container.containerSize = NSSize(width:availableText,height:10000)
        layoutManager.ensureLayout(for:container)
        let used = layoutManager.usedRect(for:container)
        let width = min(maxWidth,ceil(used.maxX)+chrome)
        let height = max(ceil(baseFont.pointSize+10*scale),ceil(used.maxY)+verticalInset*2)
        return NSSize(width:width,height:height)
    }

    override var intrinsicContentSize:NSSize {preferredSize()}

    var firstLineBaseline:CGFloat {
        let chrome = textLeadingInset*2+chevronGap+chevronSlot
        container.containerSize = NSSize(width:max(1,bounds.width-chrome),height:10000)
        layoutManager.ensureLayout(for:container)
        guard layoutManager.numberOfGlyphs > 0 else {return bounds.midY+baseFont.capHeight/2}
        let used = layoutManager.usedRect(for:container)
        let textTop = floor((bounds.height-used.height)/2)
        let line = layoutManager.lineFragmentRect(forGlyphAt:0,effectiveRange:nil)
        return textTop+line.minY+layoutManager.location(forGlyphAt:0).y
    }

    // 返回文字光学中心与箭头墨迹中心在当前坐标系中的差值（趋近 0）。
    var chevronOpticalOffset:CGFloat {
        guard expandable,let metrics = chevronMetrics() else {return 0}
        return abs(metrics.inkCenterY-metrics.textOpticalCenterY)
    }

    private func chevronMetrics() -> (image:NSImage,rect:NSRect,textOpticalCenterY:CGFloat,inkCenterY:CGFloat)? {
        let symbolName = expanded ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize:max(9,baseFont.pointSize*0.78),weight:.semibold)
        guard let symbol = NSImage(systemSymbolName:symbolName,accessibilityDescription:nil)?.withSymbolConfiguration(config) else {return nil}
        let textOpticalCenterY = firstLineBaseline-baseFont.capHeight/2
        let slotX = bounds.width-textLeadingInset-chevronSlot
        let drawX = slotX+(chevronSlot-symbol.size.width)/2
        // SF Symbol 在未翻转图像坐标中的真实墨迹中心位于 alignmentRect.midY；
        // 换算到翻转视图坐标后，顶边到墨迹中心的距离为 size.height - alignmentRect.midY。
        let topToInkCenter = symbol.size.height-symbol.alignmentRect.midY
        let drawY = textOpticalCenterY-topToInkCenter
        let rect = NSRect(x:drawX,y:drawY,width:symbol.size.width,height:symbol.size.height)
        return (symbol,rect,textOpticalCenterY,rect.minY+topToInkCenter)
    }

    override func updateTrackingAreas() {
        if let tracking {removeTrackingArea(tracking)}
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
        refreshHoverFromPointer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverFromPointer()
    }

    override func layout() {
        super.layout()
        refreshHoverFromPointer()
    }

    private func refreshHoverFromPointer() {
        guard expandable,let window,window.isVisible else {
            if hovering {hovering = false; needsDisplay = true}
            return
        }
        let local = convert(window.mouseLocationOutsideOfEventStream,from:nil)
        let inside = bounds.contains(local)
        if hovering != inside {hovering = inside; needsDisplay = true}
    }

    override func mouseEntered(with event:NSEvent) {
        guard expandable else {return}
        hovering = true; needsDisplay = true
    }

    override func mouseExited(with event:NSEvent) {
        hovering = false; needsDisplay = true
    }

    override func mouseDown(with event:NSEvent) {
        guard expandable,isEnabled,let window else {super.mouseDown(with:event); return}
        pressed = true; hovering = true; needsDisplay = true
        while let next = window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            let local = convert(next.locationInWindow,from:nil)
            let inside = bounds.contains(local)
            if next.type == .leftMouseDragged {
                if pressed != inside || hovering != inside {
                    pressed = inside; hovering = inside; needsDisplay = true
                }
            } else {
                pressed = false; hovering = inside; needsDisplay = true
                if inside {triggerToggle()}
                break
            }
        }
    }

    override func performClick(_ sender:Any?) {
        guard expandable,isEnabled else {return}
        triggerToggle()
    }

    override func keyDown(with event:NSEvent) {
        if expandable,isEnabled,event.charactersIgnoringModifiers == " " {
            triggerToggle(); return
        }
        super.keyDown(with:event)
    }

    override func menu(for event:NSEvent) -> NSMenu? {
        let plain = storage.string.replacingOccurrences(of:"\t",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !plain.isEmpty else {return nil}
        let menu = NSMenu()
        let copy = NSMenuItem(title:"拷贝",action:#selector(copySummary),keyEquivalent:"")
        copy.target = self; menu.addItem(copy)
        return menu
    }

    @objc private func copySummary() {
        let plain = storage.string.replacingOccurrences(of:"\t",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !plain.isEmpty else {return}
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain,forType:.string)
    }

    private func triggerToggle() {
        if let action {sendAction(action,to:target)}
        onToggle?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect:NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        if expandable && (hovering || pressed) {
            let fillAlpha:CGFloat = pressed ? (dark ? 0.18 : 0.12) : (dark ? 0.11 : 0.065)
            let strokeAlpha:CGFloat = pressed ? (dark ? 0.22 : 0.15) : (dark ? 0.15 : 0.10)
            let ink:NSColor = dark ? .white : .black
            let pillRect = bounds.insetBy(dx:0.5,dy:0.5)
            let radius = 6*scale
            let pill = NSBezierPath(roundedRect:pillRect,xRadius:radius,yRadius:radius)
            ink.withAlphaComponent(fillAlpha).setFill(); pill.fill()
            ink.withAlphaComponent(strokeAlpha).setStroke(); pill.lineWidth = 1; pill.stroke()
        }

        let chrome = textLeadingInset*2+chevronGap+chevronSlot
        container.containerSize = NSSize(width:max(1,bounds.width-chrome),height:10000)
        layoutManager.ensureLayout(for:container)
        let glyphs = layoutManager.glyphRange(for:container)
        if glyphs.length > 0 {
            let used = layoutManager.usedRect(for:container)
            let origin = NSPoint(x:textLeadingInset,y:floor((bounds.height-used.height)/2))
            layoutManager.drawBackground(forGlyphRange:glyphs,at:origin)
            layoutManager.drawGlyphs(forGlyphRange:glyphs,at:origin)
        }

        if expandable,let metrics = chevronMetrics() {
            let color = (hovering || pressed) ? (dark ? NSColor.white : NSColor.black) : chevronTint
            let tinted = NSImage(size:metrics.image.size,flipped:false) { rect in
                metrics.image.draw(in:rect)
                color.setFill(); rect.fill(using:.sourceIn)
                return true
            }
            tinted.draw(in:metrics.rect)
        }
    }
}
