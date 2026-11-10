import AppKit

final class HistoryTableView: NSTableView {
    var contextMenu: (Int) -> NSMenu? = {_ in nil}
    override func menu(for event:NSEvent) -> NSMenu? {
        let index = row(at:convert(event.locationInWindow,from:nil))
        return index >= 0 ? contextMenu(index) : nil
    }
}

// 保留完整标题供辅助功能和悬停读取；只在显示层合并空白并对超宽末尾淡化。
final class FadingTitleField: NSTextField {
    private let fade = CAGradientLayer()
    override init(frame:NSRect) {
        super.init(frame:frame)
        isEditable = false; isSelectable = false; isBordered = false; drawsBackground = false
        maximumNumberOfLines = 1; usesSingleLineMode = true; lineBreakMode = .byClipping
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        wantsLayer = true
        fade.startPoint = CGPoint(x:0,y:0.5); fade.endPoint = CGPoint(x:1,y:0.5)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let overflow = attributedStringValue.size().width > max(0,bounds.width-4)
        fade.frame = bounds
        fade.colors = [NSColor.black.cgColor,NSColor.black.cgColor,NSColor.clear.cgColor]
        fade.locations = [0,NSNumber(value:Double(max(0,1-24/max(1,bounds.width)))),1]
        layer?.mask = overflow ? fade : nil
        CATransaction.commit()
    }
}

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
    private let titleLabel = FadingTitleField(frame:.zero)
    private let snippetLabel = NSTextField(wrappingLabelWithString:"")
    private let sourceIcon = NSImageView()
    private let sourceLabel = NSTextField(labelWithString:"")
    private let titleText:String, snippetText:String?, query:String
    init(title: String, external: Bool = false, symbol:String? = nil, snippet:String? = nil, query:String = "") {
        titleText = title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" "); snippetText = snippet; self.query = query
        super.init(frame:.zero)
        let kind:ConversationKind = external ? .project : .persona
        sourceLabel.stringValue = kind.title; sourceLabel.font = .systemFont(ofSize:11)
        snippetLabel.maximumNumberOfLines = 2; snippetLabel.lineBreakMode = .byTruncatingTail
        sourceIcon.image = NSImage(systemSymbolName:symbol ?? kind.symbol,accessibilityDescription:symbol == nil ? kind.title : title)
        addSubview(sourceIcon); addSubview(titleLabel); textField = titleLabel; imageView = sourceIcon
        hoverHelp = [title,snippet].compactMap {$0}.joined(separator:"\n")
        setAccessibilityLabel((symbol == nil ? kind.title+"，" : "")+title+(snippet.map {"，"+$0} ?? ""))
        sourceIcon.translatesAutoresizingMaskIntoConstraints = false; titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sourceIcon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),sourceIcon.centerYAnchor.constraint(equalTo:titleLabel.firstBaselineAnchor,constant:-NSFont.systemFont(ofSize:13).capHeight/2),sourceIcon.widthAnchor.constraint(equalToConstant:18),sourceIcon.heightAnchor.constraint(equalToConstant:18),
            titleLabel.leadingAnchor.constraint(equalTo:sourceIcon.trailingAnchor,constant:8),titleLabel.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20)
        ])
        if symbol == nil {
            addSubview(sourceLabel); sourceLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([titleLabel.topAnchor.constraint(equalTo:topAnchor,constant:7),sourceLabel.topAnchor.constraint(equalTo:titleLabel.bottomAnchor,constant:3),sourceLabel.leadingAnchor.constraint(equalTo:titleLabel.leadingAnchor),sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo:titleLabel.trailingAnchor)])
        }
        if snippet != nil {
            addSubview(snippetLabel); snippetLabel.translatesAutoresizingMaskIntoConstraints = false
            if symbol != nil {titleLabel.topAnchor.constraint(equalTo:topAnchor,constant:7).isActive = true}
            NSLayoutConstraint.activate([snippetLabel.topAnchor.constraint(equalTo:symbol == nil ? sourceLabel.bottomAnchor : titleLabel.bottomAnchor,constant:3),snippetLabel.leadingAnchor.constraint(equalTo:titleLabel.leadingAnchor),snippetLabel.trailingAnchor.constraint(equalTo:titleLabel.trailingAnchor),snippetLabel.bottomAnchor.constraint(lessThanOrEqualTo:bottomAnchor,constant:-6)])
        } else if symbol != nil {titleLabel.centerYAnchor.constraint(equalTo:centerYAnchor).isActive = true}
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
        titleLabel.needsLayout = true
        snippetLabel.attributedStringValue = styled(snippetText ?? "",size:11,color:secondary)
        sourceLabel.textColor = secondary
        sourceIcon.contentTintColor = selected ? .alternateSelectedControlTextColor : AppAccent.color
    }
}
