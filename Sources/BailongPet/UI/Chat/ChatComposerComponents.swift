import AppKit

// 纯展示组件：会话选择、设置与操作由调用方持有。
final class ChatModeControl: AccentSegmentedControl {
    var onSelect:(Int) -> Void = {_ in}
    init(labels:[String]) {
        super.init(frame:.zero)
        segmentCount = labels.count; trackingMode = .selectOne; segmentStyle = .rounded
        for (index,title) in labels.enumerated() {setLabel(title,forSegment:index)}
        selectedSegment = 0; target = self; action = #selector(changed)
        setAccessibilityLabel("对话类型")
        setContentHuggingPriority(.required,for:.horizontal)
    }
    required init?(coder:NSCoder) {fatalError()}
    func select(_ index:Int) {if selectedSegment != index {selectedSegment = index}}
    @objc private func changed() {onSelect(selectedSegment)}
}

final class ChatMetadataRow: NSStackView {
    static let captionWidth = ("工作区" as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width.rounded(.up)
    init(_ title:String,content:NSView,accessory:NSView? = nil,expandsContent:Bool = false) {
        super.init(frame:.zero)
        orientation = .horizontal; alignment = .centerY; distribution = .fill; spacing = 8
        let caption = NSTextField(labelWithString:title)
        caption.font = .systemFont(ofSize:12); caption.textColor = .secondaryLabelColor
        caption.setContentCompressionResistancePriority(.required,for:.horizontal)
        addArrangedSubview(caption); addArrangedSubview(content)
        caption.widthAnchor.constraint(equalToConstant:Self.captionWidth).isActive = true
        if let accessory {addArrangedSubview(accessory); accessory.setContentCompressionResistancePriority(.required,for:.horizontal)}
        if !expandsContent {addArrangedSubview(NSView()); content.setContentHuggingPriority(.defaultHigh,for:.horizontal)}
    }
    required init?(coder:NSCoder) {fatalError()}
}

// 临时输入与历史共用只读显示，不拥有连接、设置缓存或模型写入。
final class ChatReadOnlyModelField: ModelSummaryButton {
    override var preservesProviderIconColor:Bool {true}
    init() {
        super.init(frame:.zero)
        isEnabled = false
        image = NSImage(systemSymbolName:"lock",accessibilityDescription:"只读"); imagePosition = .imageTrailing
        setAccessibilityRole(.staticText)
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(settings:DesktopReply.Settings?,conversation:Conversation?,error:String?) {
        if let settings {
            let effort = settings.effort.map(ChatModelSettings.effortName) ?? "未提供"
            let provider = settings.modelProvider ?? conversation?.modelProvider
            let identity = provider.map {APIProviderDirectory.identity(id:$0)}
            let providerIcon = provider == "openai" ? nil : AppIcons.apiProvider(identity?.catalogID)
            let providerTitle = provider == nil ? "供应商未记录" : ModelPresentation.provider(provider,name:identity?.name,
                usesChatGPTAccount:conversation?.createdWithChatGPT == true)
            let providerSummary = provider == nil ? "供应商未记录" : ModelPresentation.provider(provider,name:identity?.summaryName,
                usesChatGPTAccount:conversation?.createdWithChatGPT == true)
            setSummary(ModelPresentation.summary(model:settings.model,effort:effort,provider:providerSummary)+" · 只读",
                lightning:CodexServiceTier.hasLightning(settings.serviceTier),providerIcon:providerIcon)
            let source = settings.effortFromHistory ? "思考等级来自会话记录。" : ""
            var help = "沿用 Codex 原会话设置，当前只读。"+source
            if let providerTitle {help += "\n供应商："+providerTitle}
            help += "\n模型："+settings.model+"\n思考等级："+effort
            if let tier = settings.serviceTier {help += "\n速度档位："+CodexServiceTier.displayName(tier)}
            hoverHelp = help
        } else {
            setSummary(error ?? "正在读取 Codex 会话设置…",lightning:false)
            setHoverHelp(title) { [weak self] in self?.hasTruncatedTitle == true }
        }
        setAccessibilityLabel("Codex 模型与思考等级，只读")
        setAccessibilityHelp(hoverHelp)
    }
}

final class ChatReplyPreview: NSTextField {
    private var sourceID:String?
    init() {
        super.init(frame:.zero)
        isEditable = false; isSelectable = false; isBezeled = false; drawsBackground = false
        font = .systemFont(ofSize:12); textColor = .secondaryLabelColor
        usesSingleLineMode = true; lineBreakMode = .byTruncatingTail
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(turn:Turn?) {
        let identity = turn?.bodyReference.id ?? ""
        guard sourceID != identity else {return}; sourceID = identity
        let body = turn?.bodyReference.value()
        let markdown = body.map {$0.final.isEmpty ? $0.messages : $0.final} ?? ""
        // 复用现有 Markdown 解析，仅生成显示摘要；历史仍保存原文。
        let plain = MarkdownText.render(markdown,font:font!).string.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        let excerpt = String(plain.prefix(180))+(plain.count > 180 ? "…" : "")
        stringValue = excerpt.isEmpty ? "" : "最近回复："+excerpt
        isHidden = excerpt.isEmpty
        let preview = plain.isEmpty ? nil : String(plain.prefix(200))+(plain.count > 200 ? "..." : "")
        let hasMore = plain.count > 180
        setHoverHelp(preview) { [weak self] in hasMore || self?.hasTruncatedText == true }
        setAccessibilityLabel(stringValue)
    }
}

// 链接只负责路径显示和用户点击，打开目录交给调用方，不读取文件或会话数据。
final class WorkspaceLinkButton: NSButton,LinkCursorControl {
    private static let middleTruncatingParagraph:NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        return paragraph.copy() as! NSParagraphStyle
    }()
    var emphasizesLink = true
    var usesMonochromeLink = false
    var onOpen:(URL) -> Void = {_ in}
    private var directory:URL?
    private var displayedPath:String?
    init() {
        super.init(frame:.zero)
        isBordered = false; alignment = .left; font = .systemFont(ofSize:13)
        focusRingType = .exterior; target = self; action = #selector(openDirectory)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        setAccessibilityLabel("在访达中打开工作区")
        NotificationCenter.default.addObserver(self,selector:#selector(accentChanged),name:AppAccent.didChange,object:nil)
        update(path:"")
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func accentChanged() {needsDisplay = true}
    func update(path:String,displayName:String? = nil) {
        let color = path.isEmpty || !emphasizesLink ? NSColor.secondaryLabelColor : usesMonochromeLink ? .labelColor : AppAccent.foregroundColor
        let text = path.isEmpty ? "未选择工作区" : displayName ?? (path as NSString).abbreviatingWithTildeInPath
        guard displayedPath != path || attributedTitle.string != text || attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor != color || attributedTitle.attribute(.font,at:0,effectiveRange:nil) as? NSFont != font else {return}
        displayedPath = path
        directory = path.isEmpty ? nil : URL(fileURLWithPath:path,isDirectory:true)
        isEnabled = directory != nil
        var attributes:[NSAttributedString.Key:Any] = [.font:font!, .paragraphStyle:Self.middleTruncatingParagraph]
        if isEnabled && emphasizesLink {attributes.merge(LinkAppearance.attributes) {_,link in link}}
        attributes[.foregroundColor] = color
        attributedTitle = NSAttributedString(string:text,attributes:attributes)
        hoverHelp = path.isEmpty ? nil : path
        setAccessibilityValue(path)
    }
    @objc private func openDirectory() {if let directory {onOpen(directory)}}
    override func resetCursorRects() {super.resetCursorRects(); if isEnabled {LinkAppearance.addCursorRect(bounds,to:self)}}
}
