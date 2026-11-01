import AppKit

// 单行公开进展：超宽时同一句连续循环，层动画不触发历史读取。
final class MarqueeProgressField:NSView {
    private let content = NSView(), first = NSTextField(labelWithString:""), repeated = NSTextField(labelWithString:"")
    private let fade = CAGradientLayer()
    private var signature = ""
    private var began = CACurrentMediaTime()
    var stringValue = "" {didSet {if oldValue != stringValue {began = CACurrentMediaTime(); signature = ""}; needsLayout = true}}
    var font:NSFont? {didSet {needsLayout = true}}
    var textColor:NSColor? {didSet {needsLayout = true}}
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true; content.wantsLayer = true
        addSubview(content)
        for label in [first,repeated] {
            label.maximumNumberOfLines = 1; label.usesSingleLineMode = true; label.lineBreakMode = .byClipping
            content.addSubview(label)
        }
        fade.startPoint = CGPoint(x:0,y:0.5); fade.endPoint = CGPoint(x:1,y:0.5)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func layout() {super.layout(); refresh()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); refresh()}
    func stop() {content.layer?.removeAnimation(forKey:"progress-marquee"); signature = ""}
    func refresh() {
        let font = font ?? .systemFont(ofSize:11), color = textColor ?? .secondaryLabelColor
        let width = ceil((stringValue as NSString).size(withAttributes:[.font:font]).width)+4
        let overflow = width > bounds.width && bounds.width > 0
        let animate = overflow && window?.isVisible == true && !visibleRect.isEmpty && PetPreferences.shared.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let next = "\(stringValue)|\(bounds.width)|\(font.pointSize)|\(animate)|\(color)"
        guard signature != next else {return}; signature = next
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.layer?.removeAnimation(forKey:"progress-marquee")
        content.layer?.transform = CATransform3DIdentity
        for label in [first,repeated] {label.stringValue = stringValue; label.font = font; label.textColor = color}
        let gap = ("   " as NSString).size(withAttributes:[.font:font]).width, cycle = width+gap
        content.frame = NSRect(x:0,y:0,width:animate ? cycle+width : max(width,bounds.width),height:bounds.height)
        first.frame = NSRect(x:0,y:0,width:width,height:bounds.height)
        repeated.frame = NSRect(x:cycle,y:0,width:width,height:bounds.height); repeated.isHidden = !animate
        fade.frame = bounds
        fade.colors = [NSColor.black.cgColor,NSColor.black.cgColor,NSColor.clear.cgColor]
        fade.locations = [0,NSNumber(value:max(0,1-16/max(1,bounds.width))),1]
        layer?.mask = overflow ? fade : nil
        setAccessibilityValue(stringValue)
        if animate,let layer = content.layer {
            let movement = CABasicAnimation(keyPath:"transform.translation.x")
            movement.fromValue = 0; movement.toValue = -cycle
            movement.duration = cycle/28; movement.repeatCount = .infinity
            movement.timingFunction = CAMediaTimingFunction(name:.linear)
            movement.beginTime = layer.convertTime(began,from:nil)
            layer.add(movement,forKey:"progress-marquee")
        }
        CATransaction.commit()
    }
}
