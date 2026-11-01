import AppKit
import CoreText

// 单行公开进展：超宽时同一句连续循环，层动画不触发历史读取。
final class MarqueeProgressField:NSView {
    // 直接绘制完整文本图层，避免 NSTextField 只绘制 visibleRect 后随父图层移动产生空段。
    private let content = CALayer(), first = CATextLayer(), repeated = CATextLayer()
    private let fade = CAGradientLayer()
    private var signature = ""
    private var began = CACurrentMediaTime()
    var stringValue = "" {didSet {if oldValue != stringValue {began = CACurrentMediaTime(); signature = ""}; needsLayout = true}}
    var font:NSFont? {didSet {needsLayout = true}}
    var textColor:NSColor? {didSet {needsLayout = true}}
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true
        layer?.masksToBounds = true; layer?.addSublayer(content)
        for label in [first,repeated] {
            label.isWrapped = false; label.truncationMode = .none; label.alignmentMode = .left
            content.addSublayer(label)
        }
        fade.startPoint = CGPoint(x:0,y:0.5); fade.endPoint = CGPoint(x:1,y:0.5)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshColors),name:AppAccent.didChange,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func layout() {super.layout(); refresh()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); refresh()}
    override func viewDidChangeBackingProperties() {super.viewDidChangeBackingProperties(); refresh()}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); signature = ""; refresh()}
    @objc private func refreshColors() {signature = ""; refresh()}
    func stop() {content.removeAnimation(forKey:"progress-marquee"); signature = ""}
    func refresh() {
        let font = font ?? .systemFont(ofSize:11), color = textColor ?? .secondaryLabelColor
        let resolvedColor = AppAppearance.resolvedColor(color,for:effectiveAppearance)
        let width = ceil((stringValue as NSString).size(withAttributes:[.font:font]).width)+4
        // CATextLayer 使用 Core Text 的 CGColor，不能依赖动态 NSColor 自动刷新。
        let text = NSAttributedString(string:stringValue,attributes:[
            NSAttributedString.Key(kCTFontAttributeName as String):font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):resolvedColor])
        let backingScale = window?.backingScaleFactor ?? 2
        let overflow = width > bounds.width && bounds.width > 0
        let animate = overflow && window?.isVisible == true && !visibleRect.isEmpty && PetPreferences.shared.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let next = "\(stringValue)|\(bounds.size)|\(font.fontName)|\(font.pointSize)|\(backingScale)|\(animate)|\(resolvedColor.components ?? [])"
        guard signature != next else {return}; signature = next
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.removeAnimation(forKey:"progress-marquee")
        content.transform = CATransform3DIdentity
        for label in [first,repeated] {label.string = text; label.contentsScale = backingScale; label.setNeedsDisplay()}
        let gap = ("   " as NSString).size(withAttributes:[.font:font]).width, cycle = width+gap
        content.frame = NSRect(x:0,y:0,width:animate ? cycle+width : max(width,bounds.width),height:bounds.height)
        let lineHeight = ceil(font.ascender-font.descender+font.leading)+2
        first.frame = NSRect(x:0,y:(bounds.height-lineHeight)/2,width:width,height:lineHeight)
        repeated.frame = NSRect(x:cycle,y:first.frame.minY,width:width,height:lineHeight); repeated.isHidden = !animate
        fade.frame = bounds
        fade.colors = [NSColor.black.cgColor,NSColor.black.cgColor,NSColor.clear.cgColor]
        fade.locations = [0,NSNumber(value:max(0,1-16/max(1,bounds.width))),1]
        layer?.mask = overflow ? fade : nil
        setAccessibilityValue(stringValue)
        if animate {
            let movement = CABasicAnimation(keyPath:"transform.translation.x")
            movement.fromValue = 0; movement.toValue = -cycle
            movement.duration = cycle/28; movement.repeatCount = .infinity
            movement.timingFunction = CAMediaTimingFunction(name:.linear)
            movement.beginTime = content.convertTime(began,from:nil)
            content.add(movement,forKey:"progress-marquee")
        }
        CATransaction.commit()
    }
}
