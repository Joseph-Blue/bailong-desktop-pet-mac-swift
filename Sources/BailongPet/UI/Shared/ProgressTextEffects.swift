import AppKit
import CoreText

// 标题扫光与概览循环共用动态效果策略；不参与正文布局、滚动和历史数据。
enum ProgressTextEffects {
    static var enabled:Bool {PetPreferences.shared.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion}
    static let speed:CGFloat = 28
    static let marqueeDelay:CFTimeInterval = 0.5
    static func heading(_ text:String,font:NSFont,appearance:NSAppearance,elapsed:Double,frame:String) -> NSAttributedString {
        let accent = NSColor(cgColor:AppAppearance.resolvedColor(AppAccent.color,for:appearance))!
        let value = NSMutableAttributedString(attributedString:InlineStatusLayout.braille(frame,font:font,color:accent))
        value.append(NSAttributedString(string:" ",attributes:[.font:font]))
        value.append(title(text,font:font,appearance:appearance,elapsed:elapsed))
        return value
    }
    // 标题可独立扫光，盲文仍由所在视图单独绘制，不改变字宽或位置。
    static func title(_ text:String,font:NSFont,appearance:NSAppearance,elapsed:Double) -> NSAttributedString {
        let foreground = NSColor(cgColor:AppAppearance.resolvedColor(.labelColor,for:appearance))!
        let value = NSMutableAttributedString(string:text,attributes:[.font:font,.foregroundColor:foreground])
        guard enabled else {return value}
        let phase = elapsed.truncatingRemainder(dividingBy:4)
        let center = -0.25+1.5*(phase/1.2)
        let dark = appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let count = max(1,text.count-1)
        var offset = 0
        for (index,character) in text.enumerated() {
            let length = (String(character) as NSString).length
            let distance = (Double(index)/Double(count)-center)/0.18
            let strength = phase < 1.2 ? exp(-distance*distance) : 0
            value.addAttribute(.foregroundColor,value:foreground.withAlphaComponent(dark ? 0.58+0.42*strength : 1-0.55*strength),range:NSRange(location:offset,length:length))
            offset += length
        }
        return value
    }
}

// 完整文本双图层循环，避免移动 NSTextField 时出现可见区域裁切空段。
private final class ProgressLineLayer:CALayer {
    var text:NSAttributedString = NSAttributedString()
    var baseline:CGFloat = 0
    override func draw(in context:CGContext) {
        context.textMatrix = .identity
        context.textPosition = CGPoint(x:0,y:baseline)
        CTLineDraw(CTLineCreateWithAttributedString(text),context)
    }
}

final class ProgressMarqueeView:NSView {
    private let content = CALayer(), first = ProgressLineLayer(), repeated = ProgressLineLayer(), fade = CAGradientLayer()
    private var signature = ""
    private var offset:CGFloat = 0, cycle:CGFloat = 0
    private var startedAt:CFTimeInterval?
    private var delayRemaining = ProgressTextEffects.marqueeDelay
    private var active = false
    var stringValue = "" {didSet {
        guard oldValue != stringValue else {return}
        pauseMotion(); offset = 0; delayRemaining = ProgressTextEffects.marqueeDelay; signature = ""; needsLayout = true
    }}
    var font:NSFont? {didSet {needsLayout = true}}
    var textColor:NSColor? {didSet {needsLayout = true}}
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true
        layer?.masksToBounds = true; layer?.addSublayer(content)
        for label in [first,repeated] {content.addSublayer(label)}
        fade.startPoint = CGPoint(x:0,y:0.5); fade.endPoint = CGPoint(x:1,y:0.5)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        NotificationCenter.default.addObserver(self,selector:#selector(settingsChanged),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(settingsChanged),name:PetPreferences.didChange,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(settingsChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func layout() {super.layout(); refresh()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); refresh()}
    override func viewDidChangeBackingProperties() {super.viewDidChangeBackingProperties(); refresh()}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); settingsChanged()}
    @objc private func settingsChanged() {signature = ""; refresh()}
    func start() {active = true; refresh()}
    func stop() {active = false; pauseMotion(); signature = ""}
    private func pauseMotion() {
        if let startedAt,cycle > 0 {
            let elapsed = CACurrentMediaTime()-startedAt
            delayRemaining = max(0,-elapsed)
            offset = (offset+CGFloat(max(0,elapsed))*ProgressTextEffects.speed).truncatingRemainder(dividingBy:cycle)
        }
        startedAt = nil; content.removeAnimation(forKey:"progress-marquee")
    }
    func refresh() {
        let font = font ?? .systemFont(ofSize:11)
        let color = AppAppearance.resolvedColor(textColor ?? .secondaryLabelColor,for:effectiveAppearance)
        let width = ceil((stringValue as NSString).size(withAttributes:[.font:font]).width)
        let overflow = width > bounds.width && bounds.width > 0
        let animate = active && overflow && ProgressTextEffects.enabled && window?.isVisible == true && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
        let scale = window?.backingScaleFactor ?? 2
        let next = "\(stringValue)|\(bounds.size)|\(font.fontName)|\(font.pointSize)|\(scale)|\(animate)|\(color.components ?? [])"
        guard next != signature else {return}
        pauseMotion(); signature = next
        let text = NSAttributedString(string:stringValue,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):color])
        cycle = width+("   " as NSString).size(withAttributes:[.font:font]).width
        if cycle > 0 {offset = offset.truncatingRemainder(dividingBy:cycle)}
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.transform = CATransform3DIdentity
        content.frame = NSRect(x:0,y:0,width:max(bounds.width,cycle+width),height:bounds.height)
        for label in [first,repeated] {
            label.text = text; label.contentsScale = scale
            label.baseline = InlineStatusLayout.lineBaseline(font:font,height:bounds.height)
            label.setNeedsDisplay()
        }
        first.frame = NSRect(x:0,y:0,width:width,height:bounds.height)
        repeated.frame = first.frame.offsetBy(dx:cycle,dy:0); repeated.isHidden = !animate
        fade.frame = bounds; fade.colors = [NSColor.black.cgColor,NSColor.black.cgColor,NSColor.clear.cgColor]
        let fadeStart = max(0,1-16/max(1,Double(bounds.width)))
        fade.locations = [0,NSNumber(value:fadeStart),1]
        layer?.mask = overflow ? fade : nil
        setAccessibilityValue(stringValue)
        if animate {
            let animation = CABasicAnimation(keyPath:"transform.translation.x")
            animation.fromValue = 0; animation.toValue = -cycle
            animation.duration = Double(cycle/ProgressTextEffects.speed); animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name:.linear)
            startedAt = CACurrentMediaTime()+delayRemaining
            animation.beginTime = content.convertTime(startedAt!,from:nil)-Double(offset/ProgressTextEffects.speed)
            content.add(animation,forKey:"progress-marquee")
        }
        CATransaction.commit()
    }
    deinit {NSWorkspace.shared.notificationCenter.removeObserver(self)}
}
