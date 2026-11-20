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
        NSColor.secondaryLabelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:5,yRadius:5).fill()
    }
    override func drawSelection(in dirtyRect:NSRect) {
        guard selectionHighlightStyle != .none else {return}
        AppAccent.selectionColor(for:effectiveAppearance).withAlphaComponent(isEmphasized ? 0.22 : 0.12).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:5,yRadius:5).fill()
    }
}

// 两种文件详情共用原生透明列表；单击选择，双击定位文件，右键提供文件操作。
final class WorkspaceFileTable:NSTableView {
    var fileURLForRow:(Int) -> URL? = {_ in nil}
    override init(frame:NSRect) {
        super.init(frame:frame)
        style = .plain; backgroundColor = .clear; headerView = nil
        columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        target = self; doubleAction = #selector(revealClickedFile)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func menu(for event:NSEvent) -> NSMenu? {
        let index = row(at:convert(event.locationInWindow,from:nil))
        guard index >= 0,let file = fileURLForRow(index) else {return nil}
        selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
        let menu = NSMenu()
        let reveal = NSMenuItem(title:"在访达中显示",action:#selector(revealFile(_:)),keyEquivalent:"")
        let finder = AppIcons.finder.copy() as! NSImage; finder.size = NSSize(width:16,height:16)
        reveal.image = finder
        let copy = NSMenuItem(title:"拷贝文件路径",action:#selector(copyPath(_:)),keyEquivalent:"")
        copy.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil)
        for item in [reveal,copy] {item.target = self; item.representedObject = file; menu.addItem(item)}
        menu.showProvidedImages()
        return menu
    }
    @objc private func revealFile(_ sender:NSMenuItem) {
        guard let file = sender.representedObject as? URL else {return}
        WorkspaceFileRow.reveal(file)
    }
    @objc private func revealClickedFile() {
        guard clickedRow >= 0,let file = fileURLForRow(clickedRow) else {return}
        WorkspaceFileRow.reveal(file)
    }
    @objc private func copyPath(_ sender:NSMenuItem) {
        guard let file = sender.representedObject as? URL else {return}
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path,forType:.string)
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
                let count = NSTextField(labelWithString:"未提供"); count.font = Self.countFont; count.textColor = .secondaryLabelColor; count.alignment = .right
                count.widthAnchor.constraint(equalToConstant:countWidths.added+8+countWidths.removed).isActive = true
                row.addArrangedSubview(count)
            }
        }
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant:16),icon.heightAnchor.constraint(equalToConstant:16),
            row.leadingAnchor.constraint(equalTo:leadingAnchor,constant:4),row.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-6),row.centerYAnchor.constraint(equalTo:centerYAnchor)
        ])
        hoverHelp = detail; setAccessibilityLabel((change.map {$0+"，"} ?? "")+detail+(lines.map {"，新增 \($0.added) 行，删除 \($0.removed) 行"} ?? ""))
    }
    required init?(coder:NSCoder) {fatalError()}
    static let countFont = NSFont.monospacedSystemFont(ofSize:12,weight:.semibold)
    static func reveal(_ file:URL) {
        if FileManager.default.fileExists(atPath:file.path) {FinderFileReveal.reveal(file)}
        else {FinderFileReveal.openDirectory(file.deletingLastPathComponent())}
    }
    static func symbol(for entry:GitWorkspaceStatus.Entry) -> (String,NSColor) {
        if entry.group == .conflicted {return ("exclamationmark.triangle",StatusTextColor.red)}
        switch entry.change {
        case "新增":return ("plus.circle",StatusTextColor.green)
        case "删除":return ("minus.circle",StatusTextColor.red)
        case "重命名":return ("arrow.right",StatusTextColor.blue)
        case "复制":return ("doc.on.doc",StatusTextColor.teal)
        case "类型变化","子模块变化":return ("square.stack.3d.up",StatusTextColor.purple)
        default:return ("pencil",StatusTextColor.orange)
        }
    }
}

final class TurnFileEditsDetails:NSViewController,NSTableViewDataSource,NSTableViewDelegate {
    private let edits:[FileEditSummary],directory:String
    private let table = WorkspaceFileTable()
    private let countWidths:(added:CGFloat,removed:CGFloat)
    private let repeatedNames:Set<String>
    init(edits:[FileEditSummary],directory:String) {
        self.edits = edits; self.directory = directory
        let lines = edits.compactMap(\.lines)
        let minimum = ceil(("未提供" as NSString).size(withAttributes:[.font:WorkspaceFileRow.countFont]).width/2)
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
        table.setAccessibilityLabel("本轮文件修改，双击在访达中显示，右键显示文件操作")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.contentView.drawsBackground = false; scroll.verticalScrollElasticity = .allowed
        view = NSView(frame:NSRect(x:0,y:0,width:440,height:min(340,max(32,CGFloat(edits.count)*34))+16))
        scroll.frame = view.bounds.insetBy(dx:8,dy:8); scroll.autoresizingMask = [.width,.height]; view.addSubview(scroll)
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
        hoverHelp = url.absoluteString
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        target = self; action = #selector(open); setAccessibilityLabel("打开仓库网页："+url.absoluteString)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool {true}
    override func resetCursorRects() {super.resetCursorRects(); LinkAppearance.addCursorRect(bounds,to:self)}
    @objc private func open() {NSWorkspace.shared.open(url)}
}
