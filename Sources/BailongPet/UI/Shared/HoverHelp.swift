import AppKit
import ObjectiveC

private var hoverHelpKey: UInt8 = 0

extension NSView {
    var hoverHelp: String? {
        get {(objc_getAssociatedObject(self,&hoverHelpKey) as? HoverHelpTarget)?.text}
        set {setHoverHelp(newValue)}
    }
    func setHoverHelp(_ text:String?,when shouldShow:(() -> Bool)? = nil) {
        setHoverHelp(text,styled:nil,when:shouldShow)
    }
    func setHoverHelp(_ text:NSAttributedString,when shouldShow:(() -> Bool)? = nil) {
        let accessibleText = text.string.replacingOccurrences(of:"\u{FFFC} ",with:"")
            .replacingOccurrences(of:"\u{FFFC}\t",with:"")
        setHoverHelp(accessibleText,styled:text,when:shouldShow)
    }
    private func setHoverHelp(_ text:String?,styled:NSAttributedString?,when shouldShow:(() -> Bool)?) {
        let old = objc_getAssociatedObject(self,&hoverHelpKey) as? HoverHelpTarget
        if old?.text == text,old?.styled == styled {
            old?.shouldShow = shouldShow
            return
        }
        old?.detach()
        toolTip = nil
        setAccessibilityHelp(text)
        let target = text.flatMap {$0.isEmpty ? nil : HoverHelpTarget(view:self,text:$0,styled:styled,shouldShow:shouldShow)}
        objc_setAssociatedObject(self,&hoverHelpKey,target,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension NSTextField {
    func withHoverHelpIcon(_ message:String) -> NSStackView {
        let description = stringValue+L10n.text(.app,"hoverHelp.description")
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName:"questionmark.circle",accessibilityDescription:description)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(true)
        icon.setAccessibilityLabel(description)
        icon.hoverHelp = message
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant:16),
            icon.heightAnchor.constraint(equalToConstant:16)
        ])
        let stack = NSStackView(views:[self,icon])
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 5
        return stack
    }

    var hasTruncatedText:Bool {
        guard !stringValue.isEmpty,let cell else {return false}
        let area = cell.titleRect(forBounds:bounds)
        if maximumNumberOfLines == 1 || usesSingleLineMode {
            return attributedStringValue.size().width > area.width || stringValue.contains(where:\.isNewline)
        }
        let storage = NSTextStorage(attributedString:attributedStringValue)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size:area.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = maximumNumberOfLines
        container.lineBreakMode = lineBreakMode
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        return manager.hasTruncatedText(in:container)
    }
}

extension NSButton {
    var hasTruncatedTitle:Bool {hasTruncatedTitle(in:bounds)}
    func hasTruncatedTitle(in contentBounds:NSRect) -> Bool {
        guard let cell,!title.isEmpty else {return false}
        return attributedTitle.size().width > cell.titleRect(forBounds:contentBounds).width || title.contains(where:\.isNewline)
    }
}

extension NSLayoutManager {
    func hasTruncatedText(in container:NSTextContainer) -> Bool {
        ensureLayout(for:container)
        let glyphs = glyphRange(for:container)
        if NSMaxRange(glyphs) < numberOfGlyphs {return true}
        guard glyphs.length > 0 else {return false}
        return truncatedGlyphRange(inLineFragmentForGlyphAt:NSMaxRange(glyphs)-1).location != NSNotFound
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
    let styled: NSAttributedString?
    var shouldShow:(() -> Bool)?
    private var area: NSTrackingArea!
    init(view:NSView,text:String,styled:NSAttributedString?,shouldShow:(() -> Bool)?) {
        self.view = view; self.text = text; self.styled = styled; self.shouldShow = shouldShow
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
            guard view.visibleRect.contains(view.convert(point,from:nil)),next.shouldShow?() ?? true else {return}
            self.show(next,window:window)
        }
        pending = job; DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:job)
    }
    func leave(_ previous:HoverHelpTarget) {if target === previous {dismiss()}}
    private func setTextAndMeasureWidth(_ value:String) -> CGFloat {
        let font = text.font!
        guard value.contains("\t") else {
            text.stringValue = value
            return (value as NSString).size(withAttributes:[.font:font]).width
        }
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        let rows = value.components(separatedBy:"\n").map {line in
            line.components(separatedBy:"\t").map {NSAttributedString(string:$0,attributes:attributes)}
        }
        return setAttributedTextAndMeasureWidth(InlineStatusLayout.tabbedRows(rows,font:font))
    }
    private func setAttributedTextAndMeasureWidth(_ value:NSAttributedString) -> CGFloat {
        text.attributedStringValue = value
        return value.boundingRect(with:NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude),
                                  options:[.usesLineFragmentOrigin]).width
    }
    private func show(_ help:HoverHelpTarget,window:NSWindow) {
        generation += 1; pending = nil
        panel.appearance = window.effectiveAppearance
        let mouse = NSEvent.mouseLocation
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let measuredWidth:CGFloat
        if let styled = help.styled {
            measuredWidth = setAttributedTextAndMeasureWidth(styled)
        } else {
            measuredWidth = setTextAndMeasureWidth(help.text)
        }
        let naturalWidth = measuredWidth.rounded(.up)+4
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
