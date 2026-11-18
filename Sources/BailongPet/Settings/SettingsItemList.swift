import AppKit

// 两个管理页共用表格与选中行编辑器。返回上级只保存导航位置。
final class SettingsItemList:NSView,NSTableViewDataSource,NSTableViewDelegate {
    struct Position {
        let group:String, id:String?, offset:CGFloat
    }
    let section:SettingsSection
    private let items:[SettingsListItem]
    private var groupItems = [SettingsListItem]()
    private let groups = NSPopUpButton(), table = NSTableView(), scroll = NSScrollView()
    private let editor = NSStackView(), form:SettingsForm
    private let restoreButton = NSButton(title:"恢复本组默认台词",target:nil,action:nil)
    private let play:(SettingsListItem) -> Void
    private var editingRow:Int?
    private var changingGroup = false
    private var group:String {groups.titleOfSelectedItem ?? ""}
    var position:Position {Position(group:group,id:editingRow.map {groupItems[$0].id},offset:scroll.contentView.bounds.minY)}

    init(items:[SettingsListItem],section:SettingsSection,window:NSWindow,preferences:PetPreferences,
         back:@escaping () -> Void,play:@escaping (SettingsListItem) -> Void) {
        self.items = items; self.section = section; self.play = play
        form = SettingsForm(content:editor,preferences:preferences,window:window)
        super.init(frame:.zero)
        editor.orientation = .vertical; editor.alignment = .leading; editor.spacing = 6
        form.moveToAdjacentEntry = { [weak self] step in
            guard let self,let row = self.editingRow,self.groupItems.indices.contains(row+step) else {return false}
            self.select(row+step,focus:true)
            return true
        }
        var added = Set<String>()
        for item in items where added.insert(item.group).inserted {groups.addItem(withTitle:item.group)}
        groups.target = self; groups.action = #selector(changeGroup)
        groups.setAccessibilityLabel(section == .identity ? "台词分组" : "动作分组")
        restoreButton.target = self; restoreButton.action = #selector(restoreGroup)
        let bar = NSStackView(views:[form.navigationButton(section.title,back:true,action:back),groups,restoreButton])
        bar.alignment = .centerY; bar.spacing = 12
        addSubview(bar); addSubview(scroll)
        for view in [bar,scroll] {view.translatesAutoresizingMaskIntoConstraints = false}
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),bar.topAnchor.constraint(equalTo:topAnchor,constant:14),
            bar.trailingAnchor.constraint(lessThanOrEqualTo:trailingAnchor,constant:-16),
            scroll.topAnchor.constraint(equalTo:bar.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),
            scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),scroll.bottomAnchor.constraint(equalTo:bottomAnchor)
        ])
        table.addTableColumn(NSTableColumn(identifier:.init("item"))); table.headerView = nil; table.style = .inset
        table.backgroundColor = .clear; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]; table.allowsEmptySelection = true
        table.setAccessibilityLabel(section == .identity ? "台词列表" : "动作列表")
        table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(activateRow)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = table
        changeGroup()
    }
    required init?(coder:NSCoder) {fatalError()}

    func restore(_ position:Position?) {
        guard let position,groups.item(withTitle:position.group) != nil else {return}
        groups.selectItem(withTitle:position.group); changeGroup()
        if let row = groupItems.firstIndex(where:{$0.id == position.id}) {select(row,focus:false)}
        layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        clip.scroll(to:clip.constrainBoundsRect(NSRect(origin:NSPoint(x:0,y:position.offset),size:clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }
    func reveal(group:String,id:String) {
        if self.group != group {groups.selectItem(withTitle:group); changeGroup()}
        if let row = groupItems.firstIndex(where:{$0.id == id}) {select(row,focus:true)}
    }
    @objc private func changeGroup() {
        window?.makeFirstResponder(nil)
        changingGroup = true
        editingRow = nil; editor.removeFromSuperview(); form.reset(section:section)
        table.deselectAll(nil); groupItems = items.filter {$0.group == group}
        restoreButton.isHidden = section != .identity || !["工作中台词","互动台词"].contains(group)
        restoreButton.setAccessibilityLabel("恢复"+group+"默认值")
        table.reloadData(); scroll.contentView.scroll(to:.zero)
        changingGroup = false
    }
    @objc private func restoreGroup() {
        window?.makeFirstResponder(nil)
        let saved = position
        if group == "工作中台词" {form.preferences.reset(["randomWorkingLines"]+ConversationLines.working.map(\.key))}
        else if group == "互动台词" {form.preferences.set([String:String](),for:"customLines")}
        restore(saved)
    }
    func numberOfRows(in tableView:NSTableView) -> Int {groupItems.count}
    func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {row == editingRow ? max(88,ceil(editor.fittingSize.height)+16) : 49}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        if row == editingRow {
            let cell = NSTableCellView()
            editor.removeFromSuperview(); cell.addSubview(editor); editor.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([editor.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),
                editor.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),editor.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            return cell
        }
        let reuse = NSUserInterfaceItemIdentifier("setting-summary")
        let cell = table.makeView(withIdentifier:reuse,owner:self) as? SettingsSummaryCell ?? SettingsSummaryCell()
        cell.identifier = reuse
        let item = groupItems[row]
        cell.update(item,preferences:form.preferences,showsTokens:section == .identity) { [weak self] in self?.preview(item) }
        return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification) {
        guard !changingGroup else {return}
        let row = table.selectedRow
        let next = groupItems.indices.contains(row) ? row : nil
        guard editingRow != next else {return}
        window?.makeFirstResponder(table)
        let old = editingRow
        editor.removeFromSuperview(); form.reset(section:section); editingRow = next
        if let next {edit(groupItems[next])}
        let changed = IndexSet([old,next].compactMap {$0})
        table.noteHeightOfRows(withIndexesChanged:changed)
        table.reloadData(forRowIndexes:changed,columnIndexes:IndexSet(integer:0))
    }
    private func select(_ row:Int,focus:Bool) {
        table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        table.scrollRowToVisible(row)
        if focus {focusEditor()}
    }
    @objc private func activateRow() {
        if table.clickedRow >= 0 || table.selectedRow >= 0 {focusEditor()}
    }
    private func focusEditor() {
        guard let row = editingRow else {return}
        _ = table.view(atColumn:0,row:row,makeIfNecessary:true)
        if let field = form.currentTemplateField {window?.makeFirstResponder(field)}
        else {window?.makeFirstResponder(table)}
    }
    private func preview(_ item:SettingsListItem) {
        guard window?.makeFirstResponder(nil) == true else {return}
        play(item)
    }
    private func edit(_ item:SettingsListItem) {
        let preview = item.preview.map { _ in form.animationPreviewButton(item.title,compact:true) { [weak self] in self?.preview(item) } }
        let view:NSView
        switch item.kind {
        case .template(let key,_):
            view = form.text(item.title,key,limit:ConversationLines.limit(key),action:preview)
        case .interaction(let clip):
            let prefs = form.preferences
            view = form.entry(item.title,value:item.summary(prefs),emptyFallback:prefs.templateSource(clip.line ?? ""),limit:120,action:preview) {prefs.setLine($0,for:clip.id)}
        case .animation(let clip,let weighted):
            if let preview {form.fill(form.row(item.title,control:preview),in:editor)}
            if weighted {form.fill(form.row("随机播放权重",control:form.animationWeight(clip)),in:editor)}
            let prefs = form.preferences
            view = form.popup("此动作播放速度",options:[("0.75","0.75×"),("1.0","1×（默认）"),("1.25","1.25×"),("1.5","1.5×")],value:String(prefs.clipSpeed(clip.id))) {prefs.setSpeed(Double($0)!,for:clip.id)}
        }
        form.fill(view,in:editor)
    }
}

private final class SettingsSummaryCell:NSTableCellView {
    private let name = NSTextField(labelWithString:""), summary = SettingsTemplateField(string:"")
    private let button = NSButton(image:NSImage(systemSymbolName:"play.fill",accessibilityDescription:"播放")!,target:nil,action:nil)
    private var onPlay:(() -> Void)?
    init() {
        super.init(frame:.zero)
        name.font = .systemFont(ofSize:13,weight:.medium)
        summary.isEditable = false; summary.isSelectable = false; summary.isBordered = false; summary.drawsBackground = false
        summary.font = .systemFont(ofSize:12); summary.usesSingleLineMode = true
        for field in [name,summary] {field.lineBreakMode = .byTruncatingTail; field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)}
        button.bezelStyle = .rounded; button.controlSize = .small; button.target = self; button.action = #selector(play)
        let labels = NSStackView(views:[name,summary]); labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 2
        let row = NSStackView(views:[labels,button]); row.alignment = .centerY; row.spacing = 8
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8),
            row.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-8),row.centerYAnchor.constraint(equalTo:centerYAnchor),
            summary.widthAnchor.constraint(equalTo:labels.widthAnchor)])
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(_ item:SettingsListItem,preferences:PetPreferences,showsTokens:Bool,onPlay:@escaping () -> Void) {
        name.stringValue = item.title; summary.stringValue = item.summary(preferences); summary.hoverHelp = summary.stringValue
        setAccessibilityLabel(item.title+"，"+summary.stringValue)
        summary.allowsTokens = showsTokens
        if showsTokens {summary.refreshHighlight()}
        button.isHidden = item.preview == nil; button.setAccessibilityLabel("播放"+item.title); self.onPlay = onPlay
    }
    @objc private func play() {onPlay?()}
}
