import AppKit

enum AppIcons {
    static var application: NSImage? {NSImage(contentsOf:Paths.resources.appendingPathComponent("BailongPet.icns"))}
    private static let about = AboutWindowController()
    static func showAbout() {
        about.updateIdentity(); about.showWindow(nil)
        about.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    // 保留素材的透明轮廓，菜单栏交由系统按背景绘制为白/黑剪影。
    static func petSilhouette(_ frame: Frame) -> NSImage {
        let crop = frame.image.cropping(to:frame.bounds.integral) ?? frame.image
        let source = NSImage(cgImage:crop,size:NSSize(width:crop.width,height:crop.height))
        let image = NSImage(size:NSSize(width:18,height:18),flipped:false) { rect in
            let scale = min(rect.width/source.size.width,rect.height/source.size.height)
            let size = NSSize(width:source.size.width*scale,height:source.size.height*scale)
            let fitted = NSRect(x:(rect.width-size.width)/2,y:(rect.height-size.height)/2,width:size.width,height:size.height)
            source.draw(in:fitted)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .sourceIn
            NSColor.white.setFill(); NSBezierPath(rect:fitted).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = PetPreferences.shared.appName
        return image
    }
    static let finder: NSImage = {
        let image = NSImage(size:NSSize(width:22,height:22),flipped:false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect:NSRect(x:2,y:2,width:18,height:18),xRadius:3,yRadius:3)
            outline.lineWidth = 1.5; outline.stroke()
            let face = NSBezierPath(); face.lineWidth = 1.4; face.lineCapStyle = .round; face.lineJoinStyle = .round
            face.move(to:NSPoint(x:11.5,y:19.5)); face.curve(to:NSPoint(x:9.5,y:10),controlPoint1:NSPoint(x:11.5,y:16),controlPoint2:NSPoint(x:10,y:13))
            face.line(to:NSPoint(x:12.5,y:10)); face.line(to:NSPoint(x:12.5,y:2.5))
            face.move(to:NSPoint(x:6.5,y:14.5)); face.line(to:NSPoint(x:6.5,y:13.5))
            face.move(to:NSPoint(x:15.5,y:14.5)); face.line(to:NSPoint(x:15.5,y:13.5))
            face.move(to:NSPoint(x:6,y:8)); face.curve(to:NSPoint(x:16,y:8),controlPoint1:NSPoint(x:8.5,y:5.5),controlPoint2:NSPoint(x:13.5,y:5.5)); face.stroke()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "访达中打开"
        return image
    }()
}

// 两个“关于”入口复用同一窗口，关闭后保留实例；架构取编译目标，不以宿主 CPU 猜测。
private final class AboutWindowController: NSWindowController {
    private static let repositoryURL = URL(string:"https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift")!
    private var textViews = [NSTextView]()
    private let titleLabel = NSTextField(labelWithString:"")
    private let appIcon = NSImageView()
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
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:640),
                              styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "关于"+PetPreferences.shared.appName
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window:window)
        buildContent()
        window.center()
        NotificationCenter.default.addObserver(self,selector:#selector(updateAccent),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(updateIdentity),name:PetPreferences.didChange,object:nil)
    }
    required init?(coder: NSCoder) {fatalError()}

    private func buildContent() {
        guard let root = window?.contentView else {return}
        let icon = appIcon
        icon.image = AppIcons.application
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = titleLabel
        updateIdentity()
        title.maximumNumberOfLines = 1; title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize:23,weight:.semibold)
        title.alignment = .center
        let version = NSTextField(labelWithString:"版本 \(Paths.version) · \(Self.architecture)")
        version.font = .systemFont(ofSize:13)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let tabs = NSTabView()
        tabs.tabViewType = .topTabsBezelBorder
        tabs.font = .systemFont(ofSize:13)
        for (identifier,label,text) in [("about","关于",aboutText()),("credits","开源致谢",creditsText())] {
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

    private func readingView(_ content: NSAttributedString) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = NSTextView(frame:NSRect(x:0,y:0,width:560,height:360))
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
        window?.title = "关于"+name
        titleLabel.stringValue = name; titleLabel.toolTip = titleLabel.stringValue
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
        paragraph("本项目采用与原版不同的技术栈，功能适配与后续维护均需独立进行，目前属于实验性项目。如果更重视长期使用，建议同时了解沿用原版技术栈、持续维护并明确支持 macOS 的社区移植版本。",to:text)
        link("本项目仓库（私有，需访问权限）",url:Self.repositoryURL.absoluteString,to:text)
        link("原作：GPT白龙娘动态桌宠 · jingh12312-rgb",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)
        return text
    }

    private func creditsText() -> NSAttributedString {
        let text = NSMutableAttributedString(string:"")
        paragraph("感谢原作者及以下项目。本页分别记录原作、素材和软件组件的来源；它们各自适用的许可并不相同。",to:text,color:.secondaryLabelColor)

        heading("原作 · GPT白龙娘动态桌宠",to:text)
        paragraph("作者：jingh12312-rgb。行为与文案参考 v0.5.1 源码。原作 README 声明尚未指定开源许可证，不能将公开源码等同于任意使用或再分发授权。",to:text)
        link("原作仓库与说明",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet",to:text)

        heading("角色动画与应用图标",to:text)
        paragraph("角色动画来自原作者 v0.5.1 发布包。应用图标由待机画面制作；本项目对部分素材的本地处理不改变其原始来源。上游 ASSETS.md 未额外授予美术素材商用或再分发许可。",to:text)
        link("原作素材说明",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet/blob/main/ASSETS.md",to:text)

        heading("点击音效",to:text)
        paragraph("来自原作 app/sounds/click.wav。随附来源说明标注为程序合成的柔和点击音，无外部录音采样；来源说明未另列许可证。",to:text)
        link("音效及来源说明",url:"https://github.com/jingh12312-rgb/bailong-desktop-pet/tree/main/app/sounds",to:text)

        heading("FFmpeg · 动画解码",to:text)
        #if arch(x86_64)
        paragraph("当前随包版本：7.1（Intel x86_64）。Copyright © 2000–2024 the FFmpeg developers。此二进制启用了 --enable-nonfree，自带许可声明为 nonfree and unredistributable；当前仅作私有开发验证，公开发行前需替换解码器。",to:text)
        link("FFmpeg 项目与许可说明",url:"https://ffmpeg.org/legal.html",to:text)
        #else
        paragraph("当前随包版本：7.1。Copyright © 2000–2024 the FFmpeg developers。当前二进制自带许可声明为 GNU GPL 第 2 版或后续版本；其中集成的第三方组件另有各自许可。",to:text)
        link("FFmpeg 项目与许可说明",url:"https://ffmpeg.org/legal.html",to:text)
        link("GNU GPL 第 2 版全文",url:"https://www.gnu.org/licenses/old-licenses/gpl-2.0.html",to:text)
        #endif

        heading("libvpx · WebM 透明动画解码",to:text)
        paragraph("The WebM Project。在 FFmpeg 中提供 VP9 解码，保留角色动画透明通道。许可：BSD 3-Clause。",to:text)
        link("libvpx 源码及许可证全文",url:"https://chromium.googlesource.com/webm/libvpx/+/refs/heads/main/LICENSE",to:text)

        heading("imageio-ffmpeg · 解码器来源",to:text)
        paragraph("FFmpeg 二进制取自 imageio-ffmpeg 0.6.0。本应用未集成其 Python 封装。imageio-ffmpeg 封装采用 BSD 2-Clause，FFmpeg 二进制仍遵循上述自身许可。",to:text)
        link("imageio-ffmpeg 项目",url:"https://github.com/imageio/imageio-ffmpeg",to:text)
        link("imageio-ffmpeg 许可证全文",url:"https://github.com/imageio/imageio-ffmpeg/blob/v0.6.0/LICENSE",to:text)

        heading("SQLite · 本机任务记录读取",to:text)
        paragraph("使用 macOS 提供的 SQLite 动态库，不另附数据库运行库。SQLite 项目声明其发布代码与文档属于公有领域。",to:text)
        link("SQLite 官方版权说明",url:"https://www.sqlite.org/copyright.html",to:text)

        heading("开发技术与系统服务",to:text)
        paragraph("使用 Swift、AppKit、Foundation、Core Graphics 及 macOS 系统符号构建原生界面。这些系统技术单独列出，不将 AppKit 标注为第三方开源组件。对话功能调用用户已安装的 Codex，不随本应用分发 Codex。",to:text)
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
