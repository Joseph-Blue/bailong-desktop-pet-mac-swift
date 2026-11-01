import AppKit

// 仅使用明确列出的诊断字段，不将错误 userInfo、对话、路径或凭证拼入报告。
struct RecoveryReport {
    let title: String
    let message: String
    let module: String
    let operation: String
    var error: Error?
    var facts: [String] = []
    let date = Date()
    var text: String {
        var lines = [PetPreferences.shared.appName+"错误报告", "版本："+Paths.version,
                     "系统："+ProcessInfo.processInfo.operatingSystemVersionString,
                     "架构："+architecture, "时间："+date.formatted(date:.numeric,time:.standard),
                     "模块："+module, "操作："+operation, "状态："+title, "说明："+message]
        if let error {
            let value = error as NSError
            let allowed = [NSCocoaErrorDomain,NSPOSIXErrorDomain,NSURLErrorDomain,"AVFoundationErrorDomain","NSOSStatusErrorDomain"]
            lines += ["错误类型："+String(reflecting:type(of:error)),
                      "错误域："+(allowed.contains(value.domain) ? value.domain : "应用错误"),"错误码：\(value.code)"]
            if let settings = error as? PlaybackSettingsError {lines.append("无效播放设置："+settings.key)}
            if let decoding = error as? DecodingError {
                switch decoding {
                case .dataCorrupted: lines.append("数据状态：内容损坏或格式错误")
                case .keyNotFound: lines.append("数据状态：缺少必需字段")
                case .typeMismatch: lines.append("数据状态：字段类型不符")
                case .valueNotFound: lines.append("数据状态：必需字段为空")
                @unknown default: lines.append("数据状态：解析未完成")
                }
            }
        }
        return (lines+facts).joined(separator:"\n")
    }
    private var architecture: String {
        #if arch(arm64)
        return "arm64 / Apple Silicon"
        #else
        return "x86_64 / Intel"
        #endif
    }
}

// 含退出按钮：Return 与小键盘 Enter 均不触发操作，Esc 仅收起窗口。
private final class RecoveryPanel: NSWindow {
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.type == .keyDown && [36,76].contains(event.keyCode) {return true}
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        if [36,76].contains(event.keyCode) {return}
        if event.keyCode == 53 {performClose(nil); return}
        super.keyDown(with:event)
    }
}

final class RecoveryWindow: NSObject, NSWindowDelegate {
    private static var windows = [String:RecoveryWindow]()
    static var quit: () -> Void = {NSApp.terminate(nil)}
    static func show(id:String, report:RecoveryReport, actionTitle:String, action:@escaping () -> Void) {
        let existed = windows[id] != nil
        let controller = windows[id] ?? RecoveryWindow()
        windows[id] = controller
        controller.heading.stringValue = report.title; controller.explanation.stringValue = report.message
        controller.report.string = report.text; controller.retry.title = actionTitle
        controller.recoveryAction = action; controller.retry.isEnabled = true
        controller.activity.stringValue = controller.retrying ? "重试未完成 · "+report.date.formatted(date:.omitted,time:.standard) : ""
        controller.retrying = false
        controller.copy.title = "拷贝报告"
        if !existed {controller.present(takeFocus:false)}
    }
    static func resolve(_ id:String) {
        guard let controller = windows.removeValue(forKey:id) else {return}
        controller.window.close()
    }
    static func revealAll() {
        let controllers = Array(windows.values)
        for controller in controllers {controller.present(takeFocus:false)}
        controllers.first?.present(takeFocus:true)
    }
    static var hasIssues: Bool {!windows.isEmpty}

    private let window = RecoveryPanel(contentRect:NSRect(x:0,y:0,width:680,height:480),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    private let heading = label("",bold:true), explanation = label("")
    private let report = AppTextView()
    private var retry: ActionButton!, copy: ActionButton!
    private let activity = NSTextField(labelWithString:"")
    private var recoveryAction:() -> Void = {}
    private var retrying = false
    override private init() {
        super.init()
        window.title = "错误与恢复"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentMinSize = NSSize(width:580,height:420); window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let root = NSView(); window.contentView = root
        let icon = NSImageView(image:NSImage(systemSymbolName:"exclamationmark.triangle",accessibilityDescription:"运行错误")!)
        icon.contentTintColor = .systemRed; icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant:28).isActive = true; icon.heightAnchor.constraint(equalToConstant:28).isActive = true
        heading.font = .systemFont(ofSize:19,weight:.semibold)
        explanation.font = .systemFont(ofSize:13); explanation.textColor = .secondaryLabelColor
        let description = NSStackView(views:[heading,explanation]); description.orientation = .vertical; description.alignment = .leading; description.spacing = 8
        let header = NSStackView(views:[icon,description]); header.alignment = .top; header.spacing = 12
        description.widthAnchor.constraint(equalTo:header.widthAnchor,constant:-40).isActive = true
        for field in [heading,explanation] {
            field.widthAnchor.constraint(equalTo:description.widthAnchor).isActive = true
            field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        }
        let caption = label("错误报告",bold:true)
        activity.font = .systemFont(ofSize:11); activity.textColor = .secondaryLabelColor
        let reportHeader = NSStackView(views:[caption,NSView(),activity]); reportHeader.alignment = .firstBaseline; reportHeader.spacing = 12
        report.isEditable = false; report.isSelectable = true; report.drawsBackground = true
        report.backgroundColor = .textBackgroundColor; report.textColor = .labelColor
        report.font = .monospacedSystemFont(ofSize:12,weight:.regular); report.textContainerInset = NSSize(width:12,height:12)
        report.isVerticallyResizable = true; report.isHorizontallyResizable = false; report.autoresizingMask = [.width]
        report.textContainer?.widthTracksTextView = true
        report.minSize = .zero; report.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        report.setAccessibilityLabel("可拷贝的错误报告")
        let scroll = GutterScrollView(); scroll.documentView = report; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor; scroll.borderType = .noBorder
        copy = ActionButton("拷贝报告") { [weak self] in
            guard let self else {return}
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(self.report.string,forType:.string) {self.copy.title = "已拷贝"}
        }
        copy.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil); copy.imagePosition = .imageLeading
        let issue = ActionButton("反馈 Issue…") {NSWorkspace.shared.open(UpdateChecker.repository.appendingPathComponent("issues/new"))}
        issue.image = NSImage(systemSymbolName:"arrow.up.right.square",accessibilityDescription:nil); issue.imagePosition = .imageLeading
        issue.hoverHelp = "打开项目仓库的新建 Issue 页面"
        retry = ActionButton("") { [weak self] in self?.retryRecovery() }; retry.keepsAccentWhenInactive = true; retry.emphasize()
        let quit = SettingsFooterButton(title:"退出程序",target:self,action:#selector(exitApplication))
        quit.hasDestructiveAction = true; quit.isBordered = false
        for button in [copy!,issue,retry!] {
            button.configureFlexible(font:.systemFont(ofSize:13))
            button.heightAnchor.constraint(equalToConstant:32).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant:108).isActive = true
        }
        quit.font = .systemFont(ofSize:13)
        quit.widthAnchor.constraint(equalTo:retry.widthAnchor).isActive = true
        quit.heightAnchor.constraint(equalTo:retry.heightAnchor).isActive = true
        for button in [copy!,issue,retry!,quit] as [NSButton] {button.keyEquivalent = ""}
        window.defaultButtonCell = nil
        let footer = NSStackView(views:[copy!,issue,NSView(),quit,retry!]); footer.spacing = 8; footer.alignment = .centerY; footer.distribution = .fill
        for view in [header,reportHeader,scroll,footer] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
            view.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24).isActive = true
            view.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24).isActive = true
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo:root.topAnchor,constant:24),
            reportHeader.topAnchor.constraint(equalTo:header.bottomAnchor,constant:20),
            scroll.topAnchor.constraint(equalTo:reportHeader.bottomAnchor,constant:8),
            scroll.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:100),
            footer.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20),footer.heightAnchor.constraint(equalToConstant:32)
        ])
        window.center()
    }
    private func retryRecovery() {
        guard !retrying else {return}
        retrying = true; retry.isEnabled = false; activity.stringValue = "正在处理…"
        window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        // 成功由 resolve 收起窗口，失败由 show 更新报告及重新启用按钮；不伪造恢复成功。
        DispatchQueue.main.async { [weak self] in self?.recoveryAction() }
    }
    private func present(takeFocus:Bool) {
        NSApp.setActivationPolicy(.regular)
        NSApp.addWindowsItem(window,title:window.title,filename:false)
        if takeFocus {
            if window.isMiniaturized {window.deminiaturize(nil)}
            if !NSApp.isActive {NSApp.activate(ignoringOtherApps:true)}; window.makeKeyAndOrderFront(nil)
        } else if !window.isVisible && !window.isMiniaturized {window.orderFront(nil)}
    }
    @objc private func exitApplication() {Self.quit()}
    func windowWillClose(_ notification:Notification) {NSApp.removeWindowsItem(window)}
}
