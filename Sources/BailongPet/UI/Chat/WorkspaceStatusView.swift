import AppKit

@objc protocol WorkspaceStatusSettingsAction {
    func showWorkspaceStatusSettings(_ sender:Any?)
}

// 一条共用的次级信息行：目录入口、Git 摘要、本轮修改。可见入口与倒计时收起的独立小窗按事件更新。
final class WorkspaceStatusView:NSStackView,NSPopoverDelegate {
    static let compactButtonHeight:CGFloat = 20
    private let directory = WorkspaceLinkButton()
    private let git = HoverIconButton(symbol:"arrow.triangle.branch",label:"Git 状态"), changes = HoverIconButton(symbol:"doc",label:"本轮文件修改")
    private let popover = AnchoredPopover()
    private let popoverDismissal = PopoverDismissal()
    private var showsChanges = false, fileEdits = [FileEditSummary]()
    private var path = "", conversationKey:String?, taskKey:String?, wasExecuting = false
    private var editSignature = [String]()
    private var monitor:GitWorkspaceMonitor?
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
        git.target = self; git.action = #selector(openDetails); git.setAccessibilityLabel("Git 工作区状态")
        (git.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        git.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        changes.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:11,weight:.semibold))
        changes.imagePosition = .imageLeading; changes.imageScaling = .scaleProportionallyDown
        changes.target = self; changes.action = #selector(openChanges)
        changes.setContentCompressionResistancePriority(.required,for:.horizontal)
        changes.setAccessibilityLabel("本轮累计修改行数")
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
        guard let keys = note.userInfo?["keys"] as? [String],keys.contains(GitStatusStyle.key) else {return}
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
            feed.attach(self) { [weak self,weak feed] changed,meaningful in
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
            if known.count < edits.count {text.append(NSAttributedString(string:" · 部分",attributes:[.foregroundColor:StatusTextColor.secondary]))}
        }
        text.addAttribute(.font,value:changes.font!,range:NSRange(location:0,length:text.length))
        fullChanges = text
        fitButtons()
        let description = "本轮修改 \(edits.count) 个文件。"+(known.isEmpty ? "" : "累计新增 \(added) 行、删除 \(removed) 行。")+(known.count < edits.count ? "\n\(edits.count-known.count) 个文件未提供行数。" : "")
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
            git.isHidden = false; git.image = sourceIcon(.generic); git.title = "读取中…"; git.contentTintColor = .secondaryLabelColor
        } else if popover.isShown {
            if !showsChanges && changed {presentPopoverContent()}
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
            git.image = sourceIcon(.generic); git.title = "读取失败"; git.contentTintColor = StatusTextColor.orange
            git.setAccessibilityValue(failure ?? "Git 状态读取失败"); return
        }
        guard let snapshot else {return}
        git.image = sourceIcon(snapshot.repositoryKind)
        let font = git.font!
        let style = PetPreferences.shared.gitStatusStyle
        let heading = snapshot.title+(snapshot.initial ? " · 首次提交前" : "")
        let compactHeading = snapshot.operation.map {heading+" · "+$0.compactTitle} ?? heading
        let help = NSMutableAttributedString(string:compactHeading+"\n",attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.labelColor])
        help.append(GitStatusText.legend(style))
        git.setHoverHelp(help) { [weak self] in
            guard let self,!self.popover.isShown else {return false}
            return self.git.imagePosition == .imageOnly || self.git.hasTruncatedTitle(in:self.git.contentBounds)
        }
        let text = NSMutableAttributedString(string:compactHeading+"  ")
        text.append(GitStatusText.compact(snapshot,font:font,style:style))
        text.addAttribute(.font,value:font,range:NSRange(location:0,length:text.length))
        if git.attributedTitle != text {git.attributedTitle = text}
        git.contentTintColor = .secondaryLabelColor
        let tracking = GitStatusText.tracking(snapshot,font:font).string
        let repository = snapshot.repositoryKind == .generic ? nil : snapshot.repositoryKind.title
        let accessibility = [repository,heading,snapshot.detachedSummary,snapshot.operation?.detailTitle,snapshot.summary,"上游："+tracking]
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
        let content = GitWorkspaceDetails(snapshot:snapshot,failure:failure ?? monitor?.observationFailure,loading:monitor?.loading == true,style:PetPreferences.shared.gitStatusStyle)
        content.onRetry = { [weak self] in self?.refreshGit() }
        return content
    }
    func popoverDidClose(_ notification:Notification) {
        popoverDismissal.stop(); popover.contentViewController = nil
        guard active else {return}
        presentStatus(); updateDirectory(); updateChanges(fileEdits); onStatusChange()
    }
    func containsInteraction(at point:NSPoint) -> Bool {popover.isShown && popover.contentViewController?.view.window?.frame.contains(point) == true}
}

private final class GitWorkspaceDetails:NSViewController,NSTableViewDataSource,NSTableViewDelegate {
    private enum Row {case heading(GitWorkspaceStatus.Group,Int), file(GitWorkspaceStatus.Entry)}
    private let snapshot:GitWorkspaceStatus?, failure:String?
    private let style:GitStatusStyle
    private var loading:Bool
    private var retryButton:NSButton?
    func setLoading(_ loading:Bool) {
        self.loading = loading
        retryButton?.isEnabled = !loading
        retryButton?.title = loading ? "重试中…" : "重试"
    }
    private var rows = [Row]()
    private let table = WorkspaceFileTable()
    var onRetry:() -> Void = {}
    private func fileEntry(at row:Int) -> GitWorkspaceStatus.Entry? {
        guard rows.indices.contains(row),case .file(let entry) = rows[row] else {return nil}
        return entry
    }
    func restoreReadingPosition(from previous:GitWorkspaceDetails) {
        view.layoutSubtreeIfNeeded()
        if let origin = previous.table.enclosingScrollView?.contentView.bounds.origin,let scroll = table.enclosingScrollView {
            scroll.contentView.scroll(to:origin); scroll.reflectScrolledClipView(scroll.contentView)
        }
        let selected = previous.table.selectedRowIndexes.compactMap {index -> GitWorkspaceStatus.Entry? in
            guard previous.rows.indices.contains(index),case .file(let entry) = previous.rows[index] else {return nil}
            return entry
        }
        let indices = rows.indices.filter {index in
            guard case .file(let entry) = rows[index] else {return false}
            return selected.contains {$0.path == entry.path && $0.group == entry.group}
        }
        table.selectRowIndexes(IndexSet(indices),byExtendingSelection:false)
    }
    init(snapshot:GitWorkspaceStatus?,failure:String?,loading:Bool,style:GitStatusStyle) {
        self.snapshot = snapshot; self.failure = failure; self.loading = loading
        self.style = style
        super.init(nibName:nil,bundle:nil)
        if let snapshot {
            for group in GitWorkspaceStatus.Group.allCases {
                let entries = snapshot.entries.filter {$0.group == group}
                if !entries.isEmpty {rows.append(.heading(group,entries.count)); rows += entries.map(Row.file)}
            }
        }
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        let detailWidth:CGFloat = 420
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        let heading = NSTextField(labelWithString:snapshot?.title ?? "Git 工作区")
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
            let retry = ActionButton("重试") { [weak self] in self?.onRetry() }
            retryButton = retry
            retry.widthAnchor.constraint(greaterThanOrEqualToConstant:70).isActive = true
            top.addArrangedSubview(retry)
            setLoading(loading)
        }
        let settings = HoverIconButton(symbol:"questionmark.circle",label:"打开工作区状态设置")
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
            let summaryInset:CGFloat = 10, captionWidth:CGFloat = 40, columnSpacing:CGFloat = 6
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
            metadata("工作区",workspace)
            if let url = snapshot.remoteWebURL {
                let repository = [snapshot.remoteHost,snapshot.remoteRepository].compactMap {$0}.joined(separator:"/")
                metadata("远端",RepositoryLinkButton(url:url,label:[snapshot.remoteName,repository.isEmpty ? nil : repository].compactMap {$0}.joined(separator:" · ")))
            } else if snapshot.remoteName == "." {metadata("远端",label("上游位于本地仓库"))}
            else if let remote = snapshot.remoteName {
                metadata("远端",label(([remote]+[snapshot.remoteHost,snapshot.remoteRepository].compactMap {$0}).joined(separator:" · ")))
            } else {metadata("远端",label(snapshot.remoteNames.isEmpty ? "未配置" : snapshot.remoteNames.joined(separator:"、")))}
            let upstream = GitStatusText.tracking(snapshot,font:summaryFont,style:style)
            metadata("上游",selectableLabel(upstream,width:valueWidth))
            stack.addArrangedSubview(RoundedSectionBackground(content:summary,horizontalInset:summaryInset,verticalInset:8,solidFill:true))
            let states = GitStatusText.stateDetails(snapshot,font:summaryFont,style:style)
            if states.length > 0 {stack.addArrangedSubview(selectableLabel(states,width:detailWidth))}
            if rows.isEmpty {
                let clean = NSAttributedString(string:"工作区干净",attributes:[.font:summaryFont,.foregroundColor:StatusTextColor.green])
                stack.addArrangedSubview(selectableLabel(clean,width:detailWidth))
            }
        } else {stack.addArrangedSubview(label(failure ?? (loading ? "正在读取 Git 状态…" : "非 Git 工作区")))}
        if !rows.isEmpty {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.verticalScrollElasticity = .allowed
            let column = NSTableColumn(identifier:.init("file")); column.resizingMask = .autoresizingMask
            table.addTableColumn(column); table.rowHeight = 26; table.intercellSpacing = .zero
            table.delegate = self; table.dataSource = self
            table.fileURLForRow = { [weak self] row in
                guard let self,let entry = fileEntry(at:row),let root = snapshot?.root else {return nil}
                return URL(fileURLWithPath:root,isDirectory:true).appendingPathComponent(entry.path)
            }
            table.fileGroupForRow = { [weak self] row in
                guard let self,rows.indices.contains(row) else {return nil}
                switch rows[row] {
                case .heading(let group,_):return group
                case .file(let entry):return entry.group
                }
            }
            table.setAccessibilityLabel("Git 文件状态，双击在访达中显示，右键显示文件操作")
            scroll.documentView = table; stack.addArrangedSubview(scroll)
            scroll.heightAnchor.constraint(equalToConstant:min(300,rows.indices.reduce(CGFloat.zero) {$0+rowHeight($1)})).isActive = true
        }
        view = NSView(); view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16),stack.widthAnchor.constraint(equalToConstant:detailWidth)])
        for row in stack.arrangedSubviews {row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        preferredContentSize = view.fittingSize
    }
    private func rowHeight(_ row:Int) -> CGFloat {
        if case .heading = rows[row] {return row == 0 ? 22 : 30}
        return 26
    }
    func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {rowHeight(row)}
    func numberOfRows(in tableView:NSTableView) -> Int {rows.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {
        if case .file = rows[row] {return WorkspaceFileTableRow()}
        return nil
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        switch rows[row] {
        case .heading(let group,let count):
            let font = NSFont.systemFont(ofSize:11,weight:.semibold)
            let text = NSTextField(labelWithString:""); text.attributedStringValue = GitStatusText.groupDetail(group,count:count,font:font,style:style)
            text.setAccessibilityLabel("\(group.rawValue)，\(count) 项")
            let cell = TopDownView(); cell.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:4),
                text.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-6),
                text.centerYAnchor.constraint(equalTo:cell.centerYAnchor,constant:row == 0 ? 0 : 3)
            ])
            return cell
        case .file(let entry):
            let (symbol,color) = WorkspaceFileRow.symbol(for:entry)
            let parent = (entry.path as NSString).deletingLastPathComponent
            return WorkspaceFileRow(title:(entry.path as NSString).lastPathComponent,symbol:symbol,color:color,
                detail:entry.originalPath.map {$0+" → "+entry.path} ?? entry.path,directory:parent,change:entry.change)
        }
    }
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int) -> Bool {if case .file = rows[row] {return true}; return false}
}
