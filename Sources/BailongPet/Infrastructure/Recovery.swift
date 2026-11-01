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
        var lines = ["白龙娘桌宠错误报告", "版本："+Paths.version,
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
        controller.retry.callback = action; controller.retry.isEnabled = true
        controller.copy.title = "拷贝错误报告"
        if !existed {controller.present()}
    }
    static func resolve(_ id:String) {
        guard let controller = windows.removeValue(forKey:id) else {return}
        controller.window.close()
    }
    static func revealAll() {for controller in windows.values {controller.present()}}
    static var hasIssues: Bool {!windows.isEmpty}

    private let window = RecoveryPanel(contentRect:NSRect(x:0,y:0,width:680,height:440),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    private let heading = label("",bold:true), explanation = label("")
    private let report = AppTextView()
    private var retry: ActionButton!, copy: ActionButton!
    override private init() {
        super.init()
        window.title = "错误与恢复"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width:560,height:400); window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let root = NSView(); window.contentView = root
        let icon = NSImageView(image:NSImage(systemSymbolName:"exclamationmark.triangle",accessibilityDescription:"运行错误")!)
        icon.contentTintColor = .systemRed; icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant:32).isActive = true; icon.heightAnchor.constraint(equalToConstant:32).isActive = true
        heading.font = .systemFont(ofSize:20,weight:.semibold)
        explanation.font = .systemFont(ofSize:13); explanation.textColor = .secondaryLabelColor
        let description = NSStackView(views:[heading,explanation]); description.orientation = .vertical; description.alignment = .leading; description.spacing = 6
        let header = NSStackView(views:[icon,description]); header.alignment = .top; header.spacing = 12
        let caption = label("错误报告",bold:true)
        report.isEditable = false; report.isSelectable = true; report.drawsBackground = true
        report.backgroundColor = .textBackgroundColor; report.textColor = .labelColor
        report.font = .monospacedSystemFont(ofSize:12,weight:.regular); report.textContainerInset = NSSize(width:12,height:12)
        report.isVerticallyResizable = true; report.isHorizontallyResizable = false; report.autoresizingMask = [.width]
        report.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.documentView = report; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        copy = ActionButton("拷贝错误报告") { [weak self] in
            guard let self else {return}
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(self.report.string,forType:.string) {self.copy.title = "已拷贝"}
        }
        copy.image = NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil); copy.imagePosition = .imageLeading
        retry = ActionButton("") { }; retry.keepsAccentWhenInactive = true; retry.emphasize()
        let quit = SettingsFooterButton(title:"退出程序",target:self,action:#selector(exitApplication))
        quit.hasDestructiveAction = true; quit.isBordered = false; quit.keyEquivalent = ""
        quit.widthAnchor.constraint(equalToConstant:92).isActive = true; quit.heightAnchor.constraint(equalToConstant:30).isActive = true
        let footer = NSStackView(views:[copy,NSView(),retry,quit]); footer.spacing = 10
        let stack = NSStackView(views:[header,caption,scroll,footer]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:24),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-24)])
        for view in [header,scroll,footer] {view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        description.setContentHuggingPriority(.defaultLow,for:.horizontal)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:180).isActive = true
        scroll.setContentHuggingPriority(.defaultLow,for:.vertical)
        window.center()
    }
    private func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.addWindowsItem(window,title:window.title,filename:false)
        if window.isMiniaturized {window.deminiaturize(nil)}
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func exitApplication() {Self.quit()}
    func windowWillClose(_ notification:Notification) {NSApp.removeWindowsItem(window)}
}
