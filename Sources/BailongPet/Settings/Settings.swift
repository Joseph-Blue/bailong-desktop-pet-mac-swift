import AppKit
import ServiceManagement

final class SettingsPanel: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSToolbarDelegate {
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    let preferences: PetPreferences
    let catalog: Catalog?
    private let splitController = NSSplitViewController()
    private let sidebar = NSTableView(), scroll = NSScrollView(), content = NSStackView()
    private let resetButton = SettingsFooterButton(title:"恢复本页设置为默认值",target:nil,action:nil)
    private var actions = [SettingsAction]()
    private var textActions = [ObjectIdentifier:(String)->Void]()
    private var textEndActions = [ObjectIdentifier:(String)->Void]()
    private var identityPreview: NSTextField?
    private let templateEditor = SettingsTemplateEditor()
    private weak var updateStatusLabel: NSTextField?
    private weak var updateTimeLabel: NSTextField?
    private weak var automaticUpdateSwitch: NSSwitch?
    private weak var diagnosticsSwitch: NSSwitch?
    private var bufferControls = [NSControl]()
    private weak var bufferRow: NSView?
    private var selected: SettingsSection = .general
    private var hasShown = false
    private var materialPreview: Bubble?
    private var previewDismissal: DispatchWorkItem?
    private weak var glassSlider: GlassOpacitySlider?
    private weak var glassFollowSwitch: NSSwitch?
    private var glassControls = [NSView]()
    private var accentButtons = [NSButton]()
    private var accentNames = [NSTextField]()
    var petSymbol: () -> NSImage? = {nil}
    var onClose: () -> Void = {}
    var onPreview: (Clip) -> Void = { _ in }
    var onMessagePreview: (MessagePurpose) -> Void = { _ in }
    var onPreviewDetails: () -> Void = {}
    var onClearLocalData: (() throws -> Void)?
    private var storageGeneration = 0
    init(preferences: PetPreferences = .shared, catalog: Catalog? = nil) {
        self.preferences = preferences; self.catalog = catalog
        super.init()
        templateEditor.isFieldEditor = true; templateEditor.isRichText = false; templateEditor.allowsUndo = true
        window.title = "设置"; window.isReleasedWhenClosed = false; window.delegate = self
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width:800,height:540); window.setFrameAutosaveName("BailongSettingsWindow")
        let side = NSVisualEffectView(); side.material = .sidebar; side.blendingMode = .behindWindow
        side.state = .followsWindowActiveState
        let sideScroll = NSScrollView(); sideScroll.drawsBackground = false; sideScroll.hasVerticalScroller = true; sideScroll.autohidesScrollers = true
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section")); sidebar.addTableColumn(column)
        sidebar.headerView = nil; sidebar.style = .plain; sidebar.rowHeight = 32; sidebar.backgroundColor = .clear
        sidebar.selectionHighlightStyle = .none; sidebar.intercellSpacing = .zero
        sidebar.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; sidebar.autoresizingMask = [.width]
        column.minWidth = 0; column.resizingMask = .autoresizingMask
        sideScroll.hasHorizontalScroller = false; sideScroll.horizontalScrollElasticity = .none
        sidebar.dataSource = self; sidebar.delegate = self; sidebar.allowsEmptySelection = false
        sidebar.setAccessibilityLabel("设置分类"); sideScroll.documentView = sidebar
        side.addSubview(sideScroll)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let detail = NSView(), document = TopDownView(); scroll.documentView = document; detail.addSubview(scroll)
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 24
        document.addSubview(content)
        resetButton.target = self; resetButton.action = #selector(restorePage); resetButton.focusRingType = .exterior
        let resetAll = SettingsFooterButton(title:"恢复全部设置为默认值",target:self,action:#selector(restoreAll))
        resetAll.bezelStyle = .rounded; resetAll.hasDestructiveAction = true
        resetAll.focusRingType = .exterior
        let footerLine = NSBox(); footerLine.boxType = .separator
        let sidebarFooter = NSStackView(views:[footerLine,resetButton,resetAll])
        sidebarFooter.orientation = .vertical; sidebarFooter.spacing = 8; sidebarFooter.alignment = .leading
        for button in [resetButton as NSButton,resetAll] {
            button.font = .systemFont(ofSize:11); button.controlSize = .small
            button.heightAnchor.constraint(equalToConstant:28).isActive = true
            button.widthAnchor.constraint(equalTo:sidebarFooter.widthAnchor).isActive = true
        }
        footerLine.widthAnchor.constraint(equalTo:sidebarFooter.widthAnchor).isActive = true
        side.addSubview(sidebarFooter); sidebarFooter.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([sidebarFooter.leadingAnchor.constraint(equalTo:side.leadingAnchor,constant:12),sidebarFooter.trailingAnchor.constraint(equalTo:side.trailingAnchor,constant:-12),sidebarFooter.bottomAnchor.constraint(equalTo:side.safeAreaLayoutGuide.bottomAnchor,constant:-12)])
        let navigation = NSViewController(); navigation.view = side
        let destination = NSViewController(); destination.view = detail
        let sidebarItem = NSSplitViewItem(sidebarWithViewController:navigation)
        sidebarItem.minimumThickness = 180; sidebarItem.maximumThickness = 260; sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        let detailItem = NSSplitViewItem(viewController:destination); detailItem.minimumThickness = 560
        splitController.addSplitViewItem(sidebarItem); splitController.addSplitViewItem(detailItem)
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
        let toolbar = NSToolbar(identifier:"BailongSettingsToolbar"); toolbar.delegate = self; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar; window.toolbarStyle = .unified
        for view in [sideScroll,scroll,document,content] {view.translatesAutoresizingMaskIntoConstraints = false}
        let preferredWidth = content.widthAnchor.constraint(equalTo:document.widthAnchor,constant:-48); preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            sideScroll.leadingAnchor.constraint(equalTo:side.leadingAnchor),sideScroll.trailingAnchor.constraint(equalTo:side.trailingAnchor),
            sideScroll.topAnchor.constraint(equalTo:side.safeAreaLayoutGuide.topAnchor,constant:8),sideScroll.bottomAnchor.constraint(equalTo:sidebarFooter.topAnchor,constant:-12),
            scroll.leadingAnchor.constraint(equalTo:detail.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:detail.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:detail.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:detail.bottomAnchor),
            document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            content.centerXAnchor.constraint(equalTo:document.centerXAnchor),content.widthAnchor.constraint(lessThanOrEqualToConstant:660),preferredWidth,
            content.leadingAnchor.constraint(greaterThanOrEqualTo:document.leadingAnchor,constant:24),content.trailingAnchor.constraint(lessThanOrEqualTo:document.trailingAnchor,constant:-24),
            content.topAnchor.constraint(equalTo:document.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-24)
        ])
        splitController.splitView.setPosition(200,ofDividerAt:0)
        sidebar.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAccent),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshUpdateStatus),name:UpdateChecker.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshDiagnosticsSwitch),name:PetPreferences.didChange,object:preferences)
        render()
    }
    @objc private func refreshDiagnosticsSwitch() {
        diagnosticsSwitch?.state = preferences.bool("showDiagnostics") ? .on : .off
        automaticUpdateSwitch?.state = preferences.bool("automaticallyCheckUpdates") ? .on : .off
        updateBufferAvailability()
        glassSlider?.isEnabled = !preferences.bool("glassFollowsSystem")
        glassFollowSwitch?.state = preferences.bool("glassFollowsSystem") ? .on : .off
        for view in glassControls {view.alphaValue = preferences.bool("glassFollowsSystem") ? 0.45 : 1}
    }
    private func updateBufferAvailability() {
        let enabled = !preferences.bool("preloadWholeAnimation")
        for control in bufferControls { control.isEnabled = enabled }
        bufferRow?.alphaValue = enabled ? 1 : 0.45
    }
    func show(section: SettingsSection? = nil) {
        if let section {select(section)} else {render()}
        if !hasShown {window.center(); hasShown = true}
        NSApp.setActivationPolicy(.regular)
        NSApp.addWindowsItem(window,title:window.title,filename:false)
        if window.isMiniaturized {window.deminiaturize(nil)}
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func select(_ section: SettingsSection) {selected = section; sidebar.selectRowIndexes(IndexSet(integer:section.rawValue),byExtendingSelection:false); render()}
    func numberOfRows(in tableView: NSTableView) -> Int {SettingsSection.allCases.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {AccentHistoryRow()}
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = SettingsSection(rawValue:row)!
        let cell = HistoryConversationCell(title:section.title,symbol:section.symbol)
        cell.toolTip = nil
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {if let section = SettingsSection(rawValue:sidebar.selectedRow) {window.makeFirstResponder(nil); selected = section; render()}}
    func windowWillClose(_ notification: Notification) {window.makeFirstResponder(nil); dismissMaterialPreview(); NSApp.removeWindowsItem(window); onClose()}
    func windowWillReturnFieldEditor(_ sender:NSWindow, to client:Any?) -> Any? {
        guard let field = client as? SettingsTemplateField else {return nil}
        templateEditor.allowsTokens = field.allowsTokens
        return templateEditor
    }
    func controlTextDidBeginEditing(_ notification:Notification) {
        (notification.object as? SettingsTemplateField)?.refreshHighlight()
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {return}
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {return}
        textActions[ObjectIdentifier(field)]?(field.stringValue)
        (field as? SettingsTemplateField)?.refreshHighlight()
        identityPreview?.stringValue = preferences.statusLine("greetingTemplate")
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        textEndActions[ObjectIdentifier(field)]?(field.stringValue)
        // 等原生 field editor 退出后，为未聚焦的输入框恢复相同高亮。
        DispatchQueue.main.async { [weak field] in (field as? SettingsTemplateField)?.refreshHighlight() }
    }
    private func attach(_ control: NSControl, _ callback: @escaping (NSControl)->Void) {
        let action = SettingsAction(callback); actions.append(action); control.target = action; control.action = #selector(SettingsAction.invoke(_:))
    }
    private func fill(_ view: NSView, in stack: NSStackView) {view.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
    private func note(_ text: String) -> NSTextField {
        let field = label(text)
        field.font = .systemFont(ofSize:11); field.textColor = .secondaryLabelColor
        field.identifier = NSUserInterfaceItemIdentifier("settings-explanation")
        return field
    }
    private func group(_ title: String, _ rows: [NSView], action:NSView? = nil) {
        let section = NSStackView(); section.orientation = .vertical; section.alignment = .leading; section.spacing = 10
        let heading = label(title,bold:true); heading.font = .systemFont(ofSize:13,weight:.semibold)
        if let action {fill(alignedRow(leading:heading,control:action),in:section)} else {fill(heading,in:section)}
        let surface = SettingsSectionBackground(), items = NSStackView()
        items.orientation = .vertical; items.alignment = .leading; items.spacing = 10
        surface.addSubview(items); items.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([items.leadingAnchor.constraint(equalTo:surface.leadingAnchor,constant:12),items.trailingAnchor.constraint(equalTo:surface.trailingAnchor,constant:-12),items.topAnchor.constraint(equalTo:surface.topAnchor,constant:12),items.bottomAnchor.constraint(equalTo:surface.bottomAnchor,constant:-12)])
        for (index,row) in rows.enumerated() {
            if index > 0 && row.identifier?.rawValue != "settings-explanation" {let line = NSBox(); line.boxType = .separator; fill(line,in:items)}
            fill(row,in:items)
        }
        fill(surface,in:section); fill(section,in:content)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {[.init("settings-sidebar"),.init("settings-divider"),.flexibleSpace]}
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {toolbarAllowedItemIdentifiers(toolbar)}
    func toolbar(_ toolbar: NSToolbar,itemForItemIdentifier id: NSToolbarItem.Identifier,willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "settings-divider" {return NSTrackingSeparatorToolbarItem(identifier:id,splitView:splitController.splitView,dividerIndex:0)}
        guard id.rawValue == "settings-sidebar" else {return nil}
        let item = NSToolbarItem(itemIdentifier:id); item.label = "显示或隐藏侧栏"; item.toolTip = item.label
        item.image = NSImage(systemSymbolName:"sidebar.left",accessibilityDescription:item.label)
        item.target = splitController; item.action = #selector(NSSplitViewController.toggleSidebar(_:)); item.isBordered = true
        return item
    }
    private func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let texts = NSStackView(); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 4
        fill(label(title),in:texts)
        if let detail {let explanation = label(detail); explanation.font = .systemFont(ofSize:11); explanation.textColor = .secondaryLabelColor; fill(explanation,in:texts)}
        return alignedRow(leading:texts,control:control)
    }
    private func alignedRow(leading: NSView, control: NSView) -> NSView {
        // 显式固定左右两端；多余宽度留给左侧说明，不拉长开关或按钮。
        let row = NSView()
        compactControl(control)
        if let field = control as? NSTextField, !field.isEditable {field.alignment = .right}
        for view in [leading,control] {view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view)}
        leading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        control.setContentHuggingPriority(.defaultHigh,for:.horizontal)
        control.setContentCompressionResistancePriority(.defaultHigh,for:.horizontal)
        let compactHeight = row.heightAnchor.constraint(equalToConstant:32); compactHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo:row.leadingAnchor),
            leading.trailingAnchor.constraint(equalTo:control.leadingAnchor,constant:-24),
            leading.centerYAnchor.constraint(equalTo:row.centerYAnchor),
            leading.topAnchor.constraint(greaterThanOrEqualTo:row.topAnchor),
            leading.bottomAnchor.constraint(lessThanOrEqualTo:row.bottomAnchor),
            control.trailingAnchor.constraint(equalTo:row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo:row.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo:row.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo:row.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant:32),compactHeight
        ])
        return row
    }
    private func compactControl(_ view: NSView) {
        if let stack = view as? NSStackView {
            // 普通 contentHugging 不控制 NSStackView 的 gravity 区域间距。
            // fill 让末个控件贴住操作区尾端，内部间距和控件都保持自然宽度。
            stack.distribution = .fill
            stack.setHuggingPriority(.defaultHigh,for:.horizontal)
            stack.edgeInsets = NSEdgeInsets(top:0,left:0,bottom:0,right:0)
            for child in stack.arrangedSubviews {compactControl(child)}
            // 操作组不承担整行的剩余空间；已有明确宽度的滑块组沿用该宽度。
            if !stack.constraints.contains(where: {$0.isActive && $0.firstAttribute == .width && $0.secondItem == nil && $0.relation == .equal}) {
                stack.widthAnchor.constraint(equalToConstant:stack.fittingSize.width.rounded(.up)).isActive = true
            }
        }
    }
    private func toggle(_ title: String, _ key: String, detail: String? = nil) -> NSView {
        let control = AccentSwitch(); control.state = preferences.bool(key) ? .on : .off; control.setAccessibilityLabel(title)
        if key == "showDiagnostics" { diagnosticsSwitch = control }
        if key == "automaticallyCheckUpdates" { automaticUpdateSwitch = control }
        attach(control) { [weak self] sender in self?.preferences.set((sender as! NSSwitch).state == .on,for:key) }
        return row(title,detail:detail,control:control)
    }
    private func popup(_ title: String, options: [(String,String)], value: String, width: CGFloat = 190, identifier: String? = nil, changed: @escaping (String)->Void) -> NSView {
        let menu = NSPopUpButton(); menu.addItems(withTitles:options.map(\.1)); menu.selectItem(at:options.firstIndex {$0.0 == value} ?? 0)
        if let identifier {menu.identifier = NSUserInterfaceItemIdentifier(identifier)}
        menu.widthAnchor.constraint(equalToConstant:width).isActive = true; menu.setAccessibilityLabel(title)
        attach(menu) {sender in let index = (sender as! NSPopUpButton).indexOfSelectedItem; if options.indices.contains(index) {changed(options[index].0)}}
        return row(title,control:menu)
    }
    private func choice(_ title: String, _ key: String, _ options: [(String,String)]) -> NSView {
        popup(title,options:options,value:preferences.string(key),width:key == "sendShortcut" ? 260 : key == "animationQuality" ? 250 : 190,identifier:key) { [weak self] value in
            self?.preferences.set(value,for:key)
            if key == "addressMode" {self?.render()}
            self?.identityPreview?.stringValue = self?.preferences.statusLine("greetingTemplate") ?? ""
        }
    }
    @objc private func refreshAccent() {
        func update(_ view: NSView) {
            if let slider = view as? NSSlider {slider.trackFillColor = AppAccent.color}
            if let well = view as? NSColorWell {well.color = AppAccent.color}
            if let menu = view as? NSPopUpButton, menu.identifier?.rawValue == "accentStyle" {menu.selectItem(at:AppAccent.choices.firstIndex {$0.0 == preferences.string("accentStyle")} ?? 0)}
            for child in view.subviews {update(child)}
        }
        if let root = window.contentView {update(root)}
        for (index,button) in accentButtons.enumerated() {
            let chosen = AppAccent.choices[index].0 == preferences.string("accentStyle")
            button.state = chosen ? .on : .off; button.needsDisplay = true
            accentNames[index].stringValue = chosen ? AppAccent.choices[index].1 : ""
        }
        sidebar.enumerateAvailableRowViews { [weak self] row,index in
            row.needsDisplay = true
            let cell = self?.sidebar.view(atColumn:0,row:index,makeIfNecessary:false) as? NSTableCellView
            cell?.backgroundStyle = row.interiorBackgroundStyle
        }
    }
    private func entry(_ title: String, value: String, placeholder: String = "", limit: Int = 20, allowsTokens:Bool = true, icon:NSImage? = nil, tokenHint:String? = nil, changed: @escaping (String)->Void) -> NSView {
        let field: NSTextField = selected == .identity ? SettingsTemplateField(string:value) : NSTextField(string:value)
        let templateField = field as? SettingsTemplateField
        templateField?.allowsTokens = allowsTokens
        field.placeholderString = placeholder; field.delegate = self
        templateField?.refreshHighlight(); field.setAccessibilityLabel(title)
        let count = NSTextField(labelWithString:"")
        count.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); count.alignment = .right
        count.widthAnchor.constraint(equalToConstant:54).isActive = true
        let clear = NSButton(image:NSImage(systemSymbolName:"xmark.circle.fill",accessibilityDescription:"清空"+title)!,target:nil,action:nil)
        clear.isBordered = false; clear.contentTintColor = .secondaryLabelColor
        clear.setAccessibilityLabel("清空"+title)
        clear.widthAnchor.constraint(equalToConstant:20).isActive = true
        clear.heightAnchor.constraint(equalToConstant:24).isActive = true
        let updateCount: (String)->Void = {value in
            let length = allowsTokens ? TemplateSyntax.count(value) : value.count
            count.stringValue = "\(length)/\(limit)"
            count.textColor = length >= limit ? .systemRed : .secondaryLabelColor
            count.setAccessibilityLabel("已输入 \(length) 字，上限 \(limit) 字")
            clear.isEnabled = !value.isEmpty
        }
        updateCount(value)
        textActions[ObjectIdentifier(field)] = {text in
            let bounded = allowsTokens ? TemplateSyntax.bounded(text,limit:limit) : String(text.prefix(limit))
            if bounded != text {
                if let editor = field.currentEditor() as? NSTextView {
                    let selection = editor.selectedRange(); editor.string = bounded
                    editor.setSelectedRange(NSRange(location:min(selection.location,(bounded as NSString).length),length:0))
                }
                field.stringValue = bounded
            }
            updateCount(bounded); changed(bounded)
        }
        attach(clear) { [weak self,weak field] _ in
            guard let self,let field else {return}
            self.window.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                let all = NSRange(location:0,length:(editor.string as NSString).length)
                if editor.shouldChangeText(in:all,replacementString:"") {editor.replaceCharacters(in:all,with:""); editor.didChangeText()}
            } else {
                field.stringValue = ""; self.textActions[ObjectIdentifier(field)]?(""); (field as? SettingsTemplateField)?.refreshHighlight()
            }
        }
        let controls = NSStackView(views:[field,clear,count]); controls.orientation = .horizontal; controls.spacing = 6; controls.alignment = .centerY; controls.distribution = .fill
        field.setContentHuggingPriority(.defaultLow,for:.horizontal)
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        if limit >= 120 {
            // 台词标签在上，输入横向铺满；不再给短标签留出大半行空白。
            field.usesSingleLineMode = false; field.maximumNumberOfLines = 0
            field.cell?.wraps = true; field.cell?.isScrollable = false
            field.heightAnchor.constraint(equalToConstant:52).isActive = true
            let row = NSStackView(); row.orientation = .vertical; row.alignment = .leading; row.spacing = 8
            fill(label(title),in:row); fill(controls,in:row)
            return row
        }
        field.widthAnchor.constraint(equalToConstant:240).isActive = true
        let caption = identityLabel(title,token:tokenHint)
        let leading = NSStackView(); leading.orientation = .horizontal; leading.alignment = .centerY; leading.spacing = 6
        if let icon {
            let image = NSImageView(image:icon); image.contentTintColor = .secondaryLabelColor
            image.widthAnchor.constraint(equalToConstant:18).isActive = true; image.heightAnchor.constraint(equalToConstant:18).isActive = true
            leading.addArrangedSubview(image)
        }
        leading.addArrangedSubview(caption)
        return alignedRow(leading:leading,control:controls)
    }
    private func identityLabel(_ title:String,token:String?) -> NSTextField {
        let caption = label(title)
        if let token {
            let value = NSMutableAttributedString(string:title+"  "+token,attributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.labelColor])
            SettingsTemplateTokens.ranges(in:value.string) {range,color in
                value.addAttributes([.font:NSFont.systemFont(ofSize:11),.foregroundColor:color,.backgroundColor:color.withAlphaComponent(0.13)],range:range)
            }
            caption.attributedStringValue = value
        }
        return caption
    }
    private func addressChoice() -> NSView {
        let radios = NSStackView(); radios.orientation = .horizontal; radios.alignment = .centerY; radios.spacing = 16
        for (key,title) in [("name","你的名字"),("custom","特定称呼")] {
            let button = AccentChoiceButton(title:title,type:.radio)
            button.state = preferences.string("addressMode") == key ? .on : .off
            attach(button) { [weak self] _ in
                guard let self else {return}
                self.window.makeFirstResponder(nil); self.preferences.set(key,for:"addressMode"); self.render()
            }
            radios.addArrangedSubview(button)
        }
        return alignedRow(leading:identityLabel("怎么称呼你",token:"{特定称呼}"),control:radios)
    }
    private func text(_ title: String, _ key: String, placeholder: String = "", limit: Int = 20) -> NSView {
        let icon:NSImage?
        switch key {
        case "ownerName": icon = NSImage(systemSymbolName:"person.crop.circle",accessibilityDescription:nil)
        case "petName": icon = petSymbol()
        case "customAddress": icon = NSImage(systemSymbolName:"bubble.left",accessibilityDescription:nil)
        default: icon = nil
        }
        let token = ["ownerName":"{用户名}","petName":"{桌宠名}","customAddress":"{特定称呼}"][key]
        return entry(title,value:preferences.string(key),placeholder:placeholder,limit:limit,allowsTokens:!["ownerName","petName"].contains(key),icon:icon,tokenHint:token) { [weak self] value in self?.preferences.set(value,for:key) }
    }
    private func slider(_ title: String, _ key: String, range: ClosedRange<Double>, step: Double = 1, suffix: String, detail: String? = nil) -> NSView {
        let slider = NSSlider(value:preferences.number(key),minValue:range.lowerBound,maxValue:range.upperBound,target:nil,action:nil)
        slider.isContinuous = true; slider.trackFillColor = AppAccent.color; slider.widthAnchor.constraint(equalToConstant:180).isActive = true
        if key == "petPercent" || key == "bubblePercent" {slider.numberOfTickMarks = Int((range.upperBound-range.lowerBound)/25)+1; slider.tickMarkPosition = .below}
        slider.setAccessibilityLabel(title)
        let number = NSTextField(string:""); number.alignment = .right; number.widthAnchor.constraint(equalToConstant:54).isActive = true; number.setAccessibilityLabel(title+suffix); (number.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        let formatter = NumberFormatter(); formatter.minimum = NSNumber(value:range.lowerBound); formatter.maximum = NSNumber(value:range.upperBound); formatter.maximumFractionDigits = step < 1 ? 2 : 0; formatter.usesGroupingSeparator = false; number.formatter = formatter
        func format(_ value: Double) {number.doubleValue = value}
        format(slider.doubleValue)
        attach(slider) { [weak self] sender in
            let value = ((sender.doubleValue/step).rounded()*step); format(value); self?.preferences.set(value,for:key)
        }
        attach(number) { [weak self] sender in let value = max(range.lowerBound,min(range.upperBound,(sender.doubleValue/step).rounded()*step)); slider.doubleValue = value; format(value); self?.preferences.set(value,for:key) }
        let unit = label(suffix); unit.font = .systemFont(ofSize:11); unit.textColor = .secondaryLabelColor
        unit.widthAnchor.constraint(equalToConstant:22).isActive = true
        let controls = NSStackView(views:[number,unit,slider]); controls.spacing = 8; controls.alignment = .centerY
        controls.widthAnchor.constraint(equalToConstant:272).isActive = true
        return row(title,detail:detail,control:controls)
    }
    private func bufferFrames() -> NSView {
        let slider = NSSlider(value: Double(preferences.animationBufferFrames), minValue: 6, maxValue: 240, target: nil, action: nil)
        slider.isContinuous = false; slider.trackFillColor = AppAccent.color
        slider.numberOfTickMarks = 7; slider.tickMarkPosition = .below; slider.allowsTickMarkValuesOnly = false
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slider.setAccessibilityLabel("动画缓冲帧数")
        let minimum = label("6 帧"), maximum = label("240 帧")
        for label in [minimum, maximum] { label.font = .systemFont(ofSize: 10); label.textColor = .secondaryLabelColor }
        let limits = NSView()
        for label in [minimum, maximum] { limits.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            limits.widthAnchor.constraint(equalToConstant: 180), limits.heightAnchor.constraint(equalToConstant: 14),
            minimum.leadingAnchor.constraint(equalTo: limits.leadingAnchor), minimum.centerYAnchor.constraint(equalTo: limits.centerYAnchor),
            maximum.trailingAnchor.constraint(equalTo: limits.trailingAnchor), maximum.centerYAnchor.constraint(equalTo: limits.centerYAnchor)
        ])
        let track = NSStackView(views: [slider, limits]); track.orientation = .vertical; track.spacing = 0
        let number = NSTextField(string: String(preferences.animationBufferFrames))
        number.alignment = .right; number.widthAnchor.constraint(equalToConstant: 54).isActive = true
        number.setAccessibilityLabel("输入动画缓冲帧数"); number.delegate = self
        // 不用 formatter 阻止退出非法输入；提交时统一回到默认值。
        let commit: (String) -> Void = { [weak self] text in
            guard let self else { return }
            let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
            let value = parsed.flatMap { (6...240).contains($0) ? $0 : nil } ?? (PetPreferences.defaults["animationBufferFrames"] as! Int)
            number.integerValue = value; slider.integerValue = value
            if self.preferences.animationBufferFrames != value { self.preferences.set(value, for: "animationBufferFrames") }
        }
        textEndActions[ObjectIdentifier(number)] = commit
        attach(number) { sender in commit(sender.stringValue) }
        attach(slider) { sender in commit(String(Int(sender.doubleValue.rounded()))) }
        let unit = label("帧"); unit.font = .systemFont(ofSize:11); unit.textColor = .secondaryLabelColor
        unit.widthAnchor.constraint(equalToConstant:22).isActive = true
        let controls = NSStackView(views: [number, unit, track]); controls.orientation = .horizontal
        controls.widthAnchor.constraint(equalToConstant:272).isActive = true
        controls.alignment = .centerY; controls.spacing = 8
        let result = row("动画缓冲帧数", control: controls)
        bufferControls = [slider, number]; bufferRow = result; updateBufferAvailability()
        return result
    }
    private func time(_ title: String, _ key: String) -> NSView {
        let picker = NSDatePicker(); picker.datePickerStyle = .textFieldAndStepper; picker.datePickerElements = [.hourMinute]; picker.locale = Locale(identifier:"zh_CN")
        let minutes = Int(preferences.number(key)); picker.dateValue = Calendar.current.date(from:DateComponents(year:2026,month:1,day:1,hour:minutes/60,minute:minutes%60))!
        picker.setAccessibilityLabel(title)
        attach(picker) { [weak self] sender in let c = Calendar.current.dateComponents([.hour,.minute],from:(sender as! NSDatePicker).dateValue); self?.preferences.set((c.hour ?? 0)*60+(c.minute ?? 0),for:key) }
        return row(title,control:picker)
    }
    private func render() {
        guard window.contentView != nil else {return}
        dismissMaterialPreview(); accentButtons.removeAll(); accentNames.removeAll(); glassControls.removeAll()
        for view in content.arrangedSubviews {content.removeArrangedSubview(view); view.removeFromSuperview()}
        actions.removeAll(); textActions.removeAll(); textEndActions.removeAll(); bufferControls.removeAll(); bufferRow = nil; identityPreview = nil
        window.title = selected.title
        resetButton.isEnabled = !selected.keys.isEmpty
        switch selected {
        case .general: general()
        case .identity: identity()
        case .activity: activity()
        case .messages: messages()
        case .appearance: appearance()
        case .advanced: advanced()
        case .updates: updates()
        case .developer:
            group("动画", [choice("画质", "animationQuality", [("512", "清晰 · 512×512"), ("384", "均衡 · 384×384"), ("256", "省运行内存 (RAM) · 256×256")]),
                choice("素材帧率上限", "animationFPSLimit", [("full", "满帧 (≥ 24 FPS)"), ("20", "20 FPS"), ("15", "15 FPS")]),
                bufferFrames(),
                toggle("整段动画预加载", "preloadWholeAnimation", detail: "不推荐，会显著增加运行内存 (RAM) 占用。")])
            group("应用统计", [toggle("开启应用性能信息统计浮窗", "showDiagnostics")])
        }
        scroll.contentView.scroll(to:.zero)
    }
    private func general() {
        let login = SMAppService.mainApp.status
        let loginText = login == .enabled ? "已启用" : login == .requiresApproval ? "等待系统批准" : "未启用"
        group("启动",[
            row("登录时启动",detail:loginText,control:ActionButton(login == .enabled ? "停用…" : login == .requiresApproval ? "打开登录项…" : "启用…") { [weak self] in self?.configureLogin() }),
            row("随 Codex 启动",detail:FollowLauncher.statusText,control:ActionButton("配置…") { [weak self] in FollowLauncher.configure(); self?.render() }),
            toggle("启动后显示桌宠","showOnLaunch"),toggle("记住上次位置","rememberPosition")])
        var displays = [("","跟随当前屏幕")] + NSScreen.screens.map {(PetPreferences.displayID($0),$0.localizedName)}
        let saved = preferences.string("preferredDisplay")
        if !displays.contains(where:{$0.0 == saved}) {displays.append((saved,"已断开的显示器（暂用当前屏幕）"))}
        group("桌面",[toggle("全屏时自动隐藏","autoFullscreen"),choice("所在显示器","preferredDisplay",displays)])
    }
    private func configureLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {showError("请从应用包设置登录启动",PetFailure(message:"开发脚本不会注册登录项。请使用构建后的 .app。")); return}
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
            render()
        } catch {showError("登录启动设置失败",error)}
    }
    private func identity() {
        fill(note("{用户名} 是你的名字，{桌宠名} 是桌宠的名字；{特定称呼} 按“怎么称呼你”的选择生成。每个变量按 1 字计数。"),in:content)
        var names = [text("你的名字","ownerName",placeholder:"默认为“主人”"),text("桌宠的名字","petName",placeholder:"白龙娘"),addressChoice()]
        if preferences.string("addressMode") == "custom" {names.append(text("特定称呼","customAddress",placeholder:"{桌宠名}最喜欢的{用户名}"))}
        group("我们怎么称呼彼此",names)
        let preview = label(preferences.statusLine("greetingTemplate")); preview.font = .systemFont(ofSize:15,weight:.medium); identityPreview = preview
        group("见面时说",[text("问候语","greetingTemplate",limit:120),alignedRow(leading:preview,control:ActionButton("预览消息") { [weak self] in self?.onMessagePreview(.preview) })])
        group("任务状态台词",[text("执行任务中","taskProgressTemplate",limit:120),text("等待回答","taskAnswerTemplate",limit:120),text("等待批准","taskApprovalTemplate",limit:120),text("任务成功","taskSuccessTemplate",limit:120),text("任务失败","taskFailureTemplate",limit:120),text("任务中断或取消","taskInterruptedTemplate",limit:120)])
        group("额度查询台词",[text("正在查询","quotaLoadingTemplate",limit:120)])
        if let catalog {
            let lines = (catalog.variants+catalog.work).filter {$0.line != nil}
            let restore = ActionButton("恢复默认") { [weak self] in
                guard let self else {return}
                self.window.makeFirstResponder(nil)
                self.preferences.set([String:String](),for:"customLines"); self.render()
            }
            restore.controlSize = .small; restore.font = .systemFont(ofSize:11)
            restore.setAccessibilityLabel("恢复全部互动台词为默认值")
            group("互动台词",lines.map {clip in entry(clip.title,value:(preferences.value("customLines") as? [String:String])?[clip.id] ?? "",placeholder:preferences.templateSource(clip.line ?? ""),limit:120) { [weak self] in self?.preferences.setLine($0,for:clip.id) }},action:restore)
        }
    }
    private func activity() {
        let actions = [("none","无动作"),("chat","临时聊天面板"),("quota","查看额度"),("history","查看历史消息"),("random","随机动画")]
        group("鼠标互动",[choice("单击桌宠","singleClickAction",actions),choice("双击桌宠","doubleClickAction",actions),choice("右键双击桌宠","rightDoubleClickAction",actions),note("普通状态单击松手立即执行，双击的第一下会先执行单击动作。躲在角落时，单击松手后等待 250 毫秒再召回，不执行单击动作；期间第二击取消召回并执行双击动作。拖动立即召回。右键按下立即打开菜单，双击时关闭菜单并执行所选动作。")])
        let interval = preferences.number("leisureInterval")
        let preset = interval == 60 ? "60" : interval == 15 ? "15" : interval == 8 ? "8" : "custom"
        group("自主活动",[
            popup("活跃程度",options:[("60","安静"),("15","适中"),("8","活泼"),("custom","自定义")],value:preset) { [weak self] value in if let seconds = Double(value) {self?.preferences.set(seconds,for:"leisureInterval"); self?.render()} },
            slider("活动间隔","leisureInterval",range:5...180,suffix:"秒",detail:"到达间隔后，当前动作播放完再切换。"),
            toggle("自主移动","autoMove"),choice("活动范围","movementRange",[("still","原地陪伴"),("nearby","小范围活动"),("screen","整个屏幕")]),toggle("减少重复动作","avoidRepeat"),
            slider("整体播放速度","playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:"动作和位移使用同一时间轴。单个动作倍率会与整体倍率相乘。")])
        group("任务动作",[toggle("收到任务时播放开场","taskOpening"),toggle("完成任务时播放庆祝","taskCelebration")])
        guard let catalog else {return}
        for (title,clips,automatic) in [("待机动作",catalog.idles+catalog.extras,true),("互动动作",catalog.variants,true),("工作动作",catalog.work,true),("移动动作",catalog.movementAnimations,true),("鼠标与额度动作",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false)] {
            group(title,clips.map {clip in animationRow(clip,automatic:automatic)})
        }
        fill(note("频率控制同组随机选择的偏好；星标会让该动作更常出现。手动预览和明确的拖拽、落地、额度及任务事件不受随机频率影响。默认待机始终保留。"),in:content)
    }
    private func animationRow(_ clip: Clip, automatic: Bool) -> NSView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let controls = NSStackView(); controls.spacing = 8
        let preview = ActionButton("播放") { [weak self] in self?.onPreview(clip) }; preview.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil); preview.imagePosition = .imageLeading
        if automatic {
            let star = AccentChoiceButton(title:"偏爱",type:.switch); star.state = preferences.favorites.contains(clip.id) ? .on : .off
            attach(star) { [weak self] sender in guard let self else {return}; var values = self.preferences.favorites.filter {$0 != clip.id}; if (sender as! NSButton).state == .on {values.append(clip.id)}; self.preferences.set(values,for:"favorites") }
            controls.addArrangedSubview(star)
            let menu = NSPopUpButton(); let values = clip.id == "idle" ? [1,3,4,6] : [0,1,3,4,6]
            let names = [0:"关闭",1:"很少",3:"偶尔",4:"较常",6:"经常"]
            menu.addItems(withTitles:values.map {names[$0]!}); menu.selectItem(at:values.firstIndex(of:preferences.baseWeight(clip.id)) ?? 0)
            menu.setAccessibilityLabel(clip.title+"出现频率")
            attach(menu) { [weak self] sender in self?.preferences.setWeight(values[(sender as! NSPopUpButton).indexOfSelectedItem],for:clip.id) }
            controls.addArrangedSubview(menu)
        }
        controls.addArrangedSubview(preview)
        let image = NSImageView(); image.image = NSImage(systemSymbolName:"film",accessibilityDescription:nil); image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant:20).isActive = true; image.heightAnchor.constraint(equalToConstant:20).isActive = true
        let name = label(clip.title); let nameStack = NSStackView(views:[image,name]); nameStack.spacing = 8
        fill(alignedRow(leading:nameStack,control:controls),in:stack)
        let options = [("0.75","0.75×"),("1.0","1×（默认）"),("1.25","1.25×"),("1.5","1.5×")]
        fill(popup("此动作播放速度",options:options,value:String(preferences.clipSpeed(clip.id))) { [weak self] in self?.preferences.setSpeed(Double($0)!,for:clip.id) },in:stack)
        return stack
    }
    private func messages() {
        group("历史记录",[toggle("记录历史","recordHistory"),note("关闭后停止新增和更新本机历史，已有记录保留。当前任务上下文暂留运行内存 (RAM)，重新开启不补写关闭期间的内容。Codex 原有记录不受此开关影响。")])
        group("输入快捷键",[
            choice("发送与换行","sendShortcut",[("commandReturn","⌘ Command + ↩ Enter 发送"),("returnToSend","↩ Enter 发送")]),
            note("默认：⌘ Command + ↩ Enter 发送，↩ Enter 换行。\n备选：↩ Enter 发送；⇧ Shift + ↩ Enter 或 ⌥ Option + ↩ Enter 换行。\n临时对话和历史对话同步生效，中文输入法选词时不会发送。")])
        group("显示哪些消息",[toggle("任务气泡提醒","taskBubbles"),toggle("任务进展","progressBubbles"),toggle("最终回复","resultBubbles"),toggle("互动台词","interactionBubbles"),note("需要处理的审批、补充输入与任务失败仍保留通知入口。关闭气泡不会停止任务或删除历史。")])
        group("停留时间",[
            slider("互动台词","interactionSeconds",range:0...60,suffix:"秒"),slider("任务进展","progressSeconds",range:0...60,suffix:"秒"),slider("最终回复","resultSeconds",range:0...120,suffix:"秒"),slider("额度信息","quotaSeconds",range:0...120,suffix:"秒"),note("设为 0 秒表示手动关闭。审批、补充输入和失败提示保留到处理或手动关闭。"),
            toggle("长回复自动延长阅读时间","autoReadTime",detail:"最多延长到 120 秒；手动关闭模式不受影响。"),toggle("鼠标移入时暂停倒计时","pauseOnHover"),toggle("文字显示完毕后开始计时","countAfterReveal")])
        group("显示与声音",[toggle("逐步显示文字","typingEffect"),toggle("播放音效","soundEnabled"),row("最终回复时长",control:ActionButton("预览…") { [weak self] in self?.onMessagePreview(.result) })])
        group("安静陪伴",[toggle("安静陪伴模式","quietCompanion",detail:"减少自主活动、停止自动移动，关闭互动台词、进展气泡和音效。最终回复与待处理通知保留。"),toggle("启用专注时段","quietSchedule"),time("开始时间","quietStart"),time("结束时间","quietEnd"),note("按本机时间生效，支持跨午夜；起止相同表示全天。")])
    }
    private func appearance() {
        group("大小",[slider("桌宠大小","petPercent",range:50...200,suffix:"%"),slider("气泡大小","bubblePercent",range:50...150,suffix:"%"),slider("消息文字大小","messageFontSize",range:11...20,suffix:"pt")])
        let palette = NSStackView(); palette.spacing = 3; palette.alignment = .top
        for (key,name) in AppAccent.choices {
            let dot = AccentSwatch(key:key,name:name)
            dot.state = preferences.string("accentStyle") == key ? .on : .off
            attach(dot) { [weak self] _ in
                guard let self else {return}
                self.preferences.set(key,for:"accentStyle")
                self.render()
            }
            let caption = NSTextField(labelWithString:dot.state == .on ? name : "")
            caption.font = .systemFont(ofSize:9); caption.textColor = .secondaryLabelColor; caption.alignment = .center
            caption.heightAnchor.constraint(equalToConstant:13).isActive = true
            let column = NSStackView(views:[dot,caption]); column.orientation = .vertical; column.spacing = 2
            column.widthAnchor.constraint(equalToConstant:38).isActive = true
            caption.widthAnchor.constraint(equalTo:column.widthAnchor).isActive = true
            palette.addArrangedSubview(column); accentButtons.append(dot); accentNames.append(caption)
        }
        var themeRows = [choice("外观模式","appearanceMode",AppAppearance.choices),row("强调色",control:palette)]
        if preferences.string("accentStyle") == "custom" {
            let well = NSColorWell(); well.color = AppAccent.color; well.widthAnchor.constraint(equalToConstant:70).isActive = true
            attach(well) { [weak self] sender in guard let rgb = (sender as! NSColorWell).color.usingColorSpace(.sRGB) else {return}; self?.preferences.set([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],for:"accentRGB") }
            themeRows.append(row("自定义",control:well))
        }
        group("主题",themeRows)
        let radios = NSStackView(); radios.orientation = .vertical; radios.alignment = .leading; radios.spacing = 8
        for (key,name) in [("glass","液态玻璃材质"),("plain","普通材质")] {
            let button = AccentChoiceButton(title:name,type:.radio)
            button.state = (preferences.usesGlass ? "glass" : "plain") == key ? .on : .off
            button.isEnabled = PetPreferences.glassAvailable
            attach(button) { [weak self] _ in self?.preferences.set(key,for:"bubbleMaterial"); self?.render(); self?.showMaterialPreview() }
            radios.addArrangedSubview(button)
        }
        let materialNote = note("液态玻璃材质仅在 macOS 26、27 系统中可用")
        var materialRows = [row("消息窗口材质",control:radios),materialNote]
        if preferences.usesGlass {
            let follow = AccentSwitch(); follow.state = preferences.bool("glassFollowsSystem") ? .on : .off; glassFollowSwitch = follow
            attach(follow) { [weak self] sender in self?.preferences.set((sender as! NSSwitch).state == .on,for:"glassFollowsSystem"); self?.showMaterialPreview() }
            materialRows.append(row("液态玻璃跟随系统设定",control:follow))
            let slider = GlassOpacitySlider(); slider.minValue = 0; slider.maxValue = 1; slider.doubleValue = preferences.number("glassOpacity")
            slider.numberOfTickMarks = 5; slider.allowsTickMarkValuesOnly = false; slider.isContinuous = true
            slider.trackFillColor = AppAccent.color; slider.widthAnchor.constraint(equalToConstant:180).isActive = true
            slider.setAccessibilityLabel("玻璃不透明度"); slider.isEnabled = !preferences.bool("glassFollowsSystem"); glassSlider = slider
            attach(slider) { [weak self] sender in self?.preferences.set((sender as! NSSlider).doubleValue,for:"glassOpacity"); self?.showMaterialPreview() }
            slider.ended = { [weak self] in self?.schedulePreviewDismissal() }
            let left = glassSymbol(filled:false), right = glassSymbol(filled:true)
            let controls = NSStackView(views:[left,slider,right]); controls.spacing = 8; controls.alignment = .centerY
            controls.widthAnchor.constraint(equalToConstant:244).isActive = true
            controls.alphaValue = slider.isEnabled ? 1 : 0.45; glassControls = [controls]
            materialRows.append(row("玻璃不透明度",control:controls))
        }
        materialRows.append(toggle("动态效果","bubbleMotion"))
        materialRows.append(row("气泡效果",control:ActionButton("预览气泡") { [weak self] in self?.showMaterialPreview() }))
        group("消息窗口",materialRows)
    }
    private func glassSymbol(filled:Bool) -> NSImageView {
        let name = "capsule.on.rectangle.liquid.glass" + (filled ? ".fill" : "")
        let image = NSImage(systemSymbolName:name,accessibilityDescription:nil) ?? NSImage(contentsOf:Paths.resources.appendingPathComponent("glass-symbols/"+name+".pdf"))
        image?.isTemplate = true
        let view = NSImageView(); view.image = image; view.contentTintColor = .secondaryLabelColor
        view.setAccessibilityLabel(filled ? "更不透明" : "更通透")
        view.widthAnchor.constraint(equalToConstant:24).isActive = true; view.heightAnchor.constraint(equalToConstant:24).isActive = true
        return view
    }
    private func showMaterialPreview() {
        previewDismissal?.cancel()
        if materialPreview == nil {materialPreview = Bubble(); materialPreview?.onDetails = { [weak self] in self?.onPreviewDetails() }}
        guard let preview = materialPreview else {return}
        if !preview.visible {preview.show(title:preferences.petName,body:preferences.statusLine("greetingTemplate"),kind:"preview",scale:preferences.number("bubblePercent")/100,seconds:0,details:true)}
        guard let screen = window.screen ?? NSScreen.main else {return}
        let visible = screen.visibleFrame, size = preview.targetFrame.size
        let x = min(visible.maxX-size.width-12,max(visible.minX+12,window.frame.maxX+12))
        let y = min(visible.maxY-size.height-12,max(visible.minY+12,window.frame.maxY-size.height-72))
        preview.move(to:NSPoint(x:x,y:y))
        if glassSlider?.tracking != true {schedulePreviewDismissal()}
    }
    private func schedulePreviewDismissal() {
        previewDismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.materialPreview?.hide() }
        previewDismissal = work; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    private func dismissMaterialPreview() {previewDismissal?.cancel(); previewDismissal = nil; materialPreview?.hide()}
    @objc private func refreshUpdateStatus() {
        updateStatusLabel?.stringValue = UpdateChecker.shared.recordText
        updateTimeLabel?.stringValue = UpdateChecker.shared.lastCheckText
    }
    private func updates() {
        group("版本",[row("当前版本",control:label(Paths.version)),
            row("检查正式版本",control:ActionButton("检查更新…") {UpdateWindow.show()}),
            row("公开仓库",control:ActionButton("GitHub 发布页") {
                if !NSWorkspace.shared.open(UpdateChecker.releases) {showError("无法打开发布页",PetFailure(message:UpdateChecker.releases.absoluteString))}
            })])
        group("自动检查",[toggle("启动时检查更新","automaticallyCheckUpdates",detail:"发现新版时提醒，检查失败仅记录在本页。")])
        let status = note(UpdateChecker.shared.recordText), time = label(UpdateChecker.shared.lastCheckText)
        updateStatusLabel = status; updateTimeLabel = time
        group("检查记录",[row("上次检查时间",control:time),status])
        group("安装",[note("从 GitHub 下载新版，退出桌宠后替换 App。设置和聊天记录保留。")])
    }
    private func advanced() {
        group("设置文件",[row("导出设置",detail:"只包含本页设置，不含会话、凭证或模型配置。",control:ActionButton("导出…") { [weak self] in self?.exportSettings() }),row("导入设置",detail:"导入前检查全部字段；登录启动项不随设置文件改变。",control:ActionButton("导入…") { [weak self] in self?.importSettings() })])
        let data = label("正在统计…"), work = label("正在统计…"), cache = label("正在统计…")
        let total = label("正在统计本应用磁盘存储…")
        total.font = .systemFont(ofSize:11); total.textColor = .secondaryLabelColor
        total.identifier = .init("settings-explanation")
        let dataButton = SettingsFooterButton(title:"清空数据…",target:self,action:#selector(clearLocalData))
        let cacheButton = SettingsFooterButton(title:"清空缓存…",target:self,action:#selector(clearLocalCache))
        for button in [dataButton,cacheButton] {button.bezelStyle = .rounded; button.hasDestructiveAction = true}
        group("本机存储",[total,
            row("本机数据",detail:"聊天记录、同步副本和应用设置",control:data),
            row("默认任务文件夹",detail:"任务创建的文件，清空数据时保留。",control:work),
            row("磁盘缓存",detail:"不含动画帧缓冲的运行内存 (RAM)。",control:cache),
            row("清空本机数据",control:dataButton),row("清空磁盘缓存",control:cacheButton),
            row("数据目录",detail:Paths.data.path,control:ActionButton("在访达中显示") {if !NSWorkspace.shared.open(Paths.data) {showError("无法打开数据目录",PetFailure(message:Paths.data.path))}})],
            action:ActionButton("刷新") { [weak self] in self?.render() })
        storageGeneration += 1; let generation = storageGeneration
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let result = Result {try LocalStorage.usage()}
            DispatchQueue.main.async {
                guard let self, self.storageGeneration == generation, self.selected == .advanced else {return}
                switch result {
                case .success(let usage):
                    total.stringValue = "合计 "+ByteCountFormatter.string(fromByteCount:usage.total,countStyle:.file)+" · 以下占比以三项合计为基准"
                    data.stringValue = usage.description(usage.data); work.stringValue = usage.description(usage.workspace); cache.stringValue = usage.description(usage.cache)
                case .failure(let error):
                    total.stringValue = "统计失败："+error.localizedDescription
                    for field in [data,work,cache] {field.stringValue = "未获取"}
                }
            }
        }
    }
    @objc private func clearLocalData() {
        confirmStorage(title:"清空本机数据？",body:"删除桌宠的聊天记录和 Codex 同步副本，并恢复应用设置。默认任务文件夹、其他工作目录、Codex 原始记录和登录信息保留。",button:"清空数据") { [weak self] in
            guard let action = self?.onClearLocalData else {throw PetFailure(message:"数据管理尚未就绪。")}
            try action()
        }
    }
    @objc private func clearLocalCache() {
        confirmStorage(title:"清空磁盘缓存？",body:"删除本应用的磁盘缓存；后续使用时重新生成。聊天记录、设置和动画素材保留。",button:"清空缓存") {try LocalStorage.clearCache()}
    }
    private func confirmStorage(title:String,body:String,button:String,action:@escaping () throws -> Void) {
        window.makeFirstResponder(nil)
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = body
        alert.addButton(withTitle:"取消"); alert.addButton(withTitle:button).hasDestructiveAction = true
        alert.beginDangerousSheet(for:window) { [weak self] response in
            guard response == .alertSecondButtonReturn else {return}
            do {try action(); self?.render()} catch {showError("清理未完成",error)}
        }
    }
    @objc private func restorePage() {window.makeFirstResponder(nil); preferences.reset(selected.keys); render(); if selected == .appearance {showMaterialPreview()} else if selected == .identity {onMessagePreview(.preview)}}
    @objc private func restoreAll() {
        window.makeFirstResponder(nil); dismissMaterialPreview()
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "恢复全部设置为默认值？"
        alert.informativeText = "全部应用设置将恢复默认。聊天记录、动画素材和系统登录启动项保持不变。"
        alert.addButton(withTitle:"取消")
        let confirm = alert.addButton(withTitle:"恢复全部设置")
        confirm.hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = "\u{1b}"; confirm.keyEquivalent = ""
        alert.beginDangerousSheet(for:window) { [weak self] response in guard response == .alertSecondButtonReturn, let self else {return}; self.preferences.reset(Array(PetPreferences.defaults.keys)); self.render() }
    }
    private func exportSettings() {
        window.makeFirstResponder(nil)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = PetPreferences.productName+"设置.json"
        panel.beginSheetModal(for:window) { [weak self] response in guard response == .OK, let url = panel.url, let self else {return}; do {try self.preferences.exportData().write(to:url,options:.atomic)} catch {showError("导出设置失败",error)} }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else {return}
            do {try self.preferences.importData(Data(contentsOf:url),clipIDs:Set(self.catalog?.all.map(\.id) ?? [])); self.render()}
            catch {showError("导入设置失败",error)}
        }
    }
}
