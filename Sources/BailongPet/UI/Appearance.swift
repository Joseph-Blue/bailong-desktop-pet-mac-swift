import AppKit
import CoreImage

// 只覆盖本应用外观；nil 交给 AppKit 随系统明暗模式实时更新。
enum AppAppearance {
    static let choices = [("system","跟随系统"),("light","浅色"),("dark","深色")]
    static var selection: String {UserDefaults.standard.string(forKey:"appearanceMode") ?? "system"}
    private static let systemColorObserver = NotificationCenter.default.addObserver(forName:NSColor.systemColorsDidChangeNotification,object:nil,queue:.main) { _ in
        NotificationCenter.default.post(name:AppAccent.didChange,object:nil)
    }
    static func apply() {
        _ = systemColorObserver
        switch selection {
        case "light": NSApp.appearance = NSAppearance(named:.aqua)
        case "dark": NSApp.appearance = NSAppearance(named:.darkAqua)
        default: NSApp.appearance = nil
        }
    }
    static func select(_ value: String) {
        UserDefaults.standard.set(value,forKey:"appearanceMode")
        apply()
    }
}

enum AppAccent {
    static let didChange = Notification.Name("BailongAccentDidChange")
    static let choices = [("system","跟随系统"),("blue","蓝色"),("purple","紫色"),("pink","粉色"),("red","红色"),("orange","橙色"),("yellow","黄色"),("green","绿色"),("gray","石墨色"),("custom","自定义")]
    static var selection: String {UserDefaults.standard.string(forKey:"accentStyle") ?? "system"}
    static var color: NSColor {color(for:selection)}
    // 用户图三：每个色点中心 19×19 区域的 RGB 众数，排除边缘、双环与阴影。
    static let paletteRGB: [String:(Int,Int,Int)] = [
        "blue":(0,122,255), "purple":(149,61,150), "pink":(247,79,158), "red":(224,56,62),
        "orange":(247,130,27), "yellow":(255,199,38), "green":(98,186,70), "gray":(152,152,152)
    ]
    static func color(for key:String) -> NSColor {
        if key == "system" {return .controlAccentColor}
        if key == "custom", let rgb = UserDefaults.standard.array(forKey:"accentRGB") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed:rgb[0],green:rgb[1],blue:rgb[2],alpha:1)
        }
        let rgb = paletteRGB[key] ?? paletteRGB["purple"]!
        return NSColor(srgbRed:Double(rgb.0)/255,green:Double(rgb.1)/255,blue:Double(rgb.2)/255,alpha:1)
    }
    static func select(_ key: String) {
        UserDefaults.standard.set(key,forKey:"accentStyle")
        NotificationCenter.default.post(name:didChange,object:nil)
    }
    static func selectionColor(for appearance: NSAppearance) -> NSColor {
        guard appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua else {return color}
        // 只加深选中背景；链接、标题和图标仍用较明亮的强调色。
        return color.blended(withFraction:0.18,of:.black) ?? color
    }
    static func setCustom(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else {return}
        UserDefaults.standard.set([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],forKey:"accentRGB")
        select("custom")
    }
}

// NSSwitch 没有公开 tint 属性。公开 contentFilters 仅映射原生绘制的颜色，
// 不访问内部子视图、不重画形状，也不替换系统动画、键盘或辅助功能。
enum NativeAccentTint {
    private static let workingSpace = NSColorSpace(cgColorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!)!
    static func apply(to view:NSView) {
        view.wantsLayer = true
        // 在关闭状态也保留映射，原生动画第一帧就使用应用强调色。
        guard AppAccent.selection != "system" else {view.contentFilters = []; return}
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let source = NSColor.controlAccentColor.usingColorSpace(workingSpace)!
            let target = AppAccent.color.usingColorSpace(workingSpace)!
            let from = [source.redComponent,source.greenComponent,source.blueComponent]
            let to = [target.redComponent,target.greenComponent,target.blueComponent]
            let mean = from.reduce(0,+)/3
            let chroma = from.map {$0-mean}, norm = from.map {($0-mean)*($0-mean)}.reduce(0,+)
            let filter:CIFilter
            if norm > 0.00001 {
                // 保持黑、白、灰和 alpha；把原生强调色映射到应用选色。
                filter = CIFilter(name:"CIColorMatrix")!
                for (row,key) in ["inputRVector","inputGVector","inputBVector"].enumerated() {
                    let values = (0..<3).map { column in (row == column ? CGFloat(1) : 0)+(to[row]-from[row])*chroma[column]/norm }
                    filter.setValue(CIVector(x:values[0],y:values[1],z:values[2],w:0),forKey:key)
                }
                filter.setValue(CIVector(x:0,y:0,z:0,w:1),forKey:"inputAVector")
                filter.setValue(CIVector(x:0,y:0,z:0,w:0),forKey:"inputBiasVector")
            } else {
                // 系统石墨色没有色度；只对选中的中间灰值着色，黑白端点不变。
                filter = CIFilter(name:"CIColorPolynomial")!
                for (row,key) in ["inputRedCoefficients","inputGreenCoefficients","inputBlueCoefficients"].enumerated() {
                    let adjustment = (to[row]-from[row])/max(0.00001,from[row]*(1-from[row]))
                    filter.setValue(CIVector(x:0,y:1+adjustment,z:-adjustment,w:0),forKey:key)
                }
                filter.setValue(CIVector(x:0,y:1,z:0,w:0),forKey:"inputAlphaCoefficients")
            }
            view.contentFilters = [filter]
        }
    }
}
final class AccentSwitch: NSSwitch {
    override init(frame:NSRect) {
        super.init(frame:frame)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshTint),name:AppAccent.didChange,object:nil)
        refreshTint()
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func refreshTint() {NativeAccentTint.apply(to:self)}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refreshTint()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); refreshTint()}
}
final class AccentChoiceButton: NSButton {
    init(title:String,type:NSButton.ButtonType) {
        super.init(frame:.zero); self.title = title; setButtonType(type)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshTint),name:AppAccent.didChange,object:nil)
        refreshTint()
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func refreshTint() {NativeAccentTint.apply(to:self)}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refreshTint()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); refreshTint()}
}

// 原生按钮保留键盘、焦点与辅助功能；仅绘制色点及选中双环。
final class AccentSwatch: NSButton {
    let key: String
    init(key:String,name:String) {
        self.key = key; super.init(frame:.zero)
        title = ""; isBordered = false; setButtonType(.toggle); focusRingType = .exterior
        hoverHelp = name; setAccessibilityLabel(name)
        widthAnchor.constraint(equalToConstant:38).isActive = true
        heightAnchor.constraint(equalToConstant:34).isActive = true
    }
    required init?(coder:NSCoder) {fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        let circle = NSRect(x:6,y:4,width:26,height:26)
        let path = NSBezierPath(ovalIn:circle)
        if key == "system" {
            NSGraphicsContext.saveGraphicsState(); path.addClip(); NSGraphicsContext.current?.shouldAntialias = false
            for index in 0..<72 {
                NSColor(calibratedHue:CGFloat(index)/72,saturation:0.9,brightness:0.96,alpha:1).setFill()
                let wedge = NSBezierPath(); wedge.move(to:NSPoint(x:circle.midX,y:circle.midY))
                wedge.appendArc(withCenter:NSPoint(x:circle.midX,y:circle.midY),radius:20,startAngle:CGFloat(index)*5,endAngle:CGFloat(index+1)*5+0.5)
                wedge.close(); wedge.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            AppAccent.color(for:key).setFill(); path.fill()
            if key == "custom" {
                let image = NSImage(systemSymbolName:"paintpalette",accessibilityDescription:nil)
                image?.draw(in:circle.insetBy(dx:5,dy:5))
            }
        }
        NSColor.labelColor.withAlphaComponent(0.14).setStroke(); path.lineWidth = 0.5; path.stroke()
        if state == .on {
            AppAccent.color.setStroke()
            let ring = NSBezierPath(ovalIn:circle.insetBy(dx:-3,dy:-3)); ring.lineWidth = 2; ring.stroke()
        }
        if isHighlighted {NSColor.labelColor.withAlphaComponent(0.12).setFill(); path.fill()}
    }
    override var focusRingMaskBounds:NSRect {NSRect(x:2,y:0,width:34,height:34)}
    override func drawFocusRingMask() {NSBezierPath(ovalIn:focusRingMaskBounds).fill()}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}

// 仍使用 AppKit 进度控件的数据和辅助功能，仅将确定进度条着色为应用强调色。
final class AccentProgressIndicator: NSProgressIndicator {
    override init(frame: NSRect) {
        super.init(frame:frame)
        NotificationCenter.default.addObserver(self,selector:#selector(updateColor),name:AppAccent.didChange,object:nil)
    }
    required init?(coder: NSCoder) {fatalError()}
    @objc private func updateColor() {needsDisplay = true}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
    override func draw(_ dirtyRect: NSRect) {
        guard !isIndeterminate && style == .bar else {super.draw(dirtyRect); return}
        let track = NSBezierPath(roundedRect:bounds,xRadius:bounds.height/2,yRadius:bounds.height/2)
        AppAccent.color.withAlphaComponent(0.16).setFill(); track.fill()
        let amount = max(0,min(1,(doubleValue-minValue)/max(1,maxValue-minValue)))
        guard amount > 0 else {return}
        NSGraphicsContext.saveGraphicsState(); track.addClip()
        let fill = NSRect(x:bounds.minX,y:bounds.minY,width:bounds.width*amount,height:bounds.height)
        AppAccent.color.setFill(); NSBezierPath(roundedRect:fill,xRadius:bounds.height/2,yRadius:bounds.height/2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}


// 普通窗口中的危险操作使用淡红背景与动态红字；保留 NSButton 的交互和辅助功能。
final class SettingsFooterButton: NSButton {
    override func draw(_ dirtyRect:NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let strength: CGFloat = isHighlighted ? (dark ? 0.32 : 0.28) : (dark ? 0.22 : 0.16)
        let foreground = hasDestructiveAction ? NSColor.systemRed : NSColor.labelColor
        let background = hasDestructiveAction ? NSColor.systemRed.withAlphaComponent(strength) : NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.08)
        background.withAlphaComponent(background.alphaComponent * (isEnabled ? 1 : 0.45)).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:0,dy:1),xRadius:8,yRadius:8).fill()
        let attributes: [NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:foreground.withAlphaComponent(isEnabled ? 1 : 0.45)]
        let size = (title as NSString).size(withAttributes:attributes)
        (title as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
    override var focusRingMaskBounds:NSRect {bounds.insetBy(dx:0,dy:1)}
    override func drawFocusRingMask() {NSBezierPath(roundedRect:focusRingMaskBounds,xRadius:8,yRadius:8).fill()}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}

extension NSAlert {
    // 视觉主操作与回车默认操作分开，审批仍默认拒绝。
    func applyAccent(primary: Int = 0, keyboardDefault: Int? = 0) {
        if buttons.isEmpty {addButton(withTitle:"好")}
        layout()
        for (index,button) in buttons.enumerated() {
            // NSAlert 的危险按钮由系统绘制，不能再覆盖为纯红底。
            button.bezelColor = button.hasDestructiveAction ? nil : index == primary ? AppAccent.color : nil
            if button.keyEquivalent == "\r" || button.keyEquivalent == "\u{3}" {button.keyEquivalent = ""}
        }
        let dangerous = buttons.contains(where: \.hasDestructiveAction)
        if !dangerous, let keyboardDefault, buttons.indices.contains(keyboardDefault) {
            buttons[keyboardDefault].keyEquivalent = "\r"; window.defaultButtonCell = buttons[keyboardDefault].cell as? NSButtonCell
        } else {window.defaultButtonCell = nil}
    }
    func beginDangerousSheet(for parent:NSWindow, completion:@escaping (NSApplication.ModalResponse)->Void) {
        precondition(buttons.contains(where: \.hasDestructiveAction))
        applyAccent(primary:buttons.firstIndex(where: \.hasDestructiveAction)!,keyboardDefault:nil)
        // 连聚焦按钮的回车激活也拦截；仅拦当前确认框，不影响其他窗口。
        let monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, parent.attachedSheet === self.window else {return event}
            let target = event.window ?? NSApp.keyWindow
            guard target === self.window || target === parent else {return event}
            if event.keyCode == 36 || event.keyCode == 76 {return nil}
            return event
        }
        beginSheetModal(for:parent) { response in
            if let monitor {NSEvent.removeMonitor(monitor)}
            completion(response)
        }
        window.defaultButtonCell = nil
    }
}
