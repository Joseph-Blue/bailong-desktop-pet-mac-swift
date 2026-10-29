import AppKit

// 只覆盖本应用外观；nil 交给 AppKit 随系统明暗模式实时更新。
enum AppAppearance {
    static let choices = [("system","跟随系统"),("light","浅色"),("dark","深色")]
    static var selection: String {UserDefaults.standard.string(forKey:"appearanceMode") ?? "system"}
    static func apply() {
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
    static let choices = [("purple","紫色（默认）"),("blue","蓝色"),("pink","粉色"),("green","绿色"),("orange","橙色"),("system","跟随 macOS"),("custom","自定义颜色")]
    static var selection: String {UserDefaults.standard.string(forKey:"accentStyle") ?? "purple"}
    static var color: NSColor {
        switch selection {
        case "system": return .controlAccentColor
        case "blue": return .systemBlue
        case "pink": return .systemPink
        case "green": return .systemGreen
        case "orange": return .systemOrange
        case "custom":
            if let rgb = UserDefaults.standard.array(forKey:"accentRGB") as? [Double], rgb.count == 3 {
                return NSColor(srgbRed:rgb[0],green:rgb[1],blue:rgb[2],alpha:1)
            }
            fallthrough
        default:
            return NSColor(name:NSColor.Name("BailongPurple")) {appearance in
                appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
                    ? NSColor(srgbRed:0.72,green:0.55,blue:0.86,alpha:1)
                    : NSColor(srgbRed:0.60,green:0.40,blue:0.74,alpha:1)
            }
        }
    }
    static func select(_ key: String) {
        UserDefaults.standard.set(key,forKey:"accentStyle")
        NotificationCenter.default.post(name:didChange,object:nil)
    }
    static func selectionColor(for appearance: NSAppearance) -> NSColor {
        guard appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua else {return color}
        // 只加深选中背景；链接、标题和图标仍用较明亮的强调色。
        if selection == "purple" {return NSColor(srgbRed:0.50,green:0.30,blue:0.65,alpha:1)}
        return color.blended(withFraction:0.18,of:.black) ?? color
    }
    static func setCustom(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else {return}
        UserDefaults.standard.set([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],forKey:"accentRGB")
        select("custom")
    }
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


extension NSAlert {
    func applyAccent(primary: Int = 0) {
        if buttons.isEmpty {addButton(withTitle:"好")}
        for (index,button) in buttons.enumerated() {button.bezelColor = index == primary ? AppAccent.color : nil}
    }
}
