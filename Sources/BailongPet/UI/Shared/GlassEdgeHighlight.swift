import AppKit

// 只绘制，不命中鼠标，不参与键盘响应或窗口激活。
final class GlassEdgeHighlight:NSView {
    var cornerRadius:CGFloat = 14 {didSet {needsDisplay = true}}
    override func hitTest(_ point:NSPoint) -> NSView? {nil}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
    override func viewDidChangeBackingProperties() {super.viewDidChangeBackingProperties(); needsDisplay = true}
    override func draw(_ rect:NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {return}
        let width = 1 / (window?.backingScaleFactor ?? 2)
        let shape = bounds.insetBy(dx:width/2,dy:width/2)
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        context.saveGState()
        context.addPath(CGPath(roundedRect:shape,cornerWidth:cornerRadius-width/2,cornerHeight:cornerRadius-width/2,transform:nil))
        context.setLineWidth(width); context.replacePathWithStrokedPath(); context.clip()
        let gradient = NSGradient(colorsAndLocations:(NSColor.white.withAlphaComponent(dark ? 0.22 : 0.36),0),
            (NSColor.white.withAlphaComponent(dark ? 0.08 : 0.16),0.45),
            (NSColor.white.withAlphaComponent(dark ? 0.42 : 0.72),1))!
        gradient.draw(in:bounds,angle:90)
        context.restoreGState()
    }
}
