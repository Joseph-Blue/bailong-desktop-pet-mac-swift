import AppKit
import CoreText

// 标题扫光与概览循环共用动态效果策略；不参与正文布局、滚动和历史数据。
enum ProgressTextEffects {
    static var enabled:Bool {PetPreferences.shared.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion}
    static let speed:CGFloat = 28
    static let marqueeDelay:CFTimeInterval = 0.5
    private static let sweepSteps = 16
    private struct PaletteKey:Hashable {
        let fontName:String
        let pointSize:CGFloat
        let dark:Bool
        let highContrast:Bool
        let r:Int, g:Int, b:Int
    }
    private struct SweepPalette {
        let attributes:[[NSAttributedString.Key:Any]]
        let prototypes:[NSAttributedString]
    }
    private static var palettes = [PaletteKey:SweepPalette]()
    private static var paletteOrder = [PaletteKey]()

    static func sweepTick(elapsed:Double) -> Int {
        guard enabled else {return -1}
        let phase = elapsed.truncatingRemainder(dividingBy:4)
        guard phase >= 0,phase < 1.2 else {return -1}
        return Int((phase/1.2)*36)
    }

    private static func cachedPalette(font:NSFont,appearance:NSAppearance) -> SweepPalette {
        let resolved = AppAppearance.resolvedColor(.labelColor,for:appearance)
        let label = (NSColor(cgColor:resolved) ?? .labelColor).usingColorSpace(.sRGB) ?? .labelColor
        let dark = appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let key = PaletteKey(fontName:font.fontName,pointSize:font.pointSize,dark:dark,highContrast:highContrast,
                             r:Int((label.redComponent*255).rounded()),g:Int((label.greenComponent*255).rounded()),b:Int((label.blueComponent*255).rounded()))
        if let existing = palettes[key] {return existing}
        let base = label.withAlphaComponent(1)
        let sweepAmount = highContrast ? 0.18 : 0.30
        let target:NSColor = dark ? .black : .white
        var attributes = [[NSAttributedString.Key:Any]]()
        var prototypes = [NSAttributedString]()
        attributes.reserveCapacity(sweepSteps+1)
        prototypes.reserveCapacity(sweepSteps+1)
        for step in 0...sweepSteps {
            let fraction = sweepAmount*Double(step)/Double(sweepSteps)
            let color = step == 0 ? base : (base.blended(withFraction:fraction,of:target) ?? base)
            let dict:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
            attributes.append(dict)
            // 持有固定档位原型，防止 UIFoundation 全局弱属性字典哈希表堆积 tombstone。
            prototypes.append(NSAttributedString(string:" ",attributes:dict))
        }
        let created = SweepPalette(attributes:attributes,prototypes:prototypes)
        if paletteOrder.count >= 12,let oldest = paletteOrder.first {
            paletteOrder.removeFirst(); palettes.removeValue(forKey:oldest)
        }
        paletteOrder.append(key); palettes[key] = created
        return created
    }

    static func heading(_ text:String,font:NSFont,appearance:NSAppearance,elapsed:Double,frame:String) -> NSAttributedString {
        let palette = cachedPalette(font:font,appearance:appearance)
        let value = NSMutableAttributedString(attributedString:InlineStatusLayout.braille(frame,font:font,color:AppAccent.foregroundColor))
        value.append(NSAttributedString(string:" ",attributes:palette.attributes[0]))
        value.append(title(text,font:font,appearance:appearance,elapsed:elapsed))
        return value
    }
    // 标题可独立扫光，盲文仍由所在视图单独绘制，不改变字宽或位置。
    static func title(_ text:String,font:NSFont,appearance:NSAppearance,elapsed:Double) -> NSAttributedString {
        let palette = cachedPalette(font:font,appearance:appearance)
        guard enabled else {return NSAttributedString(string:text,attributes:palette.attributes[0])}
        let phase = elapsed.truncatingRemainder(dividingBy:4)
        guard phase >= 0,phase < 1.2,!text.isEmpty else {
            return NSAttributedString(string:text,attributes:palette.attributes[0])
        }
        // 保留黑／白底字，扫过时向反方向的灰色按离散档位过渡；不靠透明度制造变化。
        let value = NSMutableAttributedString(string:text,attributes:palette.attributes[0])
        let center = -0.25+1.5*(phase/1.2)
        let count = max(1,text.count-1)
        var offset = 0
        for (index,character) in text.enumerated() {
            let length = (String(character) as NSString).length
            let distance = (Double(index)/Double(count)-center)/0.18
            let level = min(sweepSteps,max(0,Int((exp(-distance*distance)*Double(sweepSteps)).rounded())))
            if level > 0 {
                value.setAttributes(palette.attributes[level],range:NSRange(location:offset,length:length))
            }
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
    private var textWidth:CGFloat {ceil((stringValue as NSString).size(withAttributes:[.font:font ?? .systemFont(ofSize:11)]).width)}
    var textOverflows:Bool {bounds.width > 0 && textWidth > bounds.width}
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
        let width = textWidth
        let overflow = width > bounds.width && bounds.width > 0
        let animate = active && overflow && ProgressTextEffects.enabled && window?.isVisible == true && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
        let scale = window?.backingScaleFactor ?? 2
        let next = "\(stringValue)|\(bounds.size)|\(font.fontName)|\(font.pointSize)|\(scale)|\(animate)|\(color.components ?? [])"
        guard next != signature else {return}
        pauseMotion(); signature = next
        // 分隔符只用于滚动衔接，不改变原文及辅助功能朗读。
        let loopingText = stringValue+"　·　"
        let text = NSAttributedString(string:animate ? loopingText : stringValue,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):color])
        cycle = ceil((loopingText as NSString).size(withAttributes:[.font:font]).width)
        let displayWidth = animate ? cycle : width
        if cycle > 0 {offset = offset.truncatingRemainder(dividingBy:cycle)}
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.transform = CATransform3DIdentity
        content.frame = NSRect(x:0,y:0,width:max(bounds.width,cycle+displayWidth),height:bounds.height)
        for label in [first,repeated] {
            label.text = text; label.contentsScale = scale
            label.baseline = InlineStatusLayout.lineBaseline(font:font,height:bounds.height)
            label.setNeedsDisplay()
        }
        first.frame = NSRect(x:0,y:0,width:displayWidth,height:bounds.height)
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

// 原生 SF Symbol 视图，操作与结果各有自己的位置；结果不遮挡操作轮廓。
final class TaskActivitySymbolView:NSView {
    fileprivate let operationIcon = NSImageView(), resultIcon = NSImageView()
    fileprivate var textColor:NSColor = .labelColor
    private var renderedSymbol:String?, renderedResult:String?
    private(set) var activity:TaskActivity?
    private var pointSize:CGFloat = 15
    // 固定操作图标槽位；宽符号等比缩放，不再挤占相邻进展文字。
    private var operationWidth:CGFloat {pointSize}
    var layoutSize:NSSize {NSSize(width:operationWidth+(activity?.outcome == nil ? 0 : pointSize*0.75+pointSize/5),height:pointSize)}
    override init(frame:NSRect) {
        super.init(frame:frame)
        for icon in [operationIcon,resultIcon] {
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityElement(false); addSubview(icon)
        }
        setAccessibilityElement(true); setAccessibilityRole(.image)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func update(_ activity:TaskActivity?,pointSize:CGFloat) {
        let resized = self.pointSize != pointSize
        self.activity = activity; self.pointSize = pointSize
        let symbol = activity?.symbolName, result = activity?.outcome?.symbol
        if resized || renderedSymbol != symbol {
            renderedSymbol = symbol
            operationIcon.image = symbol.flatMap {NSImage(systemSymbolName:$0,accessibilityDescription:nil)}?
                .withSymbolConfiguration(.init(pointSize:pointSize,weight:.semibold))
        }
        if resized || renderedResult != result {
            renderedResult = result
            resultIcon.image = result.flatMap {NSImage(systemSymbolName:$0,accessibilityDescription:nil)}?
                .withSymbolConfiguration(.init(pointSize:pointSize*0.75,weight:.semibold))
        }
        resultIcon.isHidden = result == nil
        setAccessibilityLabel(activity?.title ?? "")
        needsLayout = true
    }
    override func layout() {
        super.layout()
        operationIcon.frame = NSRect(x:0,y:(bounds.height-pointSize)/2,width:operationWidth,height:pointSize)
        let side = pointSize*0.75
        resultIcon.frame = NSRect(x:operationWidth+pointSize/5,y:(bounds.height-side)/2,width:side,height:side)
    }
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); if window == nil {TaskActivityAppearance.stop(self)}}
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        TaskActivityAppearance.apply(activity,icon:self,visible:window?.isVisible == true && !isHiddenOrHasHiddenAncestor)
    }
}

// 连接状态共用语义色；呼吸只作用于图标，不重建正文或增加刷新计时器。
enum TaskActivityAppearance {
    static func color(_ activity:TaskActivity?) -> NSColor {
        if activity?.kind == .attention || activity?.outcome == .declined {return StatusTextColor.orange}
        if activity?.outcome == .failed {return StatusTextColor.red}
        switch activity?.statusSymbol {
        case "wifi.exclamationmark":return StatusTextColor.orange
        case "wifi":return StatusTextColor.green
        case "wifi.slash":return StatusTextColor.red
        default:return activity?.kind == .status ? StatusTextColor.red : StatusTextColor.secondary
        }
    }
    static func apply(_ activity:TaskActivity?,icon:TaskActivitySymbolView,text:ProgressMarqueeView? = nil,visible:Bool) {
        let color = color(activity)
        if let text {
            text.textColor = color
            icon.textColor = color
        }
        icon.operationIcon.contentTintColor = activity?.kind == .status || activity?.kind == .attention ? color : icon.textColor
        icon.resultIcon.contentTintColor = activity?.outcome == .declined ? .systemOrange : .systemRed
        if visible && activity?.statusSymbol == "wifi.exclamationmark" && ProgressTextEffects.enabled {
            icon.operationIcon.wantsLayer = true
            if icon.operationIcon.layer?.animation(forKey:"connectionBreathing") == nil {
                let pulse = CABasicAnimation(keyPath:"opacity")
                pulse.fromValue = 0.4; pulse.toValue = 1; pulse.duration = 1
                pulse.autoreverses = true; pulse.repeatCount = .infinity
                icon.operationIcon.layer?.add(pulse,forKey:"connectionBreathing")
            }
        } else {stop(icon)}
    }
    static func stop(_ icon:TaskActivitySymbolView) {icon.operationIcon.layer?.removeAnimation(forKey:"connectionBreathing")}
}
