import AppKit

final class HistoryWindow: NSWindow {
    private var restoredFrame:NSRect?
    override func zoom(_ sender:Any?) {
        guard let area = screen?.visibleFrame else {return}
        if frame.equalTo(area),let restoredFrame {setFrame(restoredFrame,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion); self.restoredFrame = nil}
        else {restoredFrame = frame; setFrame(area,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)}
    }
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
final class ChatInterface: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
    private let composerView:ChatComposer
    var composer:ComposerPanel {composerView.composer}
    var composerEditor:MessageEditor {composerView.composerEditor}
    var status:NSTextField {composerView.status}
    var composerVisible:Bool {composerView.composerVisible}
    var composerFrame:NSRect {composerView.composerMotion.frame}
    func moveComposer(to origin:NSPoint) {composerView.composerMotion.move(to:origin)}
    let history = HistoryWindow(contentRect:NSRect(x:0,y:0,width:1100,height:850),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
    let historyEditor = MessageEditor(), transcript = MessageTextView()
    private let historySplit = NSSplitViewController()
    private var historyDetailItem: NSSplitViewItem!
    private var historyInputHeight: NSLayoutConstraint!
    let list = HistoryTableView(), folder = label("")
    let historyStatus = label(PetPreferences.shared.fixedText("主人的叮嘱，我都记在这台电脑里啦"))
    let models: ChatModelSettings
    let composerModels = ChatModelSettings()
    private(set) var historyModel: ModelSelector!
    var historyButton: ActionButton!
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
    var onOpenWorkspace:(URL) -> Void = {_ in}
    var onGoCodex: () -> Void = {}
    var onComposerHistory:() -> Void = {}
    var onRetrySettings:(ChatEntry) -> Void = {_ in}
    var onCheckDelivery: (String,ChatEntry) -> Void = {_,_ in}
    var onRename: (String,String) -> Void = {_,_ in}
    var onSyncTitle: (String) -> Void = {_ in}
    var onDelete: (String) -> Void = {_ in}
    var selected: String?
    var onSelect: (String) -> Void = { _ in }, onSubmit: (String,String,ChatEntry) -> Void = { _,_,_ in }
    var onStop:(String) -> Void = {_ in}, onNew:(ChatEntry) -> Void = {_ in}, onFolder:(ChatEntry) -> Void = {_ in}
    var onNewDefault:(ChatEntry) -> Void = {_ in}
    var onComposerSelect:(String) -> Void = {_ in}, onMode:(ConversationKind) -> Void = {_ in}
    var onReleaseHistory:() -> Void = {}
    var onHistoryPage:(Conversation,[Turn]) -> Void = {_,_ in}
    var onHide: () -> Void = {}, onOpenHistory: () -> Void = {}, onRevealFolder: () -> Void = {}, onComposerResize: () -> Void = {}
    var presentingFolderPicker:Bool {get {composerView.presentingFolderPicker} set {composerView.presentingFolderPicker = newValue}}
    var isPetInteraction:(NSEvent) -> Bool {get {composerView.isPetInteraction} set {composerView.isPetInteraction = newValue}}
    private var historyInput: MessageInputBox!
    private var inputStates = [ChatEntry:ChatInputState]()
    private let drafts = ChatDraftCache()
    private var historyStop:ActionButton!, historyCheck:ActionButton!, historyRetrySettings:ActionButton!
    private let sourceLabel = label("",bold:true)
    func targetKey(_ entry:ChatEntry) -> String? {drafts.target(entry)}
    func modelSettings(_ entry:ChatEntry) -> ChatModelSettings {entry == .composer ? composerModels : models}
    private func editor(_ entry:ChatEntry) -> MessageEditor {entry == .composer ? composerEditor : historyEditor}
    private let inheritedSettings = ChatReadOnlyModelField()
    private var historyPlaceholder: String {PetPreferences.shared.fixedText("主人，我们接着聊吧…")}
    private var renderedTranscriptSignature = [String]()
    private var historyPage = HistoryPageWindow()
    private var pageConversation:String?, pageQuery:String?
    private var renderedPageStart:Int?
    private let pageLabel = label("")
    private var pageNavigation:NSSegmentedControl!
    private var renderedConversation: String?
    private let transcriptRenderer = TranscriptRenderer()
    var busy = false
    private var updatingList = false
    private var listSnapshot = [String]()
    private var searchDataSignature = [String]()
    override convenience init() {self.init(models:ChatModelSettings())}
    init(models: ChatModelSettings) {
        self.models = models; composerView = ChatComposer(models:composerModels)
        super.init()
        history.collectionBehavior.insert(.fullScreenNone)
        composer.title = ""; history.title = PetPreferences.productName+" · 历史对话"
        for w in [composer as NSWindow,history] {w.isReleasedWhenClosed = false; w.delegate = self}
        history.contentMinSize = NSSize(width:760,height:600)
        composerView.onSubmit = { [weak self] in guard let self else {return}; self.submit(self.composerEditor) }
        composerView.onOpenWorkspace = { [weak self] url in self?.onOpenWorkspace(url) }
        composerView.onFolder = { [weak self] in self?.onFolder(.composer) }
        composerView.onNew = { [weak self] in self?.onNew(.composer) }
        composerView.onNewDefault = { [weak self] in self?.onNewDefault(.composer) }
        composerView.onMode = { [weak self] mode in self?.onMode(mode) }
        composerView.onSelect = { [weak self] key in self?.onComposerSelect(key) }
        composerView.onStop = { [weak self] in self?.stopTarget(.composer) }
        composerView.onCheck = { [weak self] in self?.checkTarget(.composer) }
        composerView.onHistory = { [weak self] in self?.onComposerHistory() }
        composerView.onOpenCodex = { [weak self] in CodexConnection.openConversation(self?.inputStates[.composer]?.conversation?.threadID) }
        composerView.onRetrySettings = { [weak self] in self?.onRetrySettings(.composer) }
        composerView.onHide = { [weak self] in self?.onHide() }
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
        transcript.onContentLayoutChange = { [weak self] in self?.updateSearchHighlights(reveal:false) }
        let reading = ChatViewLayout.editorScroll(transcript); reading.drawsBackground = false
        transcript.textContainerInset = NSSize(width:24,height:20)
        historyEditor.placeholder = historyPlaceholder
        historyInput = ChatViewLayout.inputBox(historyEditor)
        let drafting = historyInput!
        historyButton = ActionButton("发送") { [weak self] in
            guard let self else{return}
            self.submit(self.historyEditor)
        }
        ChatViewLayout.configureSendButton(historyButton)
        historyButton.emphasize(); historyButton.setContentHuggingPriority(.required,for:.horizontal)
        historyButton.setContentCompressionResistancePriority(.required,for:.horizontal)
        historyModel = ModelSelector(models)
        historyStop = ActionButton("停止任务") { [weak self] in self?.stopTarget(.history) }
        historyCheck = ActionButton("检查发送结果") { [weak self] in self?.checkTarget(.history) }
        historyRetrySettings = ActionButton("重新读取") { [weak self] in self?.onRetrySettings(.history) }
        let preferences = NSStackView(views:[historyModel,inheritedSettings,historyRetrySettings!,NSView(),historyStop,historyCheck,historyButton]); preferences.spacing = 12; preferences.alignment = .centerY
        let inputArea = NSStackView(views:[drafting,preferences]); inputArea.orientation = .vertical; inputArea.alignment = .leading; inputArea.spacing = 8
        for view in [drafting,preferences] {view.widthAnchor.constraint(equalTo:inputArea.widthAnchor).isActive = true}
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
        let targetMetadata = NSStackView(views:[sourceLabel,folder]); targetMetadata.orientation = .vertical; targetMetadata.alignment = .leading; targetMetadata.spacing = 3
        let metadata = NSStackView(views:[targetMetadata,NSView(),historyStatus,matchLabel,previousMatch!,nextMatch!]); metadata.spacing = 8; metadata.alignment = .centerY
        [matchLabel,previousMatch!,nextMatch!].forEach {$0.isHidden = true}
        pageNavigation = NSSegmentedControl(images:[NSImage(systemSymbolName:"chevron.left",accessibilityDescription:"较早记录")!,NSImage(systemSymbolName:"chevron.right",accessibilityDescription:"较新记录")!],trackingMode:.momentary,target:self,action:#selector(changeHistoryPage(_:)))
        pageNavigation.controlSize = .small
        for index in 0...1 {pageNavigation.setWidth(28,forSegment:index)}
        pageNavigation.setToolTip("查看较早的 20 轮记录",forSegment:0)
        pageNavigation.setToolTip("查看较新的 20 轮记录",forSegment:1)
        pageNavigation.setAccessibilityLabel("历史记录翻页")
        pageLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); pageLabel.textColor = .secondaryLabelColor
        let pages = NSStackView(views:[pageLabel,NSView(),pageNavigation!]); pages.spacing = 8; pages.alignment = .centerY; pages.distribution = .fill
        let separator = NSBox(); separator.boxType = .separator
        for view in [metadata,pages,reading,separator,inputArea] {view.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(view)}
        NSLayoutConstraint.activate([
            metadata.leadingAnchor.constraint(equalTo:right.leadingAnchor,constant:24),metadata.trailingAnchor.constraint(equalTo:right.trailingAnchor,constant:-24),metadata.topAnchor.constraint(equalTo:right.safeAreaLayoutGuide.topAnchor,constant:12),
            pages.leadingAnchor.constraint(equalTo:right.leadingAnchor,constant:24),pages.trailingAnchor.constraint(equalTo:right.trailingAnchor,constant:-24),pages.topAnchor.constraint(equalTo:metadata.bottomAnchor,constant:8),
            reading.leadingAnchor.constraint(equalTo:right.leadingAnchor),reading.trailingAnchor.constraint(equalTo:right.trailingAnchor),reading.topAnchor.constraint(equalTo:pages.bottomAnchor,constant:8),reading.bottomAnchor.constraint(equalTo:separator.topAnchor),reading.heightAnchor.constraint(greaterThanOrEqualToConstant:180),
            separator.leadingAnchor.constraint(equalTo:right.leadingAnchor),separator.trailingAnchor.constraint(equalTo:right.trailingAnchor),
            inputArea.leadingAnchor.constraint(equalTo:right.leadingAnchor,constant:20),inputArea.trailingAnchor.constraint(equalTo:right.trailingAnchor,constant:-20),inputArea.topAnchor.constraint(equalTo:separator.bottomAnchor,constant:16),inputArea.bottomAnchor.constraint(equalTo:right.bottomAnchor,constant:-16)
        ])
        historyInputHeight = drafting.heightAnchor.constraint(equalToConstant:76); historyInputHeight.isActive = true
        historyEditor.onTextChange = { [weak self] in self?.resizeHistoryInput() }
        historyEditor.send = { [weak self] in guard let self else{return}; self.submit(self.historyEditor) }
        updateShortcuts()
        if !history.setFrameUsingName("BailongHistory") {
            if let screen = NSScreen.main {
                history.setContentSize(NSSize(width:min(1100,screen.visibleFrame.width-80),height:min(850,screen.visibleFrame.height-100)))
            }
            history.center()
        }
        history.setFrameAutosaveName("BailongHistory")
        NotificationCenter.default.addObserver(self,selector:#selector(accentChanged),name:AppAccent.didChange,object:nil)
        for settings in [models,composerModels] {
            NotificationCenter.default.addObserver(self,selector:#selector(modelStateChanged),name:ChatModelSettings.changed,object:settings)
        }
        NotificationCenter.default.addObserver(self,selector:#selector(updateShortcuts),name:PetPreferences.didChange,object:nil)
    }
    @objc private func updateShortcuts() {
        let shortcut = PetPreferences.shared.sendShortcut
        for entry in [ChatEntry.composer,.history] {
            let state = inputStates[entry] ?? ChatInputState()
            let hint = shortcut.hint
            let button = entry == .composer ? composerView.composerButton! : historyButton!
            button.title = "发送"; button.keyEquivalent = ""
            button.hoverHelp = hint
            button.isEnabled = state.canSend(models:modelSettings(entry))
            editor(entry).setAccessibilityHelp(hint)
        }
    }
    private func stopTarget(_ entry:ChatEntry) {
        guard let state = inputStates[entry],state.ownsRunningTask,!state.stopping,let key = state.conversation?.key else {return}
        onStop(key)
    }
    private func checkTarget(_ entry:ChatEntry) {
        guard let state = inputStates[entry],state.unconfirmed,let key = state.conversation?.key else {return}
        onCheckDelivery(key,entry)
    }

    func showComposer() {composerView.showComposer()}
    func hideComposer() {composerView.hideComposer()}
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
        updateShortcuts()
        composerView.updateLayout()
        let detailWidth = max(520,historyModel.layoutWidth+historyButton.intrinsicContentSize.width+64)
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
        refreshVisibleHistory()
        updateSearchHighlights(reveal:true)
    }
    @objc private func revealSearchResult() {if searching {matchIndex = 0; updateSearchHighlights(reveal:true)}}
    private func navigateMatch(_ direction:Int) {
        guard searching,!findMatches.isEmpty else {focusHistorySearch(); return}
        matchIndex = (matchIndex+direction+findMatches.count)%findMatches.count
        updateSearchHighlights(reveal:true)
    }
    private func updateSearchHighlights(reveal:Bool) {
        if searching {transcript.revealFileEdits(matching:searchField.stringValue)}
        guard let layout = transcript.layoutManager else {return}
        let text = transcript.string, whole = NSRange(location:0,length:(text as NSString).length)
        if !findMatches.isEmpty {layout.removeTemporaryAttribute(.backgroundColor,forCharacterRange:whole)}
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
        guard history.isVisible && !history.isMiniaturized else {return}
        let searchSignature = [searchField.stringValue] + conversations.flatMap {[$0.key,$0.title] + (searching ? $0.turns.map {$0.bodyReference.id} : [])}
        if searchSignature != searchDataSignature {
            visibleConversations = HistorySearch.filter(conversations,query:searchField.stringValue)
            snippets = Dictionary(uniqueKeysWithValues:visibleConversations.compactMap {c in HistorySearch.snippet(c,query:searchField.stringValue).map {(c.key,$0)}})
            searchDataSignature = searchSignature
        }
        noSearchResults.isHidden = !searching || !visibleConversations.isEmpty
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
        // 渲染缓存按轮次键保存，会话删除必须清空整页，而不是拿会话键查轮次缓存。
        invalidateHistoryDisplay()
        drafts.forget(key); models.forget(key); composerModels.forget(key)
        if selected == key {historyEditor.string = ""; renderedConversation = nil}
    }
    func clearDrafts() {drafts.clear(); models.clearSelections(); composerModels.clearSelections(); composerEditor.string = ""; historyEditor.string = ""}
    @objc private func newChat() {onNew(.history)}
    @objc private func chooseFolder() {onFolder(.history)}
    @objc private func revealFolder() {onRevealFolder()}
    func clearFailure() {composerView.clearFailure()}
    func showFailure(_ failure:AppFailure,restore:@escaping () -> Void) {composerView.showFailure(failure,busy:busy,restore:restore)}
    func submit(_ editor:NSTextView) {
        let entry:ChatEntry = editor === composerEditor ? .composer : .history
        guard let state = inputStates[entry],state.canSend(models:modelSettings(entry)),let key = state.conversation?.key else {return}
        let text = editor.string.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty {onSubmit(key,text,entry)}
    }
    func clearSubmittedDraft(key:String,fromComposer:Bool,text:String) {
        let entry:ChatEntry = fromComposer ? .composer : .history
        if drafts.target(entry) == key {
            let input = editor(entry)
            if input.string.trimmingCharacters(in:.whitespacesAndNewlines) == text {input.string = ""}
        }
        drafts.clearSubmitted(key:key,entry:entry,text:text)
    }
    func restoreInput(_ text:String,key:String,entry:ChatEntry) {
        guard drafts.target(entry) == key else {return}
        if editor(entry).string.isEmpty {editor(entry).string = text}
    }
    func refresh(_ conversations:[Conversation],selected:Conversation,historyState:ChatInputState,composerState:ChatInputState) {
        for (entry,state) in [(ChatEntry.history,historyState),(.composer,composerState)] {
            if let restored = drafts.select(state.conversation?.key,entry:entry,current:editor(entry).string) {
                editor(entry).string = restored
                if entry == .composer {clearFailure()}
            }
            inputStates[entry] = state
        }
        self.conversations = conversations.enumerated().sorted {
            let left = $0.element.lastActivity, right = $1.element.lastActivity
            return left == right ? $0.offset > $1.offset : left > right
        }.map(\.element)
        self.selected = selected.key; self.busy = historyState.runningTitle != nil
        inheritedSettings.update(settings:historyState.modelSettings,error:historyState.modelNote)
        refreshList()
        sourceLabel.stringValue = selected.kind.title
        folder.stringValue = "工作区："+selected.cwd; folder.hoverHelp = selected.cwd
        historyInput.fillColor = .textBackgroundColor
        historyEditor.placeholder = selected.external ? "发送到这条 Codex 项目对话…" : historyPlaceholder
        let messageFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
        historyModel.font = messageFont; inheritedSettings.font = messageFont
        historyEditor.font = messageFont
        composerView.refresh(font:messageFont,state:composerState,conversations:self.conversations)
        historyButton.emphasize()
        historyModel.isEnabled = historyState.canEdit && !selected.external
        historyModel.isHidden = selected.external; inheritedSettings.isHidden = !selected.external
        historyRetrySettings.isHidden = !selected.external || historyState.desktopReady || historyState.modelNote == nil
        historyRetrySettings.isEnabled = !historyState.sending
        historyStop.isEnabled = !historyState.stopping
        historyStop.title = historyState.stopping ? "正在停止…" : "停止任务"
        historyStop.isHidden = !historyState.ownsRunningTask; historyCheck.isHidden = !historyState.unconfirmed
        historyStatus.stringValue = historyState.historyNote; historyStatus.hoverHelp = historyState.replyNote ?? historyState.historyNote
        history.title = selected.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" "); history.subtitle = selected.kind.title
        resizeHistoryInput(); modelStateChanged()
        composerEditor.placeholder = composerState.kind == .project ? "发送到这条 Codex 项目对话…" : PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…")
        historyEditor.isEditable = historyState.canEdit
        let messageDirectory = selected.cwd.isEmpty ? nil : URL(fileURLWithPath:selected.cwd,isDirectory:true)
        transcript.linkBaseDirectory = {messageDirectory}
        guard history.isVisible && !history.isMiniaturized else {return}
        let selectionChanged = renderedConversation != selected.key
        if pageConversation != selected.key {historyPage = HistoryPageWindow(); pageConversation = selected.key; pageQuery = nil}
        if pageQuery != searchField.stringValue {
            pageQuery = searchField.stringValue
            if searching,let index = selected.turns.firstIndex(where:{HistorySearch.matches($0,query:searchField.stringValue)}) {historyPage.reveal(index)}
            else if !searching {historyPage = HistoryPageWindow()}
        }
        let range = historyPage.range(count:selected.turns.count)
        let turns = Array(selected.turns[range])
        onHistoryPage(selected,turns)
        let pageChanged = renderedPageStart != range.lowerBound
        pageNavigation.setEnabled(range.lowerBound > 0,forSegment:0)
        pageNavigation.setEnabled(range.upperBound < selected.turns.count,forSegment:1)
        pageNavigation.isHidden = selected.turns.count <= HistoryPageWindow.size
        pageLabel.stringValue = turns.isEmpty ? "暂无记录" : pageNavigation.isHidden ? "共 \(selected.turns.count) 轮记录" : "第 \(range.lowerBound+1)–\(range.upperBound) 轮 · 共 \(selected.turns.count) 轮"
        let signature = transcriptRenderer.style(selected) + turns.flatMap {[ $0.key ] + transcriptRenderer.turnSignature($0)}
        let contentChanged = selectionChanged || pageChanged || signature != renderedTranscriptSignature
        if contentChanged {
            let readingOrigin = transcript.enclosingScrollView?.contentView.bounds.origin
            transcript.setContent(transcriptRenderer.content(selected,turns:turns),reset:selectionChanged || pageChanged)
            if (selectionChanged || pageChanged) && !searching {
                if historyPage.followsLatest {transcript.scrollToEndOfDocument(nil)} else {transcript.scrollToBeginningOfDocument(nil)}
            }
            else if let scroll = transcript.enclosingScrollView,let readingOrigin {
                scroll.contentView.scroll(to:readingOrigin); scroll.reflectScrolledClipView(scroll.contentView)
            }
            renderedTranscriptSignature = signature
        }
        if selectionChanged {matchIndex = 0}
        renderedConversation = selected.key; renderedPageStart = range.lowerBound
        if contentChanged || searching || !findMatches.isEmpty {updateSearchHighlights(reveal:searching && (selectionChanged || pageChanged))}
    }
    @objc private func accentChanged() {
        transcriptRenderer.invalidate()
        list.needsDisplay = true; list.enumerateAvailableRowViews {row,_ in row.needsDisplay = true}; renderedTranscriptSignature = []
        refreshVisibleHistory()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleConversations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = visibleConversations[row]
        return HistoryConversationCell(title:c.title,external:c.external,snippet:snippets[c.key],query:searchField.stringValue)
    }
    func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {searching ? 86 : 50}
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {AccentHistoryRow()}
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingList else { return }
        let row = list.selectedRow
        guard row >= 0 && row < visibleConversations.count else { return }
        let key = visibleConversations[row].key
        guard key != selected else { return }
        onSelect(key)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == composer {hideComposer(); return false}
        sender.makeFirstResponder(nil)
        return true
    }
    func invalidateHistoryDisplay() {
        transcriptRenderer.invalidate(); renderedTranscriptSignature.removeAll()
        renderedConversation = nil; searchDataSignature.removeAll()
    }
    @objc private func changeHistoryPage(_ sender:NSSegmentedControl) {
        guard sender.selectedSegment >= 0 else {return}
        moveHistoryPage(sender.selectedSegment == 0 ? -1 : 1)
    }
    private func moveHistoryPage(_ direction:Int) {
        guard let current = conversations.first(where:{$0.key == selected}) else {return}
        historyPage.move(direction,count:current.turns.count)
        refreshVisibleHistory()
    }
    func windowWillClose(_ notification:Notification) {
        guard notification.object as? NSWindow === history else {return}
        transcriptRenderer.invalidate()
        renderedTranscriptSignature.removeAll(); renderedConversation = nil
        renderedPageStart = nil; pageConversation = nil; pageQuery = nil
        searchDataSignature.removeAll(); snippets.removeAll()
        visibleConversations.removeAll(); listSnapshot.removeAll(); list.reloadData()
        findMatches.removeAll(); matchIndex = 0
        transcript.releaseRenderedContent()
        onReleaseHistory()
    }
    func openHistory() {
        hideComposer(); onOpenHistory()
        // 历史窗口打开或最小化期间保留 Dock 入口，关闭后移除。
        InterfaceWindows.shared.opened(history)
        if let icon = AppIcons.application {NSApp.applicationIconImage = icon}
        history.miniwindowImage = NSApp.applicationIconImage
        if history.isMiniaturized {history.deminiaturize(nil)}
        if !NSApp.isActive {NSApp.activate(ignoringOtherApps:true)}; history.makeKeyAndOrderFront(nil)
        refreshVisibleHistory()
        history.contentView?.layoutSubtreeIfNeeded()
        if searching {updateSearchHighlights(reveal:true)}
        else {transcript.scrollToEndOfDocument(nil)}
    }
    private func refreshVisibleHistory() {
        guard let current = conversations.first(where:{$0.key == selected}) else {return}
        // 搜索、重新打开和取消最小化只刷新显示，不重置发送状态、只读保护和原会话设置。
        refresh(Array(conversations.reversed()),selected:current,historyState:inputStates[.history] ?? ChatInputState(),composerState:inputStates[.composer] ?? ChatInputState())
    }
    func windowDidDeminiaturize(_ notification:Notification) {
        if notification.object as? NSWindow === history {refreshVisibleHistory()}
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === history {history.miniwindowImage = NSApp.applicationIconImage}
    }
}
