import AppKit

// 保留原生分栏拖动，中间 16pt 为呼吸空间，不再叠两条边框。
final class HistorySplitView: NSSplitView {
    override var dividerThickness: CGFloat {16}
    override func drawDivider(in rect: NSRect) {}
}
final class HistorySidebarView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame:frame)
        material = .sidebar; blendingMode = .behindWindow; state = .followsWindowActiveState
        wantsLayer = true; layer?.cornerRadius = 10; layer?.masksToBounds = true
    }
    required init?(coder:NSCoder) {fatalError()}
}

final class AccentHistoryRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle {isSelected ? .emphasized : .normal}
    override func drawSelection(in dirtyRect: NSRect) {
        // 侧栏缩窄或出现滚动条时，按实际可见宽度绘制，保留右侧两个圆角。
        let left = max(bounds.minX,visibleRect.minX), right = min(bounds.maxX,visibleRect.maxX)
        let frame = NSRect(x:left,y:bounds.minY,width:max(0,right-left),height:bounds.height).insetBy(dx:5,dy:2)
        guard frame.width > 0 && frame.height > 0 else {return}
        AppAccent.selectionColor(for:effectiveAppearance).setFill()
        NSBezierPath(roundedRect:frame,xRadius:7,yRadius:7).fill()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
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
