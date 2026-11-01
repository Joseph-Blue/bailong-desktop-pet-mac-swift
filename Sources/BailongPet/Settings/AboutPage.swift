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

        tabs.tabViewType = .topTabsBezelBorder
        tabs.font = .systemFont(ofSize:13)
        for (identifier,label,text) in [("about","关于",aboutText()),("credits","开源项目、技术栈与致谢",creditsText())] {
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

    func selectTab(_ identifier:String) {loadViewIfNeeded(); tabs.selectTabViewItem(withIdentifier:identifier)}

    private func readingView(_ content: NSAttributedString) -> NSScrollView {
        let scroll = GutterScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = AppTextView(frame:NSRect(x:0,y:0,width:560,height:360))
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
            text.linkTextAttributes = [.foregroundColor:AppAccent.color,.underlineStyle:NSUnderlineStyle.single.rawValue]
            text.needsDisplay = true
        }
    }

    private func aboutText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("基于 jingh12312-rgb 的《GPT白龙娘动态桌宠》，进行非官方 macOS 移植及 Swift + AppKit 原生重写，独立维护。",to:text)
        paragraph("使用 Swift + AppKit 构建原生设置、历史对话与任务交互，透明动画由 Apple 系统框架播放。支持自定义台词、消息外观、720×720 原画、运行统计及本机历史管理。",to:text)
        link("本项目公开仓库 · GitHub",url:Self.repositoryURL.absoluteString,to:text)
        paragraph("对话功能连接本机 Codex，支持桌宠内发起任务与观察桌面端任务。更新入口位于设置的“更新”页及应用菜单，通过 GitHub 正式发布检查版本。",to:text)
        link("GitHub 发布与更新说明",url:UpdateChecker.releases.absoluteString,to:text)
        link("原作：GPT白龙娘动态桌宠 · jingh12312-rgb",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)
        return text
    }

    private func creditsText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("感谢原作者及以下项目。本页分别记录原作、素材和软件组件的来源；它们各自适用的许可并不相同。",to:text,color:.secondaryLabelColor)

        heading("原作 · GPT白龙娘动态桌宠",to:text)
        paragraph("作者：jingh12312-rgb。行为与文案参考 v0.5.1 源码。原作 README 声明尚未指定开源许可证。",to:text)
        link("原作仓库与说明",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)

        heading("角色动画与应用图标",to:text)
        paragraph("角色动画与应用图标来自原作者 v0.5.1 发布包。",to:text)

        heading("原生透明动画",to:text)
        paragraph("角色动画使用 HEVC with Alpha，运行时通过 macOS 的 AVFoundation 与 Core Image 解码和缩放。PNG 素材接入由 AVAssetWriter 和 Apple avconvert 完成。",to:text)
        link("Apple 透明 HEVC 说明",url:"https://developer.apple.com/videos/play/wwdc2019/506/",to:text)

        heading("SQLite · 本机任务记录读取",to:text)
        paragraph("使用 macOS 提供的 SQLite 动态库，不另附数据库运行库。SQLite 项目声明其发布代码与文档属于公有领域。",to:text)
        link("SQLite 官方版权说明",url:"https://www.sqlite.org/copyright.html",to:text)

        heading("macOS 界面设计参考 · macos-golden-gate-design",to:text)
        paragraph("设置、侧栏、工具栏与原生控件布局参考 gambadio 的 macos-golden-gate-design 技能。该技能声明采用 MIT 许可证，用于开发阶段的设计与审查。",to:text)
        link("macos-golden-gate-design · GitHub",url:"https://github.com/gambadio/macos-golden-gate-design",to:text)

        heading("开发技术与系统服务",to:text)
        paragraph("使用 Swift、AppKit、Foundation、AVFoundation、Core Image、Core Graphics 及 macOS 系统符号构建原生界面。这些系统技术单独列出，不将 AppKit 标注为第三方开源组件。对话功能调用用户已安装的 Codex，不随本应用分发 Codex。",to:text)
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
        text.addAttribute(.link,value:URL(string:url)!,range:NSRange(location:start,length:(title as NSString).length))
    }
}
