import AppKit

final class ConversationPicker:NSButton,NSPopoverDelegate {
    var conversations:() -> [Conversation] = {[]}
    var onSelect:(String) -> Void = {_ in}
    private let popover = NSPopover()
    init() {
        super.init(frame:.zero)
        title = "选择会话…"; bezelStyle = .rounded
        image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil); imagePosition = .imageTrailing
        target = self; action = #selector(open)
        popover.delegate = self
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        setAccessibilityLabel("选择目标会话")
    }
    required init?(coder:NSCoder) {fatalError()}
    func close() {popover.performClose(nil)}
    func popoverDidClose(_ notification:Notification) {popover.contentViewController = nil}
    func containsInteraction(at point:NSPoint,window:NSWindow?) -> Bool {
        guard popover.isShown,let panel = popover.contentViewController?.view.window else {return false}
        return panel === window || panel.frame.contains(point)
    }
    @objc private func open() {
        if popover.isShown {close(); return}
        let content = ConversationPickerContent(conversations:conversations())
        content.onSelect = { [weak self] key in self?.close(); self?.onSelect(key) }
        popover.contentViewController = content; popover.behavior = .transient; popover.animates = false
        popover.contentSize = NSSize(width:400,height:320)
        popover.show(relativeTo:bounds,of:self,preferredEdge:.maxY)
        content.view.window?.makeFirstResponder(content.search)
    }
}

private final class ConversationPickerContent:NSViewController,NSTableViewDataSource,NSTableViewDelegate {
    let search = NSSearchField()
    private let table = NSTableView(), empty = label("没有可选会话")
    private let conversations:[Conversation]
    private var filtered = [Conversation]()
    var onSelect:(String) -> Void = {_ in}
    init(conversations:[Conversation]) {self.conversations = conversations; filtered = conversations; super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        view = NSView(frame:NSRect(x:0,y:0,width:400,height:320))
        search.placeholderString = "搜索会话标题或工作区"; search.target = self; search.action = #selector(filter)
        search.sendsSearchStringImmediately = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let column = NSTableColumn(identifier:.init("conversation")); table.addTableColumn(column); table.headerView = nil
        table.delegate = self; table.dataSource = self; table.target = self; table.action = #selector(selectRow)
        table.rowHeight = 82; table.style = .plain; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        scroll.documentView = table; empty.textColor = .secondaryLabelColor; empty.isHidden = !filtered.isEmpty
        for child in [search,scroll,empty] {view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false}
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo:view.topAnchor,constant:12),search.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:12),search.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-12),
            scroll.topAnchor.constraint(equalTo:search.bottomAnchor,constant:8),scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo:scroll.centerXAnchor),empty.topAnchor.constraint(equalTo:scroll.topAnchor,constant:16)
        ])
    }
    @objc private func filter() {
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        filtered = query.isEmpty ? conversations : conversations.filter {($0.title+" "+$0.cwd).localizedStandardContains(query)}
        table.reloadData(); empty.isHidden = !filtered.isEmpty
    }
    @objc private func selectRow() {
        guard filtered.indices.contains(table.selectedRow) else {return}
        onSelect(filtered[table.selectedRow].key)
    }
    func numberOfRows(in tableView:NSTableView) -> Int {filtered.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let conversation = filtered[row]
        let active = conversation.turns.last.map {activeStatuses.contains($0.status)} ?? false
        return HistoryConversationCell(title:conversation.title,external:conversation.external,snippet:(active ? "执行中 · " : "")+conversation.cwd)
    }
}
