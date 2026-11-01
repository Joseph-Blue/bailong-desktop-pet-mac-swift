import AppKit

final class HistoryWindow: NSWindow {
    var focusSearch: () -> Void = {}
    var nextMatch: (Bool) -> Void = {_ in}
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command,.shift,.option,.control])
        if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {focusSearch(); return true}
        if (modifiers == .command || modifiers == [.command,.shift]) && event.charactersIgnoringModifiers?.lowercased() == "g" {
            nextMatch(modifiers.contains(.shift)); return true
        }
        return super.performKeyEquivalent(with:event)
    }
}
final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool {true}
    override var canBecomeMain: Bool {false}
}
final class ChatInterface: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
    let composer = ComposerPanel(contentRect:NSRect(x:0,y:0,width:500,height:350),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private lazy var composerMotion = BubbleMotion(window:composer)
    var composerVisible: Bool {composerMotion.presented}
    var composerFrame: NSRect {composerMotion.frame}
    func moveComposer(to origin: NSPoint) {composerMotion.move(to:origin)}
    let history = HistoryWindow(contentRect:NSRect(x:0,y:0,width:920,height:700),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
    let composerEditor = MessageEditor(), historyEditor = MessageEditor(), transcript = StreamingTextView()
    private let historySplit = NSSplitViewController()
    private var historyDetailItem: NSSplitViewItem!
    private var historyInputHeight: NSLayoutConstraint!
    let list = HistoryTableView(), status = label(PetPreferences.shared.fixedText("主人，今天想让我帮什么忙呀？")), folder = label("")
    let historyStatus = label(PetPreferences.shared.fixedText("主人的叮嘱，我都记在这台电脑里啦"))
    private let composerKeys = label(""), historyKeys = label("")
    let models: ChatModelSettings
    private(set) var composerModel: ModelSelector!, historyModel: ModelSelector!
    var composerButton: ActionButton!, historyButton: ActionButton!
    var conversations: [Conversation] = []
    private(set) var visibleConversations: [Conversation] = []
    let searchField = NSSearchField()
    private var searchItem: NSSearchToolbarItem?
    private var snippets = [String:String]()
    private let noSearchResults = label("未找到匹配记录")
    private var findMatches = [NSRange](), matchIndex = 0
    private let matchLabel = label("")
    private var previousMatch: ActionButton!, nextMatch: ActionButton!
    private var searching: Bool {!searchField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
    var onGoCodex: () -> Void = {}
    var onCheckDelivery: () -> Void = {}
    var onRename: (String,String) -> Void = {_,_ in}
    var onSyncTitle: (String) -> Void = {_ in}
    var onDelete: (String) -> Void = {_ in}
    var selected: String?
    var onSelect: (String) -> Void = { _ in }, onSubmit: (String,Bool) -> Void = { _,_ in }
    var onStop: () -> Void = {}, onNew: () -> Void = {}, onFolder: () -> Void = {}, onHide: () -> Void = {}, onOpenHistory: () -> Void = {}, onRevealFolder: () -> Void = {}, onComposerResize: () -> Void = {}
    private let recovery = NSStackView()
    private let composerClose = BubbleCloseButton()
    private var localDismissMonitor: Any?, globalDismissMonitor: Any?
    var presentingFolderPicker = false
    var isPetInteraction:(NSEvent) -> Bool = {_ in false}
    private var composerInput: NSView!
    private var historyInput: MessageInputBox!
    private var external = false, externalSending = false, externalUnconfirmed = false, externalReady = false
    private var replyNote:String?
    private var externalMode:DesktopReply.Mode?
    private var externalModelNote:String?
    private let composerInheritedSettings = label("正在读取 Codex 会话设置…")
    private var drafts = [String:(composer:String,history:String)]()
    private var composerModelRow:NSStackView!
    private let inheritedSettings = label("沿用 Codex 原会话的模型与权限")
    private var historyPlaceholder: String {PetPreferences.shared.fixedText("主人，我们接着聊吧…")}
    private var composerFolder: ActionButton!, composerNew: ActionButton!
    private var renderedConversation: String?
    private var transcriptCache = [String:([String],NSAttributedString)]()
    var busy = false
    private var updatingList = false
    private var listSnapshot = [String]()
    override convenience init() {self.init(models:ChatModelSettings())}
    init(models: ChatModelSettings) {
        self.models = models
        super.init()
        composer.title = ""; history.title = PetPreferences.productName+" · 历史对话"
        for w in [composer as NSWindow,history] {w.isReleasedWhenClosed = false; w.delegate = self}
        composer.level = .floating; composer.contentMinSize = NSSize(width:500,height:350)
        composer.isOpaque = false; composer.backgroundColor = .clear; composer.hasShadow = true
        composer.isMovable = false; composer.isMovableByWindowBackground = false
        composer.hidesOnDeactivate = false
        composer.collectionBehavior.insert(.fullScreenNone)
        history.contentMinSize = NSSize(width:760,height:600)
        let c = BubbleBackgroundView(); composer.contentView = c
        composerInput = inputBox(composerEditor)
        recovery.orientation = .vertical; recovery.alignment = .leading; recovery.spacing = 8; recovery.isHidden = true
        status.font = .systemFont(ofSize:14); status.textColor = .labelColor
        status.maximumNumberOfLines = 2; status.lineBreakMode = .byTruncatingTail
        composerClose.onClose = { [weak self] in self?.hideComposer() }
        composerClose.widthAnchor.constraint(equalToConstant:24).isActive = true
        composerClose.heightAnchor.constraint(equalToConstant:24).isActive = true
        let header = NSStackView(views:[composerClose,status,NSView()]); header.spacing = 8; header.alignment = .centerY
        composerButton = ActionButton("发送") { [weak self] in guard let self else{return}; self.submit(self.composerEditor) }
        composerButton.emphasize()
        // 快捷键由聚焦的 MessageEditor 处理，避免输入法选词误触默认按钮。
        composerButton.keyEquivalent = ""
        composerFolder = ActionButton("文件夹…") { [weak self] in self?.onFolder() }
        let historyLink = ActionButton("历史") { [weak self] in self?.openHistory() }
        composerNew = ActionButton("开启新对话") { [weak self] in self?.onNew() }
        let footer = NSStackView(views:[composerFolder,historyLink,composerNew,NSView(),composerButton]); footer.distribution = .fill; footer.spacing = 8
        composerModel = ModelSelector(models)
        let modelRow = NSStackView(views:[modelHint(),composerModel,NSView()]); modelRow.spacing = 8; modelRow.alignment = .centerY
        composerModelRow = modelRow
        let stack = NSStackView(views:[header,composerInput,composerKeys,recovery,modelRow,composerInheritedSettings,footer]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        pin(stack,to:c.body,inset:16)
        [composerInput!,composerKeys,recovery,header,modelRow,composerInheritedSettings,footer].forEach {v in v.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        composerInheritedSettings.font = .systemFont(ofSize:11); composerInheritedSettings.textColor = .secondaryLabelColor
        composerInheritedSettings.maximumNumberOfLines = 2
        composerInput.heightAnchor.constraint(greaterThanOrEqualToConstant:120).isActive = true
        composerEditor.send = { [weak self] in guard let self else{return}; self.submit(self.composerEditor) }

        history.styleMask.insert(.fullSizeContentView)
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow; sidebar.state = .followsWindowActiveState
        let left = NSScrollView(); left.hasVerticalScroller = true; left.autohidesScrollers = true; left.drawsBackground = false
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("会话")); column.width = 224; column.resizingMask = .autoresizingMask
        list.addTableColumn(column); list.headerView = nil; list.rowHeight = 32; list.delegate = self; list.dataSource = self
        list.style = .plain; list.selectionHighlightStyle = .none; list.intercellSpacing = .zero
        list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; list.backgroundColor = .clear
        list.autoresizingMask = [.width]; column.minWidth = 0; left.hasHorizontalScroller = false; left.horizontalScrollElasticity = .none
        list.allowsEmptySelection = true; list.setAccessibilityLabel("历史对话"); left.documentView = list
        sidebar.addSubview(left); left.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([left.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor),left.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor),left.topAnchor.constraint(equalTo:sidebar.safeAreaLayoutGuide.topAnchor,constant:8),left.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor)])
        noSearchResults.textColor = .secondaryLabelColor; noSearchResults.alignment = .center; noSearchResults.isHidden = true
        sidebar.addSubview(noSearchResults); noSearchResults.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([noSearchResults.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:16),noSearchResults.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-16),noSearchResults.topAnchor.constraint(equalTo:left.topAnchor,constant:24)])
        let right = NSView()
        let navigation = NSViewController(); navigation.view = sidebar
        let destination = NSViewController(); destination.view = right
        let sidebarItem = NSSplitViewItem(sidebarWithViewController:navigation)
        sidebarItem.minimumThickness = 180; sidebarItem.maximumThickness = 340; sidebarItem.canCollapse = true; sidebarItem.allowsFullHeightLayout = true
        historyDetailItem = NSSplitViewItem(viewController:destination); historyDetailItem.minimumThickness = 520
        historySplit.addSplitViewItem(sidebarItem); historySplit.addSplitViewItem(historyDetailItem); historySplit.splitView.dividerStyle = .thin
        history.contentViewController = historySplit
        let toolbar = NSToolbar(identifier:"白龙历史工具栏"); toolbar.delegate = self; toolbar.displayMode = .iconOnly
        history.toolbar = toolbar; history.toolbarStyle = .unified
        history.focusSearch = { [weak self] in self?.focusHistorySearch() }
        history.nextMatch = { [weak self] backwards in self?.navigateMatch(backwards ? -1 : 1) }
        list.contextMenu = { [weak self] row in self?.conversationMenu(row) }
        list.target = self; list.action = #selector(revealSearchResult)
        historySplit.splitView.setPosition(240,ofDividerAt:0)
        transcript.isEditable = false; transcript.isSelectable = true
        let reading = editorScroll(transcript); reading.drawsBackground = false
        transcript.textContainerInset = NSSize(width:24,height:20)
        historyEditor.placeholder = historyPlaceholder
        historyInput = inputBox(historyEditor)
        let drafting = historyInput!
        historyButton = ActionButton("发送") { [weak self] in
            guard let self else{return}
            self.submit(self.historyEditor)
        }
        historyButton.emphasize(); historyButton.setContentHuggingPriority(.required,for:.horizontal)
        historyButton.setContentCompressionResistancePriority(.required,for:.horizontal)
        historyModel = ModelSelector(models)
        inheritedSettings.font = .systemFont(ofSize:11); inheritedSettings.textColor = .secondaryLabelColor
        let preferences = NSStackView(views:[historyModel,inheritedSettings,NSView(),historyButton]); preferences.spacing = 12; preferences.alignment = .centerY
        let inputArea = NSStackView(views:[drafting,preferences,historyKeys]); inputArea.orientation = .vertical; inputArea.alignment = .leading; inputArea.spacing = 8
        for view in [drafting,preferences,historyKeys] {view.widthAnchor.constraint(equalTo:inputArea.widthAnchor).isActive = true}
        folder.font = .systemFont(ofSize:11); folder.textColor = .secondaryLabelColor; folder.maximumNumberOfLines = 1; folder.lineBreakMode = .byTruncatingMiddle
        folder.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        historyStatus.font = .systemFont(ofSize:11); historyStatus.textColor = .secondaryLabelColor
        historyStatus.alignment = .right; historyStatus.maximumNumberOfLines = 1; historyStatus.lineBreakMode = .byTruncatingTail
        matchLabel.font = .systemFont(ofSize:11); matchLabel.textColor = .secondaryLabelColor
        previousMatch = ActionButton("") { [weak self] in self?.navigateMatch(-1) }
        nextMatch = ActionButton("") { [weak self] in self?.navigateMatch(1) }
        for (button,symbol,title) in [(previousMatch!,"chevron.up","上一处匹配（⇧⌘G）"),(nextMatch!,"chevron.down","下一处匹配（⌘G）")] {
            button.image = NSImage(systemSymbolName:symbol,accessibilityDescription:title)
            button.imagePosition = .imageOnly; button.setAccessibilityLabel(title)
            button.widthAnchor.constraint(equalToConstant:28).isActive = true
        }
        let metadata = NSStackView(views:[folder,NSView(),historyStatus,matchLabel,previousMatch!,nextMatch!]); metadata.spacing = 8; metadata.alignment = .centerY
        [matchLabel,previousMatch!,nextMatch!].forEach {$0.isHidden = true}
        let separator = NSBox(); separator.boxType = .separator
        for view in [metadata,reading,separator,inputArea] {view.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(view)}
        NSLayoutConstraint.activate([
            metadata.leadingAnchor.constraint(equalTo:right.leadingAnchor,constant:24),metadata.trailingAnchor.constraint(equalTo:right.trailingAnchor,constant:-24),metadata.topAnchor.constraint(equalTo:right.safeAreaLayoutGuide.topAnchor,constant:12),
            reading.leadingAnchor.constraint(equalTo:right.leadingAnchor),reading.trailingAnchor.constraint(equalTo:right.trailingAnchor),reading.topAnchor.constraint(equalTo:metadata.bottomAnchor,constant:8),reading.bottomAnchor.constraint(equalTo:separator.topAnchor),reading.heightAnchor.constraint(greaterThanOrEqualToConstant:180),
            separator.leadingAnchor.constraint(equalTo:right.leadingAnchor),separator.trailingAnchor.constraint(equalTo:right.trailingAnchor),
            inputArea.leadingAnchor.constraint(equalTo:right.leadingAnchor,constant:20),inputArea.trailingAnchor.constraint(equalTo:right.trailingAnchor,constant:-20),inputArea.topAnchor.constraint(equalTo:separator.bottomAnchor,constant:16),inputArea.bottomAnchor.constraint(equalTo:right.bottomAnchor,constant:-16)
        ])
        historyInputHeight = drafting.heightAnchor.constraint(equalToConstant:76); historyInputHeight.isActive = true
        historyEditor.onTextChange = { [weak self] in self?.resizeHistoryInput() }
        historyEditor.send = { [weak self] in guard let self else{return}; self.submit(self.historyEditor) }
        for text in [composerKeys,historyKeys] {text.font = .systemFont(ofSize:11); text.textColor = .secondaryLabelColor}
        updateShortcuts()
        history.center()
        NotificationCenter.default.addObserver(self,selector:#selector(accentChanged),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(modelStateChanged),name:ChatModelSettings.changed,object:models)
        NotificationCenter.default.addObserver(self,selector:#selector(updateShortcuts),name:PetPreferences.didChange,object:nil)
    }
    @objc private func updateShortcuts() {
        let shortcut = PetPreferences.shared.sendShortcut
        let action = external ? (externalSending ? "正在发送…" : externalUnconfirmed ? "检查发送结果" : externalMode == .steer ? "插话到 Codex" : "发送到 Codex") : busy ? "停止" : "发送"
        let hint = external ? (externalSending ? "正在发送到原会话…" : externalUnconfirmed ? "发送结果待确认，草稿已保留" : !externalReady ? "当前会话等待处理，请转到 Codex" : replyNote ?? shortcut.hint) : busy ? "停止："+shortcut.sendLabel : shortcut.hint
        composerKeys.stringValue = hint; historyKeys.stringValue = hint.replacingOccurrences(of:"\n",with:"  ·  ")
        composerButton.title = action; historyButton.title = action
        composerButton.hoverHelp = action+"："+shortcut.sendLabel
        historyButton.hoverHelp = composerButton.hoverHelp
        composerButton.keyEquivalent = ""; historyButton.keyEquivalent = ""
        composerEditor.setAccessibilityHelp(hint); historyEditor.setAccessibilityHelp(hint)
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
        stopDismissMonitoring(); composerModel.closeChoices(); composerMotion.hide(); onHide()
    }
    private func dismissComposerIfOutside(_ event: NSEvent) {
        guard composerVisible, !presentingFolderPicker, composer.attachedSheet == nil else{return}
        if isPetInteraction(event) {return}
        let point = NSEvent.mouseLocation
        if composer.frame.contains(point) || composerModel.containsInteraction(at:point,window:event.window) {return}
        hideComposer()
    }
    private func stopDismissMonitoring() {
        if let localDismissMonitor {NSEvent.removeMonitor(localDismissMonitor)}
        if let globalDismissMonitor {NSEvent.removeMonitor(globalDismissMonitor)}
        localDismissMonitor = nil; globalDismissMonitor = nil
    }
    deinit {stopDismissMonitoring()}
    private func modelHint() -> NSTextField {
        let hint = NSTextField(labelWithString:"选择模型与推理强度：")
        hint.font = .systemFont(ofSize:12); hint.textColor = .secondaryLabelColor
        hint.hoverHelp = "选择会自动记忆，并同步到两个聊天入口。"
        return hint
    }
    private func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0, verticalInset: CGFloat? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:inset),view.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-inset),view.topAnchor.constraint(equalTo:parent.topAnchor,constant:verticalInset ?? inset),view.bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-(verticalInset ?? inset))])
    }
    private func inputBox(_ editor: MessageEditor) -> MessageInputBox {
        MessageInputBox(scroll:editorScroll(editor),editor:editor)
    }
    func editorScroll(_ editor: NSTextView) -> NSScrollView {
        let scroll = GutterScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        editor.frame = NSRect(x:0,y:0,width:300,height:100)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true; editor.textContainer?.containerSize = NSSize(width:300,height:CGFloat.greatestFiniteMagnitude)
        editor.font = .systemFont(ofSize:14); editor.textColor = .labelColor; editor.drawsBackground = false
        editor.textContainerInset = NSSize(width:4,height:6); editor.isRichText = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.minSize = .zero; editor.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor
        return scroll
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("history-sidebar"),.init("history-divider"),.init("new"),.init("folder"),.init("codex"),.init("reveal"),.flexibleSpace,.init("search")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {toolbarAllowedItemIdentifiers(toolbar)}
    func toolbar(_ toolbar: NSToolbar,itemForItemIdentifier id: NSToolbarItem.Identifier,willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "search" {
            let item = NSSearchToolbarItem(itemIdentifier:id)
            searchField.placeholderString = "搜索历史记录"; searchField.setAccessibilityLabel("搜索标题和消息正文")
            searchField.sendsSearchStringImmediately = true; searchField.target = self; searchField.action = #selector(searchHistory)
            item.searchField = searchField; item.label = "搜索历史记录"; item.preferredWidthForSearchField = 220
            searchItem = item
            return item
        }
        if id.rawValue == "history-divider" {return NSTrackingSeparatorToolbarItem(identifier:id,splitView:historySplit.splitView,dividerIndex:0)}
        let item = NSToolbarItem(itemIdentifier:id); item.target = self; item.isBordered = true
        switch id.rawValue {
        case "history-sidebar":
            item.label = "显示或隐藏侧栏"; item.image = NSImage(systemSymbolName:"sidebar.left",accessibilityDescription:item.label)
            item.target = historySplit; item.action = #selector(NSSplitViewController.toggleSidebar(_:))
        case "new": item.label = "新对话"; item.image = NSImage(systemSymbolName:"square.and.pencil",accessibilityDescription:item.label); item.action = #selector(newChat)
        case "folder": item.label = "选择文件夹"; item.image = NSImage(systemSymbolName:"folder",accessibilityDescription:item.label); item.action = #selector(chooseFolder)
        case "codex": item.label = "跳转到 Codex"; item.image = AppIcons.openAI; item.action = #selector(goCodex)
        case "reveal": item.label = "访达中打开"; item.image = AppIcons.finder; item.action = #selector(revealFolder)
        default: return nil
        }
        item.paletteLabel = item.label; item.installHoverHelp()
        return item
    }
    private func resizeHistoryInput() {
        guard let height = historyInputHeight, let container = historyEditor.textContainer, let layout = historyEditor.layoutManager else {return}
        layout.ensureLayout(for:container)
        let textHeight = layout.usedRect(for:container).height + historyEditor.textContainerInset.height * 2 + 26
        height.constant = min(160,max(76,textHeight.rounded(.up)))
    }
    @objc private func modelStateChanged() {
        let enabled = external ? !busy && !externalSending && (externalReady || externalUnconfirmed) : busy || !models.loading
        composerButton.isEnabled = enabled; historyButton.isEnabled = enabled
        let selectorWidth = max(280,composerModel.intrinsicContentSize.width.rounded(.up))
        let hintWidth = ("选择模型与推理强度：" as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width.rounded(.up)+6
        let composerWidth = max(500,selectorWidth+hintWidth+40)
        composer.contentMinSize = NSSize(width:composerWidth,height:350)
        if let content = composer.contentView, content.bounds.width < composerWidth {composerMotion.resize(to:NSSize(width:composerWidth,height:content.bounds.height))}
        let detailWidth = max(520,historyModel.intrinsicContentSize.width.rounded(.up)+historyButton.intrinsicContentSize.width+64)
        historyDetailItem.minimumThickness = detailWidth
        let historyWidth = max(800,detailWidth+180)
        history.contentMinSize = NSSize(width:historyWidth,height:600)
        if let content = history.contentView, content.bounds.width < historyWidth {history.setContentSize(NSSize(width:historyWidth,height:content.bounds.height))}
    }
    func windowDidResize(_ notification: Notification) {if notification.object as? NSWindow === composer {onComposerResize()} else {resizeHistoryInput()}}
    @objc private func goCodex() {onGoCodex()}
    func focusHistorySearch() {
        searchItem?.beginSearchInteraction()
        history.makeFirstResponder(searchField); searchField.selectText(nil)
    }
    @objc private func searchHistory() {
        matchIndex = 0; refreshList()
        if let current = conversations.first(where:{$0.key == selected}) {
            refresh(Array(conversations.reversed()),selected:current,busy:busy)
        }
        updateSearchHighlights(reveal:true)
    }
    @objc private func revealSearchResult() {if searching {matchIndex = 0; updateSearchHighlights(reveal:true)}}
    private func navigateMatch(_ direction:Int) {
        guard searching,!findMatches.isEmpty else {focusHistorySearch(); return}
        matchIndex = (matchIndex+direction+findMatches.count)%findMatches.count
        updateSearchHighlights(reveal:true)
    }
    private func updateSearchHighlights(reveal:Bool) {
        guard let layout = transcript.layoutManager else {return}
        let text = transcript.string, whole = NSRange(location:0,length:(text as NSString).length)
        layout.removeTemporaryAttribute(.backgroundColor,forCharacterRange:whole)
        findMatches = searching ? HistorySearch.ranges(in:text,query:searchField.stringValue) : []
        matchIndex = findMatches.isEmpty ? 0 : min(matchIndex,findMatches.count-1)
        for (index,range) in findMatches.enumerated() {
            layout.addTemporaryAttribute(.backgroundColor,value:AppAccent.color.withAlphaComponent(index == matchIndex ? 0.38 : 0.18),forCharacterRange:range)
        }
        [matchLabel,previousMatch!,nextMatch!].forEach {$0.isHidden = !searching}
        previousMatch.isEnabled = !findMatches.isEmpty; nextMatch.isEnabled = !findMatches.isEmpty
        if searching {
            let titleHit = conversations.first(where:{$0.key == selected}).map {!HistorySearch.ranges(in:$0.title,query:searchField.stringValue).isEmpty} ?? false
            matchLabel.stringValue = findMatches.isEmpty ? (titleHit ? "标题匹配" : "正文无匹配") : "\(matchIndex+1) / \(findMatches.count)"
        }
        if reveal,!findMatches.isEmpty {transcript.scrollRangeToVisible(findMatches[matchIndex])}
    }
    private func refreshList() {
        visibleConversations = HistorySearch.filter(conversations,query:searchField.stringValue)
        noSearchResults.isHidden = !searching || !visibleConversations.isEmpty
        snippets = Dictionary(uniqueKeysWithValues:visibleConversations.compactMap {c in HistorySearch.snippet(c,query:searchField.stringValue).map {(c.key,$0)}})
        let snapshot = visibleConversations.map {$0.key+"\u{0}"+$0.title+"\u{0}"+(snippets[$0.key] ?? "")+"\u{0}"+searchField.stringValue}
        updatingList = true
        if snapshot != listSnapshot {list.reloadData(); list.noteHeightOfRows(withIndexesChanged:IndexSet(integersIn:0..<visibleConversations.count)); listSnapshot = snapshot}
        if let row = visibleConversations.firstIndex(where:{$0.key == selected}) {
            if list.selectedRow != row {list.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
        } else {list.deselectAll(nil)}
        updatingList = false
        list.setAccessibilityLabel(searchField.stringValue.isEmpty ? "历史对话" : "搜索结果：\(visibleConversations.count) 个对话")
    }
    private func conversationMenu(_ row:Int) -> NSMenu? {
        guard visibleConversations.indices.contains(row) else {return nil}
        let conversation = visibleConversations[row], menu = NSMenu()
        menu.autoenablesItems = false
        for (title,action) in [("重命名对话标题…",#selector(renameConversation(_:))),("同步 Codex 中生成的标题",#selector(syncConversationTitle(_:)))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:"")
            item.target = self; item.representedObject = conversation.key
            if action == #selector(syncConversationTitle(_:)) {item.isEnabled = conversation.threadID != nil}
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let delete = NSMenuItem(title:"删除记录…",action:#selector(deleteConversation(_:)),keyEquivalent:"")
        delete.target = self; delete.representedObject = conversation.key; menu.addItem(delete)
        return menu
    }
    @objc private func renameConversation(_ item:NSMenuItem) {
        guard let key = item.representedObject as? String,let conversation = conversations.first(where:{$0.key == key}) else {return}
        let alert = NSAlert(); alert.messageText = "重命名对话标题"
        alert.informativeText = "新标题保存在桌宠中。选择“同步 Codex 中生成的标题”可恢复跟随。"
        let field = NSTextField(string:conversation.title)
        field.frame = NSRect(x:0,y:0,width:340,height:24); field.usesSingleLineMode = true
        alert.accessoryView = field; alert.addButton(withTitle:"保存"); alert.addButton(withTitle:"取消")
        alert.applyAccent()
        alert.beginSheetModal(for:history) { [weak self] response in
            guard response == .alertFirstButtonReturn else {return}
            let title = field.stringValue.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
            if !title.isEmpty {self?.onRename(key,title)}
        }
        alert.window.makeFirstResponder(field); field.selectText(nil)
    }
    @objc private func syncConversationTitle(_ item:NSMenuItem) {
        if let key = item.representedObject as? String {onSyncTitle(key)}
    }
    @objc private func deleteConversation(_ item:NSMenuItem) {
        guard let key = item.representedObject as? String,let conversation = conversations.first(where:{$0.key == key}) else {return}
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "删除这条历史记录？"
        alert.informativeText = "从桌宠的本机历史文件中删除“\(conversation.title)”及其记录正文。Codex 原始会话和任务文件保留。"
        alert.addButton(withTitle:"取消"); alert.addButton(withTitle:"删除记录").hasDestructiveAction = true
        alert.beginDangerousSheet(for:history) { [weak self] response in
            if response == .alertSecondButtonReturn {self?.onDelete(key)}
        }
    }
    func discardHistory(_ key:String) {
        transcriptCache.removeValue(forKey:key)
        drafts.removeValue(forKey:key)
        if selected == key {historyEditor.string = ""; renderedConversation = nil}
    }
    func clearDrafts() {drafts.removeAll(); composerEditor.string = ""; historyEditor.string = ""}
    @objc private func newChat() {onNew()}
    @objc private func chooseFolder() {onFolder()}
    @objc private func revealFolder() {onRevealFolder()}
    func clearFailure() {recovery.isHidden = true; composerInput.isHidden = false; composerButton.isHidden = false}
    func showFailure(_ failure: AppFailure, restore: @escaping () -> Void) {
        recovery.arrangedSubviews.forEach {recovery.removeArrangedSubview($0); $0.removeFromSuperview()}
        let title = label(failure.title,bold:true), message = label(failure.message)
        let restoreButton = ActionButton("返回输入") { [weak self] in self?.clearFailure(); restore() }; restoreButton.emphasize()
        let details = ActionButton("技术详情…") {failure.showDetails()}
        let actions = NSStackView(views:[details,NSView(),restoreButton]); actions.spacing = 8
        for v in [title,message,actions] {recovery.addArrangedSubview(v); v.widthAnchor.constraint(equalTo:recovery.widthAnchor).isActive = true}
        if failure.openDesktop {
            let open = ActionButton("打开 Codex") {CodexConnection.openDesktop()}; open.emphasize(); recovery.insertArrangedSubview(open,at:2)
        }
        composerInput.isHidden = true; recovery.isHidden = false; composerButton.isHidden = !busy
    }
    func submit(_ editor: NSTextView) {
        if external {
            if externalUnconfirmed {onCheckDelivery(); return}
            guard externalReady && !externalSending && !busy else {return}
        } else if busy { onStop(); return }
        let text = editor.string.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty {
            if editor === historyEditor {transcript.scrollToEndOfDocument(nil)}
            onSubmit(text,editor === composerEditor)
        }
    }
    func clearSubmittedDraft(key:String,fromComposer:Bool,text:String) {
        if selected == key {
            let editor = fromComposer ? composerEditor : historyEditor
            if editor.string.trimmingCharacters(in:.whitespacesAndNewlines) == text {editor.string = ""}
        } else if var draft = drafts[key] {
            if fromComposer && draft.composer.trimmingCharacters(in:.whitespacesAndNewlines) == text {draft.composer = ""}
            if !fromComposer && draft.history.trimmingCharacters(in:.whitespacesAndNewlines) == text {draft.history = ""}
            drafts[key] = draft
        }
    }
    func refresh(_ conversations: [Conversation], selected: Conversation, busy: Bool, sending:Bool = false, unconfirmed:Bool = false, replyNote:String? = nil, replyMode:DesktopReply.Mode? = nil, modelNote:String? = nil) {
        if self.selected != selected.key {
            if let old = self.selected,conversations.contains(where:{$0.key == old}) {drafts[old] = (composerEditor.string,historyEditor.string)}
            composerEditor.string = drafts[selected.key]?.composer ?? ""
            historyEditor.string = drafts[selected.key]?.history ?? ""
            clearFailure()
        }
        self.conversations = conversations.reversed(); self.selected = selected.key; self.busy = busy
        self.external = selected.external; externalSending = sending; externalUnconfirmed = unconfirmed; self.replyNote = replyNote
        externalMode = replyMode; externalModelNote = modelNote
        externalReady = selected.threadID != nil && replyMode != nil
        let inherited = modelNote ?? "正在读取 Codex 会话设置…"
        inheritedSettings.stringValue = inherited; inheritedSettings.hoverHelp = inherited
        inheritedSettings.lineBreakMode = .byTruncatingMiddle
        inheritedSettings.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        composerInheritedSettings.stringValue = inherited; composerInheritedSettings.hoverHelp = inherited; composerInheritedSettings.isHidden = !external
        refreshList()
        folder.stringValue = "文件夹："+URL(fileURLWithPath:selected.cwd).lastPathComponent; folder.hoverHelp = selected.cwd
        historyInput.fillColor = .textBackgroundColor
        historyEditor.placeholder = external ? "回复这条 Codex 会话…" : historyPlaceholder
        updateShortcuts()
        let messageFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
        composerEditor.font = messageFont; historyEditor.font = messageFont; status.font = messageFont
        composerButton.isHidden = !recovery.isHidden && !busy
        composerButton.emphasize(!busy); historyButton.emphasize(!busy)
        modelStateChanged()
        composerFolder.isEnabled = !busy && !external; composerNew.isEnabled = !busy
        composerModel.isEnabled = !busy && !external; historyModel.isEnabled = !busy && !external
        composerModelRow.isHidden = external; historyModel.isHidden = external; inheritedSettings.isHidden = !external
        let streaming = selected.turns.last.map {activeStatuses.contains($0.status)} ?? false
        historyStatus.stringValue = sending ? "正在发送…" : unconfirmed ? "发送结果待确认" : streaming ? "处理中" : selected.external ? "Codex · 原会话回复" : ""
        history.title = selected.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" "); history.subtitle = "历史对话"
        resizeHistoryInput()
        composerEditor.placeholder = external ? "回复这条 Codex 会话…" : PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…")
        historyEditor.isEditable = !busy && !sending; composerEditor.isEditable = !busy && !sending
        let messageDirectory = selected.cwd.isEmpty ? nil : URL(fileURLWithPath:selected.cwd,isDirectory:true)
        transcript.linkBaseDirectory = {messageDirectory}
        guard history.isVisible && !history.isMiniaturized else {return}
        let selectionChanged = renderedConversation != selected.key
        transcript.automaticallyFollowsEnd = !searching
        transcript.setContent(transcriptContent(selected),animated:!searching && streaming && PetPreferences.shared.bool("typingEffect"),reset:selectionChanged)
        if selectionChanged {matchIndex = 0}
        renderedConversation = selected.key
        updateSearchHighlights(reveal:searching && selectionChanged)
    }
    @objc private func accentChanged() {
        transcriptCache.removeAll()
        list.needsDisplay = true; list.enumerateAvailableRowViews {row,_ in row.needsDisplay = true}; renderedConversation = nil
        if let c = conversations.first(where:{$0.key == selected}) {refresh(Array(conversations.reversed()),selected:c,busy:busy,sending:externalSending,unconfirmed:externalUnconfirmed,replyNote:replyNote,replyMode:externalMode,modelNote:externalModelNote)}
    }
    private func transcriptContent(_ conversation: Conversation) -> NSAttributedString {
        var result = NSMutableAttributedString()
        func append(_ text: String, font: NSFont = .systemFont(ofSize:PetPreferences.shared.number("messageFontSize")), color: NSColor = .labelColor, after: CGFloat = 12) {
            guard !text.isEmpty else {return}
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = after
            result.append(NSAttributedString(string:text+"\n",attributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph]))
        }
        func appendMarkdown(_ text: String, font: NSFont = .systemFont(ofSize:PetPreferences.shared.number("messageFontSize")), color: NSColor = .labelColor) {
            guard !text.isEmpty else{return}
            result.append(MarkdownText.render(text,font:font,color:color))
            result.append(NSAttributedString(string:"\n",attributes:[.font:font]))
        }
        if conversation.turns.isEmpty {
            append("与"+PetPreferences.shared.petName+"聊聊",font:.systemFont(ofSize:18,weight:.semibold),color:AppAccent.color)
            append("在下方输入想做的事。",color:.secondaryLabelColor)
            return result
        }
        let preferences = PetPreferences.shared
        let style = [preferences.petName,preferences.address,preferences.taskResultLine("completed"),String(preferences.number("messageFontSize")),String(conversation.external)]
        let keys = Set(conversation.turns.map(\.key))
        transcriptCache = transcriptCache.filter {keys.contains($0.key)}
        for turn in conversation.turns {
            let signature = style + [turn.input,turn.status,turn.messages,turn.summary,turn.steps,turn.final,turn.error,
                turn.sensitiveQuestionNotice ?? "",turn.sensitiveInputNotice ?? "",String(turn.date.timeIntervalSince1970)]
            if let cached = transcriptCache[turn.key],cached.0 == signature {result.append(cached.1); continue}
            let accumulated = result
            result = NSMutableAttributedString()
            if !turn.input.isEmpty {
                append(PetPreferences.shared.address+" · "+turn.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)),font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")+2,weight:.semibold),color:AppAccent.color,after:6)
                append(turn.input)
            }
            append(turn.status == "completed" ? PetPreferences.shared.petName+" · 「"+PetPreferences.shared.taskResultLine("completed")+"」" : PetPreferences.shared.petName+" · "+turnStatus(turn.status),font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")+2,weight:.semibold),color:AppAccent.color,after:6)
            // 只隐藏旧版外部观察器合成的步骤报错，不删历史字段或原始对话内容。
            let steps = conversation.external && turn.steps.hasPrefix("这一步执行遇到问题，任务尚未报告完成。") ? "" : turn.steps
            for (heading,text) in [("公开思考摘要",turn.summary),("执行记录",steps)] where !text.isEmpty {
                append(heading,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1),weight:.medium),color:.secondaryLabelColor,after:4)
                if heading == "公开思考摘要" {appendMarkdown(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
                else {append(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
            }
            if let notice = turn.sensitiveQuestionNotice {append(notice,color:.secondaryLabelColor)}
            if let notice = turn.sensitiveInputNotice {append(notice,color:.secondaryLabelColor)}
            if !turn.messages.isEmpty {appendMarkdown(turn.messages)}
            if !turn.final.isEmpty && !turn.messages.contains(turn.final) {appendMarkdown(turn.final)}
            if !turn.error.isEmpty {let failure = AppFailure.codex(turn.error); append(failure.title+"\n"+failure.message,color:.secondaryLabelColor)}
            append(" ",font:.systemFont(ofSize:4),after:12)
            transcriptCache[turn.key] = (signature,result)
            accumulated.append(result); result = accumulated
        }
        return result
    }
    private func turnStatus(_ value: String) -> String {
        ["pending":"准备中","running":"处理中","inProgress":"处理中","completed":"已完成","failed":"未完成","interrupted":"已停止","waitingForApproval":"等待批准","waitingForInput":"等待补充","unknown":"状态待确认"][value] ?? "状态待确认"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleConversations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = visibleConversations[row]
        return HistoryConversationCell(title:c.title,external:c.external,snippet:snippets[c.key],query:searchField.stringValue)
    }
    func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {searching ? 68 : 32}
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {AccentHistoryRow()}
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingList else { return }
        let row = list.selectedRow
        guard row >= 0 && row < visibleConversations.count else { return }
        let key = visibleConversations[row].key
        guard key != selected else { return }
        selected = key
        onSelect(key)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {if sender == composer {hideComposer()} else {sender.orderOut(nil)}; return false}
    func openHistory() {
        hideComposer(); onOpenHistory()
        // 历史是标准主窗口。首次打开后保留 Dock 入口，隐藏或关闭也可以从图标找回。
        NSApp.setActivationPolicy(.regular)
        if let icon = AppIcons.application {NSApp.applicationIconImage = icon}
        history.miniwindowImage = NSApp.applicationIconImage
        if history.isMiniaturized {history.deminiaturize(nil)}
        if !NSApp.isActive {NSApp.activate(ignoringOtherApps:true)}; history.makeKeyAndOrderFront(nil)
        refreshVisibleHistory()
        history.contentView?.layoutSubtreeIfNeeded()
        if searching {updateSearchHighlights(reveal:true)} else {transcript.scrollToEndOfDocument(nil)}
    }
    private func refreshVisibleHistory() {
        if let current = conversations.first(where:{$0.key == selected}) {refresh(Array(conversations.reversed()),selected:current,busy:busy)}
    }
    func windowDidDeminiaturize(_ notification:Notification) {
        if notification.object as? NSWindow === history {refreshVisibleHistory()}
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === history {history.miniwindowImage = NSApp.applicationIconImage}
    }
}
