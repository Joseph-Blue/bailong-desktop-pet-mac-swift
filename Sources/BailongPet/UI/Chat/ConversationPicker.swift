import AppKit

final class ConversationPicker:NSButton {
    var conversations:() -> [Conversation] = {[]}
    var onSelect:(String) -> Void = {_ in}
    private var panel:ConversationSearchPanel?
    var isPresented:Bool {panel != nil}

    init() {
        super.init(frame:.zero)
        title = "选择会话…"; bezelStyle = .rounded
        image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil); imagePosition = .imageTrailing
        target = self; action = #selector(open)
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        setAccessibilityLabel("选择目标会话")
    }
    required init?(coder:NSCoder) {fatalError()}

    func close(restoreFocus:Bool = true) {
        guard let panel else {return}
        self.panel = nil
        let parent = panel.parent, returnKey = restoreFocus && panel.isKeyWindow
        NotificationCenter.default.removeObserver(self,name:NSWindow.didMoveNotification,object:parent)
        NotificationCenter.default.removeObserver(self,name:NSWindow.didResizeNotification,object:parent)
        NotificationCenter.default.removeObserver(self,name:NSWindow.didBecomeKeyNotification,object:nil)
        NotificationCenter.default.removeObserver(self,name:NSApplication.didResignActiveNotification,object:NSApp)
        parent?.removeChildWindow(panel)
        panel.ignoresMouseEvents = true
        if returnKey,let parent,parent.isVisible {parent.makeKey()}
        panel.dismiss()
    }
    func containsInteraction(at point:NSPoint,window:NSWindow?) -> Bool {
        guard let panel else {return false}
        return panel === window || panel.frame.contains(point)
    }
    func dismissIfOutside(at point:NSPoint,window target:NSWindow?) {
        guard isPresented,!containsInteraction(at:point,window:target),
              window?.convertToScreen(convert(bounds,to:nil)).contains(point) != true else {return}
        close(restoreFocus:false)
    }
    @objc private func otherWindowBecameKey(_ notification:Notification) {
        guard let next = notification.object as? NSWindow,next !== panel,next !== window else {return}
        dismissForDeactivation()
    }
    @objc private func dismissForDeactivation() {close(restoreFocus:false)}
    @objc private func open() {
        if isPresented {close(); return}
        guard let parent = window else {return}
        let content = ConversationPickerContent(conversations:conversations())
        content.onSelect = { [weak self] key in self?.close(); self?.onSelect(key) }
        let panel = ConversationSearchPanel(content:content)
        self.panel = panel
        panel.level = parent.level
        panel.onCancel = { [weak self] in self?.close() }
        positionPanel()
        parent.addChildWindow(panel,ordered:.above)
        panel.present()
        panel.makeFirstResponder(content.search)
        for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(self,selector:#selector(positionPanel),name:name,object:parent)
        }
        NotificationCenter.default.addObserver(self,selector:#selector(otherWindowBecameKey(_:)),name:NSWindow.didBecomeKeyNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(dismissForDeactivation),name:NSApplication.didResignActiveNotification,object:NSApp)
    }
    @objc private func positionPanel() {
        guard let panel,let parent = window,let screen = PanelPresentation.screen(for:parent) else {return}
        let anchor = parent.convertToScreen(convert(bounds,to:nil))
        panel.position(at:anchor,on:screen.visibleFrame)
    }
}

private final class ConversationSearchPanel:ContentCursorPanel {
    var onCancel:() -> Void = {}
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
    override func cancelOperation(_ sender:Any?) {onCancel()}
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.keyCode == 53,(firstResponder as? NSTextView)?.hasMarkedText() != true {onCancel(); return true}
        return super.performKeyEquivalent(with:event)
    }

    private let material = NSVisualEffectView()
    private let content:ConversationPickerContent
    private let arrow:CGFloat = 10
    private var above = true
    private var tipX:CGFloat = 0
    init(content:ConversationPickerContent) {
        self.content = content
        super.init(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        let root = NSView()
        contentView = root
        root.addSubview(material); material.addSubview(content.view)
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        content.view.wantsLayer = true
        content.view.layer?.cornerRadius = 14
        content.view.layer?.masksToBounds = true
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        isReleasedWhenClosed = false; hidesOnDeactivate = false; animationBehavior = .none
        setAccessibilityRole(.popover)
        setAccessibilityLabel("会话搜索")
    }

    func present() {
        PanelPresentation.setAnchoredWindowLevel(self)
        alphaValue = DisclosureMotion.enabled ? 0 : 1
        makeKeyAndOrderFront(nil)
        if alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                animator().alphaValue = 1
            }
        }
    }

    func dismiss() {
        guard DisclosureMotion.enabled else {orderOut(nil); return}
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
        }
    }

    func position(at anchor:NSRect,on screen:NSRect) {
        let area = screen.insetBy(dx:4,dy:4)
        let top = area.maxY-anchor.maxY, bottom = anchor.minY-area.minY
        let opensAbove = top >= 320+arrow || top >= bottom
        let size = NSSize(width:min(400,area.width),height:min(320+arrow,max(arrow+1,opensAbove ? top : bottom)))
        let x = max(area.minX,min(anchor.midX-size.width/2,area.maxX-size.width))
        let y = opensAbove ? anchor.maxY : anchor.minY-size.height
        let frame = NSRect(origin:NSPoint(x:x,y:y),size:size)
        let tip = max(24,min(size.width-24,anchor.midX-x))
        let changed = material.frame.size != size || above != opensAbove || tipX != tip
        if self.frame != frame {setFrame(frame,display:false)}
        guard changed else {return}
        above = opensAbove; tipX = tip
        let bounds = NSRect(origin:.zero,size:size)
        material.frame = bounds
        let body = NSRect(x:0,y:above ? arrow : 0,width:size.width,height:size.height-arrow)
        content.view.frame = body
        material.maskImage = NSImage(size:size,flipped:false) { [arrow] _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect:body,xRadius:14,yRadius:14).fill()
            let base = opensAbove ? body.minY+1 : body.maxY-1
            let pointer = NSBezierPath()
            pointer.move(to:NSPoint(x:tip-arrow,y:base))
            pointer.line(to:NSPoint(x:tip,y:opensAbove ? bounds.minY : bounds.maxY))
            pointer.line(to:NSPoint(x:tip+arrow,y:base))
            pointer.close(); pointer.fill()
            return true
        }
        invalidateShadow()
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
        search.focusRingType = .none
        search.placeholderString = "搜索会话标题或工作区"; search.target = self; search.action = #selector(filter)
        search.sendsSearchStringImmediately = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
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
        TextInputFocusRing(surface:search,input:search,in:view)
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
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {AccentSelectionRow()}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let conversation = filtered[row]
        let active = conversation.turns.last.map {activeStatuses.contains($0.status)} ?? false
        return HistoryConversationCell(title:conversation.title,external:conversation.external,snippet:(active ? "执行中 · " : "")+conversation.cwd)
    }
}
