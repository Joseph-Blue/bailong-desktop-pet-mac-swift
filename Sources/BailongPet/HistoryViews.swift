import AppKit

final class AccentHistoryRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle {isSelected ? .emphasized : .normal}
    override func drawSelection(in dirtyRect: NSRect) {
        AppAccent.color.setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:5,dy:2),xRadius:7,yRadius:7).fill()
    }
}
final class FadingHistoryCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString:"")
    private let fade = CAGradientLayer()
    init(title: String) {
        super.init(frame:.zero)
        titleLabel.stringValue = title; titleLabel.font = .systemFont(ofSize:13)
        titleLabel.maximumNumberOfLines = 1; titleLabel.usesSingleLineMode = true; titleLabel.lineBreakMode = .byClipping
        titleLabel.wantsLayer = true; addSubview(titleLabel); textField = titleLabel
        toolTip = title; setAccessibilityLabel(title)
        fade.colors = [NSColor.black.cgColor,NSColor.black.cgColor,NSColor.clear.cgColor]
        fade.startPoint = CGPoint(x:0,y:0.5); fade.endPoint = CGPoint(x:1,y:0.5)
    }
    required init?(coder:NSCoder) {fatalError()}
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {titleLabel.textColor = backgroundStyle == .emphasized ? .white : .labelColor}
    }
    override func layout() {
        super.layout()
        let height = titleLabel.intrinsicContentSize.height.rounded(.up)
        titleLabel.frame = NSRect(x:12,y:(bounds.height-height)/2,width:max(0,bounds.width-24),height:height)
        if titleLabel.intrinsicContentSize.width > titleLabel.bounds.width {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            fade.frame = titleLabel.bounds
            fade.locations = [0,NSNumber(value:max(0,1-24/max(1,titleLabel.bounds.width))),1]
            titleLabel.layer?.mask = fade; CATransaction.commit()
        } else {titleLabel.layer?.mask = nil}
    }
}
