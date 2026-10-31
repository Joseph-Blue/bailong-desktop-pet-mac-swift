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
    private let snippetLabel = NSTextField(wrappingLabelWithString:"")
    private let sourceIcon = NSImageView()
    private let titleText:String, snippetText:String?, query:String
    init(title: String, external: Bool = false, symbol:String? = nil, snippet:String? = nil, query:String = "") {
        titleText = title; snippetText = snippet; self.query = query
        super.init(frame:.zero)
        titleLabel.maximumNumberOfLines = 1; titleLabel.usesSingleLineMode = true; titleLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 2; snippetLabel.lineBreakMode = .byTruncatingTail
        sourceIcon.image = NSImage(systemSymbolName:symbol ?? (external ? "arrow.down.doc" : "bubble.left"),accessibilityDescription:symbol == nil ? (external ? "Codex 同步记录" : "桌宠对话") : title)
        addSubview(sourceIcon); addSubview(titleLabel); textField = titleLabel; imageView = sourceIcon
        toolTip = [title,snippet].compactMap {$0}.joined(separator:"\n")
        setAccessibilityLabel((symbol == nil ? (external ? "Codex 同步记录，" : "桌宠对话，") : "")+title+(snippet.map {"，"+$0} ?? ""))
        sourceIcon.translatesAutoresizingMaskIntoConstraints = false; titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sourceIcon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),sourceIcon.centerYAnchor.constraint(equalTo:titleLabel.centerYAnchor),sourceIcon.widthAnchor.constraint(equalToConstant:18),sourceIcon.heightAnchor.constraint(equalToConstant:18),
            titleLabel.leadingAnchor.constraint(equalTo:sourceIcon.trailingAnchor,constant:8),titleLabel.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20)
        ])
        if snippet != nil {
            addSubview(snippetLabel); snippetLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([titleLabel.topAnchor.constraint(equalTo:topAnchor,constant:7),snippetLabel.topAnchor.constraint(equalTo:titleLabel.bottomAnchor,constant:3),snippetLabel.leadingAnchor.constraint(equalTo:titleLabel.leadingAnchor),snippetLabel.trailingAnchor.constraint(equalTo:titleLabel.trailingAnchor),snippetLabel.bottomAnchor.constraint(lessThanOrEqualTo:bottomAnchor,constant:-6)])
        } else {titleLabel.centerYAnchor.constraint(equalTo:centerYAnchor).isActive = true}
        updateColors()
    }
    required init?(coder:NSCoder) {fatalError()}
    override var backgroundStyle: NSView.BackgroundStyle {didSet {updateColors()}}
    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        let foreground:NSColor = selected ? .alternateSelectedControlTextColor : .labelColor
        let secondary:NSColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        func styled(_ text:String,size:CGFloat,color:NSColor) -> NSAttributedString {
            let value = NSMutableAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:size,weight:selected ? .semibold : .regular),.foregroundColor:color])
            for range in HistorySearch.ranges(in:text,query:query) {
                value.addAttributes([.font:NSFont.systemFont(ofSize:size,weight:.semibold),.backgroundColor:(selected ? NSColor.white : AppAccent.color).withAlphaComponent(0.2)],range:range)
            }
            return value
        }
        titleLabel.attributedStringValue = styled(titleText,size:13,color:foreground)
        snippetLabel.attributedStringValue = styled(snippetText ?? "",size:11,color:secondary)
        sourceIcon.contentTintColor = selected ? .alternateSelectedControlTextColor : AppAccent.color
    }
}
