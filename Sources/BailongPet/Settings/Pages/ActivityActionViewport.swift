import AppKit

protocol SettingsViewportRow where Self:NSView {
    var isLoaded:Bool {get}
    func loadControls()
    func releaseControls()
}

extension SettingsViewportRow {
    func releaseControlsIfUnfocused() {
        guard isLoaded else {return}
        if let responder = window?.firstResponder as? NSView {
            if responder === self || responder.isDescendant(of:self) {return}
            if let editor = responder as? NSTextView,let field = editor.delegate as? NSView,field.isDescendant(of:self) {return}
        }
        releaseControls()
    }
}

// 分组和搜索锚点一直在原位。完整控件只属于当前视口及其上下两行。
final class SettingsRowViewport:NSObject {
    private let rows:[any SettingsViewportRow]
    private weak var scroll:NSScrollView?
    private var scheduled = false

    init(rows:[any SettingsViewportRow],scroll:NSScrollView) {
        self.rows = rows; self.scroll = scroll
        super.init()
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,selector:#selector(schedule),name:NSView.boundsDidChangeNotification,object:clip)
        schedule()
    }

    @objc func schedule() {
        guard !scheduled else {return}
        scheduled = true
        RunLoop.main.perform(inModes:[.common]) { [weak self] in self?.update() }
    }
    private func update() {
        scheduled = false
        guard let scroll,scroll.window != nil,!scroll.isHiddenOrHasHiddenAncestor,let document = scroll.documentView else {return}
        document.layoutSubtreeIfNeeded()
        let visible = scroll.documentVisibleRect
        var nearby = [any SettingsViewportRow](), onscreen = [any SettingsViewportRow]()
        for row in rows {
            let rect = row.convert(row.bounds,to:document)
            if rect.intersects(visible) {onscreen.append(row)}
            else if rect.intersects(visible.insetBy(dx:0,dy:-2 * rect.height)) {nearby.append(row)}
            else {row.releaseControlsIfUnfocused()}
        }
        let needed = (onscreen + nearby).filter {!$0.isLoaded}
        // 每次回到事件循环重新读取视口，让连续滚动或切页优先于旧位置。
        for row in needed.prefix(2) {row.loadControls()}
        if needed.count > 2 {schedule()}
    }
}

final class ActivityActionRow:NSView,SettingsViewportRow {
    typealias Controls = (form:SettingsForm,weight:NSView?)
    private let make:(NSWindow) -> Controls
    private let name:NSTextField
    private let heading = NSView()
    private var controls:Controls?
    var isLoaded:Bool {controls != nil}

    init(title:String,weightHeight:CGFloat,make:@escaping (NSWindow) -> Controls) {
        self.make = make
        name = NSTextField(labelWithString:title)
        super.init(frame:.zero)
        setAccessibilityRole(.group); setAccessibilityLabel(title)
        name.font = .systemFont(ofSize:13,weight:.medium)
        heading.translatesAutoresizingMaskIntoConstraints = false; addSubview(heading)
        name.translatesAutoresizingMaskIntoConstraints = false; heading.addSubview(name)
        let headerHeight:CGFloat = 32
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant:headerHeight+weightHeight),
            heading.leadingAnchor.constraint(equalTo:leadingAnchor),heading.trailingAnchor.constraint(equalTo:trailingAnchor),
            heading.topAnchor.constraint(equalTo:topAnchor),heading.heightAnchor.constraint(equalToConstant:headerHeight),
            name.leadingAnchor.constraint(equalTo:heading.leadingAnchor),name.centerYAnchor.constraint(equalTo:heading.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo:heading.trailingAnchor)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}

    func loadControls() {
        guard !isLoaded,let window else {return}
        let created = make(window), playback = created.form.content
        controls = created
        playback.translatesAutoresizingMaskIntoConstraints = false; heading.addSubview(playback)
        NSLayoutConstraint.activate([
            playback.trailingAnchor.constraint(equalTo:heading.trailingAnchor),playback.centerYAnchor.constraint(equalTo:heading.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo:playback.leadingAnchor,constant:-12)
        ])
        if let weight = created.weight {
            weight.translatesAutoresizingMaskIntoConstraints = false; addSubview(weight)
            NSLayoutConstraint.activate([
                weight.leadingAnchor.constraint(equalTo:leadingAnchor),weight.trailingAnchor.constraint(equalTo:trailingAnchor),
                weight.topAnchor.constraint(equalTo:heading.bottomAnchor),weight.bottomAnchor.constraint(equalTo:bottomAnchor)
            ])
        }
    }
    func releaseControls() {
        guard let controls else {return}
        controls.form.content.removeFromSuperview(); controls.weight?.removeFromSuperview(); self.controls = nil
    }

    // 全键盘导航和辅助功能也可以直接进入屏幕外的动作。
    override var acceptsFirstResponder:Bool {!isLoaded}
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else {return false}
        scrollToVisible(bounds); loadControls()
        let backwards = window?.keyViewSelectionDirection == .selectingPrevious
        DispatchQueue.main.async { [weak self] in
            guard let self,let window = self.window,window.firstResponder === self,self.isLoaded else {return}
            func inputs(_ node:NSView) -> [NSView] {
                if node is NSControl,node.acceptsFirstResponder {return [node]}
                return node.subviews.flatMap(inputs)
            }
            let fields = inputs(self)
            if let target = backwards ? fields.last : fields.first {window.makeFirstResponder(target)}
        }
        return true
    }
    override func accessibilityChildren() -> [Any]? {
        loadControls()
        return super.accessibilityChildren()
    }
}
