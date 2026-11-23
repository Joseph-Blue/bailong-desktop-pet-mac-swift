import AppKit

// 设置“关于”页保留原有图标、版本、原生分页和富文本链接；架构取编译目标。
final class AboutPageController: NSViewController {
    enum Tab: String, CaseIterable {
        case about, credits, thirdPartyNotices
        var title:String {L10n.text(.about,"aboutPage."+rawValue)}
    }

    private static let repositoryURL = URL(string:"https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift")!
    private static let thirdPartyNoticesURL = (Bundle.main.bundleURL.pathExtension == "app" ? Paths.resources : Paths.project)
        .appendingPathComponent("THIRD-PARTY-NOTICES.md")
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
        return L10n.text(.about,"aboutPage.tab.text")
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
        let version = NSTextField(labelWithString:L10n.format(.about,"aboutPage.version",String(describing:Paths.version),String(describing:Self.architecture)))
        version.font = .systemFont(ofSize:16)
        version.textColor = .labelColor
        version.alignment = .center
        let versionDetails = NSStackView(views:[version])
        versionDetails.orientation = .vertical
        versionDetails.alignment = .centerX
        versionDetails.spacing = 4
        let buildCommit = Paths.isReleaseBuild ? nil : Paths.localBuildCommit
        let buildType = Paths.isReleaseBuild ? L10n.text(.about,"aboutPage.buildType") : L10n.text(.about,"aboutPage.buildType.2")
        let buildLabel = NSTextField(labelWithString:buildCommit.map {"\(buildType) \($0.prefix(8))"} ?? buildType)
        buildLabel.font = .systemFont(ofSize:12)
        buildLabel.textColor = .secondaryLabelColor
        if let commit = buildCommit {
            let copy = HoverIconButton(symbol:"doc.on.doc",label:L10n.text(.about,"aboutPage.copy"))
            copy.bezelStyle = .inline
            copy.hoverHelp = L10n.text(.about,"aboutPage.buildContent.text")
            copy.widthAnchor.constraint(equalToConstant:20).isActive = true
            copy.heightAnchor.constraint(equalToConstant:20).isActive = true
            CopyFeedback.attach(to:copy) {commit}
            let commitRow = NSStackView(views:[buildLabel,copy])
            commitRow.alignment = .centerY
            commitRow.spacing = 4
            versionDetails.addArrangedSubview(commitRow)
        } else {
            versionDetails.addArrangedSubview(buildLabel)
        }

        tabs.tabViewType = .topTabsBezelBorder; tabs.drawsBackground = false
        tabs.font = .systemFont(ofSize:13)
        for tab in Tab.allCases {
            let item = NSTabViewItem(identifier:tab.rawValue)
            item.label = tab.title
            switch tab {
            case .about: item.view = readingView(aboutText())
            case .credits: item.view = readingView(creditsText())
            case .thirdPartyNotices: item.view = readingView(thirdPartyNoticesText(),selectable:true)
            }
            tabs.addTabViewItem(item)
        }
        for view in [icon,title,versionDetails,tabs] {
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
            versionDetails.topAnchor.constraint(equalTo:title.bottomAnchor,constant:6),
            versionDetails.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            tabs.topAnchor.constraint(equalTo:versionDetails.bottomAnchor,constant:10),
            tabs.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),
            tabs.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),
            tabs.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-24)
        ])
    }

    func selectTab(_ tab:Tab) {
        loadViewIfNeeded(); tabs.selectTabViewItem(withIdentifier:tab.rawValue)
    }

    private func thirdPartyNoticesText() -> NSAttributedString {
        do {
            let source = try String(contentsOf:Self.thirdPartyNoticesURL,encoding:.utf8)
            return MarkdownText.render(source,font:.systemFont(ofSize:13))
        } catch {
            let text = NSMutableAttributedString()
            paragraph(L10n.format(.about,"aboutPage.thirdPartyNoticesText.paragraph",String(describing:error.localizedDescription)),to:text)
            return text
        }
    }

    private func readingView(_ content: NSAttributedString,selectable:Bool = false) -> NSScrollView {
        let scroll = GutterScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = LinkTextView(frame:NSRect(x:0,y:0,width:560,height:360))
        text.isEditable = false
        text.isSelectable = selectable
        if !selectable {
            text.addGestureRecognizer(NSClickGestureRecognizer(target:self,action:#selector(openTextLink(_:))))
        }
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
        appIcon.setAccessibilityLabel(name+L10n.text(.about,"aboutPage.updateIdentity.text"))
    }

    @objc private func openTextLink(_ gesture: NSClickGestureRecognizer) {
        guard let text = gesture.view as? NSTextView,
              let url = LinkAppearance.link(at:gesture.location(in:text),in:text)?.value as? URL else {return}
        if !NSWorkspace.shared.open(url) {showError(L10n.text(.about,"aboutPage.openTextLink.error"),PetFailure(message:url.absoluteString))}
    }

    @objc private func updateAccent() {
        for text in textViews {
            text.linkTextAttributes = LinkAppearance.attributes
            text.needsDisplay = true
        }
    }

    private func aboutText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph(L10n.text(.about,"aboutPage.aboutText.paragraph"),to:text)
        paragraph(L10n.text(.about,"aboutPage.aboutText.paragraph.2"),to:text)
        paragraph(L10n.text(.about,"aboutPage.aboutText.paragraph.3"),to:text)
        link(L10n.text(.about,"aboutPage.aboutText.text"),url:Self.repositoryURL.absoluteString,to:text)
        paragraph(L10n.text(.about,"aboutPage.aboutText.paragraph.4"),to:text)
        link(L10n.text(.about,"aboutPage.aboutText.text.2"),url:UpdateChecker.releases.absoluteString,to:text)
        link(L10n.text(.about,"aboutPage.aboutText.text.3"),url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)
        return text
    }

    private func creditsText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph"),to:text,color:.secondaryLabelColor)

        heading(L10n.text(.about,"aboutPage.creditsText.heading"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.2"),to:text)
        link(L10n.text(.about,"aboutPage.creditsText.text"),url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.2"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.3"),to:text)
        link("bailong-desktop-pet-english · GitHub",url:"https://github.com/ruyeli/bailong-desktop-pet-english",to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.3"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.4"),to:text)
        link("bailong-desktop-pet-optimization · GitHub",url:"https://github.com/moon135246/bailong-desktop-pet-optimization",to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.4"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.5"),to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.5"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.6"),to:text)
        link(L10n.text(.about,"aboutPage.creditsText.text.2"),url:"https://developer.apple.com/videos/play/wwdc2019/506/",to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.6"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.7"),to:text)
        link(L10n.text(.about,"aboutPage.creditsText.text.3"),url:"https://www.sqlite.org/copyright.html",to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.7"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.8"),to:text)
        link("macos-golden-gate-design · GitHub",url:"https://github.com/gambadio/macos-golden-gate-design",to:text)

        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.9"),to:text,links:[
            ("bash-git-prompt","https://github.com/magicmonty/bash-git-prompt"),
            ("Powerlevel10k","https://github.com/romkatv/powerlevel10k"),
        ])

        heading(L10n.text(.about,"aboutPage.creditsText.heading.8"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.10"),to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.9"),to:text)
        link("SF Symbols · Apple",url:"https://developer.apple.com/sf-symbols/",to:text)
        link(L10n.text(.about,"aboutPage.creditsText.text.6"),url:"https://lucide.dev/icons/git-branch",to:text)
        link("GitHub、GitLab · Lucide Brands（ISC）",url:"https://github.com/azirali/lucide-brands",to:text)
        link("Gitee · Remix Icon（Remix Icon License v1.0）",url:"https://github.com/Remix-Design/RemixIcon/blob/master/icons/Logos/gitee-line.svg",to:text)
        link("Gitea、Hugging Face · Icon Monks（MIT）",url:"https://github.com/designmonks-llc/icon-monks",to:text)
        link(L10n.text(.about,"aboutPage.labels.text"),url:"https://github.com/simple-icons/simple-icons/blob/develop/icons/forgejo.svg",to:text)
        link(L10n.text(.about,"aboutPage.creditsText.text.8"),url:"https://openai.com/brand/",to:text)

        heading(L10n.text(.about,"aboutPage.creditsText.heading.10"),to:text)
        paragraph(L10n.text(.about,"aboutPage.creditsText.paragraph.11"),to:text)
        return text
    }

    private func paragraph(_ value: String,to text: NSMutableAttributedString,
                           color: NSColor = .labelColor,font: NSFont = .systemFont(ofSize:13),
                           links:[(title:String,url:String)] = []) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 12
        let start = text.length
        text.append(NSAttributedString(string:value+"\n",attributes:[.font:font,.foregroundColor:color,.paragraphStyle:style]))
        for (title,url) in links {
            let range = NSRange(value.range(of:title)!,in:value)
            text.addAttributes(LinkAppearance.attributes(for:URL(string:url)!),range:NSRange(location:start+range.location,length:range.length))
        }
    }
    private func heading(_ value: String,to text: NSMutableAttributedString) {
        paragraph(value,to:text,font:.systemFont(ofSize:15,weight:.semibold))
    }
    private func link(_ title: String,url: String,to text: NSMutableAttributedString) {
        paragraph(title,to:text,links:[(title,url)])
    }
}
