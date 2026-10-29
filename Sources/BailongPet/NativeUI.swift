import AppKit

func showError(_ title: String, _ error: Error) {
    let alert = NSAlert(); alert.messageText = title; alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning; alert.addButton(withTitle: "好")
    NSApp.activate(ignoringOtherApps: true); alert.runModal()
}
func label(_ text: String, bold: Bool = false) -> NSTextField {
    let view = NSTextField(wrappingLabelWithString: text)
    view.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
    return view
}
func materialView() -> NSVisualEffectView {
    let view = NSVisualEffectView(); view.material = .popover
    view.blendingMode = .behindWindow; view.state = .active; return view
}
final class ActionButton: NSButton {
    var callback: () -> Void
    init(_ title: String, _ callback: @escaping () -> Void) {
        self.callback = callback; super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; target = self; action = #selector(invokeCallback)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func invokeCallback() { callback() }
}
final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class Bubble {
    let window: PetWindow
    private let title = label("", bold: true)
    private let text = NSTextView()
    private let scroll = NSScrollView()
    private var closeButton: ActionButton!
    private var details: ActionButton!
    private var timer: Timer?
    var onClose: () -> Void = {}
    var onDetails: () -> Void = {}
    var kind = ""
    var visible: Bool { window.isVisible }
    init() {
        window = PetWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        let content = materialView(); content.wantsLayer = true; content.layer?.cornerRadius = 16; content.layer?.masksToBounds = true
        window.contentView = content
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.font = .systemFont(ofSize: 13); text.textColor = .labelColor
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        closeButton = ActionButton("×") { [weak self] in self?.hide(); self?.onClose() }
        details = ActionButton("详情") { [weak self] in self?.onDetails() }
        for view in [title, scroll, closeButton, details] as [NSView] { content.addSubview(view) }
    }
    func show(title heading: String, body: String = "", kind: String, scale: Double, seconds: Double = 4, details enabled: Bool = false) {
        timer?.invalidate()
        if scroll.documentView !== text {scroll.documentView = text}
        let same = self.kind == kind
        let clip = scroll.contentView
        let atEnd = clip.bounds.maxY >= text.bounds.maxY - 8
        let old = clip.bounds.origin
        self.kind = kind
        let w = 320 * scale, h = (body.isEmpty ? 96.0 : 240.0) * scale
        window.setContentSize(NSSize(width: w, height: h))
        title.stringValue = heading; title.font = .boldSystemFont(ofSize: 13 * scale)
        title.frame = NSRect(x: 28, y: h - 64 * scale, width: w - 50, height: 48 * scale)
        closeButton.frame = NSRect(x: 2, y: h - 28, width: 26, height: 26)
        scroll.frame = NSRect(x: 14, y: 44, width: w - 28, height: max(0, h - 112 * scale))
        scroll.isHidden = body.isEmpty
        text.frame.size.width = scroll.contentSize.width
        text.font = .systemFont(ofSize: 13 * scale); text.string = body
        if same && !atEnd { clip.scroll(to: old) } else { text.scrollToEndOfDocument(nil) }
        details.frame = NSRect(x: w - 82, y: 9, width: 68, height: 28); details.isHidden = !enabled
        window.orderFrontRegardless()
        if seconds > 0 { timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.hide(); self?.onClose() } }
    }
    func quotaRows(_ rows: [(String, Double?, String)], scale: Double) {
        let width = scroll.contentSize.width
        let rowHeight = 78 * scale
        let content = NSView(frame:NSRect(x:0,y:0,width:width,height:rowHeight*Double(rows.count)))
        for (index,row) in rows.enumerated() {
            let y = content.frame.height-Double(index+1)*rowHeight
            let amount = row.1.map {String(format:"剩余 %.0f%%",$0)} ?? "暂未提供"
            let text = label(row.0+" · "+amount+"\n重置："+row.2)
            text.font = .systemFont(ofSize:12*scale); text.frame = NSRect(x:2,y:y+26*scale,width:width-8,height:46*scale)
            let bar = NSProgressIndicator(frame:NSRect(x:2,y:y+8*scale,width:width-8,height:12*scale))
            bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100
            bar.doubleValue = row.1 ?? 0; bar.isHidden = row.1 == nil
            content.addSubview(text); content.addSubview(bar)
        }
        scroll.documentView = content
        scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,content.frame.height-scroll.contentSize.height)))
    }
    func place(near rect: CGRect, screen: NSScreen, dock: String?) {
        let a = screen.visibleFrame, s = window.frame.size
        var x = rect.midX - s.width / 2, y = rect.maxY + 8
        if dock == "left" { x = rect.maxX + 8; y = rect.midY - s.height / 2 }
        else if dock == "right" { x = rect.minX - s.width - 8; y = rect.midY - s.height / 2 }
        else if y + s.height > a.maxY { y = rect.minY - s.height - 8 }
        window.setFrameOrigin(NSPoint(x: max(a.minX, min(x, a.maxX - s.width)), y: max(a.minY, min(y, a.maxY - s.height))))
    }
    func hide() { timer?.invalidate(); window.orderOut(nil); kind = "" }
}

final class SettingsPanel: NSObject, NSWindowDelegate {
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let petSlider = NSSlider(value: 100, minValue: 50, maxValue: 200, target: nil, action: nil)
    private let bubbleSlider = NSSlider(value: 100, minValue: 50, maxValue: 150, target: nil, action: nil)
    private let petValue = NSTextField(), bubbleValue = NSTextField()
    var onChange: (Int, Int) -> Void = { _,_ in }
    var onClose: () -> Void = {}
    override init() {
        super.init(); window.title = "桌宠与气泡大小"; window.isReleasedWhenClosed = false; window.delegate = self
        let content = materialView(); window.contentView = content
        for (name, y, slider, field) in [("桌宠 · 50%—200%", 166.0, petSlider, petValue), ("气泡 · 50%—150%", 86.0, bubbleSlider, bubbleValue)] {
            let heading = label(name); heading.frame = NSRect(x: 24, y: y + 24, width: 300, height: 22); content.addSubview(heading)
            slider.frame = NSRect(x: 24, y: y - 8, width: 260, height: 28)
            slider.target = self; slider.action = #selector(slid); slider.isContinuous = true
            field.frame = NSRect(x: 300, y: y - 6, width: 80, height: 26)
            let format = NumberFormatter(); format.minimum = 50; format.maximum = NSNumber(value: slider.maxValue); format.allowsFloats = false
            field.formatter = format; field.target = self; field.action = #selector(typed)
            content.addSubview(slider); content.addSubview(field)
        }
        let reset = ActionButton("恢复 100%") { [weak self] in self?.set(100,100); self?.slid() }
        let done = ActionButton("完成") { [weak self] in self?.typed(); self?.window.close() }; done.keyEquivalent = "\r"
        reset.frame = NSRect(x: 186, y: 16, width: 120, height: 32); done.frame = NSRect(x: 310, y: 16, width: 80, height: 32)
        content.addSubview(reset); content.addSubview(done)
    }
    func set(_ p: Int, _ b: Int) { petSlider.integerValue = p; bubbleSlider.integerValue = b; petValue.integerValue = p; bubbleValue.integerValue = b }
    @objc func slid() { set(petSlider.integerValue, bubbleSlider.integerValue); onChange(petSlider.integerValue, bubbleSlider.integerValue) }
    @objc func typed() { set(max(50,min(200,petValue.integerValue)), max(50,min(150,bubbleValue.integerValue))); slid() }
    func show(_ p: Int, _ b: Int) { set(p,b); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { typed(); onClose() }
}
