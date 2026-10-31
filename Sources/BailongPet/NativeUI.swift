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
        let iconSize:CGFloat = image == nil ? 0 : min(18,max(12,(font?.pointSize ?? 13)+3))
        let iconSpace = iconSize > 0 ? iconSize+6 : 0
        let start = (bounds.width-size.width-iconSpace)/2
        if let image {
            let rect = NSRect(x:start,y:(bounds.height-iconSize)/2,width:iconSize,height:iconSize)
            let tinted = NSImage(size:rect.size,flipped:false) { bounds in
                image.draw(in:bounds)
                NSColor.white.setFill(); bounds.fill(using:.sourceIn); return true
            }
            tinted.draw(in:rect)
        }
        (title as NSString).draw(at:NSPoint(x:start+iconSpace,y:(bounds.height-size.height)/2),withAttributes:attributes)
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
        setAccessibilityLabel("关闭气泡"); target = self; action = #selector(closeBubble)
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
    var allowsInput = false
    override var canBecomeKey: Bool { allowsInput }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event:NSEvent) {
        super.sendEvent(event)
        guard allowsInput,event.type == .mouseMoved,let contentView else {return}
        let point = contentView.convert(event.locationInWindow,from:nil)
        guard contentView.bounds.insetBy(dx:6,dy:6).contains(point) else {return}
        var hit = contentView.hitTest(point)
        while let view = hit {
            if let text = view as? NSTextView,text.isEditable || text.isSelectable {NSCursor.iBeam.set(); return}
            hit = view.superview
        }
        NSCursor.arrow.set()
    }
}
// 正文与材质分开管理；切换材质不改消息、输入内容或窗口透明度。
private final class BubbleBackingView: NSView {
    var opacity: CGFloat = 1 {didSet {needsDisplay = true}}
    override var isOpaque: Bool {false}
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:14,yRadius:14).fill()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
final class BubbleBackgroundView: NSView {
    let body = NSView()
    private let ordinary = BubbleBackingView(), glassBacking = BubbleBackingView()
    private var glass: NSView?
    private var fade: Timer?
    private var targetOpacity: CGFloat = 1
    private let preferences: PetPreferences
    init(preferences: PetPreferences = .shared) {
        self.preferences = preferences
        super.init(frame:.zero)
        // 正文永远在固定根视图内；玻璃和普通背景在其下独立过渡。
        addSubview(ordinary); addSubview(body)
        for view in [ordinary,body] {view.autoresizingMask = [.width,.height]}
        NotificationCenter.default.addObserver(self,selector:#selector(preferencesChanged(_:)),name:PetPreferences.didChange,object:preferences)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(updateMaterial),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        updateMaterial()
    }
    required init?(coder:NSCoder) {fatalError()}
    override var isOpaque: Bool {false}
    @objc private func preferencesChanged(_ note: Notification) {
        let keys = note.userInfo?["keys"] as? [String] ?? []
        if !Set(keys).isDisjoint(with:["bubbleMaterial","glassFollowsSystem","glassOpacity","bubbleMotion"]) {updateMaterial()}
    }
    @objc private func updateMaterial() {
        let enabled = preferences.usesGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let next: CGFloat = enabled ? 0 : 1
        if #available(macOS 26.0, *), enabled {
            if glass == nil {
                let effect = NSGlassEffectView(frame:bounds)
                effect.autoresizingMask = [.width,.height]; effect.cornerRadius = 14
                glassBacking.autoresizingMask = [.width,.height]
                effect.contentView = glassBacking
                addSubview(effect,positioned:.below,relativeTo:ordinary); glass = effect
            }
            let effect = glass as! NSGlassEffectView
            effect.style = preferences.bool("glassFollowsSystem") ? .regular : .clear
            glassBacking.opacity = preferences.bool("glassFollowsSystem") ? 0 : CGFloat(preferences.number("glassOpacity"))
        }
        let animate = preferences.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && window?.isVisible == true
        if next == targetOpacity && fade != nil && animate {return}
        fade?.invalidate(); fade = nil; targetOpacity = next
        glass?.isHidden = false
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
        // 普通底层始终存在，先铺实再隐藏玻璃，不出现空背景帧。
        ordinary.opacity = targetOpacity; ordinary.displayIfNeeded()
        glass?.isHidden = targetOpacity == 1
        window?.invalidateShadow()
    }
    override func layout() {
        super.layout(); glass?.frame = bounds; ordinary.frame = bounds; body.frame = bounds
        glassBacking.frame = bounds
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
private enum TaskQuestionLayout {
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
                let badge = option.recommended ? text("推荐",detailFont,34*scale,color:AppAccent.color) : nil
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

final class Bubble {
    let window: PetWindow
    private lazy var motion = BubbleMotion(window:window,preferences:preferences)
    private var placement: (CGRect, String?, CGRect, NSSize)?
    private var placementSide:BubblePlacement.Side?
    private var placementArea:CGRect?
    var targetFrame: NSRect {motion.frame}
    func move(to origin: NSPoint) {motion.move(to:origin)}
    private let title = label("", bold:true)
    private let text = StreamingTextView()
    private let scroll = NSScrollView()
    private let closeButton = BubbleCloseButton()
    private var details: ActionButton!
    private var codexButton: ActionButton!
    private var retryButton: ActionButton!
    private var timer: Timer?
    private var headingTimer: Timer?
    private var plainHeading = ""
    private var headingPhase = 0
    private var headingStarted = 0.0
    private let elapsedIcon = NSImageView()
    private let elapsedLabel = NSTextField(labelWithString:"00:00")
    private var elapsedTimer: Timer?
    private var taskStartedAt: Date?
    private var taskFinishedAt: Date?
    private var timedTaskKey: String?
    private var layoutBodyHeight = 0.0
    private var elapsedLayoutWidth = 0.0
    private let headingFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var scale = 1.0
    var preferences = PetPreferences.shared
    var purpose: MessagePurpose = .interaction
    var relatedConversation: String?
    var fileLinkDirectory: (() -> URL?)? {didSet {text.linkBaseDirectory = fileLinkDirectory}}
    private var currentBody = ""
    private var questionForm:QuestionForm?
    private var previousQuestion:ActionButton!
    private var skipQuestion:ActionButton!
    var onQuestionsSkipped: ((Set<String>) -> Void)?
    private var questionModels = [TaskQuestion]()
    private var questionSize:NSSize?
    private var questionTaskKey:String?
    private var pendingAttention = false
    private let resizeDelegate = QuestionResizeDelegate()
    var onQuestionSubmit: (([String:String], @escaping (Error?) -> Void) -> Void)?
    var onClose: () -> Void = {}
    var onDetails: () -> Void = {}
    var onCodex: () -> Void = {CodexConnection.openDesktop()}
    var kind = ""
    var visible: Bool { motion.presented }
    func resolveQuestions(taskKey:String? = nil) {
        guard taskKey == nil || questionTaskKey == taskKey else {return}
        questionForm = nil; questionModels = []; questionSize = nil; onQuestionSubmit = nil
        pendingAttention = false; questionTaskKey = nil
        hide()
    }
    init() {
        window = PetWindow(contentRect:NSRect(x:0,y:0,width:320,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.hidesOnDeactivate = false
        window.worksWhenModal = true; window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces,.ignoresCycle,.fullScreenNone]
        window.delegate = resizeDelegate
        resizeDelegate.resized = { [weak self] in
            guard let self,!self.questionModels.isEmpty else {return}
            self.questionSize = self.window.frame.size; self.motion.adoptUserFrame()
            self.layoutQuestions()
        }
        let content = BubbleBackgroundView()
        window.contentView = content
        text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width:0,height:2)
        text.textColor = .labelColor
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        closeButton.onClose = { [weak self] in self?.hide(); self?.onClose() }
        details = ActionButton("查看记录详情") { [weak self] in
            guard let self else{return}
            if let form = self.questionForm,let submit = self.onQuestionSubmit {
                if !form.isLast {form.advance(); return}
                self.window.makeFirstResponder(nil)
                guard form.complete else {return}
                if form.answers.isEmpty {self.onQuestionsSkipped?(form.skippedIDs); self.hide(); return}
                form.setEnabled(false); self.previousQuestion.isEnabled = false; self.skipQuestion.isEnabled = false; self.details.isEnabled = false; self.details.title = "正在提交…"
                submit(form.answers) { [weak self,weak form] error in
                    guard let self,let form,self.questionForm === form else {return}
                    if let error {form.setEnabled(true); self.previousQuestion.isEnabled = form.canGoBack; self.skipQuestion.isEnabled = true; self.details.isEnabled = true; self.details.title = "提交回答"; showError("回答未提交",error)}
                    else {self.onQuestionsSkipped?(form.skippedIDs); self.questionForm = nil; self.onQuestionSubmit = nil; self.hide()}
                }
                return
            }
            let action = self.onDetails
            self.hide(); self.onClose(); action()
        }
        previousQuestion = ActionButton("上一题") { [weak self] in self?.questionForm?.previousPage() }
        skipQuestion = ActionButton("跳过") { [weak self] in self?.questionForm?.skipPage() }
        previousQuestion.isHidden = true; skipQuestion.isHidden = true
        details.keepsAccentWhenInactive = true
        codexButton = ActionButton("转到 Codex") { [weak self] in
            guard let self else {return}
            let action = self.onCodex
            self.hide(); self.onClose(); action()
        }
        codexButton.image = AppIcons.openAI; codexButton.imagePosition = .imageLeading; codexButton.imageScaling = .scaleProportionallyDown
        codexButton.keepsAccentWhenInactive = true
        retryButton = ActionButton("重试") {}; retryButton.keepsAccentWhenInactive = true; retryButton.emphasize(); retryButton.isHidden = true
        elapsedIcon.image = NSImage(systemSymbolName:"stopwatch",accessibilityDescription:"任务已处理时间")
        elapsedIcon.contentTintColor = .secondaryLabelColor
        elapsedLabel.alignment = .right; elapsedLabel.textColor = .secondaryLabelColor
        elapsedIcon.isHidden = true; elapsedLabel.isHidden = true
        for v in [title,scroll,closeButton,details,codexButton,retryButton,elapsedIcon,elapsedLabel,previousQuestion!,skipQuestion!] as [NSView] { content.body.addSubview(v) }
    }
    private func layout(bodyHeight: Double) {
        layoutBodyHeight = bodyHeight
        let w = min(questionSize?.width ?? 320*scale,placementArea?.width ?? .greatestFiniteMagnitude), margin = 16*scale
        let hasElapsed = taskStartedAt != nil
        let elapsedWidth = hasElapsed ? elapsedGroupWidth : 0
        elapsedLayoutWidth = elapsedWidth
        let headingWidth = w-margin*2-32*scale-(hasElapsed ? elapsedWidth+10*scale : 0)
        let font = title.font!
        let firstLineHeight = (font.ascender-font.descender+font.leading).rounded(.up)+4
        let headingHeight = max(firstLineHeight,title.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:headingWidth,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up))
        let footer = details.isHidden && codexButton.isHidden && retryButton.isHidden ? 0 : 42.0+(previousQuestion.isHidden ? 0 : 34*scale)
        // 关闭、标题首行与计时同一行；标题按剩余宽度换行，不缩字或截断。
        let h = min(questionSize?.height ?? (margin*2+headingHeight+(bodyHeight > 0 ? 12*scale+bodyHeight : 0)+footer),placementArea?.height ?? .greatestFiniteMagnitude)
        let chromeHeight = margin*2+headingHeight+(bodyHeight > 0 ? 12*scale : 0)+footer
        motion.onResize = { [weak self] size in
            guard let self else {return}
            let height = size.height
            self.title.frame = NSRect(x:margin+32*scale,y:height-margin-headingHeight,width:headingWidth,height:headingHeight)
            if hasElapsed {self.layoutElapsed(in:size)}
            let closeSide = 24*scale
            self.closeButton.frame = NSRect(x:margin-2*scale,y:height-margin-firstLineHeight/2-closeSide/2,width:closeSide,height:closeSide)
            self.closeButton.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭气泡")?.withSymbolConfiguration(.init(pointSize:13*scale,weight:.regular))
            let textHeight = max(0,height-chromeHeight)
            self.scroll.frame = NSRect(x:margin,y:margin+footer,width:w-2*margin,height:textHeight)
            self.scroll.isHidden = bodyHeight <= 0
            self.text.frame.size.width = self.scroll.contentSize.width
            self.text.textContainer?.containerSize = NSSize(width:self.scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
            self.previousQuestion.frame = NSRect(x:margin,y:44,width:76*scale,height:28*scale)
            self.skipQuestion.frame = NSRect(x:w-margin-64*scale,y:44,width:64*scale,height:28*scale)
            self.retryButton.frame = NSRect(x:w-margin-82,y:12,width:82,height:28)
            if !self.codexButton.isHidden && self.details.isHidden {
                self.codexButton.frame = NSRect(x:margin,y:12,width:w-2*margin,height:28)
            } else if !self.codexButton.isHidden {
                let gap = 8*scale, width = (w-2*margin-gap)/2
                self.codexButton.frame = NSRect(x:margin,y:12,width:width,height:28)
                self.details.frame = NSRect(x:margin+width+gap,y:12,width:width,height:28)
            } else {
                self.details.frame = self.retryButton.isHidden ? NSRect(x:margin,y:12,width:w-2*margin,height:28) : NSRect(x:margin,y:12,width:w-2*margin-94,height:28)
            }
        }
        motion.resize(to:NSSize(width:w,height:h))
    }
    private func layoutQuestions() {
        let scrollbar = scroll.scrollerStyle == .legacy ? NSScroller.scrollerWidth(for:.regular,scrollerStyle:.legacy) : 0
        let width = min(questionSize?.width ?? 320*scale,placementArea?.width ?? .greatestFiniteMagnitude)-32*scale-scrollbar
        let document:NSView
        if let questionForm {questionForm.reflow(width:width); document = questionForm}
        else {document = TaskQuestionLayout.document(questionModels,width:width,scale:scale,fontSize:preferences.number("messageFontSize")*scale)}
        scroll.documentView = document
        layout(bodyHeight:min(320*scale,document.frame.height))
    }

    func show(title heading: String, body: String = "", kind: String, scale: Double, seconds: Double = 4, details enabled: Bool = false, followsText: Bool = true, resetText: Bool = false, animateHeading: Bool = false, taskStartedAt: Date? = nil, taskKey: String? = nil, taskFinishedAt: Date? = nil, taskStatus: String? = nil, attentionAction: Bool = false, questions:[TaskQuestion] = []) {
        timer?.invalidate()
        if !visible || kind == "interaction" {placement = nil; placementSide = nil}
        let same = self.kind == kind && scroll.documentView === text && text.automaticallyFollowsEnd == followsText
        text.automaticallyFollowsEnd = followsText
        self.kind = kind; self.scale = scale
        pendingAttention = attentionAction
        let sameQuestions = questionTaskKey == taskKey && questionModels.map(\.id) == questions.map(\.id) && questionModels.map(\.prompt) == questions.map(\.prompt)
        if !sameQuestions {questionForm = nil; questionSize = nil}
        questionTaskKey = taskKey; questionModels = questions
        if !questions.isEmpty {
            window.styleMask.insert(.resizable); window.minSize = NSSize(width:320*scale,height:220*scale)
            window.maxSize = window.screen?.visibleFrame.insetBy(dx:8,dy:8).size ?? NSSize(width:1200,height:900)
        }
        else {window.styleMask.remove(.resizable)}
        previousQuestion.isHidden = true; skipQuestion.isHidden = true
        window.allowsInput = !questions.isEmpty && onQuestionSubmit != nil
        configureElapsed(start:taskStartedAt,key:taskKey,finished:taskFinishedAt,status:taskStatus)
        // 只有任务消息正文允许复制；互动、额度加载及一般提示不参与文本选择。
        text.isSelectable = kind == "task"
        if !text.isSelectable {text.setSelectedRange(NSRange(location:0,length:0))}
        currentBody = body; relatedConversation = nil
        if scroll.documentView !== text {scroll.documentView = text}
        title.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale,weight:.semibold)
        setHeading(heading, animated: animateHeading)
        text.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale)
        details.title = "查看记录详情"; details.isEnabled = true; details.isHidden = !enabled || attentionAction; details.emphasize(); retryButton.isHidden = true
        codexButton.isHidden = !enabled; codexButton.emphasize(attentionAction)
        details.font = .systemFont(ofSize:13*scale); codexButton.font = details.font
        if attentionAction && !questions.isEmpty {
            text.finishReveal()
            if onQuestionSubmit != nil && questions.allSatisfy({!$0.id.isEmpty}) {
                if questionForm == nil {questionForm = QuestionForm(questions:questions,width:288*scale,scale:scale,fontSize:preferences.number("messageFontSize")*scale)}
                questionForm?.onChange = { [weak self] in
                    guard let self,let form = self.questionForm else {return}
                    self.details.isEnabled = form.canAdvance; self.details.title = form.actionTitle
                    self.previousQuestion.isEnabled = form.canGoBack; self.skipQuestion.isEnabled = form.canSkip
                }
                questionForm?.onNavigate = { [weak self] in
                    guard let self else {return}; self.layoutQuestions()
                    self.scroll.contentView.scroll(to:.zero); self.scroll.reflectScrolledClipView(self.scroll.contentView)
                }
                questionForm?.onSkipAll = { [weak self] in
                    guard let self,let form = self.questionForm else {return}
                    self.onQuestionsSkipped?(form.skippedIDs); self.hide()
                }
                previousQuestion.isHidden = false; skipQuestion.isHidden = false
                previousQuestion.isEnabled = questionForm?.canGoBack == true; skipQuestion.isEnabled = true
                questionForm?.onSubmit = { [weak self] in self?.details.performClick(nil) }
                details.title = questionForm?.actionTitle ?? "提交回答"; details.isHidden = false; details.isEnabled = questionForm?.canAdvance == true
                codexButton.emphasize(false)
            }
            layoutQuestions()
            scroll.contentView.scroll(to:.zero); scroll.reflectScrolledClipView(scroll.contentView)
        } else {
            let rendered = kind == "task" ? MarkdownText.render(body,font:text.font!,lineSpacing:2,paragraphSpacing:6) : NSAttributedString(string:body,attributes:[.font:text.font!,.foregroundColor:NSColor.labelColor])
            let height = body.isEmpty ? 0 : min(180*scale,max(24*scale,rendered.boundingRect(with:NSSize(width:288*scale-12,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height+12))
            layout(bodyHeight:height)
            text.setContent(rendered,animated:preferences.bool("typingEffect") && kind == "task" && followsText,reset:!same || resetText)
        }
        motion.show()
        startCountdown(attentionAction ? 0 : seconds)
    }
    private func setHeading(_ heading: String, animated: Bool) {
        if plainHeading != heading || headingTimer == nil {headingStarted = ProcessInfo.processInfo.systemUptime}
        plainHeading = heading
        if !animated {
            headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0
            title.stringValue = heading; return
        }
        renderAnimatedHeading()
        guard headingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.headingPhase = Int((ProcessInfo.processInfo.systemUptime-self.headingStarted)*10) % self.headingFrames.count
            self.renderAnimatedHeading()
        }
        headingTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func renderAnimatedHeading() {
        let value = NSMutableAttributedString(string:headingFrames[headingPhase] + " " + plainHeading,
            attributes:[.font:title.font ?? NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:NSColor.labelColor])
        value.addAttribute(.foregroundColor,value:AppAccent.color,range:NSRange(location:0,length:1))
        if preferences.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // 1.2 秒扫过，2.8 秒停顿；前两字符是盲文和空格，不参与流水。
            let phase = (ProcessInfo.processInfo.systemUptime-headingStarted).truncatingRemainder(dividingBy:4)
            let center = -0.25+1.5*(phase/1.2)
            let dark = title.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
            var offset = 2
            let count = max(1,plainHeading.count-1)
            for (index,character) in plainHeading.enumerated() {
                let length = (String(character) as NSString).length
                let distance = (Double(index)/Double(count)-center)/0.18
                let strength = phase < 1.2 ? exp(-distance*distance) : 0
                // 浅色界面用深字浅扫；深色界面用灰字亮扫，亮带方向一致。
                let opacity = dark ? 0.58+0.42*strength : 1-0.55*strength
                value.addAttribute(.foregroundColor,value:NSColor.labelColor.withAlphaComponent(opacity),range:NSRange(location:offset,length:length))
                offset += length
            }
        }
        title.attributedStringValue = value
    }
    private func configureElapsed(start: Date?, key: String?, finished: Date?, status: String?) {
        if start == taskStartedAt && key == timedTaskKey && finished == taskFinishedAt && elapsedTimer != nil {return}
        elapsedTimer?.invalidate(); elapsedTimer = nil
        taskStartedAt = start; timedTaskKey = key; taskFinishedAt = finished
        setElapsedColor(finished == nil ? nil : status)
        elapsedIcon.isHidden = start == nil; elapsedLabel.isHidden = start == nil
        guard start != nil else {return}
        refreshElapsed()
        guard finished == nil else {return}
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.refreshElapsed() }
        elapsedTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private var elapsedGroupWidth: CGFloat {
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.regular)
        elapsedLabel.maximumNumberOfLines = 1; elapsedLabel.usesSingleLineMode = true
        return elapsedLabel.fittingSize.width+16*scale
    }
    private func setElapsedColor(_ status: String?) {
        let color: NSColor = status == "completed" ? .systemGreen : ["failed","interrupted","cancelled","canceled"].contains(status ?? "") ? .systemRed : .secondaryLabelColor
        elapsedIcon.contentTintColor = color; elapsedLabel.textColor = color
    }
    private func layoutElapsed(in size: NSSize) {
        let margin = 16*scale, side = 13*scale
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.regular)
        elapsedLabel.maximumNumberOfLines = 1; elapsedLabel.usesSingleLineMode = true
        let textSize = elapsedLabel.fittingSize
        // 使用原生标签的第一行基线，不以整个多行标题的矩形中心对齐。
        let baseline = title.alignmentRect(forFrame:title.frame).maxY-title.firstBaselineOffsetFromTop
        elapsedLabel.frame = NSRect(x:size.width-margin-textSize.width,y:0,width:textSize.width,height:textSize.height)
        let elapsedBaseline = elapsedLabel.alignmentRect(forFrame:elapsedLabel.frame).maxY-elapsedLabel.firstBaselineOffsetFromTop
        elapsedLabel.frame.origin.y = baseline-elapsedBaseline
        elapsedIcon.frame = NSRect(x:elapsedLabel.frame.minX-3*scale-side,y:elapsedLabel.frame.midY-side/2,width:side,height:side)
    }
    private func refreshElapsed() {
        guard let start = taskStartedAt else {return}
        let seconds = max(0,Int((taskFinishedAt ?? Date()).timeIntervalSince(start)))
        elapsedLabel.stringValue = seconds >= 3600
            ? String(format:"%d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60)
            : String(format:"%02d:%02d",seconds/60,seconds%60)
        elapsedLabel.setAccessibilityLabel("已处理 "+elapsedLabel.stringValue)
        if visible && abs(elapsedGroupWidth-elapsedLayoutWidth) > 0.5 {layout(bodyHeight:layoutBodyHeight)}
        layoutElapsed(in:window.frame.size)
    }
    func finishTask(_ key: String, status: String) {
        guard timedTaskKey == key else {return}
        taskFinishedAt = Date(); setElapsedColor(status)
        refreshElapsed(); elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil
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
    func refreshDuration() {if visible {startCountdown(pendingAttention ? 0 : preferences.duration(purpose,text:currentBody))}}
    func showFailure(_ failure: AppFailure, scale: Double, retry: (() -> Void)? = nil, taskStartedAt: Date? = nil, taskFinishedAt: Date? = nil, taskStatus: String? = nil) {
        onDetails = {failure.showDetails()}
        show(title:taskStatus.map {preferences.taskResultLine($0)} ?? failure.title,body:failure.message,kind:"error",scale:scale,seconds:0,details:true,taskStartedAt:taskStartedAt,taskFinishedAt:taskFinishedAt,taskStatus:taskStatus)
        purpose = .attention
        details.title = "技术详情…"
        codexButton.isHidden = true
        if let retry {retryButton.title = "重试"; retryButton.isHidden = false; retryButton.callback = retry}
        else if failure.openDesktop {retryButton.title = "打开 Codex"; retryButton.isHidden = false; retryButton.callback = {CodexConnection.openDesktop()}}
        layout(bodyHeight:scroll.frame.height)
    }
    func quotaRows(_ overview: QuotaOverview, scale: Double, failure: AppFailure? = nil, retry: (() -> Void)? = nil) {
        let fontScale = scale*preferences.number("messageFontSize")/13
        if let failure {
            purpose = .attention; timer?.invalidate(); timer = nil
            codexButton.isHidden = true
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
        let area = screen.visibleFrame.insetBy(dx:8,dy:8)
        if placementArea != area {
            placementArea = area
            if !questionModels.isEmpty {
                window.maxSize = area.size
                if let size = questionSize {questionSize = NSSize(width:min(size.width,area.width),height:min(size.height,area.height))}
                layoutQuestions()
            } else {layout(bodyHeight:layoutBodyHeight)}
        }
        let size = motion.frame.size
        if let previous = placement,previous.0 == rect,previous.1 == dock,previous.2 == area,previous.3 == size {return}
        let preferred:[BubblePlacement.Side]
        if dock == "left" {preferred = [.right,.above,.below,.left]}
        else if dock == "right" {preferred = [.left,.above,.below,.right]}
        else if kind.hasPrefix("quota") {preferred = [.right,.left,.above,.below]}
        else if kind == "task" || kind == "preview" {preferred = [.left,.right,.above,.below]}
        else {preferred = [.above,.below,.right,.left]}
        let oldSide = placement?.1 == dock ? placementSide : nil
        let result = BubblePlacement.resolve(size:size,pet:rect,screen:screen.visibleFrame,preferred:preferred,previous:oldSide)
        // 仅正文高度变化、原位置仍安全时保持位置；拖动、越界和遮挡时重新选边。
        let current = CGRect(origin:motion.frame.origin,size:size)
        let keepOrigin = placement.map {$0.0 == rect && $0.1 == dock && $0.2 == area} == true
            && area.contains(current) && !current.intersects(rect.insetBy(dx:-4,dy:-4))
        if !keepOrigin {move(to:result.frame.origin); placementSide = result.side}
        placement = (rect,dock,area,size)
    }
    deinit { timer?.invalidate(); headingTimer?.invalidate(); elapsedTimer?.invalidate() }
    func hide() {elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil; text.finishReveal(); headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0; timer?.invalidate(); motion.hide(); placement = nil; placementSide = nil; kind = ""; relatedConversation = nil}
}
