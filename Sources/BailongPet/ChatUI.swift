import AppKit

final class MessageEditor: NSTextView {
    var send: () -> Void = {}
    var placeholder = PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…") {didSet {needsDisplay = true}}
    override func didChangeText() {super.didChangeText(); needsDisplay = true}
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(in:NSRect(x:textContainerOrigin.x+5,y:textContainerOrigin.y,width:max(0,bounds.width-textContainerOrigin.x-14),height:bounds.height-textContainerOrigin.y),withAttributes:[.font:font ?? NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.placeholderTextColor])
        }
    }
    private func handleReturn(_ event: NSEvent) -> Bool {
        guard (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
              let sendNow = PetPreferences.shared.sendShortcut.action(modifiers:event.modifierFlags) else {return false}
        if sendNow {if !event.isARepeat {send()}} else if isEditable {insertNewline(nil)}
        return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 不给窗口默认按钮抢走输入法的确认键；只有本输入框聚焦时消费快捷键。
        guard window?.firstResponder === self else {return super.performKeyEquivalent(with:event)}
        return handleReturn(event) || super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event: NSEvent) {
        if !handleReturn(event) {super.keyDown(with:event)}
    }

}
final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool {true}
    override var canBecomeMain: Bool {false}
}
final class ChatInterface: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
    let composer = ComposerPanel(contentRect:NSRect(x:0,y:0,width:500,height:350),styleMask:[.borderless],backing:.buffered,defer:false)
    let history = NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:700),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
    let composerEditor = MessageEditor(), historyEditor = MessageEditor(), transcript = StreamingTextView()
    let list = NSTableView(), status = label("主人，今天想让我帮什么忙呀？"), folder = label("")
    let historyStatus = label("主人的叮嘱，我都记在这台电脑里啦")
    private let composerKeys = label(""), historyKeys = label("")
    let models: ChatModelSettings
    private(set) var composerModel: ModelSelector!, historyModel: ModelSelector!
    var composerButton: ActionButton!, historyButton: ActionButton!
    var conversations: [Conversation] = []
    var selected: String?
    var onSelect: (String) -> Void = { _ in }, onSubmit: (String,Bool) -> Void = { _,_ in }
    var onStop: () -> Void = {}, onNew: () -> Void = {}, onFolder: () -> Void = {}, onContinue: () -> Void = {}, onHide: () -> Void = {}, onOpenHistory: () -> Void = {}, onRevealFolder: () -> Void = {}, onComposerResize: () -> Void = {}
    private let recovery = NSStackView()
    private let composerClose = BubbleCloseButton()
    private var localDismissMonitor: Any?, globalDismissMonitor: Any?
    var presentingFolderPicker = false
    private var composerInput: NSView!
    private var historyInput: NSBox!
    private var historyReadOnly = false
    private var historyDraft: (key:String?,text:String)?
    private var historyPlaceholder: String {PetPreferences.shared.fixedText("主人，我们接着聊吧…")}
    private var composerFolder: ActionButton!, composerNew: ActionButton!
    private var renderedConversation: String?
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
        let stack = NSStackView(views:[header,composerInput,composerKeys,recovery,modelRow,footer]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        pin(stack,to:c,inset:16)
        [composerInput!,composerKeys,recovery,header,modelRow,footer].forEach {v in v.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        composerInput.heightAnchor.constraint(greaterThanOrEqualToConstant:120).isActive = true
        composerEditor.send = { [weak self] in guard let self else{return}; self.submit(self.composerEditor) }

        let toolbar = NSToolbar(identifier:"白龙历史工具栏"); toolbar.delegate = self; toolbar.displayMode = .iconOnly
        history.toolbar = toolbar; history.toolbarStyle = .unified
        let root = NSView(); history.contentView = root
        let split = HistorySplitView(); split.isVertical = true; split.dividerStyle = .thin
        let sidebar = HistorySidebarView(frame:.zero)
        let left = NSScrollView(); left.hasVerticalScroller = true; left.autohidesScrollers = true; left.drawsBackground = false
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("会话")); column.width = 224; column.resizingMask = .autoresizingMask
        list.addTableColumn(column); list.headerView = nil; list.rowHeight = 34; list.delegate = self; list.dataSource = self
        list.style = .plain; list.selectionHighlightStyle = .regular; list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; list.backgroundColor = .clear
        list.autoresizingMask = [.width]; column.minWidth = 0; left.hasHorizontalScroller = false; left.horizontalScrollElasticity = .none
        list.allowsEmptySelection = false; left.documentView = list; pin(left,to:sidebar,inset:8)
        sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant:210).isActive = true
        sidebar.widthAnchor.constraint(lessThanOrEqualToConstant:280).isActive = true
        let right = roundedPanel(); split.addSubview(sidebar); split.addSubview(right)
        sidebar.setFrameSize(NSSize(width:240,height:640)); right.setFrameSize(NSSize(width:680,height:640))
        transcript.isEditable = false; transcript.isSelectable = true
        let reading = editorScroll(transcript); reading.drawsBackground = false
        pin(reading,to:right.contentView!,inset:20,verticalInset:0)
        historyEditor.placeholder = historyPlaceholder
        historyInput = inputBox(historyEditor)
        let drafting = historyInput!
        historyButton = ActionButton("发送") { [weak self] in
            guard let self else{return}
            if self.historyReadOnly {self.onContinue()} else {self.submit(self.historyEditor)}
        }
        historyButton.emphasize()
        historyModel = ModelSelector(models)
        let preferences = NSStackView(views:[modelHint(),historyModel,NSView(),historyButton]); preferences.spacing = 12; preferences.alignment = .centerY
        historyButton.widthAnchor.constraint(equalToConstant:184).isActive = true
        folder.font = .systemFont(ofSize:11); folder.textColor = .secondaryLabelColor; folder.maximumNumberOfLines = 1; folder.lineBreakMode = .byTruncatingMiddle
        folder.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        historyStatus.font = .systemFont(ofSize:11); historyStatus.textColor = .secondaryLabelColor
        historyStatus.alignment = .right; historyStatus.maximumNumberOfLines = 1; historyStatus.lineBreakMode = .byTruncatingTail
        let metadata = NSStackView(views:[folder,NSView(),historyStatus]); metadata.spacing = 12; metadata.alignment = .firstBaseline
        let body = NSStackView(views:[metadata,split,drafting,historyKeys,preferences]); body.orientation = .vertical; body.alignment = .leading; body.spacing = 12
        pin(body,to:root,inset:16)
        [metadata,split,drafting,historyKeys,preferences].forEach {$0.widthAnchor.constraint(equalTo:body.widthAnchor).isActive = true}
        drafting.heightAnchor.constraint(equalToConstant:104).isActive = true
        split.heightAnchor.constraint(greaterThanOrEqualToConstant:200).isActive = true
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
        let action = busy ? "停止" : "发送"
        let hint = busy ? "停止："+shortcut.sendLabel : shortcut.hint
        composerKeys.stringValue = hint; historyKeys.stringValue = historyReadOnly ? "只读记录可在新对话中继续。" : hint
        composerButton.title = action; historyButton.title = historyReadOnly ? "在新对话中继续" : action
        composerButton.toolTip = action+"："+shortcut.sendLabel
        historyButton.toolTip = historyReadOnly ? "把可见记录准备为新对话草稿" : composerButton.toolTip
        composerButton.keyEquivalent = ""; historyButton.keyEquivalent = ""
        composerEditor.setAccessibilityHelp(hint); historyEditor.setAccessibilityHelp(historyReadOnly ? "只读记录" : hint)
    }
    func showComposer() {
        composer.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
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
        stopDismissMonitoring(); composerModel.closeChoices(); composer.orderOut(nil); onHide()
    }
    private func dismissComposerIfOutside(_ event: NSEvent) {
        guard composer.isVisible, !presentingFolderPicker, composer.attachedSheet == nil else{return}
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
        hint.toolTip = "选择会自动记忆，并同步到两个聊天入口。"
        return hint
    }
    private func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0, verticalInset: CGFloat? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:inset),view.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-inset),view.topAnchor.constraint(equalTo:parent.topAnchor,constant:verticalInset ?? inset),view.bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-(verticalInset ?? inset))])
    }
    private func roundedPanel() -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.fillColor = .textBackgroundColor
        box.borderWidth = 0; box.cornerRadius = 10
        box.contentViewMargins = NSSize(width:4,height:4)
        return box
    }
    private func inputBox(_ editor: NSTextView) -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.borderColor = .separatorColor; box.fillColor = .textBackgroundColor; box.cornerRadius = 8; box.borderWidth = 0.5
        box.contentViewMargins = NSSize(width:8,height:8)
        pin(editorScroll(editor),to:box.contentView!)
        return box
    }
    func editorScroll(_ editor: NSTextView) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
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
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("new"),.init("folder"),.flexibleSpace,.init("reveal")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace,.init("new"),.init("folder"),.init("reveal")] }
    func toolbar(_ toolbar: NSToolbar,itemForItemIdentifier id: NSToolbarItem.Identifier,willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier:id); item.target = self
        if id.rawValue == "new" {item.label = "新对话"; item.image = NSImage(systemSymbolName:"square.and.pencil",accessibilityDescription:item.label); item.action = #selector(newChat)}
        else if id.rawValue == "folder" {item.label = "选择文件夹"; item.image = NSImage(systemSymbolName:"folder",accessibilityDescription:item.label); item.action = #selector(chooseFolder)}
        else if id.rawValue == "reveal" {
            item.label = "访达中打开"; item.paletteLabel = item.label; item.image = AppIcons.finder
            item.toolTip = item.label; item.action = #selector(revealFolder)
        }
        else {return nil}
        // 三个等宽项内各放一个原生圆形按钮，标签拥有独立完整宽度。
        let view = NSView(frame:NSRect(x:0,y:0,width:96,height:48))
        view.widthAnchor.constraint(equalToConstant:96).isActive = true; view.heightAnchor.constraint(equalToConstant:48).isActive = true
        let button = NSButton(frame:NSRect(x:33,y:17,width:30,height:30))
        button.bezelStyle = .circular; button.isBordered = true; button.imagePosition = .imageOnly
        button.image = item.image?.withSymbolConfiguration(.init(pointSize:19,weight:.regular)) ?? item.image
        button.imageScaling = .scaleProportionallyDown; button.target = self; button.action = item.action
        button.toolTip = item.label; button.setAccessibilityLabel(item.label)
        let caption = NSTextField(labelWithString:item.label); caption.alignment = .center; caption.font = .systemFont(ofSize:12,weight:.medium)
        caption.textColor = .secondaryLabelColor; caption.frame = NSRect(x:0,y:0,width:96,height:17)
        caption.maximumNumberOfLines = 1; caption.usesSingleLineMode = true
        view.addSubview(button); view.addSubview(caption)
        item.view = view; item.isBordered = false; item.paletteLabel = item.label; item.toolTip = item.label
        return item
    }
    @objc private func modelStateChanged() {
        composerButton.isEnabled = busy || !models.loading; historyButton.isEnabled = historyReadOnly ? !busy : busy || !models.loading
        let selectorWidth = max(280,composerModel.intrinsicContentSize.width.rounded(.up))
        let hintWidth = ("选择模型与推理强度：" as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width.rounded(.up)+6
        let composerWidth = max(500,selectorWidth+hintWidth+40)
        composer.contentMinSize = NSSize(width:composerWidth,height:350)
        if let content = composer.contentView, content.bounds.width < composerWidth {composer.setContentSize(NSSize(width:composerWidth,height:content.bounds.height))}
        let historyWidth = max(760,selectorWidth+hintWidth+184+68)
        history.contentMinSize = NSSize(width:historyWidth,height:600)
        if let content = history.contentView, content.bounds.width < historyWidth {history.setContentSize(NSSize(width:historyWidth,height:content.bounds.height))}
    }
    func windowDidResize(_ notification: Notification) {if notification.object as? NSWindow === composer {onComposerResize()}}
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
        guard editor !== historyEditor || !historyReadOnly else {return}
        if busy { onStop(); return }
        let text = editor.string.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty {
            if editor === historyEditor {transcript.scrollToEndOfDocument(nil)}
            onSubmit(text,editor === composerEditor)
        }
    }
    func refresh(_ conversations: [Conversation], selected: Conversation, busy: Bool) {
        let previousSelection = renderedConversation
        self.conversations = conversations.reversed(); self.selected = selected.key; self.busy = busy
        // reloadData 会先校正选择并同步通知 delegate；这不是用户切换对话。
        // 将重载与恢复选择视作一次更新，避免 onSelect → refresh 的递归循环。
        let snapshot = self.conversations.map { $0.key+"\u{0}"+$0.title }
        updatingList = true
        if snapshot != listSnapshot {list.reloadData(); listSnapshot = snapshot}
        if let row = self.conversations.firstIndex(where:{$0.key == selected.key}), list.selectedRow != row {list.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
        updatingList = false
        folder.stringValue = "任务文件夹："+selected.cwd; folder.toolTip = selected.cwd
        if selected.external != historyReadOnly {
            if selected.external {historyDraft = (previousSelection,historyEditor.string); historyEditor.string = ""}
            else {historyEditor.string = historyDraft?.key == selected.key ? historyDraft?.text ?? "" : ""; historyDraft = nil}
        }
        historyReadOnly = selected.external
        historyInput.fillColor = historyReadOnly ? .windowBackgroundColor : .textBackgroundColor
        historyEditor.placeholder = historyReadOnly ? "这是只读记录，点击「在新对话中继续」接着聊。" : historyPlaceholder
        updateShortcuts()
        let messageFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
        composerEditor.font = messageFont; historyEditor.font = messageFont; status.font = messageFont
        composerButton.isHidden = !recovery.isHidden && !busy
        composerButton.emphasize(!busy); historyButton.emphasize(!busy)
        modelStateChanged()
        composerFolder.isEnabled = !busy; composerNew.isEnabled = !busy
        composerModel.isEnabled = !busy; historyModel.isEnabled = !busy && !selected.external
        let streaming = selected.turns.last.map {activeStatuses.contains($0.status)} ?? false
        historyStatus.stringValue = PetPreferences.shared.fixedText(streaming ? "主人，我正忙着呢，进展会记在这里哦" : "主人的叮嘱，我都记在这台电脑里啦")
        history.title = PetPreferences.productName+" · 历史对话"
        composerEditor.placeholder = PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…")
        historyEditor.isEditable = !selected.external && !busy; composerEditor.isEditable = !busy
        transcript.setContent(transcriptContent(selected),animated:streaming && PetPreferences.shared.bool("typingEffect"),reset:renderedConversation != selected.key)
        renderedConversation = selected.key
    }
    @objc private func accentChanged() {
        list.needsDisplay = true; list.enumerateAvailableRowViews {row,_ in row.needsDisplay = true}; renderedConversation = nil
        if let c = conversations.first(where:{$0.key == selected}) {refresh(Array(conversations.reversed()),selected:c,busy:busy)}
    }
    private func transcriptContent(_ conversation: Conversation) -> NSAttributedString {
        let result = NSMutableAttributedString()
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
            append("在下方输入想做的事。\n"+PetPreferences.shared.sendShortcut.hint,color:.secondaryLabelColor)
            return result
        }
        for turn in conversation.turns {
            if !turn.input.isEmpty {
                append(PetPreferences.shared.address+" · "+turn.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)),font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")+2,weight:.semibold),color:AppAccent.color,after:6)
                append(turn.input)
            }
            append(turn.status == "completed" ? PetPreferences.shared.petName+" · 「"+PetPreferences.shared.address+"，完成啦！」" : PetPreferences.shared.petName+" · "+turnStatus(turn.status),font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")+2,weight:.semibold),color:AppAccent.color,after:6)
            // 只隐藏旧版外部观察器合成的步骤报错，不删历史字段或原始对话内容。
            let steps = conversation.external && turn.steps.hasPrefix("这一步执行遇到问题，任务尚未报告完成。") ? "" : turn.steps
            for (heading,text) in [("公开思考摘要",turn.summary),("执行记录",steps)] where !text.isEmpty {
                append(heading,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1),weight:.medium),color:.secondaryLabelColor,after:4)
                if heading == "公开思考摘要" {appendMarkdown(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
                else {append(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
            }
            if !turn.messages.isEmpty {appendMarkdown(turn.messages)}
            if !turn.final.isEmpty && !turn.messages.contains(turn.final) {appendMarkdown(turn.final)}
            if !turn.error.isEmpty {let failure = AppFailure.codex(turn.error); append(failure.title+"\n"+failure.message,color:.secondaryLabelColor)}
            append(" ",font:.systemFont(ofSize:4),after:12)
        }
        return result
    }
    private func turnStatus(_ value: String) -> String {
        ["pending":"准备中","running":"处理中","inProgress":"处理中","completed":"已完成","failed":"未完成","interrupted":"已停止","waitingForApproval":"等待批准","waitingForInput":"等待补充","unknown":"状态待确认"][value] ?? "状态待确认"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { conversations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = conversations[row]
        return FadingHistoryCell(title:(c.external ? "Codex · " : "")+c.title)
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {AccentHistoryRow()}
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingList else { return }
        let row = list.selectedRow
        guard row >= 0 && row < conversations.count else { return }
        let key = conversations[row].key
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
        NSApp.unhide(nil); history.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        history.contentView?.layoutSubtreeIfNeeded(); transcript.scrollToEndOfDocument(nil)
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === history {history.miniwindowImage = NSApp.applicationIconImage}
    }
}
