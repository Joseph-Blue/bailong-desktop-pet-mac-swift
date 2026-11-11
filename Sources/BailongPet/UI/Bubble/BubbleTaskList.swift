import AppKit

struct BubbleTaskSummary: Equatable {
    let key:String, title:String, threadID:String?, status:String
    let start:Date
    let end:Date?
    var turnID:String? = nil
    var activity:TaskActivity? = nil
    var connectionFailed = false
    var activityLine:String? {active && activity?.visible == true ? activity?.line : nil}
    var active:Bool {activeStatuses.contains(status)}
}

struct BubbleTaskOverview: Equatable {
    var tasks = [BubbleTaskSummary]()
    var status:String? = nil
}

// 平面列表嵌入气泡正文，整行可点击；不为每个任务添加卡片边框。
final class BubbleTaskList: NSView {
    override var isFlipped:Bool {true}
    var provider:() -> BubbleTaskOverview = {BubbleTaskOverview()}
    var onResize:((CGFloat) -> Void)?
    private var timer:Timer?
    private var overview:BubbleTaskOverview?
    private var recentLimit = 0
    private var progressTemplates = [String]()
    private var rows = [BubbleTaskRow]()
    private var tick = 0
    private let scale:CGFloat
    init(width:CGFloat,scale:CGFloat,provider:@escaping () -> BubbleTaskOverview) {
        self.scale = scale; self.provider = provider
        super.init(frame:NSRect(x:0,y:0,width:width,height:1))
        rebuild()
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func start() {
        stop(); rebuild()
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else {return}; self.tick += 1
            if self.tick % 2 == 0 {self.rebuild()}
            let animated = ProgressTextEffects.enabled
            for row in self.rows {row.refresh(frame:animated ? self.tick % 10 : 0)}
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func stop() {timer?.invalidate(); timer = nil; rows.forEach {$0.stopMotion()}}
    private func rebuild() {
        var incoming = provider()
        incoming.tasks = incoming.tasks.map {task in var task = task; if task.activity?.visible != true {task.activity = nil}; return task}
        let limit = Int(PetPreferences.shared.number("recentTaskCount"))
        let templates = [PetPreferences.shared.statusLine("taskThinkingTemplate"),PetPreferences.shared.statusLine("taskToolTemplate"),PetPreferences.shared.statusLine("taskCommandTemplate"),PetPreferences.shared.statusLine("taskCommandCompletedTemplate")]
        guard incoming != overview || limit != recentLimit || templates != progressTemplates || subviews.isEmpty else {return}
        overview = incoming; recentLimit = limit; progressTemplates = templates
        let records = incoming.tasks; let previousRows = rows; subviews.forEach {$0.removeFromSuperview()}; rows = []
        var y:CGFloat = 0
        for (index,section) in [("正在执行的任务：",records.filter(\.active)),("近期执行结束的任务：",Array(records.filter {!$0.active}.prefix(limit)))].enumerated() {
            if index > 0 {y += 14*scale}
            let heading = label(section.0,bold:true); heading.font = .systemFont(ofSize:12*scale,weight:.medium)
            heading.frame = NSRect(x:0,y:y,width:bounds.width,height:22*scale); addSubview(heading); y += 26*scale
            if section.1.isEmpty {
                let empty = label(incoming.status ?? (index == 0 ? "暂无正在执行的任务" : "暂无近期结束的任务"))
                empty.font = .systemFont(ofSize:11*scale); empty.textColor = .secondaryLabelColor
                let height = max(22*scale,empty.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:bounds.width,height:.greatestFiniteMagnitude)).height.rounded(.up))
                empty.frame = NSRect(x:0,y:y,width:bounds.width,height:height); addSubview(empty); y += height
            }
            for task in section.1 {
                let row = previousRows.first(where:{$0.task.key == task.key && $0.task.start == task.start && $0.task.turnID == task.turnID}) ?? BubbleTaskRow(task:task,scale:scale)
                row.update(task)
                row.frame = NSRect(x:0,y:y,width:bounds.width,height:(task.activityLine == nil ? 32 : 52)*scale)
                addSubview(row); rows.append(row); row.refresh(frame:tick % 10); y += row.frame.height+2*scale
            }
        }
        if frame.height != y {frame.size.height = y; onResize?(y)}
    }
    deinit {stop()}
}

private final class BubbleTaskRow:NSButton,LinkCursorControl {
    override var isFlipped:Bool {false}
    private(set) var task:BubbleTaskSummary
    let scale:CGFloat
    private let spinner = NSTextField(labelWithString:"⠋"), name = NSTextField(labelWithString:""), elapsed = NSTextField(labelWithString:"00:00")
    private let activity = ProgressMarqueeView(frame:.zero)
    private let activityIcon = TaskActivitySymbolView(frame:.zero)
    private let watch = NSImageView()
    private let stateIcon = NSImageView()
    private let jump = NSImageView()
    private var hoverArea:NSTrackingArea?
    private var hovered = false
    private var titleEffectStart = ProcessInfo.processInfo.systemUptime
    init(task:BubbleTaskSummary,scale:CGFloat) {
        self.task = task; self.scale = scale
        super.init(frame:.zero)
        title = ""; isBordered = false; bezelStyle = .inline; target = self; action = #selector(openThread)
        name.stringValue = task.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        name.font = .systemFont(ofSize:12*scale); name.lineBreakMode = .byTruncatingTail; name.maximumNumberOfLines = 1
        spinner.font = .monospacedSystemFont(ofSize:12*scale,weight:.medium)
        elapsed.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.regular); elapsed.alignment = .right
        watch.image = NSImage(systemSymbolName:"stopwatch",accessibilityDescription:"用时")
        activity.stringValue = task.activityLine ?? ""; activity.font = .systemFont(ofSize:11*scale); activity.textColor = .secondaryLabelColor
        activity.isHidden = task.activityLine == nil
        for view in [spinner,name,elapsed,watch,stateIcon,jump,activityIcon,activity] as [NSView] {addSubview(view)}
        jump.image = NSImage(systemSymbolName:"arrow.up.right",accessibilityDescription:"在 Codex 中打开")
        jump.contentTintColor = .tertiaryLabelColor
        update(task)
    }
    func update(_ task:BubbleTaskSummary) {
        if self.task.title != task.title || self.task.active != task.active {titleEffectStart = ProcessInfo.processInfo.systemUptime}
        self.task = task
        name.stringValue = task.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        activity.stringValue = task.activityLine ?? ""; activity.isHidden = task.activityLine == nil
        activityIcon.isHidden = activity.isHidden
        activityIcon.update(task.activity,pointSize:15*scale)
        let symbol = task.connectionFailed ? "wifi.slash" : task.status == "completed" ? "checkmark.circle.fill" : task.status == "failed" ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
        stateIcon.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
        hoverHelp = [name.stringValue,task.activity?.text,"在 Codex 中打开"].compactMap {$0}.joined(separator:"\n")
        let state = task.active ? "执行中" : task.status == "completed" ? "已完成" : task.status == "failed" ? "失败" : ["cancelled","canceled"].contains(task.status) ? "用户取消" : "已中断"
        setAccessibilityLabel(name.stringValue+"，"+(task.activityLine ?? state)+"，转到 Codex")
    }
    func stopMotion() {activity.stop(); TaskActivityAppearance.stop(activityIcon); restoreTitle()}
    private func restoreTitle() {
        name.attributedStringValue = NSAttributedString(string:name.stringValue,attributes:[.font:name.font!,.foregroundColor:NSColor.labelColor])
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func hitTest(_ point:NSPoint) -> NSView? {super.hitTest(point) == nil ? nil : self}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {removeTrackingArea(hoverArea)}
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event:NSEvent) {hovered = true; needsDisplay = true; jump.contentTintColor = AppAccent.color}
    override func mouseExited(with event:NSEvent) {hovered = false; needsDisplay = true; jump.contentTintColor = .tertiaryLabelColor}
    override func resetCursorRects() {super.resetCursorRects(); addCursorRect(bounds,cursor:.pointingHand)}
    override func draw(_ dirtyRect:NSRect) {
        if hovered || isHighlighted {
            AppAccent.color.withAlphaComponent(isHighlighted ? 0.18 : 0.09).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:5*scale,yRadius:5*scale).fill()
        }
        super.draw(dirtyRect)
    }
    @objc private func openThread() {CodexConnection.openConversation(task.threadID)}
    func refresh(frame index:Int) {
        if task.active && ProgressTextEffects.enabled && window?.isVisible == true && !isHiddenOrHasHiddenAncestor {
            name.attributedStringValue = ProgressTextEffects.title(name.stringValue,font:name.font!,appearance:effectiveAppearance,elapsed:ProcessInfo.processInfo.systemUptime-titleEffectStart)
        } else {restoreTitle()}
        let waiting = task.activity?.kind == .attention
        spinner.isHidden = !task.active || waiting; stateIcon.isHidden = task.active
        if task.active {spinner.attributedStringValue = InlineStatusLayout.braille(["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"][index],font:spinner.font!,color:AppAccent.color)}
        spinner.textColor = AppAccent.color
        let hasTime = task.active || task.end != nil
        elapsed.isHidden = !hasTime; watch.isHidden = !hasTime
        elapsed.stringValue = task.end.map {TaskTiming.elapsed(start:task.start,end:$0)} ?? (task.active ? TaskTiming.elapsed(start:task.start) : "")
        let color:NSColor = task.active ? .secondaryLabelColor : task.connectionFailed ? .systemRed : task.status == "completed" ? .systemGreen : task.status == "failed" ? .systemYellow : .systemRed
        elapsed.textColor = color; watch.contentTintColor = color; stateIcon.contentTintColor = color
        let width = hasTime ? elapsed.fittingSize.width : 0, h = 32*scale, trailing = bounds.width-22*scale
        let iconSize = activityIcon.layoutSize, progressX = 22*scale
        activityIcon.frame = NSRect(x:progressX,y:32*scale+(20*scale-iconSize.height)/2,width:iconSize.width,height:iconSize.height)
        activity.frame = NSRect(x:progressX+iconSize.width+6*scale,y:32*scale,width:max(0,bounds.width-progressX-iconSize.width-10*scale),height:20*scale)
        InlineStatusLayout.align(activityIcon,toLineIn:activity,font:activity.font!,side:iconSize.height,width:iconSize.width)
        TaskActivityAppearance.apply(task.activity,icon:activityIcon,text:activity,visible:window?.isVisible == true && !isHiddenOrHasHiddenAncestor)
        activity.start()
        jump.frame = NSRect(x:bounds.width-15*scale,y:(h-11*scale)/2,width:11*scale,height:11*scale)
        let watchX = trailing-width-16*scale
        spinner.frame = NSRect(x:0,y:(h-20*scale)/2,width:18*scale,height:20*scale)
        stateIcon.frame = NSRect(x:1*scale,y:(h-14*scale)/2,width:14*scale,height:14*scale)
        let nameHeight = name.fittingSize.height
        name.frame = NSRect(x:22*scale,y:(h-nameHeight)/2,width:max(0,(hasTime ? watchX-8*scale : trailing)-22*scale),height:nameHeight)
        let baseline = InlineStatusLayout.baseline(of:name)
        InlineStatusLayout.alignBraille(spinner,to:baseline)
        InlineStatusLayout.align(stateIcon,to:name,side:14*scale)
        InlineStatusLayout.align(jump,to:name,side:11*scale)
        elapsed.frame = NSRect(x:trailing-width,y:0,width:width,height:elapsed.fittingSize.height)
        InlineStatusLayout.align(elapsed,to:baseline)
        let side = 13*scale
        watch.frame = NSRect(x:watchX,y:0,width:side,height:side)
        InlineStatusLayout.align(watch,to:elapsed,side:side)
    }
}
