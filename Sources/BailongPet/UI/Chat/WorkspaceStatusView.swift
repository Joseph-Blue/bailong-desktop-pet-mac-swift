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
            text.append(NSAttributedString(string:value,attributes:[.font:font,.foregroundColor:color]))
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
}

// 一条共用的次级信息行：目录入口、Git 摘要、本轮修改。只查询当前可见会话。
final class WorkspaceStatusView:NSStackView,NSPopoverDelegate {
    private let directory = WorkspaceLinkButton()
    private let git = HoverIconButton(symbol:"arrow.triangle.branch",label:"Git 状态"), changes = HoverIconButton(symbol:"doc",label:"本轮文件修改")
    private let popover = NSPopover()
    private var showsChanges = false, fileEdits = [FileEditSummary]()
    private var path = "", conversationKey:String?, taskKey:String?, wasExecuting = false
    private var editSignature = [String](), snapshot:GitWorkspaceStatus?, failure:String?
    private var request:GitWorkspaceRequest?, pending:DispatchWorkItem?
    private var active = false, windowObserver:NSObjectProtocol?
    var onOpen:(URL) -> Void = {_ in}
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
            button.heightAnchor.constraint(greaterThanOrEqualToConstant:24).isActive = true
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
    func update(conversation:Conversation?,executing:Bool,visible:Bool) {
        let nextPath = conversation?.cwd ?? "", changed = conversationKey != conversation?.key || path != nextPath
        if changed {stop(); snapshot = nil; failure = nil; popover.close(); editSignature = []; taskKey = nil}
        conversationKey = conversation?.key; path = nextPath
        let becameActive = visible && !active
        active = visible
        updateDirectory()
        guard visible else {stop(); snapshot = nil; fileEdits = []; return}
        let turn = conversation?.turns.max(by:{$0.date < $1.date})
        let edits = turn?.fileEdits ?? [], signature = edits.flatMap(\.signature)
        let changedEdits = signature != editSignature || taskKey != turn?.key
        editSignature = signature; taskKey = turn?.key
        if changed || changedEdits || becameActive {updateChanges(edits)}
        let ended = wasExecuting && !executing; wasExecuting = executing
        if changed || becameActive || ended {refreshGit()}
        else if changedEdits {scheduleRefresh()}
    }
    func deactivate() {active = false; stop(); snapshot = nil; fileEdits = []; popover.close()}
    private func stop() {pending?.cancel(); pending = nil; request?.cancel(); request = nil}
    deinit {stop(); if let windowObserver {NotificationCenter.default.removeObserver(windowObserver)}}
    private func updateDirectory() {
        let name = URL(fileURLWithPath:path).lastPathComponent
        let project = snapshot.map {URL(fileURLWithPath:$0.root).lastPathComponent}
        directory.update(path:path,displayName:project.flatMap {$0 == name ? nil : $0+" / "+name} ?? name)
    }
    private func updateChanges(_ edits:[FileEditSummary]) {
        fileEdits = edits
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
        if popover.isShown && showsChanges {presentPopoverContent()}
    }
    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshGit() }
        pending = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    func refreshGit() {
        guard active,!path.isEmpty else {git.isHidden = true; return}
        stop(); failure = nil
        let query = GitWorkspaceRequest(); request = query
        git.isHidden = false; git.image = snapshot?.isGitHub == true ? GitIcons.github : GitIcons.git
        git.title = snapshot.map {$0.title+"  …"} ?? "读取中…"; git.contentTintColor = .secondaryLabelColor
        git.setAccessibilityValue("正在读取 Git 状态")
        query.start(directory:path) { [weak self,weak query] result in
            guard let self,let query,self.active,self.request === query else {return}
            self.request = nil
            switch result {
            case .success(let value):self.snapshot = value
            case .failure(let error):self.snapshot = nil; self.failure = error.localizedDescription
            }
            self.presentStatus(); self.updateDirectory()
            if self.popover.isShown && !self.showsChanges {self.presentPopoverContent()}
        }
    }
    private func presentStatus() {
        git.isHidden = snapshot == nil && failure == nil
        guard let snapshot else {
            git.image = GitIcons.git; git.title = "读取失败"; git.contentTintColor = .systemOrange
            git.setAccessibilityValue(failure ?? "Git 状态读取失败"); return
        }
        git.image = snapshot.isGitHub ? GitIcons.github : GitIcons.git
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
    }
    private func presentPopoverContent() {
        let content:NSViewController = showsChanges ? TurnFileEditsDetails(edits:fileEdits,directory:path) : makeDetails()
        _ = content.view; popover.contentViewController = content; popover.contentSize = content.preferredContentSize
    }
    private func makeDetails() -> GitWorkspaceDetails {
        let content = GitWorkspaceDetails(snapshot:snapshot,failure:failure,loading:request != nil)
        content.onRefresh = { [weak self] in self?.popover.close(); self?.refreshGit() }
        return content
    }
    func popoverDidClose(_ notification:Notification) {popover.contentViewController = nil}
    func containsInteraction(at point:NSPoint) -> Bool {popover.isShown && popover.contentViewController?.view.window?.frame.contains(point) == true}
}

private final class GitWorkspaceDetails:NSViewController,NSTableViewDataSource,NSTableViewDelegate {
    private enum Row {case heading(GitWorkspaceStatus.Group,Int), file(GitWorkspaceStatus.Entry)}
    private let snapshot:GitWorkspaceStatus?, failure:String?, loading:Bool
    private var rows = [Row]()
    private let table = WorkspaceFileTable()
    var onRefresh:() -> Void = {}
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
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        let heading = NSTextField(labelWithString:snapshot?.title ?? "Git 工作区")
        heading.font = .systemFont(ofSize:13,weight:.semibold)
        let refresh = ActionButton("刷新") { [weak self] in self?.onRefresh() }
        let top = NSStackView(views:[heading,NSView(),refresh]); top.spacing = 12
        stack.addArrangedSubview(top)
        let message:String
        if let snapshot {
            var lines = [snapshot.root,snapshot.summary]
            if snapshot.detached {lines.append("HEAD 已分离")}
            if snapshot.initial {lines.append("尚无提交记录")}
            if let operation = snapshot.operation {lines.append(operation)}
            if snapshot.remoteName == "." {lines.append("上游位于本地仓库")}
            else if let remote = snapshot.remoteName {lines.append("远端："+remote+(snapshot.remoteWebURL == nil ? " · "+[snapshot.remoteHost,snapshot.remoteRepository].compactMap {$0}.joined(separator:"/") : ""))}
            else {lines.append(snapshot.remoteNames.isEmpty ? "本地仓库 · 未配置远端" : "多个远端："+snapshot.remoteNames.joined(separator:"、"))}
            if let upstream = snapshot.upstream {lines.append("上游："+upstream+" · 领先 \(snapshot.ahead)，落后 \(snapshot.behind)（本机记录）")}
            else {lines.append("未设置上游")}
            message = lines.joined(separator:"\n")
        } else {message = failure ?? (loading ? "正在读取 Git 状态…" : "非 Git 工作区")}
        let note = NSTextField(wrappingLabelWithString:message); note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor; note.isSelectable = true
        if let snapshot {
            let text = NSMutableAttributedString(string:message,attributes:[.font:note.font!,.foregroundColor:NSColor.secondaryLabelColor])
            let range = NSRange(location:(snapshot.root as NSString).length+1,length:(snapshot.summary as NSString).length)
            text.replaceCharacters(in:range,with:GitStatusText.render(snapshot,compact:false,font:.systemFont(ofSize:11,weight:.semibold)))
            note.attributedStringValue = text
        }
        stack.addArrangedSubview(note)
        if let url = snapshot?.remoteWebURL {stack.addArrangedSubview(RepositoryLinkButton(url:url))}
        if !rows.isEmpty {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.verticalScrollElasticity = .allowed
            let column = NSTableColumn(identifier:.init("file")); column.resizingMask = .autoresizingMask
            table.addTableColumn(column); table.rowHeight = 26; table.delegate = self; table.dataSource = self
            table.fileURLForRow = { [weak self] row in
                guard let self,self.rows.indices.contains(row),case .file(let entry) = self.rows[row],let root = self.snapshot?.root else {return nil}
                return URL(fileURLWithPath:root,isDirectory:true).appendingPathComponent(entry.path)
            }
            table.setAccessibilityLabel("Git 文件状态，双击在访达中显示，右键显示文件操作")
            scroll.documentView = table; stack.addArrangedSubview(scroll)
            scroll.heightAnchor.constraint(equalToConstant:min(300,CGFloat(rows.count)*28)).isActive = true
        }
        view = NSView(); view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16),stack.widthAnchor.constraint(equalToConstant:420)])
        for row in stack.arrangedSubviews {row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        preferredContentSize = view.fittingSize
    }
    func numberOfRows(in tableView:NSTableView) -> Int {rows.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        switch rows[row] {
        case .heading(let group,let count):
            let text = NSTextField(labelWithString:group.rawValue+" · \(count)"); text.font = .systemFont(ofSize:11,weight:.semibold)
            text.textColor = GitStatusText.groups.first {$0.group == group}!.color; return text
        case .file(let entry):
            let (symbol,color) = WorkspaceFileRow.symbol(for:entry)
            return WorkspaceFileRow(title:entry.change+"  "+entry.path,symbol:symbol,color:color,detail:entry.originalPath.map {$0+" → "+entry.path} ?? entry.path)
        }
    }
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int) -> Bool {if case .file = rows[row] {return true}; return false}
}
