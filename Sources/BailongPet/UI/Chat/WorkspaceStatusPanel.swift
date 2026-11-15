import AppKit

// 独立的单行工作区状态；复用状态行，不改变历史或输入目标。
final class WorkspaceStatusPanel {
    private let panel = ComposerPanel(contentRect:NSRect(x:0,y:0,width:320,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private lazy var motion = BubbleMotion(window:panel)
    private let workspace = WorkspaceStatusView()
    private let stack = NSStackView()
    private let countdown = BubbleCountdown(), preferences = PetPreferences.shared
    private var observer:NSObjectProtocol?
    private var conversation:Conversation?, executing = false
    private var placement:(pet:CGRect,screen:CGRect,avoiding:[CGRect])?
    private(set) var conversationKey:String?
    var visible:Bool {motion.presented}
    var frame:NSRect? {visible ? motion.frame : nil}
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
        workspace.configure(compact:false,fontSize:13,monochromeDirectory:true)
        workspace.spacing = 6
        [close,workspace].forEach {stack.addArrangedSubview($0)}
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 6; stack.distribution = .fill
        background.body.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:background.body.leadingAnchor,constant:10),stack.trailingAnchor.constraint(equalTo:background.body.trailingAnchor,constant:-10),
            stack.topAnchor.constraint(equalTo:background.body.topAnchor,constant:8),stack.bottomAnchor.constraint(equalTo:background.body.bottomAnchor,constant:-8)
        ])
        workspace.onOpen = {FinderFileReveal.openDirectory($0)}
        workspace.onStatusChange = { [weak self] in
            guard let self,self.visible,let placement = self.placement else {return}
            self.position(near:placement.pet,screen:placement.screen,avoiding:placement.avoiding)
        }
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
        placement = (pet,screen,avoiding)
        let content = stack.fittingSize
        let size = NSSize(width:min(ceil(content.width)+20,640,screen.width-16),height:ceil(content.height)+16)
        let result = BubblePlacement.resolve(size:size,pet:pet,screen:screen,preferred:[.below,.above],previous:nil,avoiding:avoiding,allowsSideFallback:false)
        motion.keepsTopEdge = result.side == .below
        motion.resize(to:result.frame.size); motion.move(to:result.frame.origin)
    }
    private func startCountdown() {
        countdown.start(preferences.bool("gitWindowPinned") ? 0 : preferences.number("gitWindowSeconds"),paused:{ [weak self] in
            guard let self else {return false}
            return self.workspace.hasPresentedDetails || (self.preferences.bool("pauseOnHover") && self.panel.frame.contains(NSEvent.mouseLocation))
        },expired:{ [weak self] in self?.hide() })
    }
    func hide() {
        placement = nil
        countdown.stop(); workspace.deactivate()
        let wasVisible = visible; motion.hide()
        if wasVisible {onHide()}
    }
    deinit {countdown.stop(); if let observer {NotificationCenter.default.removeObserver(observer)}}
}
