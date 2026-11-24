import AppKit

final class WorkspaceFileTableRow:NSTableRowView {
    private var tracking:NSTrackingArea?
    private var hovered = false
    override var interiorBackgroundStyle:NSView.BackgroundStyle {.normal}
    override func updateTrackingAreas() {
        if let tracking {removeTrackingArea(tracking)}
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        tracking = area; addTrackingArea(area); super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) {hovered = true; needsDisplay = true}
    override func mouseExited(with event:NSEvent) {hovered = false; needsDisplay = true}
    override func drawBackground(in dirtyRect:NSRect) {
        guard hovered,!isSelected else {return}
        WorkspaceFileHighlight.draw(bounds,selected:false,emphasized:false,appearance:effectiveAppearance)
    }
    override func drawSelection(in dirtyRect:NSRect) {
        guard selectionHighlightStyle != .none else {return}
        WorkspaceFileHighlight.draw(bounds,selected:true,emphasized:isEmphasized,appearance:effectiveAppearance)
    }
}

// 两种文件详情共用原生透明列表；单击选择，双击定位文件，右键与重压共用菜单。
final class WorkspaceFileTable:NSTableView {
    var fileURLForRow:(Int) -> URL? = {_ in nil}
    var fileGroupForRow:(Int) -> GitWorkspaceStatus.Group? = {_ in nil}
    var diffForRow:(Int) -> WorkspaceDiffTarget? = {_ in nil}
    var onDiff:(WorkspaceDiffTarget) -> Void = {_ in}
    private weak var diffButton:NSButton?
    override init(frame:NSRect) {
        super.init(frame:frame)
        style = .plain; backgroundColor = .clear; headerView = nil
        columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        target = self; doubleAction = #selector(revealClickedFile)
        NotificationCenter.default.addObserver(self,selector:#selector(selectionChanged),
            name:NSTableView.selectionDidChangeNotification,object:self)
        let forceClick = WorkspaceFileForceClick(target:self,action:#selector(showForceClickMenu(_:)))
        forceClick.canOpenMenu = { [weak self] event in
            guard let self else {return false}
            let index = row(at:convert(event.locationInWindow,from:nil))
            return index >= 0 && (fileURLForRow(index) != nil || fileGroupForRow(index) != nil)
        }
        addGestureRecognizer(forceClick)
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func showForceClickMenu(_ gesture:WorkspaceFileForceClick) {
        guard let event = gesture.mouseDownEvent,let menu = menu(for:event) else {return}
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    override func menu(for event:NSEvent) -> NSMenu? {
        let index = row(at:convert(event.locationInWindow,from:nil))
        guard index >= 0 else {return nil}
        let file = fileURLForRow(index), group = fileGroupForRow(index)
        guard file != nil || group != nil else {return nil}
        if file != nil {selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
        let groupPaths = group.map {group in
            { [weak self] in self?.filePaths(in:group) ?? [] }
        }
        let reveal = file.map {file in {WorkspaceFileMenu.reveal(file)}}
        let openDiff = onDiff
        let diff = diffForRow(index).map {target in {openDiff(target)}}
        return WorkspaceFileMenu.make(path:file?.path,reveal:reveal,diff:diff,groupPaths:groupPaths) { [weak self] in
            self?.filePaths() ?? []
        }
    }
    func makeDiffButton() -> NSButton {
        let button = NSButton(title:L10n.text(.workspace,"workspaceDiff.open"),target:self,action:#selector(openSelectedDiff))
        button.controlSize = .small; button.bezelStyle = .rounded
        diffButton = button; selectionChanged()
        return button
    }
    @objc private func selectionChanged() {diffButton?.isEnabled = selectedRow >= 0 && diffForRow(selectedRow) != nil}
    @objc private func openSelectedDiff() {if selectedRow >= 0,let target = diffForRow(selectedRow) {onDiff(target)}}
    @objc private func revealClickedFile() {
        guard clickedRow >= 0,let file = fileURLForRow(clickedRow) else {return}
        WorkspaceFileMenu.reveal(file)
    }
    private func filePaths(in group:GitWorkspaceStatus.Group? = nil) -> [String] {
        (0..<numberOfRows).compactMap {row in
            guard group == nil || fileGroupForRow(row) == group else {return nil}
            return fileURLForRow(row)?.path
        }
    }
}

// Git 文件状态与本轮修改共用图标槽、文件名和右侧计数列。
final class WorkspaceFileRow:NSView {
    init(title:String,symbol:String,color:NSColor,detail:String,lines:FileEditSummary.Lines? = nil,countWidths:(added:CGFloat,removed:CGFloat)? = nil,directory:String? = nil,change:String? = nil) {
        super.init(frame:.zero)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:13,weight:.semibold))
        icon.contentTintColor = color; icon.imageScaling = .scaleProportionallyDown
        let name = NSTextField(labelWithString:title); name.font = .systemFont(ofSize:12,weight:.semibold)
        name.lineBreakMode = .byTruncatingMiddle; name.maximumNumberOfLines = 1
        name.setContentHuggingPriority(.defaultLow,for:.horizontal)
        name.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let row = NSStackView(views:[icon,name]); row.spacing = 8; row.alignment = .centerY; row.distribution = .fill
        if let directory,!directory.isEmpty {
            let location = NSTextField(labelWithString:directory)
            location.font = .systemFont(ofSize:11); location.textColor = .labelColor
            location.lineBreakMode = .byTruncatingMiddle
            location.setContentCompressionResistancePriority(.init(249),for:.horizontal)
            location.setContentHuggingPriority(.defaultLow,for:.horizontal)
            name.setContentCompressionResistancePriority(.defaultHigh,for:.horizontal)
            row.addArrangedSubview(location)
        }
        if let change {
            let status = NSTextField(labelWithString:change)
            status.font = .systemFont(ofSize:11); status.textColor = color; status.alignment = .right
            status.setContentCompressionResistancePriority(.required,for:.horizontal)
            row.addArrangedSubview(status)
        }
        if let countWidths {
            if let lines {
                let counts = NSStackView(); counts.spacing = 8; counts.alignment = .firstBaseline
                counts.widthAnchor.constraint(equalToConstant:countWidths.added+8+countWidths.removed).isActive = true
                counts.setContentHuggingPriority(.required,for:.horizontal)
                for (number,added,width) in [(lines.added,true,countWidths.added),(lines.removed,false,countWidths.removed)] {
                    let count = NSTextField(labelWithString:""); count.font = Self.countFont; count.alignment = .right
                    count.attributedStringValue = FileEditRendering.count(number,added:added,font:Self.countFont)
                    count.widthAnchor.constraint(equalToConstant:width).isActive = true; counts.addArrangedSubview(count)
                }
                row.addArrangedSubview(counts)
            } else {
                let count = NSTextField(labelWithString:L10n.text(.workspace,"workspaceFileList.count")); count.font = Self.countFont; count.textColor = .secondaryLabelColor; count.alignment = .right
                count.widthAnchor.constraint(equalToConstant:countWidths.added+8+countWidths.removed).isActive = true
                row.addArrangedSubview(count)
            }
        }
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant:16),icon.heightAnchor.constraint(equalToConstant:16),
            row.leadingAnchor.constraint(equalTo:leadingAnchor,constant:4),row.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-6),row.centerYAnchor.constraint(equalTo:centerYAnchor)
        ])
        hoverHelp = detail; setAccessibilityLabel((change.map {$0+"，"} ?? "")+detail+(lines.map {L10n.format(.workspace,"workspaceFileList.text",String(describing:$0.added),String(describing:$0.removed))} ?? ""))
    }
    required init?(coder:NSCoder) {fatalError()}
    static let countFont = NSFont.monospacedSystemFont(ofSize:12,weight:.semibold)
    static func symbol(for entry:GitWorkspaceStatus.Entry) -> (String,NSColor) {
        if entry.group == .conflicted {return ("exclamationmark.triangle",StatusTextColor.red)}
        switch entry.change {
        case .added:return ("plus.circle",StatusTextColor.green)
        case .deleted:return ("minus.circle",StatusTextColor.red)
        case .renamed:return ("arrow.right",StatusTextColor.blue)
        case .copied:return ("doc.on.doc",StatusTextColor.teal)
        case .typeChanged,.submodule:return ("square.stack.3d.up",StatusTextColor.purple)
        default:return ("pencil",StatusTextColor.orange)
        }
    }
}

final class TurnFileEditsDetails:NSViewController,NSTableViewDataSource,NSTableViewDelegate {
    private let edits:[FileEditSummary],directory:String
    private let table = WorkspaceFileTable()
    var onDiff:(WorkspaceDiffTarget) -> Void = {_ in}
    private let countWidths:(added:CGFloat,removed:CGFloat)
    private let repeatedNames:Set<String>
    init(edits:[FileEditSummary],directory:String) {
        self.edits = edits; self.directory = directory
        let lines = edits.compactMap(\.lines)
        let minimum = ceil((L10n.text(.workspace,"workspaceFileList.count") as NSString).size(withAttributes:[.font:WorkspaceFileRow.countFont]).width/2)
        countWidths = (max(minimum,ceil(lines.map {FileEditRendering.count($0.added,added:true,font:WorkspaceFileRow.countFont).size().width}.max() ?? 0)),max(minimum,ceil(lines.map {FileEditRendering.count($0.removed,added:false,font:WorkspaceFileRow.countFont).size().width}.max() ?? 0)))
        repeatedNames = Set(Dictionary(grouping:edits,by:{($0.path as NSString).lastPathComponent}).filter {$0.value.count > 1}.keys)
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        let column = NSTableColumn(identifier:.init("file")); column.resizingMask = .autoresizingMask; table.addTableColumn(column)
        table.rowHeight = 32; table.delegate = self; table.dataSource = self
        table.fileURLForRow = { [weak self] row in
            guard let self,self.edits.indices.contains(row) else {return nil}
            return URL(fileURLWithPath:self.edits[row].path,relativeTo:URL(fileURLWithPath:self.directory,isDirectory:true)).standardizedFileURL
        }
        table.diffForRow = { [weak self] row in
            guard let self,edits.indices.contains(row) else {return nil}
            let base = directory.isEmpty ? nil : URL(fileURLWithPath:directory,isDirectory:true)
            return .turn(directory:base,edits:edits,path:edits[row].path)
        }
        table.onDiff = onDiff
        table.setAccessibilityLabel(L10n.text(.workspace,"workspaceFileList.loadView.text"))
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.contentView.drawsBackground = false; scroll.verticalScrollElasticity = .allowed
        let button = table.makeDiffButton()
        view = NSView(frame:NSRect(x:0,y:0,width:440,height:min(340,max(32,CGFloat(edits.count)*34))+44))
        for child in [scroll,button] {child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child)}
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8),
            scroll.topAnchor.constraint(equalTo:view.topAnchor,constant:8),scroll.bottomAnchor.constraint(equalTo:button.topAnchor,constant:-4),
            button.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8),button.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-8)
        ])
        preferredContentSize = view.frame.size
    }
    func numberOfRows(in tableView:NSTableView) -> Int {edits.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {WorkspaceFileTableRow()}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let edit = edits[row], name = (edits[row].path as NSString).lastPathComponent
        return WorkspaceFileRow(title:repeatedNames.contains(name) ? edit.path : name,symbol:"doc",color:.secondaryLabelColor,detail:edit.path,lines:edit.lines,countWidths:countWidths)
    }
}

final class RepositoryLinkButton:NSButton,LinkCursorControl {
    private let url:URL
    init(url:URL,label:String? = nil) {
        self.url = url; super.init(frame:.zero)
        isBordered = false; bezelStyle = .inline; alignment = .left
        let attributes = LinkAppearance.attributes.merging([.font:NSFont.systemFont(ofSize:11)]) {_,new in new}
        attributedTitle = NSAttributedString(string:label ?? url.absoluteString,attributes:attributes)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        setHoverHelp(url.absoluteString) { [weak self] in self?.hasTruncatedTitle == true }
        target = self; action = #selector(open); setAccessibilityLabel(L10n.text(.workspace,"workspaceFileList.text.2")+url.absoluteString)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool {true}
    override func resetCursorRects() {super.resetCursorRects(); LinkAppearance.addCursorRect(bounds,to:self)}
    @objc private func open() {NSWorkspace.shared.open(url)}
}
