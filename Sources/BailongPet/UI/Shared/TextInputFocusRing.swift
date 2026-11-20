import AppKit

/// 窗口恢复原响应者时也有入场过渡。只有焦点环参与动画，编辑器继续接收输入。
final class TextInputFocusRing: NSView {
    private weak var surface: NSView?
    private weak var input: NSView?
    private var responderObservation: NSKeyValueObservation?
    private var editableObservation: NSKeyValueObservation?
    private var focused = false
    private var pendingEntry = false

    @discardableResult init(surface: NSView, input: NSView, in host: NSView) {
        self.surface = surface
        self.input = input
        super.init(frame:.zero)
        focusRingType = .none
        wantsLayer = true
        alphaValue = 0
        setAccessibilityElement(false)
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        // 系统静态环画在边界外，预留绘制空间；约束只定位这层。
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo:surface.leadingAnchor, constant:-5),
            trailingAnchor.constraint(equalTo:surface.trailingAnchor, constant:5),
            topAnchor.constraint(equalTo:surface.topAnchor, constant:-5),
            bottomAnchor.constraint(equalTo:surface.bottomAnchor, constant:5)
        ])
        if let text = input as? NSTextView {
            editableObservation = text.observe(\.isEditable) { [weak self] _,_ in self?.updateFocus() }
        }
    }

    required init?(coder:NSCoder) {fatalError()}
    override func hitTest(_ point:NSPoint) -> NSView? {nil}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        responderObservation = nil
        let center = NotificationCenter.default
        center.removeObserver(self)
        if let window {
            responderObservation = window.observe(\.firstResponder) { [weak self] _,_ in self?.updateFocus() }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                center.addObserver(self, selector:#selector(updateFocus), name:name, object:window)
            }
            center.addObserver(self, selector:#selector(updateColor), name:NSColor.systemColorsDidChangeNotification, object:nil)
        }
        updateFocus()
    }

    private var hasKeyboardFocus: Bool {
        guard let window, window.isKeyWindow, let responder = window.firstResponder,
              let input, !input.isHiddenOrHasHiddenAncestor else {return false}
        if let field = input as? NSTextField {
            return field.isEnabled && field.isEditable && (field.currentEditor() === responder || (responder as? NSView)?.isDescendant(of:field) == true)
        }
        return responder === input && (input as? NSTextView)?.isEditable == true
    }

    override func viewDidHide() {super.viewDidHide(); updateFocus()}
    override func viewDidUnhide() {super.viewDidUnhide(); updateFocus()}

    @objc private func updateFocus() {
        let active = hasKeyboardFocus
        guard focused != active else {return}
        focused = active
        pendingEntry = active && DisclosureMotion.enabled
        alphaValue = active ? 1 : 0
        layer?.removeAnimation(forKey:"focusEntry")
        if active {
            needsDisplay = true
            animateEntryIfReady()
        }
    }

    override func layout() {
        super.layout()
        animateEntryIfReady()
    }

    private func animateEntryIfReady() {
        guard pendingEntry, let layer, !bounds.isEmpty else {return}
        pendingEntry = false
        // 两轴各向外展开相同点数，长输入框与搜索框使用相同的边缘位移。
        let outset: CGFloat = 8
        let x = 1 + 2*outset/bounds.width, y = 1 + 2*outset/bounds.height
        var start = CATransform3DMakeScale(x,y,1)
        start.m41 = (layer.anchorPoint.x - 0.5)*2*outset
        start.m42 = (layer.anchorPoint.y - 0.5)*2*outset
        let contract = CABasicAnimation(keyPath:"transform")
        contract.fromValue = NSValue(caTransform3D:start)
        contract.toValue = NSValue(caTransform3D:CATransform3DIdentity)
        let fade = CABasicAnimation(keyPath:"opacity")
        fade.fromValue = 0; fade.toValue = 1
        let entry = CAAnimationGroup()
        entry.duration = 0.30
        contract.duration = entry.duration; fade.duration = entry.duration
        entry.animations = [contract,fade]
        entry.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        layer.add(entry,forKey:"focusEntry")
    }

    override func draw(_ dirtyRect:NSRect) {
        guard let surface else {return}
        let rect = convert(surface.bounds,from:surface)
        let radius = (surface as? NSBox)?.cornerRadius ?? rect.height / 2
        // 外沿扩出 3pt，内沿覆盖一个设备像素。直接描边只绘制轮廓。
        let inside = 1 / (window?.backingScaleFactor ?? 1)
        let outset = (3 - inside) / 2
        let stroke = NSBezierPath(roundedRect:rect.insetBy(dx:-outset,dy:-outset),
                                  xRadius:radius+outset,yRadius:radius+outset)
        stroke.lineWidth = 3 + inside
        NSColor.keyboardFocusIndicatorColor.setStroke()
        stroke.stroke()
    }

    @objc private func updateColor() {needsDisplay = true}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
