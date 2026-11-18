import AppKit

struct BubbleTaskSummary: Equatable {
    let key:String, title:String, threadID:String?, status:String
    let start:Date
    let end:Date?
    var turnID:String? = nil
    var activity:TaskActivity? = nil
    var connectionFailed = false
    var directory = ""
    var fileEdits = [FileEditSummary]()
    var activityLine:String? {active && activity?.groupActivity.visible == true ? activity?.groupActivity.line : nil}
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
    private var showsTaskInfo = false
    private var metadataLayoutDirty = false
    private var renderedWidth:CGFloat = -1
    private var recentLimit = 0
    private var rows = [BubbleTaskRow]()
    var hasPresentedDetails:Bool {rows.contains {$0.hasPresentedDetails}}
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
            for row in self.rows where row.task.active {row.refresh(frame:animated ? self.tick % 10 : 0)}
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func stop() {timer?.invalidate(); timer = nil; rows.forEach {$0.stopMotion()}}
    private func rebuild() {
        var incoming = provider()
        incoming.tasks = incoming.tasks.map {task in
            var task = task; task.activity = task.activity?.groupActivity
            if task.activity?.visible != true {task.activity = nil}
            return task
        }
        let showInfo = PetPreferences.shared.bool("taskInfoBarEnabled")
        let limit = Int(PetPreferences.shared.number("recentTaskCount"))
        defer {
            let visible = showInfo && window?.isVisible == true && !isHiddenOrHasHiddenAncestor
            for row in rows {row.setMetadataVisible(visible && (!row.visibleRect.isEmpty || row.hasPresentedDetails))}
            if let monitor = TerminalMonitor.active,window?.isVisible == true,!isHiddenOrHasHiddenAncestor {
                for row in rows where row.task.active && !row.visibleRect.isEmpty {row.recordActivity(in:monitor)}
            }
        }
        guard incoming != overview || limit != recentLimit || showInfo != showsTaskInfo || metadataLayoutDirty || renderedWidth != bounds.width || subviews.isEmpty else {return}
        metadataLayoutDirty = false; renderedWidth = bounds.width
        overview = incoming; showsTaskInfo = showInfo; recentLimit = limit
        let records = incoming.tasks; let previousRows = rows; subviews.filter {!($0 is BubbleTaskRow)}.forEach {$0.removeFromSuperview()}; rows = []
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
                row.onMetadataResize = { [weak self] in self?.metadataLayoutDirty = true }
                row.update(task)
                row.frame = NSRect(x:0,y:y,width:bounds.width,height:row.rowHeight)
                if row.superview == nil {addSubview(row)}
                rows.append(row); row.refresh(frame:tick % 10); y += row.frame.height+2*scale
            }
        }
        for row in previousRows where !rows.contains(where:{$0 === row}) {row.stopMotion(); row.removeFromSuperview()}
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
    private var metadata:WorkspaceStatusView?
    private var hasGit = false
    var onMetadataResize:() -> Void = {}
    private var metadataHeight:CGFloat {PetPreferences.shared.bool("taskInfoBarEnabled") && (hasGit || !task.fileEdits.isEmpty) ? 22*scale : 0}
    var rowHeight:CGFloat {32*scale+(task.activityLine == nil ? 0 : 20*scale)+metadataHeight}
    var hasPresentedDetails:Bool {metadata?.hasPresentedDetails == true}
    private var hoverArea:NSTrackingArea?
    private var hovered = false
    private var titleEffectStart = ProcessInfo.processInfo.systemUptime
    private var renderedSweep = Int.min
    private var renderedFrame = -1
    private var monitoredActivity:String?
    private var needsRowLayout = true
    init(task:BubbleTaskSummary,scale:CGFloat) {
        self.task = task; self.scale = scale
        super.init(frame:.zero)
        title = ""; isBordered = false; bezelStyle = .inline; target = self; action = #selector(openThread)
        name.stringValue = task.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        name.font = .systemFont(ofSize:12*scale); name.lineBreakMode = .byTruncatingTail; name.maximumNumberOfLines = 1
        spinner.font = .monospacedSystemFont(ofSize:12*scale,weight:.medium)
        elapsed.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.medium); elapsed.alignment = .right
        watch.image = NSImage(systemSymbolName:"stopwatch",accessibilityDescription:"用时")
        activity.stringValue = task.activityLine ?? ""; activity.font = .systemFont(ofSize:11*scale); activity.textColor = StatusTextColor.secondary
        activity.isHidden = task.activityLine == nil
        for view in [spinner,name,elapsed,watch,stateIcon,jump,activityIcon,activity] as [NSView] {addSubview(view)}
        jump.image = NSImage(systemSymbolName:"arrow.up.right",accessibilityDescription:"在 Codex 中打开")
        jump.contentTintColor = .tertiaryLabelColor
        update(task)
    }
    func update(_ task:BubbleTaskSummary) {
        if self.task.title != task.title || self.task.active != task.active {titleEffectStart = ProcessInfo.processInfo.systemUptime}
        let workspaceChanged = self.task.directory != task.directory || self.task.fileEdits != task.fileEdits || self.task.active != task.active
        if self.task.directory != task.directory {hasGit = false}
        self.task = task
        if workspaceChanged {updateWorkspace()}
        name.stringValue = task.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        activity.stringValue = task.activityLine ?? ""; activity.isHidden = task.activityLine == nil
        activityIcon.isHidden = activity.isHidden
        activityIcon.update(task.activity,pointSize:15*scale)
        let symbol = task.connectionFailed ? "wifi.slash" : task.status == "completed" ? "checkmark.circle.fill" : task.status == "failed" ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
        stateIcon.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
        hoverHelp = [name.stringValue,task.activity?.text,"在 Codex 中打开"].compactMap {$0}.joined(separator:"\n")
        let state = task.active ? "执行中" : task.status == "completed" ? "已完成" : task.status == "failed" ? "失败" : ["cancelled","canceled"].contains(task.status) ? "用户取消" : "已中断"
        setAccessibilityLabel(name.stringValue+"，"+(task.activityLine ?? state)+"，转到 Codex")
        renderedSweep = Int.min; renderedFrame = -1; needsRowLayout = true
    }
    func recordActivity(in monitor:TerminalMonitor) {
        let label = activity.isHidden ? "无进展行" : task.activity?.monitorLabel ?? "无进展行"
        guard monitoredActivity != label else {return}
        let change = monitoredActivity.map {$0+" → "+label} ?? label
        monitor.write(.bubble,"轮次#"+TerminalMonitor.tag(task.turnID ?? task.key)+"  任务概览  ·  "+change)
        monitoredActivity = label
    }
    func setMetadataVisible(_ visible:Bool) {
        guard visible != (metadata != nil) else {return}
        if visible {
            let bar = WorkspaceStatusView(frame:.zero)
            bar.configure(compact:true,fontSize:11*scale)
            bar.onStatusChange = { [weak self,weak bar] in
                guard let self,let bar,self.metadata === bar,let present = bar.knownGitPresence else {return}
                let previous = self.metadataHeight
                self.hasGit = present
                if previous != self.metadataHeight {self.needsRowLayout = true; self.onMetadataResize()}
            }
            metadata = bar; addSubview(bar)
            layoutMetadata(); updateWorkspace()
        } else {
            metadata?.deactivate(); metadata?.removeFromSuperview(); metadata = nil
        }
    }
    private func updateWorkspace() {
        metadata?.update(directory:task.directory,context:task.key,turn:task.turnID,edits:task.fileEdits,executing:task.active,visible:true)
    }
    private func layoutMetadata() {
        guard let metadata else {return}
        let inset = 22*scale, width = max(0,bounds.width-inset)
        metadata.isHidden = metadataHeight == 0
        metadata.fitOverview(to:width)
        metadata.frame = NSRect(x:inset,y:0,width:width,height:22*scale)
    }
    func stopMotion() {setMetadataVisible(false); activity.stop(); TaskActivityAppearance.stop(activityIcon); restoreTitle(); renderedSweep = Int.min; renderedFrame = -1}
    private func restoreTitle() {
        guard renderedSweep != -2 else {return}
        renderedSweep = -2
        name.attributedStringValue = NSAttributedString(string:name.stringValue,attributes:[.font:name.font!,.foregroundColor:NSColor.labelColor])
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else {return nil}
        var view:NSView? = hit
        while let child = view,child !== self {
            if child is NSButton {return child}
            view = child.superview
        }
        return self
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {removeTrackingArea(hoverArea)}
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event:NSEvent) {hovered = true; needsDisplay = true; jump.contentTintColor = AppAccent.foregroundColor}
    override func mouseExited(with event:NSEvent) {hovered = false; needsDisplay = true; jump.contentTintColor = .tertiaryLabelColor}
    override func resetCursorRects() {super.resetCursorRects(); addCursorRect(bounds,cursor:.pointingHand)}
    override func draw(_ dirtyRect:NSRect) {
        if hovered || isHighlighted {
            AppAccent.color.withAlphaComponent(isHighlighted ? 0.18 : 0.09).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:5*scale,yRadius:5*scale).fill()
        }
        super.draw(dirtyRect)
    }
    override var frame:NSRect {
        didSet {if oldValue.size != frame.size {needsRowLayout = true}}
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderedSweep = Int.min; renderedFrame = -1
    }
    @objc private func openThread() {CodexConnection.openConversation(task.threadID)}
    func refresh(frame index:Int) {
        if task.active && ProgressTextEffects.enabled && window?.isVisible == true && !isHiddenOrHasHiddenAncestor {
            let elapsedSweep = ProcessInfo.processInfo.systemUptime-titleEffectStart
            let sweep = ProgressTextEffects.sweepTick(elapsed:elapsedSweep)
            if sweep != renderedSweep {
                renderedSweep = sweep
                name.attributedStringValue = ProgressTextEffects.title(name.stringValue,font:name.font!,appearance:effectiveAppearance,elapsed:elapsedSweep)
            }
        } else {restoreTitle()}
        let waiting = task.activity?.kind == .attention
        spinner.isHidden = !task.active || waiting; stateIcon.isHidden = task.active
        if task.active && renderedFrame != index {
            renderedFrame = index
            spinner.attributedStringValue = InlineStatusLayout.braille(["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"][index],font:spinner.font!,color:AppAccent.foregroundColor)
            spinner.textColor = AppAccent.foregroundColor
        }
        let hasTime = task.active || task.end != nil
        elapsed.isHidden = !hasTime; watch.isHidden = !hasTime
        let nextElapsed = task.end.map {TaskTiming.elapsed(start:task.start,end:$0)} ?? (task.active ? TaskTiming.elapsed(start:task.start) : "")
        if elapsed.stringValue != nextElapsed {
            elapsed.stringValue = nextElapsed
            needsRowLayout = true
        }
        guard needsRowLayout else {return}
        needsRowLayout = false
        let textColor = task.active ? StatusTextColor.secondary : task.connectionFailed ? StatusTextColor.red : task.status == "completed" ? StatusTextColor.green : task.status == "failed" ? StatusTextColor.yellow : StatusTextColor.red
        elapsed.textColor = textColor; watch.contentTintColor = textColor; stateIcon.contentTintColor = textColor
        let width = hasTime ? elapsed.fittingSize.width : 0, h = 32*scale, trailing = bounds.width-22*scale
        let headingY = bounds.height-h, metadataHeight = self.metadataHeight
        let iconSize = activityIcon.layoutSize, progressX = 22*scale
        layoutMetadata()
        activityIcon.frame = NSRect(x:progressX,y:metadataHeight+(20*scale-iconSize.height)/2,width:iconSize.width,height:iconSize.height)
        activity.frame = NSRect(x:progressX+iconSize.width+6*scale,y:metadataHeight,width:max(0,bounds.width-progressX-iconSize.width-10*scale),height:20*scale)
        InlineStatusLayout.align(activityIcon,toLineIn:activity,font:activity.font!,side:iconSize.height,width:iconSize.width)
        TaskActivityAppearance.apply(task.activity,icon:activityIcon,text:activity,visible:window?.isVisible == true && !isHiddenOrHasHiddenAncestor)
        activity.start()
        jump.frame = NSRect(x:bounds.width-15*scale,y:headingY+(h-11*scale)/2,width:11*scale,height:11*scale)
        let watchX = trailing-width-16*scale
        spinner.frame = NSRect(x:0,y:headingY+(h-20*scale)/2,width:18*scale,height:20*scale)
        stateIcon.frame = NSRect(x:1*scale,y:headingY+(h-14*scale)/2,width:14*scale,height:14*scale)
        let nameHeight = name.fittingSize.height
        name.frame = NSRect(x:22*scale,y:headingY+(h-nameHeight)/2,width:max(0,(hasTime ? watchX-8*scale : trailing)-22*scale),height:nameHeight)
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
