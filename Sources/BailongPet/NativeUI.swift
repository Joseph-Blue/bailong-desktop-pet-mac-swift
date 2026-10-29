import AppKit

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
    private var prominent = false
    var keepsAccentWhenInactive = false {didSet {updateAccent()}}
    init(_ title: String, _ callback: @escaping () -> Void) {
        self.callback = callback; super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; target = self; action = #selector(invokeCallback)
        NotificationCenter.default.addObserver(self,selector:#selector(updateAccent),name:AppAccent.didChange,object:nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    func emphasize(_ enabled: Bool = true) {prominent = enabled; updateAccent()}
    @objc private func updateAccent() {
        bezelColor = prominent ? AppAccent.color : nil
        isBordered = !(prominent && keepsAccentWhenInactive); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard prominent && keepsAccentWhenInactive else {super.draw(dirtyRect); return}
        let color = isHighlighted ? AppAccent.color.blended(withFraction:0.15,of:.black) ?? AppAccent.color : AppAccent.color
        color.withAlphaComponent(isEnabled ? 1 : 0.45).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:0,dy:1),xRadius:7,yRadius:7).fill()
        let attributes: [NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.white]
        let size = (title as NSString).size(withAttributes:attributes)
        (title as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
    @objc func invokeCallback() { callback() }
}
final class BubbleCloseButton: NSButton {
    var onClose: () -> Void = {}
    private var tracking: NSTrackingArea?
    private var hovering = false
    init() {
        super.init(frame:.zero)
        title = ""; image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭气泡")
        imagePosition = .imageOnly; isBordered = false; contentTintColor = .secondaryLabelColor
        toolTip = "关闭气泡"; target = self; action = #selector(closeBubble)
    }
    required init?(coder: NSCoder) {fatalError()}
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
            NSBezierPath(ovalIn:bounds.insetBy(dx:1,dy:1)).fill()
        }
        super.draw(dirtyRect)
    }
    @objc private func closeBubble() {onClose()}
}
final class TopDownView: NSView {override var isFlipped: Bool {true}}
final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
// 单层绘制透明圆角，避免 NSVisualEffectView 的边缘高光与圆角裁切叠出白边。
final class BubbleBackgroundView: NSView {
    override var isOpaque: Bool {false}
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect:bounds,xRadius:14,yRadius:14).fill()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
final class Bubble {
    let window: PetWindow
    private let title = label("", bold:true)
    private let text = StreamingTextView()
    private let scroll = NSScrollView()
    private let closeButton = BubbleCloseButton()
    private var details: ActionButton!
    private var retryButton: ActionButton!
    private var timer: Timer?
    private var scale = 1.0
    var preferences = PetPreferences.shared
    var purpose: MessagePurpose = .interaction
    var relatedConversation: String?
    private var currentBody = ""
    var onClose: () -> Void = {}
    var onDetails: () -> Void = {}
    var kind = ""
    var visible: Bool { window.isVisible }
    init() {
        window = PetWindow(contentRect:NSRect(x:0,y:0,width:320,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces,.ignoresCycle,.fullScreenNone]
        let content = BubbleBackgroundView()
        window.contentView = content
        text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width:0,height:2)
        text.textColor = .labelColor
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        closeButton.onClose = { [weak self] in self?.hide(); self?.onClose() }
        details = ActionButton("详情") { [weak self] in
            guard let self else{return}
            let action = self.onDetails
            self.hide(); self.onClose(); action()
        }
        details.keepsAccentWhenInactive = true
        retryButton = ActionButton("重试") {}; retryButton.keepsAccentWhenInactive = true; retryButton.emphasize(); retryButton.isHidden = true
        for v in [title,scroll,closeButton,details,retryButton] as [NSView] { content.addSubview(v) }
    }
    private func layout(bodyHeight: Double) {
        let w = 320*scale, margin = 16*scale
        let headingWidth = w-margin*2-32*scale
        let font = title.font!
        let firstLineHeight = (font.ascender-font.descender+font.leading).rounded(.up)+4
        let headingHeight = max(firstLineHeight,(title.stringValue as NSString).boundingRect(with:NSSize(width:headingWidth,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height.rounded(.up)+4)
        let footer = details.isHidden && retryButton.isHidden ? 0 : 42.0
        let h = margin*2+headingHeight+(bodyHeight > 0 ? 12*scale+bodyHeight : 0)+footer
        window.setContentSize(NSSize(width:w,height:h))
        title.frame = NSRect(x:margin+32*scale,y:h-margin-headingHeight,width:headingWidth,height:headingHeight)
        let closeSide = 24*scale
        closeButton.frame = NSRect(x:margin-2*scale,y:h-margin-firstLineHeight/2-closeSide/2,width:closeSide,height:closeSide)
        closeButton.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭气泡")?.withSymbolConfiguration(.init(pointSize:13*scale,weight:.regular))
        scroll.frame = NSRect(x:margin,y:margin+footer,width:w-2*margin,height:bodyHeight)
        scroll.isHidden = bodyHeight <= 0
        text.frame.size.width = scroll.contentSize.width
        text.textContainer?.containerSize = NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
        retryButton.frame = NSRect(x:w-margin-82,y:12,width:82,height:28)
        details.frame = retryButton.isHidden ? NSRect(x:margin,y:12,width:w-2*margin,height:28) : NSRect(x:margin,y:12,width:w-2*margin-94,height:28)
    }
    func show(title heading: String, body: String = "", kind: String, scale: Double, seconds: Double = 4, details enabled: Bool = false, followsText: Bool = true, resetText: Bool = false) {
        timer?.invalidate()
        let same = self.kind == kind && scroll.documentView === text && text.automaticallyFollowsEnd == followsText
        text.automaticallyFollowsEnd = followsText
        self.kind = kind; self.scale = scale
        // 只有任务消息正文允许复制；互动、额度加载及一般提示不参与文本选择。
        text.isSelectable = kind == "task"
        if !text.isSelectable {text.setSelectedRange(NSRange(location:0,length:0))}
        currentBody = body; relatedConversation = nil
        if scroll.documentView !== text {scroll.documentView = text}
        title.stringValue = heading; title.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale,weight:.semibold)
        text.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale)
        details.title = "详情"; details.isHidden = !enabled; details.emphasize(); retryButton.isHidden = true
        let rendered = kind == "task" ? MarkdownText.render(body,font:text.font!,lineSpacing:2,paragraphSpacing:6) : NSAttributedString(string:body,attributes:[.font:text.font!,.foregroundColor:NSColor.labelColor])
        let height = body.isEmpty ? 0 : min(180*scale,max(24*scale,rendered.boundingRect(with:NSSize(width:288*scale-12,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height+12))
        layout(bodyHeight:height)
        text.setContent(rendered,animated:preferences.bool("typingEffect") && kind == "task" && followsText,reset:!same || resetText)
        window.orderFrontRegardless()
        startCountdown(seconds)
    }
    private func startCountdown(_ seconds: Double) {
        timer?.invalidate(); timer = nil
        guard seconds > 0 else {return}
        var remaining = seconds, previous = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else {return}
            let now = ProcessInfo.processInfo.systemUptime, delta = now-previous; previous = now
            let hovering = self.preferences.bool("pauseOnHover") && self.window.frame.contains(NSEvent.mouseLocation)
            if hovering || self.preferences.bool("countAfterReveal") && self.text.isRevealing {return}
            remaining -= delta
            if remaining <= 0 {self.hide(); self.onClose()}
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func finishTyping() {text.finishReveal()}
    func refreshDuration() {if visible {startCountdown(preferences.duration(purpose,text:currentBody))}}
    func showFailure(_ failure: AppFailure, scale: Double, retry: (() -> Void)? = nil) {
        onDetails = {failure.showDetails()}
        show(title:failure.title,body:failure.message,kind:"error",scale:scale,seconds:0,details:true)
        purpose = .attention
        details.title = "技术详情…"
        if let retry {retryButton.title = "重试"; retryButton.isHidden = false; retryButton.callback = retry}
        else if failure.openDesktop {retryButton.title = "打开 Codex"; retryButton.isHidden = false; retryButton.callback = {CodexConnection.openDesktop()}}
        layout(bodyHeight:scroll.frame.height)
    }
    func quotaRows(_ overview: QuotaOverview, scale: Double, failure: AppFailure? = nil, retry: (() -> Void)? = nil) {
        let fontScale = scale*preferences.number("messageFontSize")/13
        if let failure {
            purpose = .attention; timer?.invalidate(); timer = nil
            onDetails = {failure.showDetails()}; details.title = "技术详情…"; details.isHidden = false; details.emphasize(false)
            if let retry {retryButton.title = "重试"; retryButton.callback = retry; retryButton.isHidden = false}
        }
        let width = scroll.frame.width - (scroll.scrollerStyle == .legacy ? NSScroller.scrollerWidth(for:.regular,scrollerStyle:.legacy) : 0)
        let content = TopDownView(frame:NSRect(x:0,y:0,width:width,height:1))
        var y = 0.0
        @discardableResult func addText(_ value: String, font: NSFont, color: NSColor = .labelColor) -> CGFloat {
            let text = label(value); text.font = font; text.textColor = color
            let height = max(font.pointSize+5,(value as NSString).boundingRect(with:NSSize(width:width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height.rounded(.up)+3)
            text.frame = NSRect(x:0,y:y,width:width,height:height); content.addSubview(text); y += height
            return height
        }
        addText("套餐 · "+overview.plan,font:.systemFont(ofSize:13*fontScale,weight:.semibold)); y += 12*scale
        for (index,row) in overview.rows.enumerated() {
            if index > 0 {
                let line = NSBox(frame:NSRect(x:0,y:y,width:width,height:1)); line.boxType = .separator; content.addSubview(line); y += 12*scale
            }
            let headingFont = NSFont.systemFont(ofSize:12*fontScale,weight:.medium)
            let amountFont = NSFont.monospacedDigitSystemFont(ofSize:13*fontScale,weight:.semibold)
            // 使用单行原生标签的 fittingSize，包含文字单元格内边距；
            // 只按 NSString 字宽分配空间会让“剩余 55%”换行并被固定行高裁掉。
            let heading = NSTextField(labelWithString:row.title); heading.font = headingFont
            let amount = NSTextField(labelWithString:row.value); amount.font = amountFont; amount.alignment = .right
            for field in [heading,amount] {
                field.maximumNumberOfLines = 1; field.usesSingleLineMode = true
                field.lineBreakMode = .byTruncatingTail; field.toolTip = field.stringValue
            }
            let gap = 12*scale
            let headingMinimum = min(heading.fittingSize.width,96*scale)
            let amountWidth = min(amount.fittingSize.width.rounded(.up),width-headingMinimum-gap)
            let rowHeight = max(22*scale,max(heading.fittingSize.height,amount.fittingSize.height).rounded(.up))
            heading.frame = NSRect(x:0,y:y,width:width-amountWidth-gap,height:rowHeight)
            amount.frame = NSRect(x:width-amountWidth,y:y,width:amountWidth,height:rowHeight)
            content.addSubview(heading); content.addSubview(amount); y += rowHeight
            if let amount = row.remaining {
                y += 4*scale
                let bar = AccentProgressIndicator(frame:NSRect(x:0,y:y,width:width,height:9*scale))
                bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = amount
                content.addSubview(bar); y += 16*scale
            }
            if let detail = row.detail {addText(detail,font:.systemFont(ofSize:11*fontScale),color:.secondaryLabelColor)}
            y += 12*scale
        }
        if let notice = overview.notice {addText(notice,font:.systemFont(ofSize:11*fontScale,weight:.medium))}
        content.frame.size.height = y
        layout(bodyHeight:min(320*scale,y))
        scroll.documentView = content; scroll.contentView.scroll(to:.zero)
    }
    func place(near rect: CGRect, screen: NSScreen, dock: String?) {
        let a = screen.visibleFrame, s = window.frame.size
        var x = rect.midX-s.width/2, y = rect.maxY+10
        if dock == "left" {x = rect.maxX+10; y = rect.midY-s.height/2}
        else if dock == "right" {x = rect.minX-s.width-10; y = rect.midY-s.height/2}
        else if kind == "quota" {
            // 额度在桌宠右侧显示；右侧放不下时切到左侧。
            x = rect.maxX+10; y = rect.midY-s.height/2
            if x+s.width > a.maxX {x = rect.minX-s.width-10}
        }
        else if kind == "task" || kind == "preview" {
            x = rect.minX-s.width-10; y = rect.midY-s.height/2
            if x < a.minX {x = rect.maxX+10}
        }
        else if y+s.height > a.maxY {y = rect.minY-s.height-10}
        let origin = NSPoint(x:max(a.minX,min(x,a.maxX-s.width)).rounded(),y:max(a.minY,min(y,a.maxY-s.height)).rounded())
        if origin != window.frame.origin {window.setFrameOrigin(origin)}
    }
    func hide() {text.finishReveal(); timer?.invalidate(); window.orderOut(nil); kind = ""; relatedConversation = nil}
}
