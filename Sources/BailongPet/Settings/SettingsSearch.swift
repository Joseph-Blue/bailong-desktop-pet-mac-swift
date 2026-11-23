import AppKit

final class SettingsWindow: NSWindow {
    private var restoredFrame:NSRect?
    func restoreSavedFrame(named name:String) -> Bool {
        // 保存标准尺寸作为绿灯恢复目标，再读取用户保存的窗口位置与尺寸。
        restoredFrame = frame
        let restored = setFrameUsingName(name)
        setFrameAutosaveName(name)
        return restored
    }
    override func zoom(_ sender:Any?) {
        guard let area = screen?.visibleFrame else {return}
        if frame.equalTo(area),let restoredFrame {setFrame(restoredFrame,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion); self.restoredFrame = nil}
        else {restoredFrame = frame; setFrame(area,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)}
    }
    var focusSearch: () -> Void = {}
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command,.shift,.option,.control]) == .command {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "f" {focusSearch(); return true}
            if let editor = firstResponder as? SettingsTemplateEditor,
               let item = SettingsTemplateTokens.items.first(where:{$0.keyEquivalent == key}),
               editor.insertTemplateToken(item.token) {return true}
        }
        return super.performKeyEquivalent(with:event)
    }
}

struct SettingsSearchEntry {
    let section:SettingsSection
    let group:String
    let title:String
    var keywords = ""
    var condition = ""
    var detail:SettingsDetail?
    var itemID:String?
    var aboutTab:AboutPageController.Tab?
    var anchorTitle:String?
    var anchor:String {group+"/"+(anchorTitle ?? title)}
    var location:String {[section.title,detail?.title,detail?.title == group ? nil : group].compactMap {$0}.joined(separator:" › ")}

    // 索引只保存设置文案，不创建页面或触发预览、磁盘统计、登录项查询。
    static func all(catalog:Catalog?) -> [Self] {
        var entries = [Self]()
        func add(_ section:SettingsSection,_ group:String,_ titles:[String],_ keywords:String = "") {
            entries += titles.map {Self(section:section,group:group,title:$0,keywords:keywords)}
        }
        let glass = PetPreferences.glassAvailable
        let availability = PetPreferences.glassAvailabilityDescription
        let conditions:[String:String] = [
            "appearance.bubbleMaterial.title":availability,
            "appearance.glassFollowsSystem.title":glass ? L10n.text(.settings,"search.add.text.122") : availability,
            "appearance.render.text.4":glass ? L10n.text(.settings,"search.add.text.123") : availability,
            "appearance.render.text.2":L10n.text(.settings,"search.add.text.124"),
            "appearance.bubbleAspectRatio.title":L10n.text(.settings,"search.add.text.125"),
            "search.add.text.88":L10n.text(.settings,"search.add.text.126"),
            "search.add.text.89":L10n.text(.settings,"search.add.text.126"),
            "search.add.text.95":L10n.text(.settings,"search.add.text.127"),
            "search.add.text.102":L10n.text(.settings,"search.add.text.128"),
            "activity.sideExposurePercent.title":L10n.text(.settings,"search.add.text.129"),
            "activity.notchExposurePercent.title":L10n.text(.settings,"search.add.text.130"),
            "activity.movementRange.title":L10n.text(.settings,"search.add.text.131"),
        ]
        func add(_ section:SettingsSection,_ group:String,titleKeys:[String],_ keywords:String) {
            for key in titleKeys {
                let extra = key == "appearance.bubbleMaterial.title" ? L10n.text(.settings,"search.add.text.121") : ""
                entries.append(.init(section:section,group:group,title:L10n.text(.settings,key),
                                     keywords:keywords+extra,condition:conditions[key] ?? ""))
            }
        }
        add(.general,L10n.text(.settings,"search.add.text"),titleKeys:["search.add.text.2","autostart.configure.messageText","search.add.text.4"],L10n.text(.settings,"search.add.text.5"))
        add(.general,L10n.text(.settings,"search.add.text.6"),titleKeys:["search.add.text.7"],L10n.text(.settings,"search.add.text.8"))
        add(.general,L10n.text(.settings,"search.add.text.6"),titleKeys:["search.add.text.9"],L10n.text(.settings,"search.add.text.10"))
        add(.general,L10n.text(.settings,"search.add.text.6"),titleKeys:["search.add.text.11"],L10n.text(.settings,"search.add.text.12"))
        add(.general,L10n.text(.settings,"search.add.text.13"),titleKeys:["search.add.text.14"],L10n.text(.settings,"search.add.text.15"))
        add(.general,L10n.text(.settings,"search.add.text.13"),titleKeys:["search.add.text.16"],L10n.text(.settings,"search.add.text.17"))
        add(.general,BrowserSearchEngine.group,[BrowserSearchEngine.settingTitle],L10n.text(.settings,"search.add.text.18") + BrowserSearchEngine.options.map(\.1).joined(separator:" "))
        add(.general,ProjectSendChannel.group,[ProjectSendChannel.settingTitle],L10n.format(.settings,"search.add.text.19",String(describing:ProjectSendChannel.legacyVersion),String(describing:ProjectSendChannel.modernVersion)) + ProjectSendChannel.options.map(\.1).joined(separator:" "))
        add(.identity,L10n.text(.settings,"identity.templatePreview.text"),titleKeys:["identity.names","identity.names.3","identity.names.5"],L10n.text(.settings,"search.add.text.24"))
        add(.identity,L10n.text(.settings,"identity.templatePreview.text.2"),titleKeys:["identity.greetingPreview"],L10n.text(.settings,"search.add.text.27"))
        add(.identity,L10n.text(.settings,"identity.workingLineEditTarget.text"),titleKeys:["identity.randomWorkingLines.title"],L10n.text(.settings,"search.add.text.30"))
        entries.append(.init(section:.identity,group:L10n.text(.settings,"identity.workingLineEditTarget.text"),title:IdentitySettingsPage.editWorkingLineTitle,keywords:L10n.text(.settings,"search.add.keywords"),detail:.lines))
        entries.append(.init(section:.identity,group:SettingsDetail.lines.title,title:SettingsDetail.lines.title,detail:.lines))
        entries += IdentitySettingsPage.items(catalog:catalog).map {$0.searchEntry(in:.identity)}
        if catalog != nil {entries.append(.init(section:.activity,group:SettingsDetail.actions.title,title:SettingsDetail.actions.title,detail:.actions))}
        entries += ActivitySettingsPage.items(catalog:catalog).map {$0.searchEntry(in:.activity)}
        let actionNames = PetGestureSetting.actions.map(\.1).joined(separator:" ")
        for gesture in PetGestureSetting.all {
            let keywords = [gesture.keywords, gesture.help, actionNames].compactMap {$0}.joined(separator:" ")
            add(.activity,PetGestureSetting.group,[gesture.title],keywords)
        }
        add(.activity,L10n.text(.settings,"activity.render.text"),titleKeys:["activity.sideDockEnabled.title","activity.sideExposurePercent.title","activity.notchDockEnabled.title","activity.notchExposurePercent.title"],L10n.text(.settings,"search.add.text.36"))
        add(.activity,L10n.text(.settings,"activity.render.text.2"),titleKeys:["activity.leisureInterval.title"],L10n.text(.settings,"search.add.text.39"))
        add(.activity,L10n.text(.settings,"activity.render.text.2"),titleKeys:["activity.autoMove.title","activity.movementRange.title","activity.avoidRepeat.title","activity.playbackSpeed.title"],L10n.text(.settings,"search.add.text.44"))
        add(.activity,L10n.text(.settings,"activity.render.text.3"),titleKeys:["activity.taskOpening.title","activity.taskCelebration.title"],L10n.text(.settings,"search.add.text.48"))
        entries += MessageSettingsPage.Topic.allCases.map {Self(section:.messages,group:$0.title,title:$0.title,detail:.messages($0))}
        entries += MessageSettingsPage.searchEntries
        add(.appearance,L10n.text(.settings,"appearance.render.text"),titleKeys:["appearance.petPercent.title","appearance.bubblePercent.title","appearance.messageFontSize.title"],L10n.text(.settings,"search.add.text.53"))
        add(.appearance,L10n.text(.settings,"appearance.render.text"),titleKeys:["appearance.bubbleAspectEnabled.title","appearance.bubbleAspectRatio.title"],L10n.text(.settings,"search.add.text.56"))
        add(.appearance,L10n.text(.settings,"appearance.render.text.3"),titleKeys:["appearance.appearanceMode.title","appearance.appearanceMode.title.2","appearance.render.text.2"],L10n.text(.settings,"search.add.text.61"))
        add(.appearance,L10n.text(.settings,"appearance.render.text.6"),titleKeys:["appearance.bubbleMaterial.title","appearance.glassFollowsSystem.title","appearance.render.text.4","appearance.render.text.5"],L10n.text(.settings,"search.add.text.67"))
        add(.appearance,L10n.text(.settings,"appearance.render.text.6"),[BubbleCloseButtonPosition.title],L10n.text(.settings,"search.add.text.68"))
        add(.advanced,L10n.text(.settings,"search.add.text.69"),titleKeys:["search.add.text.70","search.add.text.71"],L10n.text(.settings,"search.add.text.72"))
        add(.advanced,L10n.text(.settings,"search.add.text.73"),titleKeys:["search.add.text.74","search.add.text.75","search.add.text.76"],L10n.text(.settings,"search.add.text.77"))
        add(.advanced,L10n.text(.settings,"search.add.text.78"),titleKeys:["search.add.text.79","search.add.text.80","search.add.text.81","search.add.text.82","search.add.text.83","search.add.text.84"],L10n.text(.settings,"search.add.text.85"))
        add(.developer,L10n.text(.settings,"search.add.text.48"),titleKeys:["search.add.text.86","search.add.text.87","search.add.text.88","search.add.text.89","search.add.text.90"],L10n.text(.settings,"search.add.text.91"))
        add(.developer,L10n.text(.settings,"search.add.text.92"),titleKeys:["search.add.text.93"],L10n.text(.settings,"search.add.text.94"))
        add(.developer,L10n.text(.settings,"search.add.text.92"),titleKeys:["search.add.text.95","search.add.text.96"],L10n.text(.settings,"search.add.text.97"))
        add(.developer,L10n.text(.settings,"search.add.text.92"),titleKeys:["search.add.text.98"],L10n.text(.settings,"search.add.text.99"))
        add(.developer,L10n.text(.settings,"search.add.text.100"),titleKeys:["search.add.text.101","search.add.text.102"],L10n.text(.settings,"search.add.text.103"))
        add(.developer,L10n.text(.settings,"search.add.text.104"),titleKeys:["search.add.text.105"],L10n.text(.settings,"search.add.text.106"))
        add(.updates,L10n.text(.settings,"search.add.text.107"),titleKeys:["search.add.text.108","search.add.text.109","search.add.text.110"],L10n.text(.settings,"search.add.text.111"))
        add(.updates,L10n.text(.settings,"search.add.text.112"),titleKeys:["search.add.text.113"],L10n.text(.settings,"search.add.text.114"))
        add(.updates,L10n.text(.settings,"search.add.text.115"),titleKeys:["search.add.text.116"],L10n.text(.settings,"search.add.text.117"))
        let aboutKeywords = L10n.text(.settings,"search.aboutKeywords")
        let remoteIconKeywords = L10n.text(.settings,"settingsSearch.remoteIconKeywords.text")
        entries.append(.init(section:.about,group:AboutPageController.Tab.about.title,title:AboutPageController.Tab.about.title,keywords:aboutKeywords,aboutTab:.about))
        entries.append(.init(section:.about,group:AboutPageController.Tab.about.title,title:AboutPageController.Tab.credits.title,keywords:aboutKeywords+L10n.text(.settings,"settingsSearch.labels.text")+remoteIconKeywords,aboutTab:.credits))
        entries.append(.init(section:.about,group:AboutPageController.Tab.about.title,title:AboutPageController.Tab.thirdPartyNotices.title,keywords:L10n.text(.settings,"settingsSearch.labels.keywords")+remoteIconKeywords,aboutTab:.thirdPartyNotices))
        return entries
    }
    static func matching(_ query:String,in entries:[Self]) -> [Self] {
        let words = query.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard !words.isEmpty else {return []}
        let matches = entries.filter {entry in
            let text = [entry.title,entry.location,entry.keywords].joined(separator:" ")
            return words.allSatisfy {text.localizedStandardContains($0)}
        }
        return matches.filter {$0.title.localizedStandardContains(query)} + matches.filter {!$0.title.localizedStandardContains(query)}
    }
}

private final class SettingsSearchTable: NSTableView {
    var open:() -> Void = {}
    var cancel:() -> Void = {}
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {open(); return}
        if event.keyCode == 53 {cancel(); return}
        super.keyDown(with:event)
    }
}

final class SettingsSearchResults: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = SettingsSearchTable()
    private let caption = NSTextField(labelWithString:"")
    private let empty = NSTextField(labelWithString:L10n.text(.settings,"search.empty"))
    private var entries = [SettingsSearchEntry]()
    var onOpen:(SettingsSearchEntry) -> Void = {_ in}
    var onCancel:() -> Void = {}
    init() {
        super.init(frame:.zero)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        table.addTableColumn(NSTableColumn(identifier:.init("setting")))
        table.headerView = nil; table.style = .plain; table.backgroundColor = .clear; table.rowHeight = 62
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.autoresizingMask = [.width]
        table.intercellSpacing = .zero; table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(openSelection)
        table.setAccessibilityLabel(L10n.text(.settings,"search.text"))
        table.open = { [weak self] in self?.openSelection() }; table.cancel = { [weak self] in self?.onCancel() }
        scroll.documentView = table
        caption.font = .systemFont(ofSize:12,weight:.medium); caption.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize:14); empty.textColor = .secondaryLabelColor
        for view in [caption,scroll,empty] {view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)}
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo:leadingAnchor,constant:24),caption.topAnchor.constraint(equalTo:topAnchor,constant:20),
            scroll.topAnchor.constraint(equalTo:caption.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),scroll.bottomAnchor.constraint(equalTo:bottomAnchor),
            empty.centerXAnchor.constraint(equalTo:centerXAnchor),empty.topAnchor.constraint(equalTo:caption.bottomAnchor,constant:40)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}
    func show(_ values:[SettingsSearchEntry]) {
        entries = values; caption.stringValue = L10n.format(.settings,"search.show.text",String(describing:values.count)); empty.isHidden = !values.isEmpty
        table.reloadData()
        if !values.isEmpty {table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false); table.scrollRowToVisible(0)}
    }
    func focus() {window?.makeFirstResponder(table)}
    @objc func openSelection() {
        guard entries.indices.contains(table.selectedRow) else {return}
        onOpen(entries[table.selectedRow])
    }
    func numberOfRows(in tableView:NSTableView) -> Int {entries.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {AccentSelectionRow()}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let entry = entries[row], cell = NSTableCellView()
        let title = NSTextField(labelWithString:entry.title)
        title.font = .systemFont(ofSize:13,weight:.medium)
        let path = NSTextField(labelWithString:entry.location+(entry.condition.isEmpty ? "" : " · "+entry.condition))
        path.font = .systemFont(ofSize:11); path.textColor = .secondaryLabelColor
        for field in [title,path] {field.lineBreakMode = .byTruncatingTail}
        let arrow = NSImageView(image:NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil)!)
        arrow.contentTintColor = .tertiaryLabelColor
        for view in [title,path,arrow] {view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view)}
        cell.hoverHelp = entry.title+"\n"+path.stringValue
        cell.textField = title; cell.setAccessibilityLabel(entry.title+"，"+path.stringValue)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:12),title.topAnchor.constraint(equalTo:cell.topAnchor,constant:11),
            path.leadingAnchor.constraint(equalTo:title.leadingAnchor),path.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),
            arrow.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-12),arrow.centerYAnchor.constraint(equalTo:cell.centerYAnchor),arrow.widthAnchor.constraint(equalToConstant:12),
            title.trailingAnchor.constraint(lessThanOrEqualTo:arrow.leadingAnchor,constant:-12),path.trailingAnchor.constraint(lessThanOrEqualTo:arrow.leadingAnchor,constant:-12)
        ])
        return cell
    }
}

final class SettingsSearchHighlight: NSView {
    override func hitTest(_ point:NSPoint) -> NSView? {nil}
    override func draw(_ dirtyRect:NSRect) {
        AppAccent.color.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill()
    }
}
