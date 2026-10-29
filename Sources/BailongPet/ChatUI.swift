import AppKit

final class MessageEditor: NSTextView {
    var send: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && (event.keyCode == 36 || event.keyCode == 76) { send(); return }
        super.keyDown(with:event)
    }
}
final class ChatInterface: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let composer = NSPanel(contentRect:NSRect(x:0,y:0,width:370,height:215),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    let history = NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:640),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
    let composerEditor = MessageEditor(), historyEditor = MessageEditor(), transcript = NSTextView()
    let list = NSTableView(), status = label("⌘ Command + ↩ Enter 发送"), folder = label("")
    var composerButton: ActionButton!, historyButton: ActionButton!, continueButton: ActionButton!
    var conversations: [Conversation] = []
    var selected: String?
    var onSelect: (String) -> Void = { _ in }, onSubmit: (String) -> Void = { _ in }
    var onStop: () -> Void = {}, onNew: () -> Void = {}, onFolder: () -> Void = {}, onContinue: () -> Void = {}, onHide: () -> Void = {}
    var busy = false
    override init() {
        super.init()
        composer.title = "与白龙对话"; history.title = "白龙桌宠 · 历史对话"
        for w in [composer as NSWindow,history] { w.isReleasedWhenClosed = false; w.delegate = self; w.contentMinSize = w.frame.size; w.contentView = materialView() }
        composer.level = .floating
        let c = composer.contentView!
        let edit = editorScroll(composerEditor); edit.frame = NSRect(x:16,y:58,width:338,height:116); edit.autoresizingMask = [.width,.height]; c.addSubview(edit)
        status.frame = NSRect(x:16,y:20,width:238,height:24); c.addSubview(status)
        composerButton = ActionButton("发送") { [weak self] in self?.submit(self!.composerEditor) }
        composerButton.frame = NSRect(x:274,y:14,width:80,height:32); composerButton.autoresizingMask = [.minXMargin]; c.addSubview(composerButton)
        composerEditor.send = { [weak self] in guard let self else{return}; self.submit(self.composerEditor) }
        let root = history.contentView!
        let split = NSSplitView(frame:NSRect(x:0,y:0,width:920,height:588)); split.isVertical = true; split.dividerStyle = .thin; split.autoresizingMask = [.width,.height]
        let left = NSScrollView(frame:NSRect(x:0,y:0,width:240,height:588)); left.hasVerticalScroller = true
        list.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("会话"))); list.headerView = nil; list.rowHeight = 54; list.delegate = self; list.dataSource = self
        list.allowsEmptySelection = false; left.documentView = list; split.addSubview(left)
        let right = NSView(frame:NSRect(x:0,y:0,width:680,height:588)); split.addSubview(right); root.addSubview(split)
        transcript.isEditable = false; transcript.isSelectable = true; transcript.drawsBackground = false; transcript.textColor = .labelColor; transcript.font = .systemFont(ofSize:14)
        let reading = editorScroll(transcript); reading.frame = NSRect(x:16,y:180,width:648,height:392); reading.autoresizingMask = [.width,.height]; right.addSubview(reading)
        let drafting = editorScroll(historyEditor); drafting.frame = NSRect(x:16,y:52,width:648,height:116); drafting.autoresizingMask = [.width]; right.addSubview(drafting)
        historyButton = ActionButton("发送") { [weak self] in self?.submit(self!.historyEditor) }; historyButton.frame = NSRect(x:574,y:12,width:90,height:32); historyButton.autoresizingMask = [.minXMargin]; right.addSubview(historyButton)
        continueButton = ActionButton("在新对话中继续") { [weak self] in self?.onContinue() }; continueButton.frame = NSRect(x:16,y:12,width:160,height:32); right.addSubview(continueButton)
        historyEditor.send = { [weak self] in guard let self else{return}; self.submit(self.historyEditor) }
        let new = ActionButton("新对话") { [weak self] in self?.onNew() }; new.frame = NSRect(x:16,y:600,width:100,height:28); new.autoresizingMask = [.minYMargin]; root.addSubview(new)
        let choose = ActionButton("选择任务文件夹…") { [weak self] in self?.onFolder() }; choose.frame = NSRect(x:126,y:600,width:160,height:28); choose.autoresizingMask = [.minYMargin]; root.addSubview(choose)
        folder.frame = NSRect(x:300,y:600,width:600,height:28); folder.autoresizingMask = [.width,.minYMargin]; root.addSubview(folder)
        history.center()
    }
    func editorScroll(_ editor: NSTextView) -> NSScrollView {
        let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.documentView = editor
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true; editor.font = .systemFont(ofSize:14)
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.minSize = .zero; editor.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        return scroll
    }
    func submit(_ editor: NSTextView) {
        if busy { onStop(); return }
        let text = editor.string.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty { onSubmit(text) }
    }
    func refresh(_ conversations: [Conversation], selected: Conversation, busy: Bool) {
        self.conversations = conversations.reversed(); self.selected = selected.key; self.busy = busy
        list.reloadData()
        if let row = self.conversations.firstIndex(where:{$0.key == selected.key}) { list.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
        folder.stringValue = selected.cwd; folder.toolTip = selected.cwd
        composerButton.title = busy ? "停止" : "发送"; historyButton.title = busy ? "停止" : "发送"
        continueButton.isHidden = !selected.external; continueButton.isEnabled = !busy
        historyEditor.isEditable = !selected.external && !busy; composerEditor.isEditable = !busy
        let body = selected.turns.map { turn in
            var sections = ["\(turn.date.formatted()) · \(turn.status)"]
            if !turn.input.isEmpty { sections.append("主人：\n"+turn.input) }
            if !turn.summary.isEmpty { sections.append("思考摘要（公开）：\n"+turn.summary) }
            if !turn.steps.isEmpty { sections.append("执行记录：\n"+turn.steps) }
            if !turn.messages.isEmpty { sections.append("回复：\n"+turn.messages) }
            if !turn.final.isEmpty && !turn.messages.contains(turn.final) { sections.append("结果：\n"+turn.final) }
            if !turn.error.isEmpty { sections.append("提示：\n"+turn.error) }
            return sections.joined(separator:"\n\n")
        }.joined(separator:"\n\n────────────\n\n")
        if transcript.string != body {
            let clip = transcript.enclosingScrollView!.contentView, old = transcript.enclosingScrollView!.contentView.bounds.origin
            let follow = clip.bounds.maxY >= transcript.bounds.maxY-8
            transcript.string = body
            if follow { transcript.scrollToEndOfDocument(nil) } else { clip.scroll(to:old) }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { conversations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = conversations[row]; let v = label((c.external ? "Codex · " : "")+c.title+"\n"+(c.turns.last?.status ?? "尚未发送")); v.font = .systemFont(ofSize:13); return v
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = list.selectedRow
        if row >= 0 && row < conversations.count && conversations[row].key != selected { onSelect(conversations[row].key) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); if sender == composer {onHide()}; return false }
    func openHistory() { history.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
}
