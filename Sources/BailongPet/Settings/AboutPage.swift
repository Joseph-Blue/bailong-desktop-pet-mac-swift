import AppKit

// 设置“关于”页保留原有图标、版本、原生分页和富文本链接；架构取编译目标。
final class AboutPageController: NSViewController {
    private static let repositoryURL = URL(string:"https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift")!
    private var textViews = [NSTextView]()
    private let titleLabel = NSTextField(wrappingLabelWithString:"")
    private let appIcon = NSImageView()
    private let tabs = NSTabView()
    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon（arm64）"
        #elseif arch(x86_64)
        return "Intel（x86_64）"
        #else
        return "其他架构"
        #endif
    }

    init() {
        super.init(nibName:nil,bundle:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(updateAccent),name:AppAccent.didChange,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        view = NSView()
        buildContent()
    }

    private func buildContent() {
        let root = view
        let icon = appIcon
        icon.image = AppIcons.application
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = titleLabel
        updateIdentity()
        title.maximumNumberOfLines = 0; title.lineBreakMode = .byWordWrapping
        title.font = .systemFont(ofSize:23,weight:.semibold)
        title.alignment = .center
        let version = NSTextField(labelWithString:"版本 \(Paths.version) · \(Self.architecture)")
        version.font = .systemFont(ofSize:13)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        tabs.tabViewType = .topTabsBezelBorder; tabs.drawsBackground = false
        tabs.font = .systemFont(ofSize:13)
        for (identifier,label,text) in [("about","关于",aboutText()),("credits","来源与致谢",creditsText())] {
            let item = NSTabViewItem(identifier:identifier)
            item.label = label
            item.view = readingView(text)
            tabs.addTabViewItem(item)
        }
        for view in [icon,title,version,tabs] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo:root.topAnchor,constant:20),
            icon.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant:80), icon.heightAnchor.constraint(equalToConstant:80),
            title.topAnchor.constraint(equalTo:icon.bottomAnchor,constant:12),
            title.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo:root.leadingAnchor,constant:24),
            title.trailingAnchor.constraint(lessThanOrEqualTo:root.trailingAnchor,constant:-24),
            version.topAnchor.constraint(equalTo:title.bottomAnchor,constant:6),
            version.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            tabs.topAnchor.constraint(equalTo:version.bottomAnchor,constant:22),
            tabs.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),
            tabs.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),
            tabs.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-24)
        ])
    }

    func selectTab(_ identifier:String) {
        loadViewIfNeeded(); tabs.selectTabViewItem(withIdentifier:identifier)
    }

    private func readingView(_ content: NSAttributedString) -> NSScrollView {
        let scroll = GutterScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = LinkTextView(frame:NSRect(x:0,y:0,width:560,height:360))
        text.isEditable = false
        text.isSelectable = false
        // 说明文字不允许选中；链接通过点击手势打开，不依赖 NSTextView 的选择行为。
        text.addGestureRecognizer(NSClickGestureRecognizer(target:self,action:#selector(openTextLink(_:))))
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width:560,height:CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width:16,height:18)
        text.textStorage?.setAttributedString(content)
        textViews.append(text)
        scroll.documentView = text
        updateAccent()
        return scroll
    }

    @objc func updateIdentity() {
        let name = PetPreferences.shared.appName
        titleLabel.stringValue = name; titleLabel.hoverHelp = titleLabel.stringValue
        appIcon.setAccessibilityLabel(name+"应用图标")
    }

    @objc private func openTextLink(_ gesture: NSClickGestureRecognizer) {
        guard let text = gesture.view as? NSTextView,
              let layout = text.layoutManager, let container = text.textContainer,
              let storage = text.textStorage, storage.length > 0 else {return}
        let location = gesture.location(in:text), origin = text.textContainerOrigin
        let point = NSPoint(x:location.x-origin.x,y:location.y-origin.y)
        let glyph = layout.glyphIndex(for:point,in:container)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange:NSRange(location:glyph,length:1),in:container).contains(point) else {return}
        let character = layout.characterIndexForGlyph(at:glyph)
        if let url = storage.attribute(.link,at:character,effectiveRange:nil) as? URL {NSWorkspace.shared.open(url)}
    }

    @objc private func updateAccent() {
        for text in textViews {
            text.linkTextAttributes = LinkAppearance.attributes
            text.needsDisplay = true
        }
    }

    private func aboutText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("让白龙娘住进你的 Mac 桌面，陪你聊天、工作。她会播放动作、显示 Codex 任务进展，也能提醒你回答问题或确认操作。",to:text)
        paragraph("你可以给她起名字、修改台词，调整大小和气泡外观，在历史会话中查看之前的对话。聊天和任务功能需要本机安装 Codex。",to:text)
        paragraph("作者：Joseph Blue（约瑟Blue）。本项目在《GPT白龙娘动态桌宠》的基础上，为 Mac 重新开发，由本项目作者独立维护。感谢原作者 jingh12312-rgb（風-隐）带来的白龙娘。",to:text)
        link("项目主页与问题反馈",url:Self.repositoryURL.absoluteString,to:text)
        paragraph("想更新应用，可以打开设置中的“更新”，或前往下面的发布页下载。",to:text)
        link("下载与更新说明",url:UpdateChecker.releases.absoluteString,to:text)
        link("原作：GPT白龙娘动态桌宠 · jingh12312-rgb（風-隐）",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)
        return text
    }

    private func creditsText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("感谢原作者，以及帮助这个 Mac 版本完成的项目和工具。",to:text,color:.secondaryLabelColor)

        heading("原作 · GPT白龙娘动态桌宠",to:text)
        paragraph("作者：jingh12312-rgb（風-隐）。桌宠的互动方式和台词参考原作 v0.5.1；原作的使用说明与许可信息见仓库 README。",to:text)
        link("原作仓库与说明",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)

        heading("角色动画与应用图标",to:text)
        paragraph("角色动画来自原作 v0.5.1 发布包，应用图标取自角色画面。",to:text)

        heading("动画播放",to:text)
        paragraph("使用 macOS 自带的动画播放与图像处理功能，让角色周围保持透明。动画文件采用 Apple 的透明 HEVC 格式。",to:text)
        link("Apple 透明 HEVC 说明",url:"https://developer.apple.com/videos/play/wwdc2019/506/",to:text)

        heading("SQLite · 对话记录",to:text)
        paragraph("使用 macOS 自带的 SQLite 保存本机对话记录、读取 Codex 任务信息。SQLite 的代码和文档属于公有领域。",to:text)
        link("SQLite 官方版权说明",url:"https://www.sqlite.org/copyright.html",to:text)

        heading("macOS 界面设计参考 · macos-golden-gate-design",to:text)
        paragraph("界面设计参考 gambadio 的 macos-golden-gate-design，让设置和窗口更贴近 Mac 的使用习惯。该设计指南采用 MIT 许可证。",to:text)
        link("macos-golden-gate-design · GitHub",url:"https://github.com/gambadio/macos-golden-gate-design",to:text)

        heading("Mac 与 Codex",to:text)
        paragraph("应用用 Swift 和 AppKit 开发，窗口、菜单和设置使用 Mac 原生控件。聊天和任务由本机安装的 Codex 处理。",to:text)
        return text
    }

    private func paragraph(_ value: String,to text: NSMutableAttributedString,
                           color: NSColor = .labelColor,font: NSFont = .systemFont(ofSize:13)) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 12
        text.append(NSAttributedString(string:value+"\n",attributes:[.font:font,.foregroundColor:color,.paragraphStyle:style]))
    }
    private func heading(_ value: String,to text: NSMutableAttributedString) {
        paragraph(value,to:text,font:.systemFont(ofSize:15,weight:.semibold))
    }
    private func link(_ title: String,url: String,to text: NSMutableAttributedString) {
        let start = text.length
        paragraph(title,to:text)
        text.addAttributes(LinkAppearance.attributes(for:URL(string:url)!),range:NSRange(location:start,length:(title as NSString).length))
    }
}
