import AppKit

// 独立的紧凑工作区状态；复用状态行和原生会话选择，不改变历史或输入目标。
final class WorkspaceStatusPanel {
    private let panel = ComposerPanel(contentRect:NSRect(x:0,y:0,width:440,height:78),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private lazy var motion = BubbleMotion(window:panel)
    private let workspace = WorkspaceStatusView(), picker = ConversationPicker()
    private let countdown = BubbleCountdown(), preferences = PetPreferences.shared
    private var observer:NSObjectProtocol?
    private var conversation:Conversation?, executing = false
    private(set) var conversationKey:String?
    var visible:Bool {motion.presented}
    var frame:NSRect? {visible ? motion.frame : nil}
    var conversations:() -> [Conversation] = {[]}
    var onSelect:(String) -> Void = {_ in}
    var onShowRequested:() -> Void = {}
    var onHide:() -> Void = {}
    init() {
        panel.title = "工作区状态"; panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior.insert(.fullScreenNone)
        panel.tracksContentCursor = true; panel.acceptsMouseMovedEvents = true
        let background = BubbleBackgroundView()
        panel.contentView = background
        let close = BubbleCloseButton(); close.onClose = { [weak self] in self?.hide() }
        close.widthAnchor.constraint(equalToConstant:22).isActive = true
        close.heightAnchor.constraint(equalToConstant:22).isActive = true
        picker.bezelStyle = .inline; picker.isBordered = false; picker.font = .systemFont(ofSize:12,weight:.medium)
        picker.conversations = { [weak self] in self?.conversations() ?? [] }
        picker.onSelect = { [weak self] key in self?.onSelect(key) }
        let heading = NSStackView(views:[close,picker]); heading.alignment = .centerY; heading.spacing = 6
        let stack = NSStackView(views:[heading,workspace]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        background.body.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:background.body.leadingAnchor,constant:12),stack.trailingAnchor.constraint(equalTo:background.body.trailingAnchor,constant:-12),
            stack.topAnchor.constraint(equalTo:background.body.topAnchor,constant:10),stack.bottomAnchor.constraint(equalTo:background.body.bottomAnchor,constant:-10),
            heading.widthAnchor.constraint(equalTo:stack.widthAnchor),workspace.widthAnchor.constraint(equalTo:stack.widthAnchor)
        ])
        workspace.onOpen = {FinderFileReveal.openDirectory($0)}
        observer = NotificationCenter.default.addObserver(forName:PetPreferences.didChange,object:preferences,queue:.main) { [weak self] note in
            guard let self else {return}
            let keys = Set(note.userInfo?["keys"] as? [String] ?? [])
            guard !keys.isDisjoint(with:["gitWindowEnabled","gitWindowPinned","gitWindowSeconds"]) else {return}
            if !self.preferences.bool("gitWindowEnabled") {self.hide()}
            else if self.visible {self.startCountdown()}
            else if keys.contains("gitWindowEnabled") || keys.contains("gitWindowPinned") {self.onShowRequested()}
        }
    }
    func update(conversation:Conversation,executing:Bool) {
        self.conversation = conversation; self.executing = executing; conversationKey = conversation.key
        picker.title = conversation.title; picker.hoverHelp = conversation.title
        workspace.update(conversation:conversation,executing:executing,visible:visible)
    }
    func show(near pet:CGRect,screen:CGRect,avoiding:[CGRect]) {
        position(near:pet,screen:screen,avoiding:avoiding,opening:true)
        // 自动到达的任务仅显示小窗，不抢键盘或激活其他窗口。
        motion.show()
        workspace.update(conversation:conversation,executing:executing,visible:true)
        startCountdown()
    }
    func position(near pet:CGRect,screen:CGRect,avoiding:[CGRect],opening:Bool = false) {
        guard visible || opening else {return}
        let result = BubblePlacement.resolve(size:NSSize(width:440,height:78),pet:pet,screen:screen,preferred:[.below,.above],previous:nil,avoiding:avoiding,allowsSideFallback:false)
        motion.keepsTopEdge = result.side == .below
        motion.resize(to:result.frame.size); motion.move(to:result.frame.origin)
    }
    private func startCountdown() {
        countdown.start(preferences.bool("gitWindowPinned") ? 0 : preferences.number("gitWindowSeconds"),paused:{ [weak self] in
            guard let self else {return false}
            return self.workspace.hasPresentedDetails || self.picker.isPresented || self.picker.isHighlighted || (self.preferences.bool("pauseOnHover") && self.panel.frame.contains(NSEvent.mouseLocation))
        },expired:{ [weak self] in self?.hide() })
    }
    func hide() {
        countdown.stop(); workspace.deactivate(); picker.close()
        let wasVisible = visible; motion.hide()
        if wasVisible {onHide()}
    }
    deinit {countdown.stop(); if let observer {NotificationCenter.default.removeObserver(observer)}}
}
