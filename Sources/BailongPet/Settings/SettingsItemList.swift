import AppKit

// 两页均以表格复用可见行。台词共用一个编辑器，动作的列和行高在操作期间保持固定。
final class SettingsItemList:NSView,NSTableViewDataSource,NSTableViewDelegate {
    struct Position {
        let group:String, id:String?, offset:CGFloat
    }
    private enum Row {
        case heading(String,SettingsLineResetGroup?), item(SettingsListItem)
        var item:SettingsListItem? {if case .item(let item) = self {return item}; return nil}
    }
    let section:SettingsSection
    private let rows:[Row]
    private let table = NSTableView(), scroll = NSScrollView()
    private let editor = NSStackView(), form:SettingsForm
    private let play:(SettingsListItem) -> Void
    private var editingRow:Int?
    var position:Position {
        let item = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].item : nil
        return Position(group:item?.group ?? "",id:item?.id,offset:scroll.contentView.bounds.minY)
    }

    init(items:[SettingsListItem],section:SettingsSection,window:NSWindow,preferences:PetPreferences,
         back:@escaping () -> Void,play:@escaping (SettingsListItem) -> Void) {
        self.section = section; self.play = play
        var grouped = [Row](), previous:String?
        for item in items {
            if item.group != previous {grouped.append(.heading(item.group,item.lineResetGroup)); previous = item.group}
            grouped.append(.item(item))
        }
        rows = grouped
        form = SettingsForm(content:editor,preferences:preferences,window:window)
        super.init(frame:.zero)
        editor.orientation = .vertical; editor.alignment = .leading; editor.spacing = 6
        form.reset(section:section)
        form.moveToAdjacentEntry = { [weak self] step in
            guard let self,let row = self.editingRow else {return false}
            var next = row+step
            while self.rows.indices.contains(next) {
                if self.rows[next].item != nil {self.select(next,focus:true); return true}
                next += step
            }
            return false
        }
        let backButton = form.backButton(section.title,action:back)
        addSubview(backButton); addSubview(scroll)
        for view in [backButton,scroll] {view.translatesAutoresizingMaskIntoConstraints = false}
        let preferredWidth = scroll.widthAnchor.constraint(equalTo:widthAnchor,constant:-48)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo:scroll.leadingAnchor),backButton.topAnchor.constraint(equalTo:topAnchor,constant:20),
            scroll.topAnchor.constraint(equalTo:backButton.bottomAnchor,constant:14),scroll.centerXAnchor.constraint(equalTo:centerXAnchor),
            scroll.widthAnchor.constraint(lessThanOrEqualToConstant:680),preferredWidth,scroll.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-12)
        ])
        let name = NSTableColumn(identifier:.init("name")); name.title = L10n.text(.settings,"settingsItemList.title"); name.minWidth = 115
        name.resizingMask = .autoresizingMask; table.addTableColumn(name)
        table.style = .fullWidth
        if section == .activity {
            table.usesAlternatingRowBackgroundColors = true
            for (key,title,width) in [("play",L10n.text(.settings,"settingsItemList.text"),CGFloat(56)),("speed",L10n.text(.settings,"activity.speed"),98),("weight",L10n.text(.settings,"settingsForm.slider"),88)] {
                let column = NSTableColumn(identifier:.init(key)); column.title = title
                column.headerCell.alignment = .center
                column.width = width; column.minWidth = width; column.maxWidth = width; column.resizingMask = []
                table.addTableColumn(column)
            }
        } else {table.headerView = nil}
        table.floatsGroupRows = false
        table.backgroundColor = .clear; table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.allowsColumnReordering = false; table.autoresizingMask = [.width]; table.allowsEmptySelection = true
        table.setAccessibilityLabel(section == .identity ? L10n.text(.settings,"settingsItemList.text.4") : L10n.text(.settings,"settingsItemList.text.5"))
        table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(activateRow)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = table
    }
    required init?(coder:NSCoder) {fatalError()}

    func restore(_ position:Position?) {
        guard let position else {return}
        if let row = rows.firstIndex(where:{$0.item?.id == position.id && $0.item?.group == position.group}) {select(row,focus:false)}
        layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        clip.scroll(to:clip.constrainBoundsRect(NSRect(origin:NSPoint(x:0,y:position.offset),size:clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }
    func reveal(group:String,id:String) {
        if let row = rows.firstIndex(where:{$0.item?.group == group && $0.item?.id == id}) {select(row,focus:true)}
    }
    private func restoreGroup(_ group:SettingsLineResetGroup) {
        window?.makeFirstResponder(nil)
        let saved = position
        group.restore(in:form.preferences)
        table.deselectAll(nil); table.reloadData(); restore(saved)
    }
    func numberOfRows(in tableView:NSTableView) -> Int {rows.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {rows[row].item == nil ? nil : AccentSelectionRow()}
    func tableView(_ tableView:NSTableView,isGroupRow row:Int) -> Bool {rows[row].item == nil}
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int) -> Bool {rows[row].item != nil}
    func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {
        if rows[row].item == nil {return 38}
        if section == .activity {return 36}
        return row == editingRow ? max(88,ceil(editor.fittingSize.height)+16) : 49
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        switch rows[row] {
        case .heading(let title,let resetGroup):
            let field = NSTextField(labelWithString:title); field.font = .systemFont(ofSize:13,weight:.semibold)
            let stack = NSStackView(views:[field]); stack.alignment = .centerY
            stack.edgeInsets = NSEdgeInsets(top:0,left:8,bottom:0,right:8)
            if section == .identity,let group = resetGroup {
                let restore = ActionButton(L10n.text(.settings,"settingsItemList.restore")) { [weak self] in self?.restoreGroup(group) }
                restore.controlSize = .small; restore.setAccessibilityLabel(L10n.text(.settings,"identity.restore.text")+title+L10n.text(.settings,"settingsItemList.tableView.text.2"))
                stack.addArrangedSubview(NSView()); stack.addArrangedSubview(restore)
            }
            return stack
        case .item(let item):
            if case .animation(let clip,let weighted) = item.kind {
                return actionCell(tableColumn?.identifier.rawValue ?? "name",item:item,clip:clip,weighted:weighted)
            }
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
            cell.update(item,preferences:form.preferences) { [weak self] in self?.preview(item) }
            return cell
        }
    }
    private func actionCell(_ column:String,item:SettingsListItem,clip:Clip,weighted:Bool) -> NSView {
        let id = NSUserInterfaceItemIdentifier(column == "weight" && !weighted ? "unused-weight" : column)
        let cell:SettingsActionCell
        if let reused = table.makeView(withIdentifier:id,owner:self) as? SettingsActionCell {
            cell = reused
        } else {
            let control:NSControl
            switch id.rawValue {
            case "name","unused-weight":
                let field = NSTextField(labelWithString:"")
                field.lineBreakMode = .byTruncatingTail
                control = field
            case "play":
                let button = ActionButton("") {}
                button.controlSize = .small; button.bezelStyle = .rounded
                button.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil)
                button.imagePosition = .imageOnly
                control = button
            default:
                control = SettingsActionChoice(frame:.zero,pullsDown:false)
            }
            cell = SettingsActionCell(control:control,leading:column == "name")
            cell.identifier = id
        }
        if let field = cell.control as? NSTextField {
            field.stringValue = column == "name" ? clip.title : "—"
            field.textColor = column == "name" ? .labelColor : .tertiaryLabelColor
        } else if let button = cell.control as? ActionButton {
            button.setAccessibilityLabel(L10n.text(.settings,"settingsForm.animationPreviewButton.button")+clip.title)
            button.callback = { [weak self] in self?.preview(item) }
        } else if let choice = cell.control as? SettingsActionChoice {
            choice.configure(clip:clip,speed:column == "speed",preferences:form.preferences)
        }
        return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification) {
        guard section == .identity else {return}
        let next = table.selectedRow >= 0 ? table.selectedRow : nil
        guard editingRow != next else {return}
        window?.makeFirstResponder(table)
        let old = editingRow
        editor.removeFromSuperview(); form.reset(section:section); editingRow = next
        if let next,let item = rows[next].item {edit(item)}
        let changed = IndexSet([old,next].compactMap {$0})
        table.noteHeightOfRows(withIndexesChanged:changed)
        table.reloadData(forRowIndexes:changed,columnIndexes:IndexSet(integer:0))
    }
    private func select(_ row:Int,focus:Bool) {
        table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        table.scrollRowToVisible(row)
        if focus {
            if section == .activity {window?.makeFirstResponder(table)} else {activateRow()}
        }
    }
    @objc private func activateRow() {
        guard section == .identity,let row = editingRow else {return}
        _ = table.view(atColumn:0,row:row,makeIfNecessary:true)
        if let field = form.currentTemplateField {window?.makeFirstResponder(field)}
    }
    private func preview(_ item:SettingsListItem) {
        guard window?.makeFirstResponder(nil) == true else {return}
        play(item)
    }
    private func edit(_ item:SettingsListItem) {
        guard let view = item.lineEditor(in:form,onPreview:{ [weak self] in self?.preview(item) }) else {return}
        form.fill(view,in:editor)
    }
}

// 表格分配整列宽度。控件保持原生高度，名称与标题左对齐，操作居中。
private final class SettingsActionCell:NSTableCellView {
    let control:NSControl
    init(control:NSControl,leading:Bool) {
        self.control = control
        super.init(frame:.zero)
        addSubview(control); control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.centerYAnchor.constraint(equalTo:centerYAnchor),
            leading ? control.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8) : control.centerXAnchor.constraint(equalTo:centerXAnchor),
            control.trailingAnchor.constraint(lessThanOrEqualTo:trailingAnchor,constant:-4)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}
}

// 单元格展示已保存值，打开原生菜单时才生成其余选项。
private final class SettingsActionChoice:AccentPopUpButton {
    private var clipID = "", speed = false, populated = false
    private weak var preferences:PetPreferences?
    func configure(clip:Clip,speed:Bool,preferences:PetPreferences) {
        self.clipID = clip.id; self.speed = speed; self.preferences = preferences
        controlSize = .small
        setAccessibilityLabel(clip.title+(speed ? L10n.text(.settings,"activity.speed") : L10n.text(.settings,"settingsForm.slider")))
        menu?.delegate = nil; removeAllItems(); populated = false
        let current = speed ? preferences.clipSpeed(clip.id) : preferences.weight(clip.id)
        addOption(current); selectItem(at:0)
        menu?.delegate = self; target = self; action = #selector(changeValue)
    }
    private func addOption(_ value:Double) {
        addItem(withTitle:value.formatted()+(speed ? "×" : "")); lastItem?.representedObject = value
    }
    override func menuNeedsUpdate(_ menu:NSMenu) {
        defer {super.menuNeedsUpdate(menu)}
        guard !populated,let preferences else {return}
        populated = true
        let values = speed ? PetPreferences.clipSpeedOptions : PetPreferences.clipWeightRange(clipID).map(Double.init)
        let current = speed ? preferences.clipSpeed(clipID) : preferences.weight(clipID)
        removeAllItems(); values.forEach(addOption)
        if let index = values.firstIndex(of:current) {selectItem(at:index)}
    }
    @objc private func changeValue() {
        guard let value = selectedItem?.representedObject as? Double,let preferences else {return}
        if speed {preferences.setSpeed(value,for:clipID)} else {preferences.setWeight(Int(value),for:clipID)}
    }
}

private final class SettingsSummaryCell:NSTableCellView {
    private let name = NSTextField(labelWithString:""), summary = SettingsTemplateField(string:"")
    private let button = NSButton(image:NSImage(systemSymbolName:"play.fill",accessibilityDescription:L10n.text(.settings,"settingsForm.animationPreviewButton.button"))!,target:nil,action:nil)
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
    func update(_ item:SettingsListItem,preferences:PetPreferences,onPlay:@escaping () -> Void) {
        name.stringValue = item.title; summary.stringValue = item.summary(preferences); summary.hoverHelp = summary.stringValue
        setAccessibilityLabel(item.title+"，"+summary.stringValue)
        summary.refreshHighlight()
        button.isHidden = item.preview == nil; button.setAccessibilityLabel(L10n.text(.settings,"settingsForm.animationPreviewButton.button")+item.title); self.onPlay = onPlay
    }
    @objc private func play() {onPlay?()}
}
