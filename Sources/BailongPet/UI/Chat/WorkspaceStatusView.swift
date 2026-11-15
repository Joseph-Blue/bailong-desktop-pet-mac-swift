import AppKit

private enum GitStatusText {
    static let groups:[(group:GitWorkspaceStatus.Group,marker:String,color:NSColor)] = [
        (.conflicted,"~",.systemRed),(.staged,"+",.systemGreen),
        (.unstaged,"!",.systemOrange),(.untracked,"?",.systemBlue)
    ]
    static func render(_ status:GitWorkspaceStatus,compact:Bool,font:NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(), counts = status.counts
        func append(_ value:String,color:NSColor) {
            if text.length > 0 {text.append(NSAttributedString(string:compact ? " " : " · ",attributes:[.font:font,.foregroundColor:NSColor.secondaryLabelColor]))}
            if compact {
                text.append(InlineStatusLayout.centeredSymbol(String(value.prefix(1)),font:font,color:color))
                text.append(NSAttributedString(string:String(value.dropFirst()),attributes:[.font:font,.foregroundColor:color]))
            } else {text.append(NSAttributedString(string:value,attributes:[.font:font,.foregroundColor:color]))}
        }
        for (group,marker,color) in groups {
            if let count = counts[group],count > 0 {append(compact ? marker+String(count) : group.rawValue+" \(count) 项",color:color)}
        }
        if status.clean {append(compact ? "✓" : "工作区干净",color:.systemGreen)}
        if status.stashes > 0 {append(compact ? "*\(status.stashes)" : "暂存栈 \(status.stashes) 份",color:.systemPurple)}
        if compact {
            if status.ahead > 0 {append("⇡\(status.ahead)",color:.systemBlue)}
            if status.behind > 0 {append("⇣\(status.behind)",color:.systemBlue)}
        }
        return text
    }
    static func tracking(_ status:GitWorkspaceStatus,font:NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(string:"上游："+(status.upstream ?? ""),attributes:[.font:font,.foregroundColor:NSColor.labelColor])
        for (label,count) in [("领先",status.ahead),("落后",status.behind)] {
            text.append(NSAttributedString(string:" · ",attributes:[.font:font,.foregroundColor:NSColor.labelColor]))
            text.append(NSAttributedString(string:label+" \(count)",attributes:[.font:count > 0 ? NSFont.systemFont(ofSize:font.pointSize,weight:.semibold) : font,.foregroundColor:count > 0 ? NSColor.systemBlue : NSColor.labelColor]))
        }
        text.append(NSAttributedString(string:"（本机记录）",attributes:[.font:font,.foregroundColor:NSColor.labelColor]))
        return text
    }
}

// 一条共用的次级信息行：目录入口、Git 摘要、本轮修改。可见入口与倒计时收起的独立小窗按事件更新。
final class WorkspaceStatusView:NSStackView,NSPopoverDelegate {
    private let directory = WorkspaceLinkButton()
    private let git = HoverIconButton(symbol:"arrow.triangle.branch",label:"Git 状态"), changes = HoverIconButton(symbol:"doc",label:"本轮文件修改")
    private let popover = NSPopover()
    private let popoverDismissal = PopoverDismissal()
    private var showsChanges = false, fileEdits = [FileEditSummary]()
    private var path = "", conversationKey:String?, taskKey:String?, wasExecuting = false
    private var editSignature = [String](), snapshot:GitWorkspaceStatus?, failure:String?
    private var request:GitWorkspaceRequest?, pending:DispatchWorkItem?
    private var compact = false
    private var buttonHeights = [NSLayoutConstraint]()
    private var active = false, windowObserver:NSObjectProtocol?
    private let observation = GitWorkspaceObservation()
    private var refreshAgain = false, hasGitBaseline = false
    private var observationFailure:String?
    var onContentChange:() -> Void = {}
    var onOpen:(URL) -> Void = {_ in}
    var onStatusChange:() -> Void = {}
    var hasStatus:Bool {snapshot != nil || failure != nil || !changes.isHidden}
    func configure(compact:Bool,fontSize:CGFloat,monochromeDirectory:Bool = false) {
        self.compact = compact
        spacing = compact ? 6 : 10
        directory.emphasizesLink = !compact
        directory.usesMonochromeLink = monochromeDirectory
        directory.font = .systemFont(ofSize:fontSize)
        updateDirectory()
        for constraint in buttonHeights {constraint.constant = compact ? 20*fontSize/11 : 24}
        for button in [git,changes] {button.horizontalPadding = compact ? 2 : 6}
        let font = NSFont.monospacedSystemFont(ofSize:fontSize,weight:.semibold)
        for button in [git,changes] where button.font != font {
            button.font = font
            let text = NSMutableAttributedString(attributedString:button.attributedTitle)
            text.addAttribute(.font,value:font,range:NSRange(location:0,length:text.length))
            button.attributedTitle = text
        }
        changes.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:fontSize,weight:.semibold))
        git.image = sourceIcon(github:snapshot?.isGitHub == true)
    }
    private func sourceIcon(github:Bool) -> NSImage {
        let original = github ? GitIcons.github : GitIcons.git
        guard compact else {return original}
        let image = original.copy() as! NSImage
        let side = (git.font?.pointSize ?? 11)+1
        image.size = NSSize(width:side,height:side)
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
        observation.onChange = { [weak self] in self?.scheduleRefresh() }
    }
    required init?(coder:NSCoder) {fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver {NotificationCenter.default.removeObserver(windowObserver)}
        windowObserver = window.map {window in
            NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main) { [weak self] _ in
                guard let self,self.active,!self.popover.isShown else {return}; self.refreshGit()
            }
        }
    }
    func update(conversation:Conversation?,executing:Bool,visible:Bool,turnKey:String? = nil,turnStart:Date? = nil) {
        let nextPath = conversation?.cwd ?? "", changed = conversationKey != conversation?.key || path != nextPath
        if changed {stop(); observation.stop(); hasGitBaseline = false; observationFailure = nil; snapshot = nil; failure = nil; popover.close(); editSignature = []; taskKey = nil}
        conversationKey = conversation?.key; path = nextPath
        let becameActive = visible && !active
        active = visible
        if !popover.isShown {updateDirectory()}
        guard visible else {deactivate(); return}
        let turn = turnKey == nil && turnStart == nil ? conversation?.turns.max(by:{$0.date < $1.date}) : conversation?.turns.first {((turnKey != nil && ($0.key == turnKey || $0.id == turnKey)) || (turnStart != nil && $0.date == turnStart))}
        let edits = turn?.fileEdits ?? [], signature = edits.flatMap(\.signature)
        let changedEdits = signature != editSignature || taskKey != turn?.key
        let notifyEdits = !changed && !becameActive && changedEdits && (signature != editSignature)
        editSignature = signature; taskKey = turn?.key
        if changed || changedEdits || becameActive {
            updateChanges(edits)
            if popover.isShown && showsChanges {presentPopoverContent()}
        }
        let ended = wasExecuting && !executing; wasExecuting = executing
        if changed || becameActive || ended {refreshGit()}
        else if changedEdits {scheduleRefresh()}
        if changed || changedEdits || becameActive {notifyLayoutChange()}
        if notifyEdits {onContentChange()}
    }
    private func notifyLayoutChange() {if !popover.isShown {onStatusChange()}}
    func deactivate() {active = false; stop(); observation.stop(); hasGitBaseline = false; observationFailure = nil; snapshot = nil; failure = nil; fileEdits = []; git.isHidden = true; changes.isHidden = true; popover.close()}
    private func stop() {pending?.cancel(); pending = nil; request?.cancel(); request = nil; refreshAgain = false}
    deinit {stop(); if let windowObserver {NotificationCenter.default.removeObserver(windowObserver)}}
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
        let text = NSMutableAttributedString(string:"\(edits.count)",attributes:[.font:changes.font!,.foregroundColor:NSColor.secondaryLabelColor])
        if !known.isEmpty {
            text.append(NSAttributedString(string:" "))
            text.append(FileEditRendering.counts(.init(added:added,removed:removed),font:changes.font!))
            if known.count < edits.count {text.append(NSAttributedString(string:" · 部分",attributes:[.foregroundColor:NSColor.secondaryLabelColor]))}
        }
        text.addAttribute(.font,value:changes.font!,range:NSRange(location:0,length:text.length))
        changes.attributedTitle = text
        let description = "本轮修改 \(edits.count) 个文件。"+(known.isEmpty ? "" : "累计新增 \(added) 行、删除 \(removed) 行。")+(known.count < edits.count ? "\n\(edits.count-known.count) 个文件未提供行数。" : "")
        changes.setAccessibilityValue(description)
    }
    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pending = nil; self?.refreshGit() }
        pending = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    func refreshGit() {
        guard active,!path.isEmpty else {git.isHidden = true; return}
        pending?.cancel(); pending = nil
        // 合并查询中到达的事件，完成后补查一次，不反复取消同一请求。
        guard request == nil else {refreshAgain = true; return}
        let oldSnapshot = snapshot, oldFailure = failure, oldObservationFailure = observationFailure
        let hadBaseline = hasGitBaseline
        let query = GitWorkspaceRequest(); request = query
        if !hasGitBaseline && !popover.isShown {
            git.isHidden = false; git.image = sourceIcon(github:false)
            git.title = "读取中…"; git.contentTintColor = .secondaryLabelColor
        }
        (popover.contentViewController as? GitWorkspaceDetails)?.setLoading(true)
        query.start(directory:path) { [weak self,weak query] result in
            guard let self,let query,self.active,self.request === query else {return}
            self.request = nil
            var meaningful = false
            switch result {
            case .success(let value):
                meaningful = self.hasGitBaseline && oldSnapshot != value
                self.hasGitBaseline = true; self.snapshot = value; self.failure = nil
                do {
                    try self.observation.update(paths:value?.observationPaths ?? [])
                    self.observationFailure = nil
                } catch {self.observationFailure = error.localizedDescription}
            case .failure(let error):self.failure = error.localizedDescription
            }
            let changed = !hadBaseline || oldSnapshot != self.snapshot || oldFailure != self.failure || oldObservationFailure != self.observationFailure
            (self.popover.contentViewController as? GitWorkspaceDetails)?.setLoading(false)
            if self.popover.isShown {
                if !self.showsChanges && changed {self.presentPopoverContent()}
            } else {
                self.presentStatus(); self.updateDirectory()
                if changed {self.onStatusChange()}
            }
            if meaningful {self.onContentChange()}
            if self.refreshAgain {self.refreshAgain = false; self.scheduleRefresh()}
        }
    }
    private func presentStatus() {
        git.isHidden = snapshot == nil && failure == nil
        if failure != nil || snapshot == nil {
            git.image = sourceIcon(github:false); git.title = "读取失败"; git.contentTintColor = .systemOrange
            git.setAccessibilityValue(failure ?? "Git 状态读取失败"); return
        }
        guard let snapshot else {return}
        git.image = sourceIcon(github:snapshot.isGitHub)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string:snapshot.title+(snapshot.initial ? " · 首次提交前" : "")))
        if let operation = snapshot.operation {text.append(NSAttributedString(string:" · "+operation))}
        text.append(NSAttributedString(string:"  "))
        text.append(GitStatusText.render(snapshot,compact:true,font:git.font!))
        text.addAttribute(.font,value:git.font!,range:NSRange(location:0,length:text.length))
        git.attributedTitle = text; git.contentTintColor = .secondaryLabelColor
        let tracking = snapshot.upstream.map {"上游："+$0+" · 领先 \(snapshot.ahead)，落后 \(snapshot.behind)（本机记录）"} ?? "未设置上游"
        git.setAccessibilityValue(snapshot.title+"，"+snapshot.summary+"，"+tracking)
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
        popoverDismissal.start(for:popover)
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
        let content = GitWorkspaceDetails(snapshot:snapshot,failure:failure ?? observationFailure,loading:request != nil)
        content.onRefresh = { [weak self] in
            guard let self else {return}
            self.refreshGit()
        }
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
    private var loading:Bool
    private var refreshButton:NSButton?
    func setLoading(_ loading:Bool) {
        self.loading = loading
        refreshButton?.isEnabled = !loading
        refreshButton?.title = loading ? "刷新中…" : "刷新"
    }
    private var rows = [Row]()
    private let table = WorkspaceFileTable()
    var onRefresh:() -> Void = {}
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
    init(snapshot:GitWorkspaceStatus?,failure:String?,loading:Bool) {
        self.snapshot = snapshot; self.failure = failure; self.loading = loading
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
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        let heading = NSTextField(labelWithString:snapshot?.title ?? "Git 工作区")
        heading.font = .systemFont(ofSize:13,weight:.semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let source = NSImageView(image:snapshot?.isGitHub == true ? GitIcons.github : GitIcons.git)
        source.imageScaling = .scaleProportionallyDown; source.contentTintColor = .secondaryLabelColor
        let title = NSStackView(views:[source,heading]); title.alignment = .centerY; title.spacing = 6
        NSLayoutConstraint.activate([source.widthAnchor.constraint(equalToConstant:16),source.heightAnchor.constraint(equalToConstant:16)])
        let refresh = ActionButton("刷新") { [weak self] in self?.onRefresh() }
        refreshButton = refresh
        refresh.widthAnchor.constraint(greaterThanOrEqualToConstant:70).isActive = true
        let top = NSStackView(views:[title,NSView(),refresh]); top.alignment = .centerY; top.spacing = 12
        stack.addArrangedSubview(top)
        refresh.isEnabled = !loading
        if loading {refresh.title = "刷新中…"}
        if let failure,snapshot != nil {
            let error = NSTextField(wrappingLabelWithString:failure); error.textColor = .systemOrange
            error.font = .systemFont(ofSize:11); stack.addArrangedSubview(error)
        }
        func label(_ value:String) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString:value)
            field.font = .systemFont(ofSize:11); field.textColor = .labelColor
            field.isSelectable = true; return field
        }
        func metadata(_ title:String,_ value:NSView) {
            let caption = NSTextField(labelWithString:title)
            caption.font = .systemFont(ofSize:11); caption.textColor = .labelColor
            caption.widthAnchor.constraint(equalToConstant:40).isActive = true
            value.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            let row = NSStackView(views:[caption,value]); row.alignment = .firstBaseline; row.spacing = 6
            row.distribution = .fill; stack.addArrangedSubview(row)
            value.setContentHuggingPriority(.defaultLow,for:.horizontal)
        }
        if let snapshot {
            let workspace = WorkspaceLinkButton(); workspace.font = .systemFont(ofSize:11)
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
            let upstream = label("未设置")
            if snapshot.upstream != nil {
                let tracking = GitStatusText.tracking(snapshot,font:upstream.font!)
                upstream.attributedStringValue = tracking.attributedSubstring(from:NSRange(location:3,length:tracking.length-3))
            }
            metadata("上游",upstream)
            var states = [String]()
            if snapshot.detached {states.append("HEAD 已分离")}
            if snapshot.initial {states.append("尚无提交记录")}
            if let operation = snapshot.operation {states.append(operation)}
            if snapshot.stashes > 0 {states.append("暂存栈 \(snapshot.stashes) 份")}
            if !states.isEmpty {stack.addArrangedSubview(label(states.joined(separator:" · ")))}
            if rows.isEmpty {
                let clean = label("工作区干净"); clean.textColor = .systemGreen
                stack.addArrangedSubview(clean)
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
                guard let self,self.rows.indices.contains(row),case .file(let entry) = self.rows[row],let root = self.snapshot?.root else {return nil}
                return URL(fileURLWithPath:root,isDirectory:true).appendingPathComponent(entry.path)
            }
            table.setAccessibilityLabel("Git 文件状态，双击在访达中显示，右键显示文件操作")
            scroll.documentView = table; stack.addArrangedSubview(scroll)
            scroll.heightAnchor.constraint(equalToConstant:min(300,rows.indices.reduce(CGFloat.zero) {$0+rowHeight($1)})).isActive = true
        }
        view = NSView(); view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16),stack.widthAnchor.constraint(equalToConstant:420)])
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
            let text = NSTextField(labelWithString:group.rawValue+" · \(count)"); text.font = .systemFont(ofSize:11,weight:.semibold)
            text.textColor = GitStatusText.groups.first {$0.group == group}!.color
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
