import AppKit

final class ComposerPanel:ContentCursorPanel {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
}

// 临时窗口拥有自己的控件、显隐及鼠标监听；发送目标和会话草稿由 ChatInterface 协调。
final class ChatComposer: NSObject {
    let composer = ComposerPanel(contentRect:NSRect(x:0,y:0,width:540,height:420),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    lazy var composerMotion = BubbleMotion(window:composer)
    var composerVisible:Bool {composerMotion.presented}
    let composerEditor = MessageEditor()
    let status = label(PetPreferences.shared.fixedText("主人，今天想让我帮什么忙呀？"))
    private(set) var composerModel:ModelSelector!
    private(set) var composerButton:ActionButton!
    private let recovery = NSStackView()
    private var recoveryActions = [ActionButton]()
    private let composerClose = BubbleCloseButton()
    private let header = NSStackView()
    private let preferences:PetPreferences
    private var closeButtonOnRight = false
    private var closeButtonScreenMidX:CGFloat?
    private(set) var composerFooterButtons = [ActionButton]()
    private var composerButtonHeight:NSLayoutConstraint?
    private var localDismissMonitor:Any?, globalDismissMonitor:Any?
    var presentingFolderPicker = false
    var isPetInteraction:(NSEvent) -> Bool = {_ in false}
    private var composerInput:MessageInputBox!
    let composerInheritedSettings = ChatReadOnlyModelField()
    private var composerModelRow:NSStackView!
    private var composerNew:ActionButton!
    private var folderAction = NSMenuItem()
    private var showingNewMenu = false
    private var contentStack:NSStackView!
    private var inputHeight:NSLayoutConstraint!
    private var modes:ChatModeControl!
    private let recentReply = ChatReplyPreview()
    private let inputStatus = ComposerStatusView()
    private let steeringHint = ChatViewLayout.steeringHint()
    private let inlineStatus = NSTextField(labelWithString:"")
    private var statusText = "", allowsInlineStatus = false, externalModel = false
    private var openCodex:ActionButton!, retrySettings:ActionButton!
    private let conversationPicker = ConversationPicker()
    private let workspace = WorkspaceStatusView()
    private var latestState:ChatInputState?
    private var stopButton:ActionButton!, checkButton:ActionButton!
    var onOpenWorkspace:(URL) -> Void = {_ in}
    var onMode:(ConversationKind) -> Void = {_ in}, onSelect:(String) -> Void = {_ in}
    var onStop:() -> Void = {}, onCheck:() -> Void = {}
    var onOpenCodex:() -> Void = {}, onRetrySettings:() -> Void = {}
    var onSubmit:() -> Void = {}, onFolder:() -> Void = {}, onNew:() -> Void = {}, onHistory:() -> Void = {}, onHide:() -> Void = {}
    var onNewDefault:() -> Void = {}
    var onLayoutSizeChange:() -> Void = {}
    init(models:ChatModelSettings,preferences:PetPreferences = .shared) {
        self.preferences = preferences
        super.init()
        composer.tracksContentCursor = true; composer.acceptsMouseMovedEvents = true
        composer.level = NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1); composer.contentMinSize = NSSize(width:540,height:420)
        composer.isOpaque = false; composer.backgroundColor = .clear; composer.hasShadow = true
        composer.isMovable = false; composer.isMovableByWindowBackground = false
        composer.hidesOnDeactivate = false
        composer.collectionBehavior.insert(.fullScreenNone)
        let c = BubbleBackgroundView()
        // 临时聊天窗统一裁切最终合成边界，避免圆角外露出矩形底板。
        c.wantsLayer = true; c.layer?.backgroundColor = NSColor.clear.cgColor
        c.layer?.cornerRadius = BubbleBackgroundView.cornerRadius; c.layer?.masksToBounds = true
        composer.contentView = c
        composerEditor.usesCompactContextMenu = true
        composerInput = ChatViewLayout.inputBox(composerEditor)
        recovery.orientation = .vertical; recovery.alignment = .leading; recovery.spacing = 8; recovery.isHidden = true
        status.font = .systemFont(ofSize:14); status.textColor = .labelColor
        status.maximumNumberOfLines = 2; status.lineBreakMode = .byTruncatingTail
        composerClose.onClose = { [weak self] in self?.hideComposer() }
        composerClose.widthAnchor.constraint(equalToConstant:24).isActive = true
        composerClose.heightAnchor.constraint(equalToConstant:24).isActive = true
        for view in [composerClose,status,NSView()] {header.addArrangedSubview(view)}
        header.orientation = .horizontal; header.spacing = 8; header.alignment = .centerY
        composerButton = ActionButton("发送") { [weak self] in guard let self else{return}; self.onSubmit() }
        ChatViewLayout.configureSendButton(composerButton)
        composerButton.emphasize()
        // 快捷键由聚焦的 MessageEditor 处理，避免输入法选词误触默认按钮。
        composerButton.keyEquivalent = ""
        let historyLink = ActionButton("查看记录") { [weak self] in self?.onHistory() }
        composerNew = ActionButton("新对话") { [weak self] in self?.showNewMenu() }
        composerNew.image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil); composerNew.imagePosition = .imageTrailing
        stopButton = ActionButton("停止任务") { [weak self] in self?.onStop() }
        checkButton = ActionButton("检查发送结果") { [weak self] in self?.onCheck() }
        openCodex = ActionButton(ChatInputState.jumpToCodexTitle) { [weak self] in self?.onOpenCodex() }
        openCodex.image = AppIcons.openAI; openCodex.imagePosition = .imageLeading
        composerFooterButtons = [historyLink,openCodex,composerNew,stopButton,checkButton,composerButton]
        for button in composerFooterButtons {
            button.configureFlexible(font:.systemFont(ofSize:13))
        }
        composerButtonHeight = composerButton.heightAnchor.constraint(equalToConstant:28); composerButtonHeight?.isActive = true
        let footer = NSStackView(views:[historyLink,openCodex,composerNew,stopButton,checkButton,NSView(),composerButton]); footer.distribution = .fill; footer.spacing = 8; footer.alignment = .centerY
        // 跨控件约束必须在共同父视图建立后启用，否则 AppKit 会中断整个会话初始化。
        for button in composerFooterButtons where button !== composerButton {
            button.heightAnchor.constraint(equalTo:composerButton.heightAnchor).isActive = true
        }
        composerModel = ModelSelector(models)
        let modelRow = ChatMetadataRow("模型",content:composerModel)
        composerModelRow = modelRow
        modes = ChatModeControl(labels:ConversationKind.allCases.map(\.title))
        modes.onSelect = { [weak self] index in
            guard let self,let mode = ConversationKind(rawValue:index) else {return}
            self.onMode(mode); self.composer.makeFirstResponder(self.composerEditor)
        }
        conversationPicker.onSelect = { [weak self] key in self?.onSelect(key) }
        workspace.onOpen = { [weak self] url in self?.onOpenWorkspace(url) }
        workspace.setContentHuggingPriority(.defaultLow,for:.horizontal)
        retrySettings = ActionButton("重新读取") { [weak self] in self?.onRetrySettings() }
        let connectionRow = ChatMetadataRow("模型",content:composerInheritedSettings,accessory:retrySettings)
        composerInheritedSettings.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let modelFields = NSStackView(views:[modelRow,connectionRow]); modelFields.orientation = .vertical; modelFields.alignment = .leading; modelFields.spacing = 0
        for row in [modelRow,connectionRow] {row.widthAnchor.constraint(equalTo:modelFields.widthAnchor).isActive = true}
        inlineStatus.font = .systemFont(ofSize:11); inlineStatus.textColor = .secondaryLabelColor
        inlineStatus.isSelectable = true; inlineStatus.isHidden = true
        inlineStatus.maximumNumberOfLines = 1; inlineStatus.usesSingleLineMode = true
        inlineStatus.setContentCompressionResistancePriority(.required,for:.horizontal)
        inlineStatus.setContentHuggingPriority(.required,for:.horizontal)
        let modelStrip = NSStackView(views:[modelFields,inlineStatus])
        modelStrip.alignment = .centerY; modelStrip.spacing = 12
        workspace.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let workspaceRow = workspace
        let targetCaption = NSTextField(labelWithString:"会话")
        targetCaption.font = .systemFont(ofSize:12); targetCaption.textColor = .secondaryLabelColor
        targetCaption.setContentCompressionResistancePriority(.required,for:.horizontal)
        modes.setContentCompressionResistancePriority(.required,for:.horizontal)
        conversationPicker.setContentHuggingPriority(.required,for:.horizontal)
        conversationPicker.widthAnchor.constraint(greaterThanOrEqualToConstant:100).isActive = true
        conversationPicker.widthAnchor.constraint(lessThanOrEqualToConstant:240).isActive = true
        let modeRow = NSStackView(views:[modes!,NSView(),targetCaption,conversationPicker])
        modeRow.alignment = .centerY; modeRow.distribution = .fill; modeRow.spacing = 8
        let body = NSStackView(views:[workspaceRow,recentReply,composerInput,recovery,modelStrip,inputStatus,steeringHint,footer])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 8
        let stack = NSStackView(views:[header,modeRow,body]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        contentStack = stack
        c.body.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:c.body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:c.body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:c.body.topAnchor,constant:16)])
        [header,modeRow,body].forEach {$0.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        [composerInput!,recovery,workspaceRow,recentReply,modelStrip,inputStatus,steeringHint,footer].forEach {$0.widthAnchor.constraint(equalTo:body.widthAnchor).isActive = true}
        inputHeight = composerInput.heightAnchor.constraint(equalToConstant:140); inputHeight.isActive = true
        composerEditor.onTextChange = { [weak self] in self?.updateLayout() }
        composerModel.onSummaryChange = { [weak self] in self?.updateLayout() }
        composerEditor.send = { [weak self] in guard let self else{return}; self.onSubmit() }
        NotificationCenter.default.addObserver(self,selector:#selector(closeButtonPreferenceChanged(_:)),
                                               name:PetPreferences.didChange,object:preferences)
        refreshCloseButtonPosition()
    }
    func move(to origin:NSPoint,screenFrame:CGRect? = nil) {
        composerMotion.move(to:origin)
        closeButtonScreenMidX = (screenFrame ?? composer.screen?.visibleFrame)?.midX
        refreshCloseButtonPosition()
    }
    @objc private func closeButtonPreferenceChanged(_ note:Notification) {
        guard (note.userInfo?["keys"] as? [String])?.contains(BubbleCloseButtonPosition.key) == true else {return}
        refreshCloseButtonPosition()
    }
    private func refreshCloseButtonPosition() {
        let onRight = preferences.bubbleCloseButtonPosition.isOnRight(
            windowMidX:composerMotion.frame.midX,screenMidX:closeButtonScreenMidX,wasOnRight:closeButtonOnRight)
        guard onRight != closeButtonOnRight else {return}
        closeButtonOnRight = onRight
        header.removeArrangedSubview(composerClose)
        header.insertArrangedSubview(composerClose,at:onRight ? header.arrangedSubviews.count : 0)
    }
    func prepareLayout() {
        updateLayout(force:true)
    }
    func showComposer() {
        updateLayout(force:true)
        composerMotion.show(key:true)
        if let state = latestState {workspace.update(conversation:state.conversation,executing:state.executing,visible:true)}
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
        workspace.deactivate()
        stopDismissMonitoring(); composerModel.closeChoices(); conversationPicker.close(restoreFocus:false); composerMotion.hide(); onHide()
    }
    private func dismissComposerIfOutside(_ event: NSEvent) {
        guard composerVisible, !presentingFolderPicker, composer.attachedSheet == nil else{return}
        let point = NSEvent.mouseLocation
        conversationPicker.dismissIfOutside(at:point,window:event.window)
        if isPetInteraction(event) {return}
        if workspace.containsInteraction(at:point) || showingNewMenu || composer.frame.contains(point) || composerModel.containsInteraction(at:point,window:event.window) || conversationPicker.containsInteraction(at:point,window:event.window) {return}
        hideComposer()
    }
    private func stopDismissMonitoring() {
        if let localDismissMonitor {NSEvent.removeMonitor(localDismissMonitor)}
        if let globalDismissMonitor {NSEvent.removeMonitor(globalDismissMonitor)}
        localDismissMonitor = nil; globalDismissMonitor = nil
    }
    deinit {stopDismissMonitoring()}
    private func releaseRecoveryContent() {
        for button in recoveryActions {button.callback = {}}
        recoveryActions.removeAll()
        recovery.arrangedSubviews.forEach {recovery.removeArrangedSubview($0); $0.removeFromSuperview()}
    }
    func clearFailure() {
        releaseRecoveryContent()
        recovery.isHidden = true; composerInput.isHidden = false; composerButton.isHidden = false; updateLayout()
    }
    func showFailure(_ failure: AppFailure,busy:Bool, restore: @escaping () -> Void) {
        releaseRecoveryContent()
        let title = label(failure.title,bold:true), message = label(failure.message)
        let restoreButton = ActionButton("返回输入") { [weak self] in self?.clearFailure(); restore() }; restoreButton.emphasize()
        let details = ActionButton("技术详情…") {failure.showDetails()}
        recoveryActions = [restoreButton,details]
        let recoveryFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
        for button in [details,restoreButton] {
            button.configureFlexible(font:recoveryFont)
            button.heightAnchor.constraint(equalToConstant:button.intrinsicContentSize.height).isActive = true
        }
        let actions = NSStackView(views:[details,restoreButton]); actions.spacing = 8; actions.distribution = .fillEqually
        for v in [title,message,actions] {recovery.addArrangedSubview(v); v.widthAnchor.constraint(equalTo:recovery.widthAnchor).isActive = true}
        if failure.openDesktop {
            let open = ActionButton("打开 Codex") {CodexConnection.openDesktop()}; open.emphasize()
            recoveryActions.append(open)
            open.configureFlexible(font:recoveryFont); open.heightAnchor.constraint(equalToConstant:open.intrinsicContentSize.height).isActive = true
            recovery.insertArrangedSubview(open,at:2)
            open.widthAnchor.constraint(equalTo:recovery.widthAnchor).isActive = true
        }
        composerInput.isHidden = true; recovery.isHidden = false; composerButton.isHidden = !busy
        updateLayout()
    }

    private func showNewMenu() {
        let menu = AccentMenuRows.menu(); menu.autoenablesItems = false
        let defaultItem = NSMenuItem(title:"在默认工作区新建",action:#selector(newDefault),keyEquivalent:""); defaultItem.target = self
        let same = NSMenuItem(title:"在当前工作区新建",action:#selector(newHere),keyEquivalent:""); same.target = self
        folderAction.target = self; folderAction.action = #selector(newElsewhere)
        menu.addItem(defaultItem); menu.addItem(same); menu.addItem(folderAction)
        showingNewMenu = true
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:composerNew.bounds.maxY+4),in:composerNew)
        showingNewMenu = false
        menu.removeItem(folderAction)
    }
    @objc private func newHere() {onNew()}
    @objc private func newDefault() {onNewDefault()}
    @objc private func newElsewhere() {onFolder()}

    func updateLayout(force:Bool = false) {
        guard composerVisible || force,let content = composer.contentView else {return}
        let previousSize = composerMotion.frame.size
        let buttons = composerFooterButtons.filter {!$0.isHidden}
        let footerWidth = buttons.reduce(CGFloat(32+buttons.count*8)) {$0+$1.intrinsicContentSize.width}
        let width = max(540,footerWidth,modes.intrinsicContentSize.width+196)
        // 先确定正文宽度再测量换行；只有编辑区随草稿增长，元信息和操作区按内容排版。
        if abs(content.bounds.width-width)>0.5 {composerMotion.resize(to:NSSize(width:width,height:composerMotion.frame.height))}
        let model = externalModel ? composerInheritedSettings : composerModel!
        let retryWidth = retrySettings.isHidden ? 0 : retrySettings.intrinsicContentSize.width+8
        let sharedWidth = max(1,width-32-ChatMetadataRow.captionWidth-16-retryWidth-12)
        let noteWidth = ceil((statusText as NSString).size(withAttributes:[.font:inlineStatus.font!]).width)+4
        let statusRequested = allowsInlineStatus && !statusText.isEmpty && !statusText.contains(where:{$0.isNewline})
        let arrangement = ModelSummaryLayout.arrange(available:sharedWidth,
            statusWidth:statusRequested ? noteWidth : 0,desiredModelWidth:model.naturalLayoutWidth)
        model.maximumLayoutWidth = arrangement.modelWidth
        content.layoutSubtreeIfNeeded()
        let available = max(0,width-32-ChatMetadataRow.captionWidth-16-model.layoutWidth-retryWidth-12)
        let inline = statusRequested && arrangement.statusInline && noteWidth <= available
        inlineStatus.stringValue = inline ? statusText : ""; inlineStatus.isHidden = !inline
        inputStatus.update(inline ? "" : statusText)
        inputStatus.measure(width:width-32)
        content.layoutSubtreeIfNeeded()
        inputHeight.constant = min(260,max(140,composerInput.contentHeight.rounded(.up)))
        let height = contentStack.fittingSize.height.rounded(.up)+32
        let size = NSSize(width:width,height:height)
        composer.contentMinSize = NSSize(width:width,height:min(height,420))
        if composerMotion.frame.size != size {composerMotion.resize(to:size)}
        if size != previousSize {onLayoutSizeChange()}
    }

    func refreshTurn(_ turn:Turn,in conversation:Conversation,editsChanged:Bool) {
        recentReply.update(turn:turn)
        if editsChanged {workspace.update(conversation:conversation,executing:true,visible:true)}
    }

    func refresh(font:NSFont,state:ChatInputState,choices:@escaping () -> [Conversation]) {
        latestState = state
        let external = state.kind == .project
        composerEditor.update(font:font,editable:state.canEdit); status.font = font
        composerModel.font = font; composerInheritedSettings.font = font
        for button in composerFooterButtons + [retrySettings!] {button.configureFlexible(font:font)}
        composerButtonHeight?.constant = composerFooterButtons.map {$0.intrinsicContentSize.height}.max() ?? 28
        composerButton.isHidden = !recovery.isHidden; composerButton.emphasize()
        composerButton.title = "发送"
        composerButton.isEnabled = state.canSend(models:composerModel.settings)
        folderAction.isEnabled = state.canEdit && !external; composerNew.isEnabled = state.runningTitle == nil && !state.readOnly
        composerNew.isHidden = external; openCodex.isHidden = false
        composerModel.isEnabled = state.canEdit && !external; composerModelRow.isHidden = external
        modes.select(state.kind.rawValue)
        conversationPicker.title = state.conversation?.title ?? "选择会话…"
        conversationPicker.setHoverHelp(state.conversation?.title) { [weak conversationPicker] in
            conversationPicker?.hasTruncatedTitle == true
        }
        conversationPicker.conversations = choices
        workspace.update(conversation:state.conversation,executing:state.executing,visible:composerVisible)
        folderAction.title = state.conversation?.threadID == nil && state.conversation?.turns.isEmpty == true ? "选择此对话的工作区…" : "在其他工作区新建…"
        composerInheritedSettings.update(settings:state.modelSettings,conversation:state.conversation,notice:state.modelNote)
        composerInheritedSettings.superview?.isHidden = !external || state.conversation == nil
        retrySettings.isHidden = !state.showsModelRetry
        retrySettings.isEnabled = !state.sending
        openCodex.isEnabled = state.conversation?.threadID != nil
        recentReply.update(turn:state.conversation?.turns.max(by:{$0.date < $1.date}))
        steeringHint.isHidden = !state.showsSteeringHint
        statusText = state.showsSteeringHint ? "" : state.note; externalModel = external
        allowsInlineStatus = state.conversation != nil
        stopButton.isHidden = !state.ownsRunningTask && !state.desktopPreparing
        stopButton.isEnabled = !state.stopping
        stopButton.title = state.desktopPreparing ? "取消发送" : state.stopping ? "正在停止…" : "停止任务"
        checkButton.isHidden = !state.unconfirmed
        status.stringValue = state.composerTitle
    }
}
