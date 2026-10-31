import AppKit

final class AccentHistoryRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle {isSelected && isEmphasized ? .emphasized : .normal}
    override var isSelected: Bool {didSet {refreshSelection()}}
    override var isEmphasized: Bool {didSet {refreshSelection()}}
    private func refreshSelection() {
        needsDisplay = true
        for cell in subviews.compactMap({$0 as? NSTableCellView}) {cell.backgroundStyle = interiorBackgroundStyle}
    }
    override func drawBackground(in dirtyRect: NSRect) {
        guard isSelected else {return}
        // 系统色与自定义色使用相同轮廓；以滚动视口为边界，避免宽行的右圆角被裁掉。
        let viewport = enclosingScrollView.map {convert($0.contentView.bounds,from:$0.contentView)} ?? visibleRect
        let left = max(bounds.minX,viewport.minX), right = min(bounds.maxX,viewport.maxX)
        let frame = NSRect(x:left,y:bounds.minY,width:max(0,right-left),height:bounds.height).insetBy(dx:10,dy:2)
        guard frame.width > 0 && frame.height > 0 else {return}
        (isEmphasized ? AppAccent.selectionColor(for:effectiveAppearance) : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        NSBezierPath(roundedRect:frame,xRadius:7,yRadius:7).fill()
    }
    override func layout() {super.layout(); needsDisplay = true}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
final class HistoryConversationCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString:"")
    private let sourceIcon = NSImageView()
    init(title: String, external: Bool = false, symbol:String? = nil) {
        super.init(frame:.zero)
        titleLabel.stringValue = title; titleLabel.font = .systemFont(ofSize:13)
        titleLabel.maximumNumberOfLines = 1; titleLabel.usesSingleLineMode = true; titleLabel.lineBreakMode = .byTruncatingTail
        sourceIcon.image = NSImage(systemSymbolName:symbol ?? (external ? "arrow.down.doc" : "bubble.left"),accessibilityDescription:symbol == nil ? (external ? "Codex 同步记录" : "桌宠对话") : title)
        addSubview(sourceIcon); addSubview(titleLabel); textField = titleLabel; imageView = sourceIcon
        toolTip = title; setAccessibilityLabel(symbol == nil ? (external ? "Codex 同步记录，" : "桌宠对话，")+title : title)
        sourceIcon.translatesAutoresizingMaskIntoConstraints = false; titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sourceIcon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),sourceIcon.centerYAnchor.constraint(equalTo:centerYAnchor),sourceIcon.widthAnchor.constraint(equalToConstant:18),sourceIcon.heightAnchor.constraint(equalToConstant:18),
            titleLabel.leadingAnchor.constraint(equalTo:sourceIcon.trailingAnchor,constant:8),titleLabel.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20),titleLabel.centerYAnchor.constraint(equalTo:centerYAnchor)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            titleLabel.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
            titleLabel.font = .systemFont(ofSize:13,weight:backgroundStyle == .emphasized ? .semibold : .regular)
            sourceIcon.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : AppAccent.color
        }
    }
}
