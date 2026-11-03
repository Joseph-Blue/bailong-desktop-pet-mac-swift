import AppKit

final class ComposerPanel:NSPanel {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
}

// 临时窗口拥有自己的控件、显隐及鼠标监听；发送目标和会话草稿由 ChatInterface 协调。
final class ChatComposer {
    let composer = ComposerPanel(contentRect:NSRect(x:0,y:0,width:540,height:460),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    lazy var composerMotion = BubbleMotion(window:composer)
    var composerVisible:Bool {composerMotion.presented}
    let composerEditor = MessageEditor()
    let status = label(PetPreferences.shared.fixedText("主人，今天想让我帮什么忙呀？"))
    let composerKeys = label("")
    private(set) var composerModel:ModelSelector!
    private(set) var composerButton:ActionButton!
    private let recovery = NSStackView()
    private let composerClose = BubbleCloseButton()
    private(set) var composerFooterButtons = [ActionButton]()
    private var composerButtonHeight:NSLayoutConstraint?
    private var localDismissMonitor:Any?, globalDismissMonitor:Any?
    var presentingFolderPicker = false
    var isPetInteraction:(NSEvent) -> Bool = {_ in false}
    private var composerInput:MessageInputBox!
    let composerInheritedSettings = label("正在读取 Codex 会话设置…")
    private var composerModelRow:NSStackView!
    private var composerFolder:ActionButton!, composerNew:ActionButton!
    private let modes = AccentTabSelector(labels:ConversationKind.allCases.map(\.title))
    private let conversationPicker = ConversationPicker()
    private let workspace = NSPathControl()
    private var stopButton:ActionButton!, checkButton:ActionButton!
    var onMode:(ConversationKind) -> Void = {_ in}, onSelect:(String) -> Void = {_ in}
    var onStop:() -> Void = {}, onCheck:() -> Void = {}
    var onSubmit:() -> Void = {}, onFolder:() -> Void = {}, onNew:() -> Void = {}, onHistory:() -> Void = {}, onHide:() -> Void = {}
    init(models:ChatModelSettings) {
        composer.level = .floating; composer.contentMinSize = NSSize(width:540,height:460)
        composer.isOpaque = false; composer.backgroundColor = .clear; composer.hasShadow = true
        composer.isMovable = false; composer.isMovableByWindowBackground = false
        composer.hidesOnDeactivate = false
        composer.collectionBehavior.insert(.fullScreenNone)
        let c = BubbleBackgroundView(); composer.contentView = c
        composerInput = ChatViewLayout.inputBox(composerEditor)
        recovery.orientation = .vertical; recovery.alignment = .leading; recovery.spacing = 8; recovery.isHidden = true
        status.font = .systemFont(ofSize:14); status.textColor = .labelColor
        status.maximumNumberOfLines = 2; status.lineBreakMode = .byTruncatingTail
        composerClose.onClose = { [weak self] in self?.hideComposer() }
        composerClose.widthAnchor.constraint(equalToConstant:24).isActive = true
        composerClose.heightAnchor.constraint(equalToConstant:24).isActive = true
        let header = NSStackView(views:[composerClose,status,NSView()]); header.spacing = 8; header.alignment = .centerY
        composerButton = ActionButton("发送") { [weak self] in guard let self else{return}; self.onSubmit() }
        composerButton.emphasize()
        // 快捷键由聚焦的 MessageEditor 处理，避免输入法选词误触默认按钮。
        composerButton.keyEquivalent = ""
        composerFolder = ActionButton("选择…") { [weak self] in self?.onFolder() }
        let historyLink = ActionButton("历史") { [weak self] in self?.onHistory() }
        composerNew = ActionButton("新对话") { [weak self] in self?.onNew() }
        stopButton = ActionButton("停止任务") { [weak self] in self?.onStop() }
        checkButton = ActionButton("检查发送结果") { [weak self] in self?.onCheck() }
        composerFooterButtons = [historyLink,composerNew,stopButton,checkButton,composerButton]
        for button in composerFooterButtons {
            button.configureFlexible(font:.systemFont(ofSize:13))
        }
        composerButtonHeight = composerButton.heightAnchor.constraint(equalToConstant:28); composerButtonHeight?.isActive = true
        let footer = NSStackView(views:[historyLink,composerNew,stopButton,checkButton,NSView(),composerButton]); footer.distribution = .fill; footer.spacing = 8; footer.alignment = .centerY
        // 跨控件约束必须在共同父视图建立后启用，否则 AppKit 会中断整个会话初始化。
        for button in composerFooterButtons where button !== composerButton {
            button.heightAnchor.constraint(equalTo:composerButton.heightAnchor).isActive = true
        }
        composerModel = ModelSelector(models)
        let modelRow = NSStackView(views:[ChatViewLayout.modelHint(),composerModel,NSView()]); modelRow.spacing = 8; modelRow.alignment = .centerY
        composerModelRow = modelRow
        modes.onSelect = { [weak self] index in if let mode = ConversationKind(rawValue:index) {self?.onMode(mode)} }
        conversationPicker.onSelect = { [weak self] key in self?.onSelect(key) }
        workspace.pathStyle = .standard; workspace.isEditable = false
        workspace.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let targetRow = NSStackView(views:[label("会话"),conversationPicker]); targetRow.spacing = 8
        let workspaceRow = NSStackView(views:[label("工作区"),workspace,composerFolder]); workspaceRow.spacing = 8
        let stack = NSStackView(views:[header,modes,targetRow,workspaceRow,composerInput,composerKeys,recovery,modelRow,composerInheritedSettings,footer]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        ChatViewLayout.pin(stack,to:c.body,inset:16)
        [composerInput!,composerKeys,recovery,header,targetRow,workspaceRow,modelRow,composerInheritedSettings,footer].forEach {v in v.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        composerInheritedSettings.font = .systemFont(ofSize:11); composerInheritedSettings.textColor = .secondaryLabelColor
        composerInheritedSettings.maximumNumberOfLines = 2
        composerInput.heightAnchor.constraint(greaterThanOrEqualToConstant:120).isActive = true
        composerEditor.send = { [weak self] in guard let self else{return}; self.onSubmit() }

    }
    func showComposer() {
        composerMotion.show(key:true)
        composer.makeFirstResponder(composerEditor)
        stopDismissMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown,.rightMouseDown,.otherMouseDown]
        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching:clicks) { [weak self] event in
            self?.dismissComposerIfOutside(event); return event
        }
        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching:clicks) { [weak self] event in
            self?.dismissComposerIfOutside(event)
        }
    }
    func hideComposer() {
        stopDismissMonitoring(); composerModel.closeChoices(); conversationPicker.close(); composerMotion.hide(); onHide()
    }
    private func dismissComposerIfOutside(_ event: NSEvent) {
        guard composerVisible, !presentingFolderPicker, composer.attachedSheet == nil else{return}
        if isPetInteraction(event) {return}
        let point = NSEvent.mouseLocation
        if composer.frame.contains(point) || composerModel.containsInteraction(at:point,window:event.window) || conversationPicker.containsInteraction(at:point,window:event.window) {return}
        hideComposer()
    }
    private func stopDismissMonitoring() {
        if let localDismissMonitor {NSEvent.removeMonitor(localDismissMonitor)}
        if let globalDismissMonitor {NSEvent.removeMonitor(globalDismissMonitor)}
        localDismissMonitor = nil; globalDismissMonitor = nil
    }
    deinit {stopDismissMonitoring()}
    func clearFailure() {recovery.isHidden = true; composerInput.isHidden = false; composerButton.isHidden = false}
    func showFailure(_ failure: AppFailure,busy:Bool, restore: @escaping () -> Void) {
        recovery.arrangedSubviews.forEach {recovery.removeArrangedSubview($0); $0.removeFromSuperview()}
        let title = label(failure.title,bold:true), message = label(failure.message)
        let restoreButton = ActionButton("返回输入") { [weak self] in self?.clearFailure(); restore() }; restoreButton.emphasize()
        let details = ActionButton("技术详情…") {failure.showDetails()}
        let recoveryFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
        for button in [details,restoreButton] {
            button.configureFlexible(font:recoveryFont)
            button.heightAnchor.constraint(equalToConstant:button.intrinsicContentSize.height).isActive = true
        }
        let actions = NSStackView(views:[details,restoreButton]); actions.spacing = 8; actions.distribution = .fillEqually
        for v in [title,message,actions] {recovery.addArrangedSubview(v); v.widthAnchor.constraint(equalTo:recovery.widthAnchor).isActive = true}
        if failure.openDesktop {
            let open = ActionButton("打开 Codex") {CodexConnection.openDesktop()}; open.emphasize()
            open.configureFlexible(font:recoveryFont); open.heightAnchor.constraint(equalToConstant:open.intrinsicContentSize.height).isActive = true
            recovery.insertArrangedSubview(open,at:2)
            open.widthAnchor.constraint(equalTo:recovery.widthAnchor).isActive = true
        }
        composerInput.isHidden = true; recovery.isHidden = false; composerButton.isHidden = !busy
    }

    func refresh(font:NSFont,state:ChatInputState,conversations:[Conversation]) {
        let external = state.kind == .project
        composerEditor.font = font; status.font = font
        for button in composerFooterButtons {button.configureFlexible(font:font)}
        composerButtonHeight?.constant = composerFooterButtons.map {$0.intrinsicContentSize.height}.max() ?? 28
        composerButton.isHidden = !recovery.isHidden; composerButton.emphasize()
        composerButton.title = "发送"
        composerButton.isEnabled = state.canSend(models:composerModel.settings)
        composerEditor.isEditable = state.canEdit
        composerFolder.isEnabled = state.canEdit && !external; composerNew.isEnabled = state.runningTitle == nil && !state.readOnly
        composerNew.isHidden = external
        composerModel.isEnabled = state.canEdit && !external; composerModelRow.isHidden = external
        modes.selectedSegment = state.kind.rawValue
        conversationPicker.title = state.conversation?.title ?? "选择会话…"
        conversationPicker.hoverHelp = state.conversation?.title
        conversationPicker.conversations = {conversations.filter {$0.kind == state.kind}}
        workspace.url = state.conversation.map {URL(fileURLWithPath:$0.cwd,isDirectory:true)}
        workspace.hoverHelp = state.conversation?.cwd
        composerFolder.title = state.conversation?.threadID == nil && state.conversation?.turns.isEmpty == true ? "选择…" : "在其他工作区新建…"
        composerFolder.isHidden = external
        composerInheritedSettings.stringValue = state.modelNote ?? "正在读取 Codex 会话设置…"
        composerInheritedSettings.isHidden = !external
        stopButton.isHidden = !state.ownsRunningTask
        checkButton.isHidden = !state.unconfirmed
        status.stringValue = state.note.isEmpty ? PetPreferences.shared.fixedText("主人，今天想让我帮什么忙呀？") : state.note
    }
}
