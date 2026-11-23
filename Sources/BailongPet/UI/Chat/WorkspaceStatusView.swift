import AppKit

@objc protocol WorkspaceStatusSettingsAction {
    func showWorkspaceStatusSettings(_ sender:Any?)
}

// 一条共用的次级信息行：目录入口、Git 摘要、本轮修改。可见入口与倒计时收起的独立小窗按事件更新。
final class WorkspaceStatusView:NSStackView,NSPopoverDelegate {
    static let compactButtonHeight:CGFloat = 20
    private let directory = WorkspaceLinkButton()
    private let git = HoverIconButton(symbol:"arrow.triangle.branch",label:L10n.text(.workspace,"status.git")), changes = HoverIconButton(symbol:"doc",label:L10n.text(.workspace,"status.git.2"))
    private let popover = AnchoredPopover()
    private let popoverDismissal = PopoverDismissal()
    private var showsChanges = false, fileEdits = [FileEditSummary]()
    private var path = "", conversationKey:String?, taskKey:String?, wasExecuting = false
    private var editSignature = [String]()
    private var monitor:GitWorkspaceMonitor?
    private var stashRequest:GitWorkspaceRequest?, stashFailure:String?
    private var stashes = [GitWorkspaceStatus.Stash]()
    private var spaceStatuses:[HuggingFaceSpace:HuggingFaceSpace.Result] {monitor?.spaceStatuses ?? [:]}
    private var snapshot:GitWorkspaceStatus? {monitor?.snapshot}
    private var failure:String? {monitor?.failure}
    private var overviewWidth:CGFloat?
    private var fullChanges = NSAttributedString(string:"")
    private var compact = false
    private var buttonHeights = [NSLayoutConstraint]()
    private var active = false, windowObserver:NSObjectProtocol?
    var onContentChange:() -> Void = {}
    var onOpen:(URL) -> Void = {_ in}
    var onStatusChange:() -> Void = {}
    var hasStatus:Bool {snapshot != nil || failure != nil || !changes.isHidden}
    var knownGitPresence:Bool? {
        if let monitor,monitor.loading && !monitor.hasBaseline && failure == nil {return nil}
        return snapshot != nil || failure != nil
    }
    func configure(compact:Bool,fontSize:CGFloat,monochromeDirectory:Bool = false) {
        self.compact = compact
        spacing = compact ? 6 : 10
        directory.emphasizesLink = !compact
        directory.usesMonochromeLink = monochromeDirectory
        directory.font = .systemFont(ofSize:fontSize)
        updateDirectory()
        for constraint in buttonHeights {constraint.constant = compact ? Self.compactButtonHeight*fontSize/11 : 24}
        for button in [git,changes] {button.horizontalPadding = compact ? 2 : 6}
        let font = NSFont.monospacedSystemFont(ofSize:fontSize,weight:.semibold)
        for button in [git,changes] where button.font != font {
            button.font = font
            let text = NSMutableAttributedString(attributedString:button.attributedTitle)
            text.addAttribute(.font,value:font,range:NSRange(location:0,length:text.length))
            button.attributedTitle = text
        }
        changes.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:fontSize,weight:.semibold))
        git.image = sourceIcon(snapshot?.repositoryKind ?? .generic)
    }
    private func sourceIcon(_ kind:GitWorkspaceStatus.RepositoryKind) -> NSImage {
        let original = GitIcons.repository(kind)
        guard compact,let font = git.font else {return original}
        let image = original.copy() as! NSImage
        let side = font.pointSize
        let factor = side/max(original.size.width,original.size.height)
        image.size = NSSize(width:original.size.width*factor,height:original.size.height*factor)
        let capCenter = InlineStatusLayout.lineBaseline(font:font,height:side)+font.capHeight/2
        image.alignmentRect = NSRect(origin:NSPoint(x:0,y:capCenter-side/2),size:image.size)
        return image
    }
    var hasPresentedDetails:Bool {popover.isShown || git.isHighlighted || changes.isHighlighted || directory.isHighlighted}
    override init(frame:NSRect) {
        super.init(frame:frame)
        orientation = .horizontal; alignment = .centerY; distribution = .fill; spacing = 10
        directory.font = .systemFont(ofSize:11); directory.onOpen = { [weak self] in self?.onOpen($0) }
        directory.setContentHuggingPriority(.defaultLow,for:.horizontal)
        directory.setContentCompressionResistancePriority(.init(249),for:.horizontal)
        for button in [git,changes] {
            button.hoverCornerRadius = 6; button.horizontalPadding = 6; button.bezelStyle = .inline
            button.hoverHelp = nil
            button.imageHugsTitle = true
            button.font = .monospacedSystemFont(ofSize:11,weight:.semibold)
            let height = button.heightAnchor.constraint(greaterThanOrEqualToConstant:24)
            height.isActive = true; buttonHeights.append(height)
        }
        git.imagePosition = .imageLeading; git.imageScaling = .scaleProportionallyDown
        git.alignment = .left
        git.target = self; git.action = #selector(openDetails); git.setAccessibilityLabel(L10n.text(.workspace,"status.text"))
        (git.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        git.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        changes.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:11,weight:.semibold))
        changes.imagePosition = .imageLeading; changes.imageScaling = .scaleProportionallyDown
        changes.target = self; changes.action = #selector(openChanges)
        changes.setContentCompressionResistancePriority(.required,for:.horizontal)
        changes.setAccessibilityLabel(L10n.text(.workspace,"status.text.2"))
        [directory,git,NSView(),changes].forEach {addArrangedSubview($0)}
        git.widthAnchor.constraint(lessThanOrEqualToConstant:280).isActive = true
        let directoryMinimum = directory.widthAnchor.constraint(greaterThanOrEqualToConstant:60)
        directoryMinimum.priority = .defaultHigh; directoryMinimum.isActive = true
        git.isHidden = true; changes.isHidden = true; popover.delegate = self
    }
    required init?(coder:NSCoder) {fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver {NotificationCenter.default.removeObserver(windowObserver)}
        NotificationCenter.default.removeObserver(self,name:PetPreferences.didChange,object:PetPreferences.shared)
        if window != nil {
            NotificationCenter.default.addObserver(self,selector:#selector(statusStyleChanged(_:)),name:PetPreferences.didChange,object:PetPreferences.shared)
            updateStatusStyle()
        }
        windowObserver = window.map {window in
            NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main) { [weak self] _ in
                guard let self,self.active,!self.popover.isShown else {return}; self.monitor?.scheduleRefresh()
            }
        }
    }
    @objc private func statusStyleChanged(_ note:Notification) {
        guard let keys = note.userInfo?["keys"] as? [String],keys.contains(where:{$0 == GitStatusStyle.key || $0 == GitTerminology.key}) else {return}
        updateStatusStyle()
    }
    private func updateStatusStyle() {
        guard active,snapshot != nil else {return}
        if popover.isShown {
            if !showsChanges {presentPopoverContent()}
        } else {
            presentStatus(); fitButtons(); onStatusChange()
        }
    }
    func update(conversation:Conversation?,executing:Bool,visible:Bool,turnKey:String? = nil,turnStart:Date? = nil) {
        guard visible else {if active {deactivate()}; return}
        let turn = turnKey == nil && turnStart == nil ? conversation?.turns.max(by:{$0.date < $1.date}) : conversation?.turns.first {((turnKey != nil && ($0.key == turnKey || $0.id == turnKey)) || (turnStart != nil && $0.date == turnStart))}
        update(directory:conversation?.cwd ?? "",context:conversation?.key,turn:turn?.key,edits:turn?.fileEdits ?? [],executing:executing,visible:visible)
    }
    func update(directory nextPath:String,context:String?,turn:String?,edits:[FileEditSummary],executing:Bool,visible:Bool) {
        let changed = conversationKey != context || path != nextPath
        if path != nextPath {detachMonitor(); git.isHidden = true}
        if changed {popover.close(); editSignature = []; taskKey = nil}
        conversationKey = context; path = nextPath
        guard visible else {
            if active {deactivate()}
            return
        }
        let becameActive = !active
        active = true
        if !popover.isShown && (changed || becameActive) {updateDirectory()}
        let signature = edits.flatMap(\.signature)
        let changedEdits = signature != editSignature || taskKey != turn
        let notifyEdits = !changed && !becameActive && changedEdits && (signature != editSignature)
        editSignature = signature; taskKey = turn
        if changed || changedEdits || becameActive {
            updateChanges(edits)
            if popover.isShown && showsChanges {presentPopoverContent()}
        }
        let ended = wasExecuting && !executing; wasExecuting = executing
        if monitor == nil,!path.isEmpty {
            let feed = GitWorkspaceMonitor.directory(path); monitor = feed
            feed.attach(self,spaceChanged:{ [weak self] in self?.updateStatusStyle() }) { [weak self,weak feed] changed,meaningful in
                guard let self,let feed,self.monitor === feed else {return}
                self.gitDidChange(changed:changed,meaningful:meaningful)
            }
            gitDidChange(changed:true,meaningful:false)
        } else if ended {refreshGit()}
        else if changedEdits {monitor?.scheduleRefresh()}
        if changed || changedEdits || becameActive {notifyLayoutChange()}
        if notifyEdits {onContentChange()}
    }
    private func notifyLayoutChange() {if !popover.isShown {onStatusChange()}}
    func deactivate() {
        active = false; detachMonitor(); fileEdits = []; git.isHidden = true; changes.isHidden = true; popover.close()
    }
    private func detachMonitor() {monitor?.detach(self); monitor = nil; git.hoverHelp = nil}
    deinit {detachMonitor(); if let windowObserver {NotificationCenter.default.removeObserver(windowObserver)}}
    private func updateDirectory() {
        directory.isHidden = compact
        let name = URL(fileURLWithPath:path).lastPathComponent
        let project = snapshot.map {URL(fileURLWithPath:$0.root).lastPathComponent}
        directory.update(path:path,displayName:project.flatMap {$0 == name ? nil : $0+" / "+name} ?? name)
    }
    private func updateChanges(_ edits:[FileEditSummary]) {
        fileEdits = edits
        guard !popover.isShown else {return}
        changes.isHidden = edits.isEmpty
        let known = edits.compactMap(\.lines)
        let added = known.reduce(0) {$0+$1.added}, removed = known.reduce(0) {$0+$1.removed}
        let text = NSMutableAttributedString(string:"\(edits.count)",attributes:[.font:changes.font!,.foregroundColor:StatusTextColor.secondary])
        if !known.isEmpty {
            text.append(NSAttributedString(string:" "))
            text.append(FileEditRendering.counts(.init(added:added,removed:removed),font:changes.font!))
            if known.count < edits.count {text.append(NSAttributedString(string:L10n.text(.workspace,"status.updateChanges.text"),attributes:[.foregroundColor:StatusTextColor.secondary]))}
        }
        text.addAttribute(.font,value:changes.font!,range:NSRange(location:0,length:text.length))
        fullChanges = text
        fitButtons()
        let description = L10n.format(.workspace,"status.description",String(describing:edits.count))+(known.isEmpty ? "" : L10n.format(.workspace,"status.description.2",String(describing:added),String(describing:removed)))+(known.count < edits.count ? L10n.format(.workspace,"status.description.3",String(describing:edits.count-known.count)) : "")
        changes.setAccessibilityValue(description)
    }
    func fitOverview(to width:CGFloat) {
        guard overviewWidth != width else {return}
        if overviewWidth == nil {
            for button in [git,changes] {
                button.heightAnchor.constraint(lessThanOrEqualToConstant:Self.compactButtonHeight*(button.font?.pointSize ?? 11)/11).isActive = true
            }
        }
        overviewWidth = width
        fitButtons()
    }
    private func fitButtons() {
        if changes.attributedTitle != fullChanges {changes.attributedTitle = fullChanges}
        guard let width = overviewWidth else {return}
        git.imagePosition = .imageLeading; changes.imagePosition = .imageLeading
        let fontSize = git.font?.pointSize ?? 11
        let gitMinimum = git.isHidden ? 0 : fontSize*4
        let gap = git.isHidden || changes.isHidden ? spacing : 2*spacing
        if !changes.isHidden && changes.intrinsicContentSize.width + gitMinimum + gap > width {
            let count = String(fileEdits.count)
            changes.attributedTitle = fullChanges.attributedSubstring(from:NSRange(location:0,length:count.utf16.count))
        }
        let fileWidth = changes.isHidden ? 0 : changes.intrinsicContentSize.width
        if width-fileWidth-gap < gitMinimum {
            git.imagePosition = .imageOnly
            if !changes.isHidden && fileWidth+gap+(git.isHidden ? 0 : git.intrinsicContentSize.width) > width {
                changes.imagePosition = .imageOnly
            }
        }
    }
    func refreshGit() {monitor?.refresh()}
    private func gitDidChange(changed:Bool,meaningful:Bool) {
        guard let monitor else {return}
        (popover.contentViewController as? GitWorkspaceDetails)?.setLoading(monitor.loading)
        if monitor.loading && !monitor.hasBaseline && failure == nil && !popover.isShown {
            git.isHidden = false; git.image = sourceIcon(.generic); git.title = L10n.text(.workspace,"status.gitDidChange.title"); git.contentTintColor = .secondaryLabelColor
        } else if popover.isShown {
            if !showsChanges {
                if !monitor.loading {refreshStashes()}
                if changed {presentPopoverContent()}
            }
        } else if changed {
            presentStatus(); updateDirectory(); onStatusChange()
        }
        if !popover.isShown && (changed || !monitor.hasBaseline) {fitButtons()}
        if meaningful {onContentChange()}
    }
    private func presentStatus() {
        git.isHidden = snapshot == nil && failure == nil
        if failure != nil || snapshot == nil {
            git.hoverHelp = nil
            git.image = sourceIcon(.generic); git.title = L10n.text(.workspace,"status.presentStatus.title"); git.contentTintColor = StatusTextColor.orange
            git.setAccessibilityValue(failure ?? L10n.text(.workspace,"status.presentStatus.text")); return
        }
        guard let snapshot else {return}
        git.image = sourceIcon(snapshot.repositoryKind)
        let font = git.font!
        let preferences = PetPreferences.shared
        let style = preferences.gitStatusStyle, terms = preferences.gitTerminology
        let heading = snapshot.title+(snapshot.initial ? terms.text("status.heading") : "")
        func statusHeading(font:NSFont,color:NSColor) -> NSMutableAttributedString {
            let text = NSMutableAttributedString(string:heading,attributes:[.font:font,.foregroundColor:color])
            if let operation = snapshot.operation {
                text.append(NSAttributedString(string:" "+operation.compactTitle,attributes:[.font:font,.foregroundColor:StatusTextColor.red]))
            }
            return text
        }
        let helpFont = NSFont.systemFont(ofSize:11)
        let help = statusHeading(font:helpFont,color:.labelColor)
        let space = snapshot.pushSpace ?? snapshot.remoteSpace
        let spaceStatus = space.flatMap {spaceStatuses[$0]}
        if space != nil {
            let attributes:[NSAttributedString.Key:Any] = [.font:helpFont,.foregroundColor:NSColor.labelColor]
            help.append(NSAttributedString(string:"\n"+L10n.text(.workspace,"spaceStatus.title")+" · ",attributes:attributes))
            help.append(GitStatusText.spaceDetail(spaceStatus,font:helpFont))
        }
        git.setHoverHelp(help) { [weak self] in
            guard let self,!self.popover.isShown else {return false}
            return self.git.imagePosition == .imageOnly || self.git.hasTruncatedTitle(in:self.git.contentBounds)
        }
        let text = statusHeading(font:font,color:.secondaryLabelColor)
        text.append(NSAttributedString(string:"  "))
        text.append(GitStatusText.compact(snapshot,font:font,style:style))
        if let badge = GitStatusText.spaceBadge(spaceStatus,font:font) {
            text.append(NSAttributedString(string:" "))
            text.append(badge)
        }
        text.addAttribute(.font,value:font,range:NSRange(location:0,length:text.length))
        if git.attributedTitle != text {git.attributedTitle = text}
        git.contentTintColor = .secondaryLabelColor
        let tracking = GitStatusText.tracking(snapshot,font:font,terms:terms).string
        let repository = snapshot.repositoryKind == .generic ? nil : snapshot.repositoryKind.title(using:terms)
        let push = snapshot.pushTarget.map {terms.format("status.pushAccessibility",GitStatusText.pushTitle(terms),GitStatusText.push($0,font:font,terms:terms).string)}
        let spaceSummary = space.map {_ in L10n.text(.workspace,"spaceStatus.title")+" "+GitStatusText.spaceStatusTitle(spaceStatus)}
        let accessibility = [repository,heading,snapshot.detachedSummary(using:terms),snapshot.operation?.detailTitle(using:terms),
            snapshot.summary(using:terms),terms.text("status.accessibility")+tracking,push,spaceSummary]
        git.setAccessibilityValue(accessibility.compactMap {$0}.joined(separator:"，"))
    }
    @objc private func openDetails() {
        openPopover(changes:false,anchor:git)
    }
    @objc private func openChanges() {openPopover(changes:true,anchor:changes)}
    private func openPopover(changes:Bool,anchor:NSView) {
        if popover.isShown && showsChanges == changes {popover.performClose(nil); return}
        popover.close(); showsChanges = changes
        popover.behavior = .transient; popover.animates = DisclosureMotion.enabled
        if !changes {refreshStashes()}
        presentPopoverContent()
        popover.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.maxY)
        popoverDismissal.start(for:popover,anchor:anchor)
    }
    private func presentPopoverContent() {
        let previous = popover.contentViewController as? GitWorkspaceDetails
        let content:NSViewController = showsChanges ? TurnFileEditsDetails(edits:fileEdits,directory:path) : makeDetails()
        _ = content.view
        // 已打开时只因真实内容变化替换一次，避免加载态与完成态两次尺寸动画。
        let animated = popover.animates
        if popover.isShown {popover.animates = false}
        popover.contentViewController = content; popover.contentSize = content.preferredContentSize
        popover.animates = animated
        if let previous,let updated = content as? GitWorkspaceDetails {updated.restoreReadingPosition(from:previous)}
    }
    private func makeDetails() -> GitWorkspaceDetails {
        let loading = monitor?.loading == true || stashRequest != nil
        let preferences = PetPreferences.shared
        let content = GitWorkspaceDetails(snapshot:snapshot,stashes:stashes,stashLoading:stashRequest != nil && stashes.isEmpty,
            failure:failure ?? monitor?.observationFailure ?? stashFailure,loading:loading,style:preferences.gitStatusStyle,
            terms:preferences.gitTerminology,spaceStatuses:spaceStatuses)
        content.onRetry = { [weak self] in self?.refreshGit() }
        return content
    }
    private func refreshStashes() {
        stashRequest?.cancel(); stashRequest = nil
        guard let snapshot,snapshot.stashes > 0 else {stashes = []; stashFailure = nil; return}
        let query = GitWorkspaceRequest(); stashRequest = query
        query.startStashes(directory:snapshot.root,previous:stashes) { [weak self,weak query] result in
            guard let self,let query,self.stashRequest === query else {return}
            self.stashRequest = nil
            guard self.popover.isShown,!self.showsChanges else {return}
            let oldStashes = self.stashes, oldFailure = self.stashFailure
            switch result {
            case .success(let stashes):self.stashes = stashes; self.stashFailure = nil
            case .failure(let error):self.stashFailure = error.localizedDescription
            }
            if oldStashes != self.stashes || oldFailure != self.stashFailure || oldStashes.isEmpty {self.presentPopoverContent()}
            else {(self.popover.contentViewController as? GitWorkspaceDetails)?.setLoading(self.monitor?.loading == true)}
        }
    }
    func popoverDidClose(_ notification:Notification) {
        popoverDismissal.stop(); popover.contentViewController = nil
        stashRequest?.cancel(); stashRequest = nil; stashes = []; stashFailure = nil
        guard active else {return}
        presentStatus(); updateDirectory(); updateChanges(fileEdits); onStatusChange()
    }
    func containsInteraction(at point:NSPoint) -> Bool {popover.isShown && popover.contentViewController?.view.window?.frame.contains(point) == true}
}

private final class GitWorkspaceDetails:NSViewController,NSTableViewDataSource,NSTableViewDelegate {
    private enum Row {
        case operation(String), heading(GitWorkspaceStatus.Group,Int), file(GitWorkspaceStatus.Entry)
        case stashHeading(String), stashSubject(String), stashLoading, stashFile(path:String,commit:String)
        var file:FileIdentity? {
            switch self {
            case .file(let entry):return .init(path:entry.path,group:entry.group,stashCommit:nil)
            case .stashFile(let path,let commit):return .init(path:path,group:nil,stashCommit:commit)
            case .operation,.heading,.stashHeading,.stashSubject,.stashLoading:return nil
            }
        }
    }
    private struct FileIdentity:Equatable {let path:String, group:GitWorkspaceStatus.Group?, stashCommit:String?}
    private let snapshot:GitWorkspaceStatus?, failure:String?
    private let style:GitStatusStyle
    private let terms:GitTerminology
    private let spaceStatuses:[HuggingFaceSpace:HuggingFaceSpace.Result]
    private var loading:Bool
    private var retryButton:NSButton?
    func setLoading(_ loading:Bool) {
        self.loading = loading
        retryButton?.isEnabled = !loading
        retryButton?.title = loading ? L10n.text(.workspace,"status.setLoading.heading") : L10n.text(.workspace,"status.setLoading.heading.2")
    }
    private var rows = [Row]()
    private let table = WorkspaceFileTable()
    var onRetry:() -> Void = {}
    func restoreReadingPosition(from previous:GitWorkspaceDetails) {
        view.layoutSubtreeIfNeeded()
        if let origin = previous.table.enclosingScrollView?.contentView.bounds.origin,let scroll = table.enclosingScrollView {
            scroll.contentView.scroll(to:origin); scroll.reflectScrolledClipView(scroll.contentView)
        }
        let selected = previous.table.selectedRowIndexes.compactMap {index in
            previous.rows.indices.contains(index) ? previous.rows[index].file : nil
        }
        let indices = rows.indices.filter {index in
            rows[index].file.map {selected.contains($0)} ?? false
        }
        table.selectRowIndexes(IndexSet(indices),byExtendingSelection:false)
    }
    init(snapshot:GitWorkspaceStatus?,stashes:[GitWorkspaceStatus.Stash],stashLoading:Bool,failure:String?,loading:Bool,
         style:GitStatusStyle,terms:GitTerminology,spaceStatuses:[HuggingFaceSpace:HuggingFaceSpace.Result]) {
        self.snapshot = snapshot; self.failure = failure; self.loading = loading
        self.style = style; self.terms = terms; self.spaceStatuses = spaceStatuses
        super.init(nibName:nil,bundle:nil)
        if let snapshot {
            if let operation = snapshot.operation {rows.append(.operation(operation.detailTitle(using:terms)))}
            for group in GitWorkspaceStatus.Group.allCases {
                let entries = snapshot.entries.filter {$0.group == group}
                if !entries.isEmpty {rows.append(.heading(group,entries.count)); rows += entries.map(Row.file)}
            }
        }
        for (index,stash) in stashes.enumerated() {
            let reference = "stash@{\(index)}"
            let titleKey = terms == .english && stash.paths.count == 1 ? "status.stashFileTitle" : "status.stashFilesTitle"
            rows.append(.stashHeading(terms.format(titleKey,reference,String(stash.paths.count))))
            if !stash.subject.isEmpty {rows.append(.stashSubject(stash.subject))}
            rows += stash.paths.map {.stashFile(path:$0,commit:stash.commit)}
        }
        if stashLoading {rows.append(.stashLoading)}
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        let detailWidth:CGFloat = 420
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        let heading = NSTextField(labelWithString:snapshot?.title ?? terms.text("status.heading.2"))
        heading.font = .systemFont(ofSize:13,weight:.semibold)
        heading.maximumNumberOfLines = 1
        heading.lineBreakMode = .byTruncatingMiddle
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        heading.setHoverHelp(snapshot?.title) { [weak heading] in heading?.hasTruncatedText == true }
        let kind = snapshot?.repositoryKind ?? .generic
        let kinds = kind == .generic ? [.generic] : [kind,.generic]
        let sources = kinds.map {kind in
            let icon = NSImageView(image:GitIcons.repository(kind))
            icon.imageScaling = .scaleProportionallyDown; icon.contentTintColor = .secondaryLabelColor
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:16),icon.heightAnchor.constraint(equalToConstant:16)])
            return icon
        }
        let title = NSStackView(views:sources); title.alignment = .centerY; title.spacing = 6
        title.addArrangedSubview(heading)
        let top = NSStackView(views:[title,NSView()])
        top.alignment = .centerY; top.spacing = 12
        if failure != nil {
            let retry = ActionButton(L10n.text(.workspace,"status.setLoading.heading.2")) { [weak self] in self?.onRetry() }
            retryButton = retry
            retry.widthAnchor.constraint(greaterThanOrEqualToConstant:70).isActive = true
            top.addArrangedSubview(retry)
            setLoading(loading)
        }
        let settings = HoverIconButton(symbol:"questionmark.circle",label:L10n.text(.workspace,"status.settings"))
        settings.symbolConfiguration = .init(pointSize:15,weight:.bold)
        settings.hoverCornerRadius = 10
        settings.widthAnchor.constraint(equalToConstant:22).isActive = true
        settings.heightAnchor.constraint(equalToConstant:22).isActive = true
        settings.target = NSApp.delegate
        settings.action = #selector(WorkspaceStatusSettingsAction.showWorkspaceStatusSettings(_:))
        top.addArrangedSubview(settings)
        stack.addArrangedSubview(top)
        if let failure,snapshot != nil {
            let error = NSTextField(wrappingLabelWithString:failure); error.textColor = StatusTextColor.orange
            error.font = .systemFont(ofSize:11); stack.addArrangedSubview(error)
        }
        let summaryFont = NSFont.systemFont(ofSize:11)
        func label(_ value:String) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString:value)
            field.font = summaryFont; field.textColor = .labelColor
            field.isSelectable = true; return field
        }
        func selectableLabel(_ content:NSAttributedString,width:CGFloat) -> SelectableRichText {
            let text = SelectableRichText(frame:.zero)
            text.attributedStringValue = content
            text.selectedTextAttributes = [.backgroundColor:AppAccent.selectedTextBackground]
            text.heightAnchor.constraint(equalToConstant:text.height(for:width)).isActive = true
            return text
        }
        if let snapshot {
            let summaryInset:CGFloat = 10, columnSpacing:CGFloat = 6
            let workspaceTitle = terms.text("status.metadata.text"), remoteTitle = terms.text("status.metadata.text.2")
            let upstreamTitle = terms.text("gitStatusText.repository.text"), pushTitle = GitStatusText.pushTitle(terms)
            let captionTitles = [workspaceTitle,remoteTitle,upstreamTitle] + (snapshot.pushTarget == nil ? [] : [pushTitle])
            let captionWidth = max(40,ceil(captionTitles.map {($0 as NSString).size(withAttributes:[.font:summaryFont]).width}.max() ?? 0)+4)
            let valueWidth = detailWidth-2*summaryInset-captionWidth-columnSpacing
            let summary = NSStackView(); summary.orientation = .vertical; summary.alignment = .leading; summary.spacing = 6
            func metadata(_ title:String,_ value:NSView) {
                let caption = NSTextField(labelWithString:title)
                caption.font = summaryFont; caption.textColor = .labelColor
                caption.widthAnchor.constraint(equalToConstant:captionWidth).isActive = true
                value.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
                value.setContentHuggingPriority(.defaultLow,for:.horizontal)
                let row = NSStackView(views:[caption,value]); row.alignment = .firstBaseline; row.spacing = columnSpacing
                row.distribution = .fill; summary.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo:summary.widthAnchor).isActive = true
            }
            let workspace = WorkspaceLinkButton(); workspace.font = summaryFont
            workspace.update(path:snapshot.root)
            workspace.onOpen = {FinderFileReveal.openDirectory($0)}
            metadata(workspaceTitle,workspace)
            if let url = snapshot.remoteWebURL {
                let repository = [snapshot.remoteHost,snapshot.remoteRepository].compactMap {$0}.joined(separator:"/")
                metadata(remoteTitle,RepositoryLinkButton(url:url,label:[snapshot.remoteName,repository.isEmpty ? nil : repository].compactMap {$0}.joined(separator:" · ")))
            } else if snapshot.remoteName == "." {metadata(remoteTitle,label(terms.text("status.metadata.text.3")))}
            else if let remote = snapshot.remoteName {
                metadata(remoteTitle,label(([remote]+[snapshot.remoteHost,snapshot.remoteRepository].compactMap {$0}).joined(separator:" · ")))
            } else {metadata(remoteTitle,label(snapshot.remoteNames.isEmpty ? terms.text("status.metadata.text.4") : snapshot.remoteNames.joined(separator:"、")))}
            let upstream = GitStatusText.tracking(snapshot,font:summaryFont,style:style,terms:terms)
            metadata(upstreamTitle,selectableLabel(upstream,width:valueWidth))
            if let pushTarget = snapshot.pushTarget {
                let push = GitStatusText.push(pushTarget,font:summaryFont,style:style,terms:terms)
                metadata(pushTitle,selectableLabel(push,width:valueWidth))
            }
            stack.addArrangedSubview(RoundedSectionBackground(content:summary,horizontalInset:summaryInset,verticalInset:8,solidFill:true))
            let remoteSpace = snapshot.remoteSpace, pushSpace = snapshot.pushSpace
            let spaces = [remoteSpace == pushSpace ? nil : remoteSpace,pushSpace].compactMap {$0}
            for space in spaces {
                let title = GitStatusText.spaceHeading(font:.systemFont(ofSize:11,weight:.semibold))
                let detail = GitStatusText.spaceDetail(spaceStatuses[space],font:summaryFont,space:spaces.count > 1 ? space : nil)
                let inset:CGFloat = 4
                let body = selectableLabel(detail,width:detailWidth-2*inset)
                let section = NSStackView(views:[NSTextField(labelWithAttributedString:title),body])
                section.orientation = .vertical; section.alignment = .leading; section.spacing = 3
                section.edgeInsets = NSEdgeInsets(top:2,left:inset,bottom:2,right:inset)
                stack.addArrangedSubview(section)
                body.widthAnchor.constraint(equalTo:section.widthAnchor,constant:-2*inset).isActive = true
            }
            let states = GitStatusText.stateDetails(snapshot,font:summaryFont,terms:terms)
            if states.length > 0 {stack.addArrangedSubview(selectableLabel(states,width:detailWidth))}
            if snapshot.clean {
                let clean = GitStatusText.cleanLabel(font:summaryFont,style:style,terms:terms)
                stack.addArrangedSubview(selectableLabel(clean,width:detailWidth))
            }
        } else {stack.addArrangedSubview(label(failure ?? (loading ? L10n.text(.workspace,"status.metadata.text.6") : terms.text("status.metadata.text.7"))))}
        if !rows.isEmpty {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.verticalScrollElasticity = .allowed
            let column = NSTableColumn(identifier:.init("file")); column.resizingMask = .autoresizingMask
            table.addTableColumn(column); table.rowHeight = 26; table.intercellSpacing = .zero
            table.delegate = self; table.dataSource = self
            table.fileURLForRow = { [weak self] row in
                guard let self,rows.indices.contains(row),let file = rows[row].file,let root = snapshot?.root else {return nil}
                return URL(fileURLWithPath:root,isDirectory:true).appendingPathComponent(file.path)
            }
            table.fileGroupForRow = { [weak self] row in
                guard let self,rows.indices.contains(row) else {return nil}
                switch rows[row] {
                case .heading(let group,_):return group
                case .file(let entry):return entry.group
                case .operation,.stashHeading,.stashSubject,.stashLoading,.stashFile:return nil
                }
            }
            table.setAccessibilityLabel(L10n.text(.workspace,"status.metadata.text.8"))
            scroll.documentView = table; stack.addArrangedSubview(scroll)
            scroll.heightAnchor.constraint(equalToConstant:min(300,rows.indices.reduce(CGFloat.zero) {$0+rowHeight($1)})).isActive = true
        }
        view = NSView(); view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16),stack.widthAnchor.constraint(equalToConstant:detailWidth)])
        for row in stack.arrangedSubviews {row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        preferredContentSize = view.fittingSize
    }
    private func rowHeight(_ row:Int) -> CGFloat {
        switch rows[row] {
        case .operation,.heading,.stashHeading:return row == 0 ? 22 : 30
        case .stashSubject,.stashLoading:return 20
        case .file,.stashFile:return 26
        }
    }
    func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {rowHeight(row)}
    func numberOfRows(in tableView:NSTableView) -> Int {rows.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {
        rows[row].file == nil ? nil : WorkspaceFileTableRow()
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        func heading(_ title:NSAttributedString,accessibility:String,subordinate:Bool = false) -> NSView {
            let text = NSTextField(labelWithString:""); text.attributedStringValue = title
            text.lineBreakMode = .byTruncatingTail
            text.setAccessibilityLabel(accessibility)
            if subordinate {text.setHoverHelp(accessibility) { [weak text] in text?.hasTruncatedText == true }}
            let cell = TopDownView(); cell.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:subordinate ? 28 : 4),
                text.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-6),
                text.centerYAnchor.constraint(equalTo:cell.centerYAnchor,constant:subordinate || row == 0 ? 0 : 3)
            ])
            return cell
        }
        func note(_ title:String) -> NSView {
            let text = NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor])
            return heading(text,accessibility:title,subordinate:true)
        }
        let font = NSFont.systemFont(ofSize:11,weight:.semibold)
        switch rows[row] {
        case .operation(let title):
            return heading(GitStatusText.operationDetail(title,font:font),accessibility:title)
        case .heading(let group,let count):
            let accessibility = terms.format("status.tableView.text",terms.text(group.titleKey),String(count))
            return heading(GitStatusText.groupDetail(group,count:count,font:font,style:style,terms:terms),accessibility:accessibility)
        case .stashHeading(let title):
            return heading(GitStatusText.stashDetail(title,font:font,style:style),accessibility:title)
        case .stashSubject(let subject):
            return note(subject)
        case .stashLoading:
            return note(terms.text("status.stashLoading"))
        case .stashFile(let path,_):
            return WorkspaceFileRow(title:(path as NSString).lastPathComponent,symbol:"doc",color:.secondaryLabelColor,
                detail:path,directory:(path as NSString).deletingLastPathComponent)
        case .file(let entry):
            let (symbol,color) = WorkspaceFileRow.symbol(for:entry)
            let parent = (entry.path as NSString).deletingLastPathComponent
            return WorkspaceFileRow(title:(entry.path as NSString).lastPathComponent,symbol:symbol,color:color,
                detail:entry.originalPath.map {$0+" → "+entry.path} ?? entry.path,directory:parent,change:entry.change.title(using:terms))
        }
    }
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int) -> Bool {rows[row].file != nil}
}
