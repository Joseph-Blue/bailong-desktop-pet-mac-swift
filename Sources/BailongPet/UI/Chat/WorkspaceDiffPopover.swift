import AppKit

enum WorkspaceDiffTarget {
    case git(directory:String,snapshot:GitWorkspaceStatus,entry:GitWorkspaceStatus.Entry)
    case turn(directory:URL?,edits:[FileEditSummary],path:String)

    func open(from anchor:NSView,rect:NSRect) {WorkspaceDiffPopover.show(self,from:anchor,rect:rect)}
}

final class WorkspaceDiffPopover:NSViewController,NSPopoverDelegate,NSTextViewDelegate {
    private struct FileKey:Equatable {let path:String, group:GitWorkspaceStatus.Group?}
    private enum Row {
        case heading(GitWorkspaceStatus.Group), git(GitWorkspaceStatus.Entry), turn(FileEditSummary)
        var key:FileKey? {
            switch self {
            case .heading:return nil
            case .git(let entry):return FileKey(path:entry.path,group:entry.group)
            case .turn(let edit):return FileKey(path:edit.path,group:nil)
            }
        }
    }

    private static var presented:AnchoredPopover?
    private static var prefersSplit = false
    static func show(_ target:WorkspaceDiffTarget,from anchor:NSView,rect:NSRect) {
        guard let window = anchor.window,window.isVisible else {return}
        presented?.close()
        let popover = AnchoredPopover()
        let controller = WorkspaceDiffPopover(nibName:nil,bundle:nil)
        controller.anchor = anchor; controller.sourceWindow = window; controller.popover = popover
        if let available = PanelPresentation.screen(for:window)?.visibleFrame {
            controller.preferredContentSize = NSSize(width:min(820,available.width-48),height:min(430,available.height-48))
        } else {controller.preferredContentSize = NSSize(width:820,height:430)}
        popover.delegate = controller; popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        popover.behavior = .transient; popover.animates = DisclosureMotion.enabled
        _ = controller.view
        controller.present(target)
        presented = popover
        popover.show(relativeTo:rect,of:anchor,preferredEdge:.maxY)
        if popover.isShown {
            controller.dismissal.start(for:popover)
            NotificationCenter.default.addObserver(controller,selector:#selector(sourceClosed),
                name:NSWindow.willCloseNotification,object:window)
        } else {
            controller.releaseSource()
            presented = nil
        }
    }
    private static var visibleController:WorkspaceDiffPopover? {
        guard let presented,presented.isShown else {return nil}
        return presented.contentViewController as? WorkspaceDiffPopover
    }
    static func isShown(in window:NSWindow) -> Bool {visibleController?.sourceWindow === window}
    static func close(in window:NSWindow) {if isShown(in:window) {presented?.close()}}
    static func close(anchoredTo anchor:NSView) {if visibleController?.anchor === anchor {presented?.close()}}
    static func contains(_ point:NSPoint,anchoredTo anchor:NSView) -> Bool {
        guard let controller = visibleController,controller.anchor === anchor else {return false}
        return controller.view.window?.frame.contains(point) == true
    }

    private weak var anchor:NSView?, sourceWindow:NSWindow?, popover:AnchoredPopover?
    private let dismissal = PopoverDismissal()
    private let files = NSPopUpButton()
    private let message = NSTextField(wrappingLabelWithString:""), operations = NSPopUpButton()
    private let scroll = WorkspaceDiffPane(), right = WorkspaceDiffPane()
    private let content = NSView()
    private let counts = NSTextField(labelWithString:"")
    private lazy var previousButton = makeAction("previous",symbol:"chevron.up",action:#selector(previousChange))
    private lazy var nextButton = makeAction("next",symbol:"chevron.down",action:#selector(nextChange))
    private lazy var copyButton = makeAction("copy",symbol:"doc.on.doc",action:#selector(copyPatch))
    private lazy var refreshButton = makeAction("refresh",symbol:"arrow.clockwise",action:#selector(refresh))
    private lazy var layoutMode = NSSegmentedControl(labels:[L10n.text(.workspace,"workspaceDiff.inline"),
        L10n.text(.workspace,"workspaceDiff.sideBySide")],trackingMode:.selectOne,target:self,action:#selector(changeLayout))
    private var splitComparison = WorkspaceDiffPopover.prefersSplit
    private var expandedContext = Set<Int>(), aligningScroll = false
    private var rows = [Row](), selected:FileKey?, operationIndex = 0
    private var gitEntries = [GitWorkspaceStatus.Entry]()
    private var initialHead = false
    private var directory:URL?, terms:GitTerminology = .localized
    private var monitor:GitWorkspaceMonitor?, request:GitWorkspaceRequest?
    private var patch:WorkspaceDiffPatch?, hunks = [NSRange](), activeHunk:Int?

    override func loadView() {
        let view = NSView(), separator = NSBox(); separator.boxType = .separator
        view.frame.size = preferredContentSize
        files.target = self; files.action = #selector(changeFile)
        files.autoenablesItems = false; files.controlSize = .small
        files.font = .systemFont(ofSize:NSFont.systemFontSize(for:.small))
        files.setAccessibilityLabel(L10n.text(.workspace,"workspaceDiff.files"))
        files.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        files.cell?.lineBreakMode = .byTruncatingMiddle
        operations.target = self; operations.action = #selector(changeOperation)
        operations.controlSize = .small
        operations.setAccessibilityLabel(L10n.text(.workspace,"workspaceDiff.operations"))
        operations.setContentCompressionResistancePriority(.required,for:.horizontal)
        let diffActions = NSStackView(views:[previousButton,nextButton,copyButton])
        diffActions.alignment = .centerY; diffActions.spacing = 2
        let header = NSStackView(views:[files,diffActions,counts,NSView(),operations,layoutMode,refreshButton])
        header.alignment = .centerY; header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top:8,left:10,bottom:8,right:10)
        counts.setContentCompressionResistancePriority(.required,for:.horizontal)
        updateActionButtons()
        layoutMode.controlSize = .small
        layoutMode.selectedSegment = splitComparison ? 1 : 0
        layoutMode.setAccessibilityLabel(L10n.text(.workspace,"workspaceDiff.layout"))
        layoutMode.setContentCompressionResistancePriority(.required,for:.horizontal)

        message.textColor = .secondaryLabelColor
        message.alignment = .center; message.isSelectable = true
        let columns = NSStackView(views:[scroll,right]); columns.distribution = .fillEqually; columns.spacing = 1
        for (pane,key) in [(scroll,"workspaceDiff.before"),(right,"workspaceDiff.after")] {
            pane.code.delegate = self
            pane.code.setAccessibilityLabel(L10n.text(.workspace,key))
            NotificationCenter.default.addObserver(self,selector:#selector(scrollBoundsChanged(_:)),
                name:NSView.boundsDidChangeNotification,object:pane.contentView)
        }
        columns.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo:content.topAnchor),columns.bottomAnchor.constraint(equalTo:content.bottomAnchor),
            columns.leadingAnchor.constraint(equalTo:content.leadingAnchor),columns.trailingAnchor.constraint(equalTo:content.trailingAnchor)
        ])
        right.isHidden = true

        for child in [header,separator,content,message] {
            child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo:view.topAnchor),header.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            separator.topAnchor.constraint(equalTo:header.bottomAnchor),separator.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            content.topAnchor.constraint(equalTo:separator.bottomAnchor),content.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo:view.trailingAnchor),content.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            message.centerXAnchor.constraint(equalTo:content.centerXAnchor),message.centerYAnchor.constraint(equalTo:content.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo:content.widthAnchor,constant:-40)
        ])
        self.view = view
    }

    private func present(_ target:WorkspaceDiffTarget) {
        let key:FileKey
        switch target {
        case .git(let path,let snapshot,let entry):
            directory = URL(fileURLWithPath:snapshot.root,isDirectory:true)
            terms = PetPreferences.shared.gitTerminology
            key = FileKey(path:entry.path,group:entry.group)
            setGitRows(snapshot)
            let feed = GitWorkspaceMonitor.directory(path); monitor = feed
            if feed.hasBaseline,feed.failure == nil {setGitRows(feed.repositories.first {$0.root == snapshot.root}?.status)}
            feed.attach(self) { [weak self,weak feed] _,_ in
                guard let self,let feed,self.monitor === feed,!feed.loading else {return}
                self.refreshGit(from:feed)
            }
        case .turn(let directory,let edits,let path):
            self.directory = directory
            key = FileKey(path:path,group:nil)
            rows = edits.map(Row.turn)
        }
        select(key)
    }

    @discardableResult private func setGitRows(_ snapshot:GitWorkspaceStatus?) -> Bool {
        initialHead = snapshot?.initial == true
        let entries = snapshot?.entries ?? []
        guard entries != gitEntries else {return false}
        gitEntries = entries
        rows = GitWorkspaceStatus.Group.allCases.flatMap {group -> [Row] in
            let groupEntries = entries.filter {$0.group == group}
            return groupEntries.isEmpty ? [] : [.heading(group)]+groupEntries.map(Row.git)
        }
        return true
    }
    private func refreshGit(from monitor:GitWorkspaceMonitor) {
        let repository = monitor.repositories.first {$0.root == directory?.path}
        if let failure = monitor.failure ?? repository?.failure {
            request?.cancel(); request = nil
            showMessage(failure)
            return
        }
        if setGitRows(repository?.status) {reloadFiles()}
        loadSelection(preservingPosition:true)
    }
    private func select(_ key:FileKey) {
        selected = key; operationIndex = 0
        reloadFiles(); loadSelection(preservingPosition:false)
    }
    private func reloadFiles() {
        files.removeAllItems()
        for row in rows {
            switch row {
            case .heading(let group):
                let heading = NSMenuItem(title:terms.text(group.titleKey),action:nil,keyEquivalent:"")
                heading.isEnabled = false
                files.menu?.addItem(heading)
            case .git(let entry):addFile(entry.path)
            case .turn(let edit):addFile(edit.path)
            }
        }
        guard let selected else {return}
        if let index = rows.firstIndex(where:{$0.key == selected}) {
            files.selectItem(at:index)
        } else {
            addFile(selected.path)
            files.lastItem?.isEnabled = false
            files.selectItem(at:files.numberOfItems-1)
        }
    }
    private func addFile(_ path:String) {
        let file = path as NSString
        let parent = (file.deletingLastPathComponent as NSString).lastPathComponent
        let title = file.lastPathComponent+(parent.isEmpty ? "" : " · "+parent)
        let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
        item.toolTip = path
        files.menu?.addItem(item)
    }
    @objc private func changeFile() {
        guard rows.indices.contains(files.indexOfSelectedItem),let key = rows[files.indexOfSelectedItem].key,key != selected else {return}
        selected = key; operationIndex = 0
        loadSelection(preservingPosition:false)
    }
    private func loadSelection(preservingPosition:Bool) {
        request?.cancel(); request = nil
        guard let selected else {return}
        operations.isHidden = true
        let comparison:String
        if let group = selected.group {
            comparison = terms.text("workspaceDiff.comparison."+(group == .staged && initialHead ? "initial" : group.diffKey))
        } else {comparison = L10n.text(.workspace,"workspaceDiff.turnComparison")}
        files.toolTip = selected.path+"\n"+comparison
        files.setAccessibilityHelp(comparison)
        guard let group = selected.group else {
            if case .turn(let edit)? = rows.first(where:{$0.key == selected}) {showTurnPatch(edit)}
            return
        }
        guard case .git(let entry)? = rows.first(where:{$0.key == selected}),let directory else {
            showMessage(terms.text("workspaceDiff.clean")); return
        }
        if !preservingPosition || patch == nil {showMessage(L10n.text(.workspace,"workspaceDiff.loading"))}
        let query = GitWorkspaceRequest(); request = query
        updateActionButtons()
        query.startDiff(root:directory.path,entry:entry) { [weak self,weak query] result in
            guard let self,let query,self.request === query else {return}
            self.request = nil
            defer {self.updateActionButtons()}
            switch result {
            case .success(let patch):
                if patch.text.isEmpty {
                    let key = group == .conflicted ? "workspaceDiff.conflicted" : "workspaceDiff.clean"
                    self.showMessage(self.terms.text(key))
                } else {self.showPatch(patch,preservingPosition:preservingPosition)}
            case .failure(let error):self.showMessage(error.localizedDescription)
            }
        }
    }
    private func showTurnPatch(_ edit:FileEditSummary) {
        let patches = edit.patches ?? []
        if patches.count > 1 {
            operations.removeAllItems()
            operations.addItems(withTitles:patches.indices.map {L10n.format(.workspace,"workspaceDiff.operation",String($0+1))})
            operations.selectItem(at:operationIndex); operations.isHidden = false
        }
        guard patches.indices.contains(operationIndex) else {showMessage(L10n.text(.workspace,"workspaceDiff.unrecorded")); return}
        let change = patches[operationIndex]
        do {
            if change.exceedsLimit {showMessage(L10n.text(.workspace,"workspaceDiff.tooLarge"))}
            else if let patch = try WorkspaceDiffPatch(edit:change,path:edit.path,directory:directory),!patch.text.isEmpty {
                showPatch(patch,preservingPosition:false)
            } else {showMessage(L10n.text(.workspace,"workspaceDiff.unrecorded"))}
        } catch {showMessage(error.localizedDescription)}
    }

    private func showMessage(_ text:String) {
        message.stringValue = text; message.isHidden = false
        content.isHidden = true; patch = nil; hunks = []; activeHunk = nil; expandedContext = []
        counts.isHidden = true
        scroll.clear(); right.clear()
        updateActionButtons()
    }
    private func showPatch(_ value:WorkspaceDiffPatch,preservingPosition:Bool) {
        if preservingPosition,patch?.text == value.text {return}
        patch = value; expandedContext = []; activeHunk = nil
        var lines = FileEditSummary.Lines(added:0,removed:0)
        for line in value.lines {
            if line.kind == .addition {lines.added += 1}
            if line.kind == .deletion {lines.removed += 1}
        }
        counts.attributedStringValue = FileEditRendering.counts(lines,font:.systemFont(ofSize:11))
        counts.isHidden = lines.added == 0 && lines.removed == 0
        renderReview(preservingPosition:preservingPosition)
    }

    private func renderReview(preservingPosition:Bool,resetHorizontal:Bool = false) {
        guard let patch,let selected else {return}
        defer {updateActionButtons()}
        let origin = preservingPosition ? scroll.contentView.bounds.origin : .zero
        let rightOrigin = preservingPosition ? right.contentView.bounds.origin : .zero
        let review = WorkspaceDiffReview(patch:patch,expanded:expandedContext)
        content.isHidden = review.rows.isEmpty
        message.isHidden = !content.isHidden
        if content.isHidden {
            message.stringValue = patch.binary ? terms.text("workspaceDiff.binary") : L10n.text(.workspace,"workspaceDiff.noText")
            hunks = []; scroll.clear(); right.clear()
            return
        }
        let primarySide:WorkspaceDiffSide = splitComparison ? .before : .inline
        let primary = WorkspaceDiffDocument(review,side:primarySide,path:selected.path)
        aligningScroll = true
        defer {aligningScroll = false}
        scroll.autohidesScrollers = !splitComparison
        right.autohidesScrollers = !splitComparison
        right.isHidden = !splitComparison
        scroll.code.setAccessibilityLabel(L10n.text(.workspace,splitComparison ? "workspaceDiff.before" : "workspaceDiff.title"))
        if splitComparison {
            right.show(WorkspaceDiffDocument(review,side:.after,path:selected.path))
        } else {right.clear()}
        scroll.show(primary); hunks = primary.changes
        content.layoutSubtreeIfNeeded()
        let reset = !preservingPosition || resetHorizontal
        scroll.scroll(to:origin,resetHorizontal:reset)
        if splitComparison {right.scroll(to:NSPoint(x:rightOrigin.x,y:scroll.contentView.bounds.minY),resetHorizontal:reset)}
    }

    @objc private func scrollBoundsChanged(_ note:Notification) {
        scroll.redrawRuler(); right.redrawRuler()
        guard splitComparison,!aligningScroll,let source = note.object as? NSClipView else {return}
        let target = source === scroll.contentView ? right : scroll
        let bounds = target.contentView.bounds
        guard abs(bounds.minY-source.bounds.minY) > 0.5 else {return}
        aligningScroll = true
        target.scroll(to:NSPoint(x:bounds.minX,y:source.bounds.minY))
        aligningScroll = false
    }
    @objc private func changeLayout() {
        splitComparison = layoutMode.selectedSegment == 1
        Self.prefersSplit = splitComparison
        renderReview(preservingPosition:true,resetHorizontal:true)
    }
    func textView(_ textView:NSTextView,clickedOnLink link:Any,at charIndex:Int) -> Bool {
        let prefix = "bailong-diff-context:"
        let value = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
        guard value.hasPrefix(prefix),let id = Int(value.dropFirst(prefix.count)) else {return false}
        if expandedContext.remove(id) == nil {expandedContext.insert(id)}
        renderReview(preservingPosition:true)
        return true
    }
    @objc private func changeOperation() {
        operationIndex = operations.indexOfSelectedItem
        loadSelection(preservingPosition:false)
    }
    @objc private func refresh() {monitor?.refresh()}
    @objc private func previousChange() {goToChange(previous:true)}
    @objc private func nextChange() {goToChange(previous:false)}
    private func goToChange(previous:Bool) {
        guard !hunks.isEmpty else {return}
        let index = activeHunk.map {($0+(previous ? -1 : 1)+hunks.count)%hunks.count} ?? (previous ? hunks.count-1 : 0)
        activeHunk = index
        scroll.code.setSelectedRange(hunks[index]); scroll.code.scrollRangeToVisible(hunks[index])
        view.window?.makeFirstResponder(scroll.code)
    }
    @objc private func copyPatch() {
        guard let patch,!patch.binary else {return}
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(patch.text,forType:.string)
    }

    private func makeAction(_ key:String,symbol:String,action:Selector) -> HoverIconButton {
        let label = L10n.text(.workspace,"workspaceDiff."+key)
        let button = HoverIconButton(symbol:symbol,label:label)
        button.controlSize = .small
        button.symbolConfiguration = .init(pointSize:NSFont.systemFontSize(for:.small),weight:.semibold)
        button.hoverCornerRadius = 5
        button.hoverHelp = label
        button.target = self; button.action = action
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant:22),button.heightAnchor.constraint(equalToConstant:22)
        ])
        return button
    }
    private func updateActionButtons() {
        previousButton.isEnabled = !hunks.isEmpty
        nextButton.isEnabled = !hunks.isEmpty
        copyButton.isEnabled = patch?.binary == false
        refreshButton.isHidden = monitor == nil
        refreshButton.isEnabled = request == nil
    }
    override func cancelOperation(_ sender:Any?) {popover?.close()}
    @objc private func sourceClosed() {popover?.close()}
    func popoverDidClose(_ notification:Notification) {
        releaseSource()
        if Self.presented === notification.object as? AnchoredPopover {Self.presented = nil}
    }
    private func releaseSource() {
        dismissal.stop()
        NotificationCenter.default.removeObserver(self,name:NSWindow.willCloseNotification,object:sourceWindow)
        request?.cancel(); request = nil
        monitor?.detach(self); monitor = nil
    }
}

private extension GitWorkspaceStatus.Group {
    var diffKey:String {
        switch self {
        case .staged:return "staged"
        case .unstaged:return "unstaged"
        case .untracked:return "untracked"
        case .conflicted:return "conflicted"
        }
    }
}
