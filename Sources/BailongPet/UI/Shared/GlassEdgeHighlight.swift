import AppKit

final class GlassEdgeHighlight: NSView {
    var cornerRadius:CGFloat = 14 {didSet {needsLayout = true}}
    private let gradient = CAGradientLayer()
    private let outline = CAShapeLayer()

    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        gradient.startPoint = CGPoint(x:0.5,y:0)
        gradient.endPoint = CGPoint(x:0.5,y:1)
        gradient.locations = [0,0.45,1]
        outline.fillColor = nil
        outline.strokeColor = NSColor.white.cgColor
        gradient.mask = outline
        layer?.addSublayer(gradient)
        updateColors()
    }
    required init?(coder:NSCoder) {fatalError()}
    override func hitTest(_ point:NSPoint) -> NSView? {nil}

    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = (dark ? [0.22,0.08,0.42] : [0.36,0.16,0.72]).map {NSColor.white.withAlphaComponent($0).cgColor}
        CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); updateColors()}
    override func viewDidChangeBackingProperties() {super.viewDidChangeBackingProperties(); needsLayout = true}
    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 1
        let width = 1/scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        outline.frame = gradient.bounds
        outline.contentsScale = scale
        outline.lineWidth = width
        let rect = outline.bounds.insetBy(dx:width/2,dy:width/2)
        let radius = max(0,cornerRadius-width/2)
        outline.path = CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil)
        CATransaction.commit()
    }
}
