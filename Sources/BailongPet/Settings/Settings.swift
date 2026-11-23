import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsPanel: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate {
    let window = SettingsWindow(contentRect:NSRect(x:0,y:0,width:1040,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    let preferences: PetPreferences
    let catalog: Catalog?
    private lazy var form:SettingsForm = {
        let form = SettingsForm(content:content,preferences:preferences,window:window)
        form.historyRecoveryReason = { [weak self] in self?.historyRecoveryReason() }
        return form
    }()
    private lazy var appearancePage = AppearanceSettingsPage(form:form,window:window,
        onPreviewDetails:{ [weak self] in self?.onPreviewDetails() })
    private lazy var activityPage = ActivitySettingsPage(form:form,catalog:catalog,
        onPreview:{ [weak self] clip in self?.onPreview(clip) })
    private let aboutPage = AboutPageController()
    private lazy var workspacePage = WorkspaceSettingsPage(form:form,window:window,reload:{ [weak self] in self?.render() },clear:{ [weak self] completion in
        guard let action = self?.onClearDefaultWorkspace else {completion(.failure(PetFailure(message:L10n.text(.settings,"settingsWindow.settingsPanel.message")))); return}
        action(completion)
    })
    private let splitController = NSSplitViewController()
    private let sidebar = NSTableView(), scroll = NSScrollView(), content = NSStackView()
    private let resetButton = SettingsFooterButton(title:L10n.text(.settings,"settingsWindow.resetButton"),target:nil,action:nil)
    private weak var updateStatusLabel: NSTextField?
    private weak var updateTimeLabel: NSTextField?
    private weak var displayMenu: NSPopUpButton?
    private let searchField = NSSearchField()
    private var searchItem:NSSearchToolbarItem?
    private let searchResults = SettingsSearchResults()
    private lazy var searchIndex = SettingsSearchEntry.all(catalog:catalog)
    private var searchHighlight:SettingsSearchHighlight?
    private var identityViewport:SettingsRowViewport?
    private var selected: SettingsSection = .general
    private var detailPage:SettingsDetail?
    private var itemList:SettingsItemList?
    private var listPositions = [SettingsSection:SettingsItemList.Position]()
    private var renderedSection: SettingsSection?
    private var selectingSidebar = false
    private var hasShown = false
    private var hasSavedFrame = false
    var onClose: () -> Void = {}
    var onPreview: (Clip) -> Void = { _ in }
    var onLinePreview: (Clip,String) -> Void = { _,_ in }
    var onMessagePreview: (MessagePurpose) -> Void = { _ in }
    var onPreviewDetails: () -> Void = {}
    var onClearLocalData: (() throws -> Void)?
    var onClearDefaultWorkspace: ((@escaping (Result<Void,Error>) -> Void) -> Void)?
    var historyRecoveryReason:() -> String? = {nil}
    var onReloadHistory:(() throws -> Void)?
    var onExportHistory:((URL) throws -> Void)?
    var historyExportExtension:() -> String = {"json"}
    private var storageGeneration = 0
    init(preferences: PetPreferences = .shared, catalog: Catalog? = nil) {
        self.preferences = preferences; self.catalog = catalog
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(startupRegistrationChanged),name:FollowLauncher.didChange,object:nil)
        window.title = L10n.text(.settings,"settingsWindow.title"); window.isReleasedWhenClosed = false; window.delegate = self
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenNone)
        window.minSize = NSSize(width:800,height:540)
        if let screen = NSScreen.main {window.setContentSize(NSSize(width:min(1040,screen.visibleFrame.width-80),height:min(900,screen.visibleFrame.height-80)))}
        window.focusSearch = { [weak self] in
            guard let self else {return}
            self.searchItem?.beginSearchInteraction(); self.window.makeFirstResponder(self.searchField)
        }
        searchResults.onOpen = { [weak self] in self?.revealSetting($0) }
        searchResults.onCancel = { [weak self] in self?.clearSearch(); self?.window.makeFirstResponder(self?.searchField) }
        let side = NSVisualEffectView(); side.material = .sidebar; side.blendingMode = .behindWindow
        side.state = .followsWindowActiveState
        let sideScroll = NSScrollView(); sideScroll.drawsBackground = false; sideScroll.hasVerticalScroller = true; sideScroll.autohidesScrollers = true
        sideScroll.verticalScrollElasticity = .allowed
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section")); sidebar.addTableColumn(column)
        sidebar.headerView = nil; sidebar.style = .plain; sidebar.rowHeight = 32; sidebar.backgroundColor = .clear
        sidebar.selectionHighlightStyle = .none; sidebar.intercellSpacing = .zero
        sidebar.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; sidebar.autoresizingMask = [.width]
        column.minWidth = 0; column.resizingMask = .autoresizingMask
        sideScroll.hasHorizontalScroller = false; sideScroll.horizontalScrollElasticity = .none
        sidebar.dataSource = self; sidebar.delegate = self; sidebar.allowsEmptySelection = false
        sidebar.setAccessibilityLabel(L10n.text(.settings,"settingsWindow.text")); sideScroll.documentView = sidebar
        side.addSubview(sideScroll)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .allowed
        let detail = NSView(), document = TopDownView(); scroll.documentView = document; detail.addSubview(scroll)
        let aboutView = aboutPage.view; aboutView.isHidden = true; aboutView.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(aboutView)
        searchResults.isHidden = true; searchResults.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(searchResults)
        NSLayoutConstraint.activate([
            searchResults.topAnchor.constraint(equalTo:detail.safeAreaLayoutGuide.topAnchor),searchResults.bottomAnchor.constraint(equalTo:detail.bottomAnchor),
            searchResults.leadingAnchor.constraint(equalTo:detail.leadingAnchor),searchResults.trailingAnchor.constraint(equalTo:detail.trailingAnchor)
        ])
        NSLayoutConstraint.activate([
            aboutView.topAnchor.constraint(equalTo:detail.safeAreaLayoutGuide.topAnchor),aboutView.bottomAnchor.constraint(equalTo:detail.bottomAnchor),
            aboutView.centerXAnchor.constraint(equalTo:detail.centerXAnchor),aboutView.widthAnchor.constraint(lessThanOrEqualToConstant:708),
            aboutView.leadingAnchor.constraint(greaterThanOrEqualTo:detail.leadingAnchor),aboutView.trailingAnchor.constraint(lessThanOrEqualTo:detail.trailingAnchor)
        ])
        let aboutWidth = aboutView.widthAnchor.constraint(equalTo:detail.widthAnchor); aboutWidth.priority = .defaultHigh; aboutWidth.isActive = true
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 24
        document.addSubview(content)
        resetButton.target = self; resetButton.action = #selector(restorePage); resetButton.focusRingType = .exterior
        let resetAll = SettingsFooterButton(title:L10n.text(.settings,"settingsWindow.resetAll"),target:self,action:#selector(restoreAll))
        resetAll.bezelStyle = .rounded; resetAll.hasDestructiveAction = true
        resetAll.focusRingType = .exterior
        let closeButton = SettingsFooterButton(title:L10n.text(.settings,"settingsWindow.closeButton"),target:window,action:#selector(NSWindow.performClose(_:)))
        closeButton.focusRingType = .exterior
        closeButton.setAccessibilityLabel(L10n.text(.settings,"settingsWindow.text.2"))
        let footerLine = NSBox(); footerLine.boxType = .separator
        let sidebarFooter = NSStackView(views:[footerLine,resetButton,resetAll,closeButton])
        sidebarFooter.orientation = .vertical; sidebarFooter.spacing = 8; sidebarFooter.alignment = .leading
        for button in [resetButton as NSButton,resetAll,closeButton] {
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
            content.centerXAnchor.constraint(equalTo:document.centerXAnchor),content.widthAnchor.constraint(lessThanOrEqualToConstant:780),preferredWidth,
            content.leadingAnchor.constraint(greaterThanOrEqualTo:document.leadingAnchor,constant:24),content.trailingAnchor.constraint(lessThanOrEqualTo:document.trailingAnchor,constant:-24),
            content.topAnchor.constraint(equalTo:document.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-24)
        ])
        splitController.splitView.setPosition(200,ofDividerAt:0)
        selectingSidebar = true
        sidebar.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        selectingSidebar = false
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAccent),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshUpdateStatus),name:UpdateChecker.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshDiagnosticsSwitch(_:)),name:PetPreferences.didChange,object:preferences)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshDisplays),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        window.center()
        hasSavedFrame = window.restoreSavedFrame(named:"BailongSettingsWindow")
    }
    @objc private func refreshDiagnosticsSwitch(_ note:Notification) {
        guard renderedSection != nil else {return}
        form.refreshAvailability()
        if !window.isVisible && !window.isMiniaturized,
           let keys = note.userInfo?["keys"] as? [String],
           let rendered = renderedSection,
           !Set(keys).isDisjoint(with:rendered.keys) {
            renderedSection = nil
        }
    }
    func show(section: SettingsSection? = nil,groupTitle:String? = nil) {
        preferences.refreshDesktopVersion()
        if let section {
            select(section)
        } else if renderedSection != selected {
            render()
        }
        if !hasShown {
            if !hasSavedFrame {window.zoom(nil)}
            hasShown = true
        }
        InterfaceWindows.shared.focus(window)
        if let groupTitle,let target = form.searchAnchors[groupTitle] {
            scrollToSetting(target,atTop:true)
            NSAccessibility.post(element:target,notification:.layoutChanged)
        }
    }
    func select(_ section:SettingsSection,detail:SettingsDetail? = nil) {
        guard let index = SettingsSection.allCases.firstIndex(of:section) else {return}
        let changed = renderedSection != section || detailPage != detail
        if changed,!window.makeFirstResponder(nil) {return}
        clearSearch()
        selected = section; detailPage = detail
        selectingSidebar = true
        sidebar.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
        selectingSidebar = false
        if changed {render()}
    }
    func numberOfRows(in tableView: NSTableView) -> Int {SettingsSection.allCases.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {AccentHistoryRow()}
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = SettingsSection.allCases[row]
        let cell = HistoryConversationCell(title:section.title,symbol:section.symbol)
        cell.hoverHelp = nil
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selectingSidebar,SettingsSection.allCases.indices.contains(sidebar.selectedRow) else {return}
        let next = SettingsSection.allCases[sidebar.selectedRow]
        window.makeFirstResponder(nil); clearSearch()
        guard next != selected || renderedSection != next else {return}
        selected = next; detailPage = nil; render()
    }
    func windowWillClose(_ notification: Notification) {
        window.makeFirstResponder(nil)
        searchHighlight?.removeFromSuperview(); searchHighlight = nil
        appearancePage.dismissPreview()
        appearancePage.reset()
        activityPage.reset()
        identityViewport = nil
        releaseItemList(); detailPage = nil
        form.reset(section:selected)
        renderedSection = nil
        NSApp.removeWindowsItem(window)
        onClose()
    }
    func windowWillReturnFieldEditor(_ sender:NSWindow,to client:Any?) -> Any? {form.fieldEditor(for:client)}
    func controlTextDidChange(_ notification:Notification) {
        guard notification.object as? NSTextField === searchField else {return}
        searchSettings()
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {[.init("settings-sidebar"),.init("settings-divider"),.flexibleSpace,.init("settings-search")]}
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {toolbarAllowedItemIdentifiers(toolbar)}
    func toolbar(_ toolbar: NSToolbar,itemForItemIdentifier id: NSToolbarItem.Identifier,willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "settings-search" {
            let item = NSSearchToolbarItem(itemIdentifier:id)
            searchField.placeholderString = L10n.text(.settings,"settingsWindow.toolbar.text"); searchField.setAccessibilityLabel(L10n.text(.settings,"settingsWindow.toolbar.text.2"))
            searchField.sendsSearchStringImmediately = true; searchField.delegate = self
            searchField.target = self; searchField.action = #selector(searchSettings)
            item.searchField = searchField; item.label = L10n.text(.settings,"settingsWindow.toolbar.text"); item.preferredWidthForSearchField = 240
            searchItem = item
            return item
        }
        if id.rawValue == "settings-divider" {return NSTrackingSeparatorToolbarItem(identifier:id,splitView:splitController.splitView,dividerIndex:0)}
        guard id.rawValue == "settings-sidebar" else {return nil}
        let item = NSToolbarItem(itemIdentifier:id); item.label = L10n.text(.settings,"settingsWindow.toolbar.label")
        item.image = NSImage(systemSymbolName:"sidebar.left",accessibilityDescription:item.label)
        item.target = splitController; item.action = #selector(NSSplitViewController.toggleSidebar(_:)); item.isBordered = true; item.installHoverHelp()
        return item
    }
    @objc private func searchSettings() {
        if let editor = searchField.currentEditor() as? NSTextView,editor.hasMarkedText() {return}
        searchResults.show(SettingsSearchEntry.matching(searchField.stringValue,in:searchIndex))
        updateSearchPresentation()
    }
    private func updateSearchPresentation() {
        let searching = !searchField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        searchResults.isHidden = !searching
        scroll.isHidden = searching || selected == .about || itemList != nil
        if !scroll.isHidden {
            activityPage.viewport?.schedule()
            identityViewport?.schedule()
        }
        itemList?.isHidden = searching
        aboutPage.view.isHidden = searching || selected != .about
        resetButton.isEnabled = !searching && !selected.keys.isEmpty
        window.title = searching ? L10n.text(.settings,"settingsWindow.toolbar.text") : detailPage?.title ?? selected.title
    }
    private func clearSearch() {
        searchField.stringValue = ""; searchResults.show([]); updateSearchPresentation()
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        guard control === searchField,!textView.hasMarkedText(),!searchField.stringValue.isEmpty else {return false}
        switch selector {
        case #selector(NSResponder.moveDown(_:)): searchResults.focus(); return true
        case #selector(NSResponder.insertNewline(_:)): searchResults.openSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)): clearSearch(); return true
        default: return false
        }
    }
    private func revealSetting(_ entry:SettingsSearchEntry) {
        let entry = entry.section == .messages ? MessageSettingsPage.prerequisite(for:entry,preferences:preferences) ?? entry : entry
        window.makeFirstResponder(nil); select(entry.section,detail:entry.detail)
        if entry.itemID == nil,entry.title == entry.detail?.title {return}
        if let itemList {
            if let id = entry.itemID {itemList.reveal(group:entry.group,id:id)}
            else if entry.detail == .lines && entry.title == IdentitySettingsPage.editWorkingLineTitle {
                let line = IdentitySettingsPage.workingLineEditTarget(preferences)
                itemList.reveal(group:line.group,id:line.key)
            }
            return
        }
        if entry.section == .about {
            if let tab = entry.aboutTab {aboutPage.selectTab(tab)}
            return
        }
        guard var target = form.searchAnchors[entry.anchor] ?? form.searchAnchors[entry.group] else {return}
        if target.isHiddenOrHasHiddenAncestor,let group = form.searchAnchors[entry.group] {target = group}
        scrollToSetting(target)
        (target as? any SettingsViewportRow)?.loadControls()
        if let button = target as? SettingsValueButton,button.isEnabled {button.showEditor(focusing:entry.title)}
        let highlight = SettingsSearchHighlight(frame:target.bounds)
        highlight.autoresizingMask = [.width,.height]
        target.addSubview(highlight,positioned:.below,relativeTo:nil); searchHighlight = highlight
        NSAccessibility.post(element:target,notification:.layoutChanged)
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak highlight] in highlight?.removeFromSuperview() }
    }
    private func scrollToSetting(_ target:NSView,atTop:Bool = false) {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let document = scroll.documentView else {return}
        let rect = target.convert(target.bounds,to:document)
        let viewportHeight = scroll.contentView.bounds.height
        let offset = atTop ? rect.minY-12 : rect.midY-viewportHeight/2
        let y = max(0,min(offset,document.bounds.height-viewportHeight))
        scroll.contentView.scroll(to:NSPoint(x:0,y:y)); scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func refreshAccent() {
        func update(_ view: NSView) {
            if let slider = view as? NSSlider {slider.trackFillColor = AppAccent.color}
            if let well = view as? NSColorWell {well.color = AppAccent.color}
            if let menu = view as? NSPopUpButton, menu.identifier?.rawValue == "accentStyle" {menu.selectItem(at:AppAccent.choices.firstIndex {$0.0 == preferences.string("accentStyle")} ?? 0)}
            for child in view.subviews {update(child)}
        }
        if let root = window.contentView {update(root)}
        appearancePage.refreshAccent()
        sidebar.enumerateAvailableRowViews { [weak self] row,index in
            row.needsDisplay = true
            let cell = self?.sidebar.view(atColumn:0,row:index,makeIfNecessary:false) as? NSTableCellView
            cell?.backgroundStyle = row.interiorBackgroundStyle
        }
    }
    @objc private func startupRegistrationChanged() {
        if selected == .general && window.isVisible {render()}
    }
    private func render() {
        guard window.contentView != nil else {return}
        releaseItemList()
        renderedSection = selected
        searchHighlight?.removeFromSuperview(); searchHighlight = nil
        appearancePage.reset()
        activityPage.reset()
        identityViewport = nil
        form.reset(section:selected)
        window.title = selected.title
        resetButton.isEnabled = !selected.keys.isEmpty
        scroll.isHidden = selected == .about; aboutPage.view.isHidden = selected != .about
        switch selected {
        case .general: general()
        case .identity where detailPage == .lines:showItemList(IdentitySettingsPage.items(catalog:catalog))
        case .activity where detailPage == .actions:showItemList(ActivitySettingsPage.items(catalog:catalog))
        case .identity:
            identityViewport = IdentitySettingsPage.render(form:form,catalog:catalog,window:window,onLinePreview:onLinePreview,
                play:{ [weak self] in self?.previewItem($0) },reload:{ [weak self] in self?.render() })
        case .activity:activityPage.render()
        case .messages:
            let topic:MessageSettingsPage.Topic?
            if case .messages(let current) = detailPage {
                topic = current
                content.addArrangedSubview(form.backButton(selected.title) { [weak self] in self?.select(.messages) })
            } else {topic = nil}
            MessageSettingsPage.render(form:form,topic:topic,onPreview:onMessagePreview)
        case .appearance: appearancePage.render()
        case .advanced: advanced()
        case .updates: updates()
        case .about: break
        case .developer:
            form.group(L10n.text(.settings,"search.add.text.48"), [form.choice(L10n.text(.settings,"search.add.text.86"), "animationQuality", [("auto", L10n.text(.settings,"settingsWindow.animationQuality.option.auto")), ("720", L10n.text(.settings,"settingsWindow.animationQuality.title.2")), ("512", L10n.text(.settings,"settingsWindow.animationQuality.title.3")), ("384", L10n.text(.settings,"settingsWindow.animationQuality.title.4")), ("256", L10n.text(.settings,"settingsWindow.animationQuality.title.5"))],width:250),
                form.choice(L10n.text(.settings,"search.add.text.87"), "animationFPSLimit", [("full", L10n.text(.settings,"settingsWindow.animationFPSLimit.option.full")), ("20", "20 FPS"), ("15", "15 FPS")]),
                form.toggle(L10n.text(.settings,"search.add.text.90"), "preloadWholeAnimation", detail: L10n.text(.settings,"settingsWindow.preloadWholeAnimation.detail")),
                form.bufferFrames(),
                form.toggle(L10n.text(.settings,"search.add.text.89"), "animationOpeningCache", detail: L10n.text(.settings,"settingsWindow.animationOpeningCache.detail"), unless:["preloadWholeAnimation"])],symbol:"film")
            form.group(L10n.text(.settings,"search.add.text.92"), [
                form.toggle(L10n.text(.settings,"search.add.text.93"), "bubbleMotion", detail:L10n.text(.settings,"settingsWindow.bubbleMotion.detail")),
                form.toggle(L10n.text(.settings,"search.add.text.95"), "animationSmoothTransition", detail:L10n.text(.settings,"settingsWindow.animationSmoothTransition.detail"), requires:["bubbleMotion"]),
                form.toggle(L10n.text(.settings,"search.add.text.96"), "animationEdgeCleanup", detail:L10n.text(.settings,"settingsWindow.animationEdgeCleanup.detail")),
                form.toggle(L10n.text(.settings,"search.add.text.98"), "petShadow")],symbol:"sparkles")
            let quotaRows = [form.toggle(L10n.text(.settings,"search.add.text.101"), "quotaCacheEnabled", detail:L10n.text(.settings,"settingsWindow.quotaCacheEnabled.detail")),
                form.conditional(form.slider(L10n.text(.settings,"search.add.text.102"), "quotaCacheSeconds", range:PetPreferences.ranges["quotaCacheSeconds"]!, suffix:L10n.text(.settings,"activity.leisureInterval.suffix")),when:{$0.bool("quotaCacheEnabled")})]
            form.group(L10n.text(.settings,"search.add.text.100"),quotaRows,symbol:AppIcons.quotaSymbol)
            form.group(L10n.text(.settings,"search.add.text.104"), [form.toggle(L10n.text(.settings,"search.add.text.105"), "showDiagnostics")],symbol:"chart.xyaxis.line")
        }
        scroll.contentView.scroll(to:.zero)
        updateSearchPresentation()
    }
    private func releaseItemList() {
        guard let itemList else {return}
        listPositions[itemList.section] = itemList.position
        itemList.removeFromSuperview(); self.itemList = nil
    }
    private func previewItem(_ item:SettingsListItem) {
        guard let clip = item.preview else {return}
        if case .template(let key,_) = item.kind {onLinePreview(clip,preferences.statusLine(key))}
        else {onPreview(clip)}
    }
    private func showItemList(_ items:[SettingsListItem]) {
        guard let host = scroll.superview else {return}
        let section = selected
        let list = SettingsItemList(items:items,section:section,window:window,preferences:preferences,
            back:{ [weak self] in self?.select(section) },
            play:{ [weak self] in self?.previewItem($0) })
        itemList = list
        host.addSubview(list,positioned:.below,relativeTo:searchResults); list.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([list.topAnchor.constraint(equalTo:host.safeAreaLayoutGuide.topAnchor),list.bottomAnchor.constraint(equalTo:host.bottomAnchor),
            list.leadingAnchor.constraint(equalTo:host.leadingAnchor),list.trailingAnchor.constraint(equalTo:host.trailingAnchor)])
        host.layoutSubtreeIfNeeded()
        list.restore(listPositions[section])
    }
    private func general() {
        if let notice = preferences.compatibilityNotice ?? SettingsStorage.compatibilityNotice {
            form.group(L10n.text(.settings,"settingsWindow.general.text"),[form.row(L10n.text(.settings,"settingsWindow.general.text.2"),control:ActionButton(L10n.text(.settings,"settingsWindow.general.button")) { [weak self] in self?.exportCompatibilitySettings() })],symbol:"gearshape.2",detail:notice)
        }
        let login = SMAppService.mainApp.status
        let loginText = LoginLauncher.statusText
        form.group(L10n.text(.settings,"search.add.text"),[
            form.row(L10n.text(.settings,"search.add.text.2"),detail:loginText,control:ActionButton(login == .enabled ? L10n.text(.settings,"settingsWindow.general.button.2") : login == .requiresApproval ? L10n.text(.settings,"settingsWindow.general.button.3") : L10n.text(.settings,"settingsWindow.general.button.4")) { [weak self] in self?.configureLogin() }),
            form.row(L10n.text(.settings,"autostart.configure.messageText"),detail:FollowLauncher.statusText,control:ActionButton(L10n.text(.settings,"settingsWindow.general.button.5")) { [weak self] in FollowLauncher.configure(); self?.render() }),
            form.toggle(L10n.text(.settings,"search.add.text.4"),"rememberPosition")],symbol:"power")
        form.group(L10n.text(.settings,"search.add.text.6"),[
            form.row(L10n.text(.settings,"search.add.text.7"),detail:L10n.text(.settings,"settingsWindow.general.text.8"),control:FinderPermissionControl(frame:.zero)),
            form.row(L10n.text(.settings,"search.add.text.9"),detail:L10n.text(.settings,"settingsWindow.general.text.10"),control:ActionButton(L10n.text(.settings,"settingsWindow.general.button.6")) {SystemPermissionSettings.open("Privacy_FilesAndFolders")}),
            form.row(L10n.text(.settings,"search.add.text.11"),detail:L10n.text(.settings,"settingsWindow.general.text.12"),control:ActionButton(L10n.text(.settings,"settingsWindow.general.button.3")) {SMAppService.openSystemSettingsLoginItems()})],symbol:"lock.shield")
        let menu = AccentPopUpButton(); displayMenu = menu
        menu.identifier = .init("preferredDisplay"); menu.setAccessibilityLabel(L10n.text(.settings,"search.add.text.16"))
        menu.widthAnchor.constraint(equalToConstant:190).isActive = true
        form.attach(menu) { [weak self] sender in
            guard let value = (sender as? NSPopUpButton)?.selectedItem?.representedObject as? String else {return}
            self?.preferences.set(value,for:"preferredDisplay")
        }
        refreshDisplays()
        form.group(L10n.text(.settings,"search.add.text.13"),[form.toggle(L10n.text(.settings,"search.add.text.14"),"autoFullscreen"),
            form.row(L10n.text(.settings,"search.add.text.16"),detail:L10n.text(.settings,"settingsWindow.general.text.15"),control:menu)],symbol:"display")
        form.group(BrowserSearchEngine.group,[form.choice(BrowserSearchEngine.settingTitle,BrowserSearchEngine.key,BrowserSearchEngine.options,
            detail:L10n.text(.settings,"settingsWindow.general.text.16"))],symbol:"magnifyingglass")
        let version = form.note("")
        form.observeValues { [weak version] preferences in
            version?.stringValue = preferences.projectChannelHint
        }
        form.group(ProjectSendChannel.group,[form.segmented(ProjectSendChannel.settingTitle,ProjectSendChannel.key,ProjectSendChannel.options,
            help:ProjectSendChannel.help,footer:version)],symbol:"bubble.left.and.bubble.right")
    }
    @objc private func refreshDisplays() {
        guard selected == .general,let menu = displayMenu else {return}
        let saved = preferences.string("preferredDisplay")
        var displays = [("",L10n.text(.settings,"settingsWindow.displays"))] + NSScreen.screens.map {(PetPreferences.displayID($0),$0.localizedName)}
        if !displays.contains(where:{$0.0 == saved}) {displays.append((saved,L10n.text(.settings,"settingsWindow.refreshDisplays.text")))}
        menu.removeAllItems()
        for (id,title) in displays {
            let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
            item.representedObject = id; menu.menu?.addItem(item)
        }
        menu.selectItem(at:displays.firstIndex {$0.0 == saved} ?? 0)
    }
    private func configureLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {showError(L10n.text(.settings,"settingsWindow.configureLogin.error"),PetFailure(message:L10n.text(.settings,"settingsWindow.configureLogin.message"))); return}
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try LoginLauncher.setEnabled(false)
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try LoginLauncher.setEnabled(true)
            }
            render()
        } catch {showError(L10n.text(.settings,"settingsWindow.configureLogin.error.2"),error)}
    }
    @objc private func refreshUpdateStatus() {
        updateStatusLabel?.stringValue = UpdateChecker.shared.recordText
        updateTimeLabel?.stringValue = UpdateChecker.shared.lastCheckText
    }
    private func updates() {
        let checkUpdate = ActionButton(L10n.text(.settings,"settingsWindow.checkUpdate")) {UpdateWindow.show()}; checkUpdate.emphasize()
        form.group(L10n.text(.settings,"search.add.text.107"),[form.row(L10n.text(.settings,"search.add.text.108"),control:label(Paths.version)),
            form.row(L10n.text(.settings,"search.add.text.109"),control:checkUpdate),
            form.row(L10n.text(.settings,"search.add.text.110"),control:ActionButton(L10n.text(.settings,"settingsWindow.updates.button")) {
                if !NSWorkspace.shared.open(UpdateChecker.releases) {showError(L10n.text(.settings,"settingsWindow.updates.error"),PetFailure(message:UpdateChecker.releases.absoluteString))}
            })],symbol:"info.circle")
        form.group(L10n.text(.settings,"search.add.text.112"),[form.toggle(L10n.text(.settings,"search.add.text.113"),"automaticallyCheckUpdates",detail:L10n.text(.settings,"settingsWindow.automaticallyCheckUpdates.detail"))],symbol:"arrow.triangle.2.circlepath")
        let status = form.note(UpdateChecker.shared.recordText), time = label(UpdateChecker.shared.lastCheckText)
        updateStatusLabel = status; updateTimeLabel = time
        form.group(L10n.text(.settings,"search.add.text.115"),[form.row(L10n.text(.settings,"search.add.text.116"),control:time),status],symbol:"clock.arrow.circlepath")
    }
    private func advanced() {
        workspacePage.render()
        if let reason = historyRecoveryReason() {
            form.group(L10n.text(.settings,"settingsWindow.advanced.text"),[
                form.row(L10n.text(.settings,"settingsWindow.advanced.text.2"),control:ActionButton(L10n.text(.settings,"settingsWindow.general.button")) { [weak self] in self?.exportOriginalHistory() }),
                form.row(L10n.text(.settings,"settingsWindow.advanced.text.3"),control:ActionButton(L10n.text(.settings,"settingsWindow.advanced.button")) { [weak self] in
                    guard let self else {return}
                    do {try self.onReloadHistory?(); self.render()} catch {showError(L10n.text(.settings,"settingsWindow.advanced.error"),error)}
                })],symbol:"arrow.counterclockwise",detail:reason)
        }
        form.group(L10n.text(.settings,"search.add.text.69"),[form.row(L10n.text(.settings,"search.add.text.70"),detail:L10n.text(.settings,"settingsWindow.advanced.text.6"),control:ActionButton(L10n.text(.settings,"settingsWindow.general.button")) { [weak self] in self?.exportSettings() }),form.row(L10n.text(.settings,"search.add.text.71"),detail:L10n.text(.settings,"settingsWindow.advanced.button.3"),control:ActionButton(L10n.text(.settings,"settingsWindow.advanced.button.4")) { [weak self] in self?.importSettings() })],symbol:"doc.badge.gearshape")
        let data = label(L10n.text(.settings,"settingsWindow.data")), work = label(L10n.text(.settings,"settingsWindow.data")), cache = label(L10n.text(.settings,"settingsWindow.data"))
        let total = label(L10n.text(.settings,"settingsWindow.total"))
        total.font = .systemFont(ofSize:11); total.textColor = .secondaryLabelColor
        total.identifier = .init("settings-explanation")
        let dataButton = SettingsFooterButton(title:L10n.text(.settings,"settingsWindow.dataButton"),target:self,action:#selector(clearLocalData))
        let cacheButton = SettingsFooterButton(title:L10n.text(.settings,"settingsWindow.cacheButton"),target:self,action:#selector(clearLocalCache))
        for button in [dataButton,cacheButton] {button.bezelStyle = .rounded; button.hasDestructiveAction = true}
        form.group(L10n.text(.settings,"search.add.text.78"),[total,
            form.row(L10n.text(.settings,"search.add.text.79"),detail:L10n.text(.settings,"settingsWindow.advanced.text.9"),control:data),
            form.row(L10n.text(.settings,"search.add.text.80"),control:work),
            form.row(L10n.text(.settings,"search.add.text.81"),control:cache),
            form.row(L10n.text(.settings,"search.add.text.82"),control:dataButton),form.row(L10n.text(.settings,"search.add.text.83"),control:cacheButton),
            form.row(L10n.text(.settings,"search.add.text.84"),detail:Paths.data.path,control:ActionButton(L10n.text(.settings,"settingsWindow.advanced.button.5")) {if !NSWorkspace.shared.open(Paths.data) {showError(L10n.text(.settings,"settingsWindow.advanced.button.6"),PetFailure(message:Paths.data.path))}})],
            symbol:"internaldrive",action:ActionButton(L10n.text(.settings,"settingsWindow.advanced.button.7")) { [weak self] in self?.render() })
        storageGeneration += 1; let generation = storageGeneration
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let result = Result {try LocalStorage.usage()}
            DispatchQueue.main.async {
                guard let self, self.storageGeneration == generation, self.selected == .advanced else {return}
                switch result {
                case .success(let usage):
                    total.stringValue = L10n.text(.settings,"settingsWindow.advanced.text.15")+ByteCountFormatter.string(fromByteCount:usage.total,countStyle:.file)+L10n.text(.settings,"settingsWindow.advanced.text.16")
                    data.stringValue = usage.description(usage.data); work.stringValue = usage.description(usage.workspace); cache.stringValue = usage.description(usage.cache)
                case .failure(let error):
                    total.stringValue = L10n.text(.settings,"settingsWindow.advanced.text.17")+error.localizedDescription
                    for field in [data,work,cache] {field.stringValue = L10n.text(.settings,"settingsWindow.advanced.text.18")}
                }
            }
        }
    }
    @objc private func clearLocalData() {
        confirmStorage(title:L10n.text(.settings,"settingsWindow.clearLocalData.title"),body:L10n.text(.settings,"settingsWindow.clearLocalData.text"),button:L10n.text(.settings,"search.add.text.82")) { [weak self] in
            guard let action = self?.onClearLocalData else {throw PetFailure(message:L10n.text(.settings,"settingsWindow.clearLocalData.message"))}
            try action()
        }
    }
    @objc private func clearLocalCache() {
        confirmStorage(title:L10n.text(.settings,"settingsWindow.clearLocalCache.title"),body:L10n.text(.settings,"settingsWindow.clearLocalCache.text"),button:L10n.text(.settings,"settingsWindow.clearLocalCache.text.2")) {try LocalStorage.clearCache()}
    }
    private func confirmStorage(title:String,body:String,button:String,action:@escaping () throws -> Void) {
        window.makeFirstResponder(nil)
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = body
        alert.addButton(withTitle:L10n.text(.settings,"autostart.configure.button")); alert.addButton(withTitle:button).hasDestructiveAction = true
        alert.beginDangerousSheet(for:window) { [weak self] response in
            guard response == .alertSecondButtonReturn else {return}
            do {try action(); self?.render()} catch {showError(L10n.text(.settings,"settingsWindow.confirmStorage.error"),error)}
        }
    }
    @objc private func restorePage() {window.makeFirstResponder(nil); preferences.reset(selected.keys); render(); if selected == .appearance {appearancePage.showPreview()} else if selected == .identity {onMessagePreview(.preview)}}
    @objc private func restoreAll() {
        window.makeFirstResponder(nil); appearancePage.dismissPreview()
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = L10n.text(.settings,"settingsWindow.restoreAll.messageText")
        alert.informativeText = L10n.text(.settings,"settingsWindow.restoreAll.informativeText")
        alert.addButton(withTitle:L10n.text(.settings,"autostart.configure.button"))
        let confirm = alert.addButton(withTitle:L10n.text(.settings,"settingsWindow.confirm"))
        confirm.hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = "\u{1b}"; confirm.keyEquivalent = ""
        alert.beginDangerousSheet(for:window) { [weak self] response in guard response == .alertSecondButtonReturn, let self else {return}; self.preferences.reset(Array(PetPreferences.defaults.keys)); self.render() }
    }
    private func exportCompatibilitySettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "白龙桌宠Swift-配置兼容备份.json"
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard response == .OK,let url = panel.url,let self else {return}
            do {
                var values = [String:Any]()
                let source = SettingsStorage.compatibilityNotice == nil ? self.preferences.defaults : UserDefaults(suiteName:SettingsStorage.domain)!
                for key in Array(PetPreferences.defaults.keys) {if let value = source.object(forKey:key) {values[key] = value}}
                let original = self.preferences.defaults.dictionary(forKey:"compatibilityRecoveredValues") ?? [:]
                values.merge(original) {_,old in old}
                try JSONSerialization.data(withJSONObject:["settings":values,"schemaVersion":source.integer(forKey:SettingsStorage.schemaKey)],options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
            } catch {showError(L10n.text(.settings,"settingsWindow.exportCompatibilitySettings.error"),error)}
        }
    }
    private func exportOriginalHistory() {
        let ext = historyExportExtension()
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension:ext) ?? .data]; panel.nameFieldStringValue = L10n.text(.settings,"settingsWindow.exportOriginalHistory.text")+ext
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard response == .OK,let url = panel.url,let self else {return}
            do {try self.onExportHistory?(url)} catch {showError(L10n.text(.settings,"settingsWindow.exportOriginalHistory.error"),error)}
        }
    }
    private func exportSettings() {
        window.makeFirstResponder(nil)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = PetPreferences.productName+"设置.json"
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in guard response == .OK, let url = panel.url, let self else {return}; do {try self.preferences.exportData().write(to:url,options:.atomic)} catch {showError(L10n.text(.settings,"settingsWindow.exportSettings.error"),error)} }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else {return}
            do {try self.preferences.importData(Data(contentsOf:url),clipIDs:Set(self.catalog?.all.map(\.id) ?? [])); self.render()}
            catch {showError(L10n.text(.settings,"settingsWindow.importSettings.error"),error)}
        }
    }
}
