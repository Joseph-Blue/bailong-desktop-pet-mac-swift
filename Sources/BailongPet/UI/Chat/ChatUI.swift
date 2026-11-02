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
    private let historyKeys = label("")
    let models: ChatModelSettings
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
    var onGoCodex: () -> Void = {}
    var onCheckDelivery: () -> Void = {}
    var onRename: (String,String) -> Void = {_,_ in}
    var onSyncTitle: (String) -> Void = {_ in}
    var onDelete: (String) -> Void = {_ in}
    var selected: String?
    var onSelect: (String) -> Void = { _ in }, onSubmit: (String,Bool) -> Void = { _,_ in }
    var onStop: () -> Void = {}, onNew: () -> Void = {}, onFolder: () -> Void = {}, onHide: () -> Void = {}, onOpenHistory: () -> Void = {}, onRevealFolder: () -> Void = {}, onComposerResize: () -> Void = {}
    var presentingFolderPicker:Bool {get {composerView.presentingFolderPicker} set {composerView.presentingFolderPicker = newValue}}
    var isPetInteraction:(NSEvent) -> Bool {get {composerView.isPetInteraction} set {composerView.isPetInteraction = newValue}}
    private var historyInput: MessageInputBox!
    private var external = false, externalSending = false, externalUnconfirmed = false, externalReady = false
    private var historyReadOnly = false
    private var replyNote:String?
    private var externalMode:DesktopReply.Mode?
    private var externalModelNote:String?
    private var drafts = [String:(composer:String,history:String)]()
    private let inheritedSettings = label("沿用 Codex 原会话的模型与权限")
    private var historyPlaceholder: String {PetPreferences.shared.fixedText("主人，我们接着聊吧…")}
    private var renderedTranscriptSignature = [String]()
    private var renderedConversation: String?
    private let transcriptRenderer = TranscriptRenderer()
    var busy = false
    private var updatingList = false
    private var listSnapshot = [String]()
    override convenience init() {self.init(models:ChatModelSettings())}
    init(models: ChatModelSettings) {
        self.models = models; composerView = ChatComposer(models:models)
        super.init()
        history.collectionBehavior.insert(.fullScreenNone)
        composer.title = ""; history.title = PetPreferences.productName+" · 历史对话"
        for w in [composer as NSWindow,history] {w.isReleasedWhenClosed = false; w.delegate = self}
        history.contentMinSize = NSSize(width:760,height:600)
        composerView.onSubmit = { [weak self] in guard let self else {return}; self.submit(self.composerEditor) }
        composerView.onFolder = { [weak self] in self?.onFolder() }
        composerView.onNew = { [weak self] in self?.onNew() }
        composerView.onHistory = { [weak self] in self?.openHistory() }
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
        let reading = ChatViewLayout.editorScroll(transcript); reading.drawsBackground = false
        transcript.textContainerInset = NSSize(width:24,height:20)
        historyEditor.placeholder = historyPlaceholder
        historyInput = ChatViewLayout.inputBox(historyEditor)
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
        for text in [composerView.composerKeys,historyKeys] {text.font = .systemFont(ofSize:11); text.textColor = .secondaryLabelColor}
        updateShortcuts()
        if !history.setFrameUsingName("BailongHistory") {
            if let screen = NSScreen.main {
                history.setContentSize(NSSize(width:min(1100,screen.visibleFrame.width-80),height:min(850,screen.visibleFrame.height-100)))
            }
            history.center()
        }
        history.setFrameAutosaveName("BailongHistory")
        NotificationCenter.default.addObserver(self,selector:#selector(accentChanged),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(modelStateChanged),name:ChatModelSettings.changed,object:models)
        NotificationCenter.default.addObserver(self,selector:#selector(updateShortcuts),name:PetPreferences.didChange,object:nil)
    }
    @objc private func updateShortcuts() {
        let shortcut = PetPreferences.shared.sendShortcut
        let action = external ? (externalSending ? "正在发送…" : externalUnconfirmed ? "检查发送结果" : externalMode == .steer ? "插话到 Codex" : "发送到 Codex") : busy ? "停止" : "发送"
        let hint = external ? (externalSending ? "正在发送到原会话…" : externalUnconfirmed ? "发送结果待确认，草稿已保留" : !externalReady ? "当前会话等待处理，请转到 Codex" : replyNote ?? shortcut.hint) : busy ? "停止："+shortcut.sendLabel : shortcut.hint
        let displayHint = historyReadOnly ? "历史只读：请在设置 → 高级导出原文件或重新读取" : hint
        composerView.composerKeys.stringValue = displayHint; historyKeys.stringValue = displayHint.replacingOccurrences(of:"\n",with:"  ·  ")
        composerView.composerButton.title = action; historyButton.title = action
        composerView.composerButton.hoverHelp = action+"："+shortcut.sendLabel
        historyButton.hoverHelp = composerView.composerButton.hoverHelp
        composerView.composerButton.keyEquivalent = ""; historyButton.keyEquivalent = ""
        composerEditor.setAccessibilityHelp(displayHint); historyEditor.setAccessibilityHelp(displayHint)
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
        let enabled = external ? !busy && !externalSending && (externalReady || externalUnconfirmed) : busy || !models.loading
        composerView.composerButton.isEnabled = enabled && !historyReadOnly; historyButton.isEnabled = enabled && !historyReadOnly
        let selectorWidth = max(280,composerView.composerModel.intrinsicContentSize.width.rounded(.up))
        let hintWidth = ("选择模型与推理强度：" as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width.rounded(.up)+6
        let footerWidth = composerView.composerFooterButtons.filter {!$0.isHidden}.reduce(CGFloat(32+4*8)) {$0+$1.intrinsicContentSize.width}
        let composerWidth = max(500,selectorWidth+hintWidth+40,footerWidth)
        composer.contentMinSize = NSSize(width:composerWidth,height:350)
        if let content = composer.contentView, content.bounds.width < composerWidth {composerView.composerMotion.resize(to:NSSize(width:composerWidth,height:content.bounds.height))}
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
        transcriptRenderer.discard(key)
        drafts.removeValue(forKey:key)
        if selected == key {historyEditor.string = ""; renderedConversation = nil}
    }
    func clearDrafts() {drafts.removeAll(); composerEditor.string = ""; historyEditor.string = ""}
    @objc private func newChat() {onNew()}
    @objc private func chooseFolder() {onFolder()}
    @objc private func revealFolder() {onRevealFolder()}
    func clearFailure() {composerView.clearFailure()}
    func showFailure(_ failure:AppFailure,restore:@escaping () -> Void) {composerView.showFailure(failure,busy:busy,restore:restore)}
    func submit(_ editor: NSTextView) {
        if external {
            if externalUnconfirmed {onCheckDelivery(); return}
            guard externalReady && !externalSending && !busy else {return}
        } else if busy { onStop(); return }
        let text = editor.string.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty {
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
    func refresh(_ conversations: [Conversation], selected: Conversation, busy: Bool, sending:Bool = false, unconfirmed:Bool = false, replyNote:String? = nil, replyMode:DesktopReply.Mode? = nil, modelNote:String? = nil,readOnly:Bool = false) {
        if self.selected != selected.key {
            if let old = self.selected,conversations.contains(where:{$0.key == old}) {drafts[old] = (composerEditor.string,historyEditor.string)}
            composerEditor.string = drafts[selected.key]?.composer ?? ""
            historyEditor.string = drafts[selected.key]?.history ?? ""
            clearFailure()
        }
        self.conversations = conversations.enumerated().sorted {
            let left = $0.element.lastActivity, right = $1.element.lastActivity
            return left == right ? $0.offset > $1.offset : left > right
        }.map(\.element)
        self.selected = selected.key; self.busy = busy
        historyReadOnly = readOnly
        self.external = selected.external; externalSending = sending; externalUnconfirmed = unconfirmed; self.replyNote = replyNote
        externalMode = replyMode; externalModelNote = modelNote
        externalReady = selected.threadID != nil && replyMode != nil
        let inherited = modelNote ?? "正在读取 Codex 会话设置…"
        inheritedSettings.stringValue = inherited; inheritedSettings.hoverHelp = inherited
        inheritedSettings.lineBreakMode = .byTruncatingMiddle
        inheritedSettings.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        composerView.composerInheritedSettings.stringValue = inherited; composerView.composerInheritedSettings.hoverHelp = inherited; composerView.composerInheritedSettings.isHidden = !external
        refreshList()
        folder.stringValue = "文件夹："+URL(fileURLWithPath:selected.cwd).lastPathComponent; folder.hoverHelp = selected.cwd
        historyInput.fillColor = .textBackgroundColor
        historyEditor.placeholder = external ? "回复这条 Codex 会话…" : historyPlaceholder
        updateShortcuts()
        let messageFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
        historyEditor.font = messageFont
        composerView.refresh(font:messageFont,busy:busy,external:external)
        historyButton.emphasize(!busy)
        modelStateChanged()
        historyModel.isEnabled = !busy && !external
        historyModel.isHidden = external; inheritedSettings.isHidden = !external
        let streaming = selected.turns.last.map {activeStatuses.contains($0.status)} ?? false
        historyStatus.stringValue = sending ? "正在发送…" : unconfirmed ? "发送结果待确认" : streaming ? "处理中" : selected.external ? "Codex · 原会话回复" : ""
        history.title = selected.title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" "); history.subtitle = "历史对话"
        resizeHistoryInput()
        composerEditor.placeholder = external ? "回复这条 Codex 会话…" : PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…")
        historyEditor.isEditable = !busy && !sending && !readOnly; composerEditor.isEditable = !busy && !sending && !readOnly
        let messageDirectory = selected.cwd.isEmpty ? nil : URL(fileURLWithPath:selected.cwd,isDirectory:true)
        transcript.linkBaseDirectory = {messageDirectory}
        guard history.isVisible && !history.isMiniaturized else {return}
        let selectionChanged = renderedConversation != selected.key
        let signature = transcriptRenderer.style(selected) + selected.turns.flatMap {[ $0.key ] + transcriptRenderer.turnSignature($0)}
        let contentChanged = selectionChanged || signature != renderedTranscriptSignature
        if contentChanged {
            let readingOrigin = transcript.enclosingScrollView?.contentView.bounds.origin
            transcript.setContent(transcriptRenderer.content(selected),reset:selectionChanged)
            if selectionChanged && !searching {transcript.scrollToEndOfDocument(nil)}
            else if let scroll = transcript.enclosingScrollView,let readingOrigin {
                scroll.contentView.scroll(to:readingOrigin); scroll.reflectScrolledClipView(scroll.contentView)
            }
            renderedTranscriptSignature = signature
        }
        if selectionChanged {matchIndex = 0}
        renderedConversation = selected.key
        if contentChanged || searching || !findMatches.isEmpty {updateSearchHighlights(reveal:searching && selectionChanged)}
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
        if searching {updateSearchHighlights(reveal:true)}
        else {transcript.scrollToEndOfDocument(nil)}
    }
    private func refreshVisibleHistory() {
        guard let current = conversations.first(where:{$0.key == selected}) else {return}
        // 搜索、重新打开和取消最小化只刷新显示，不重置发送状态、只读保护和原会话设置。
        refresh(Array(conversations.reversed()),selected:current,busy:busy,sending:externalSending,
                unconfirmed:externalUnconfirmed,replyNote:replyNote,replyMode:externalMode,
                modelNote:externalModelNote,readOnly:historyReadOnly)
    }
    func windowDidDeminiaturize(_ notification:Notification) {
        if notification.object as? NSWindow === history {refreshVisibleHistory()}
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === history {history.miniwindowImage = NSApp.applicationIconImage}
    }
}
