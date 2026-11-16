import AppKit

// 使用自身 TextKit 排版与选择，避免 NSTextField 切换共享 field editor 时丢失制表位。
final class TranscriptTokenText:AppTextView {
    override init(frame:NSRect) {
        let storage = NSTextStorage(), manager = NSLayoutManager()
        let container = NSTextContainer(size:NSSize(width:1,height:CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        super.init(frame:frame,textContainer:container)
        isEditable = false; isSelectable = true; isRichText = true; drawsBackground = false
        isVerticallyResizable = false; isHorizontallyResizable = false; autoresizingMask = []
        textContainerInset = .zero
        self.textContainer?.lineFragmentPadding = 0
        self.textContainer?.widthTracksTextView = false
        self.textContainer?.heightTracksTextView = false
    }
    required init?(coder:NSCoder) {fatalError()}
    var attributedStringValue:NSAttributedString {
        get {attributedString()}
        set {if !attributedString().isEqual(to:newValue) {textStorage?.setAttributedString(newValue)}}
    }
    func height(for width:CGFloat) -> CGFloat {
        guard let container = textContainer,let manager = layoutManager else {return 0}
        container.containerSize = NSSize(width:max(1,width),height:.greatestFiniteMagnitude)
        manager.ensureLayout(for:container)
        return ceil(manager.usedRect(for:container).maxY)
    }
    var firstLineCenter:CGFloat {
        guard let manager = layoutManager,manager.numberOfGlyphs > 0 else {return bounds.midY}
        let line = manager.lineFragmentRect(forGlyphAt:0,effectiveRange:nil)
        return textContainerOrigin.y+line.minY+manager.location(forGlyphAt:0).y-(font?.capHeight ?? 0)/2
    }
}

// 额度与历史共用可选择的 TextKit 明细，不借用全局 field editor。
final class QuotaTokenUsageView:NSView {
    override var isFlipped:Bool {true}
    private let heading = NSTextField(labelWithString:"今日用量")
    private let source = NSTextField(labelWithString:"（本机日志）")
    private let amount = NSTextField(labelWithString:"")
    private let arrow = NSButton()
    private let detail = TranscriptTokenText(frame:.zero)
    private let scale:CGFloat, expanded:Bool
    var onToggle:() -> Void = {}
    init(usage:TokenUsage,expanded:Bool,scale:CGFloat,fontScale:CGFloat) {
        self.scale = scale; self.expanded = expanded
        super.init(frame:.zero)
        autoresizesSubviews = false
        heading.font = .systemFont(ofSize:12*fontScale,weight:.medium)
        source.font = .systemFont(ofSize:11*fontScale); source.textColor = .labelColor
        amount.font = .monospacedDigitSystemFont(ofSize:13*fontScale,weight:.semibold)
        amount.stringValue = TokenUsage.formatted(usage.total)+" Tokens"; amount.isSelectable = true
        arrow.setButtonType(.pushOnPushOff); arrow.bezelStyle = .disclosure; arrow.title = ""
        arrow.state = expanded ? .on : .off; arrow.target = self; arrow.action = #selector(toggle)
        arrow.setAccessibilityLabel(expanded ? "收起今日 Token 明细" : "展开今日 Token 明细")
        detail.isHidden = !expanded
        let font = NSFont.monospacedDigitSystemFont(ofSize:12*fontScale,weight:.regular)
        let labels = ["输入","缓存命中","输出"], numbers = [usage.input,usage.cachedInput,usage.output].map(TokenUsage.formatted)
        let labelWidth = labels.map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
        let numberWidth = numbers.map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3*scale
        paragraph.tabStops = [NSTextTab(textAlignment:.left,location:ceil(labelWidth)+12*scale),NSTextTab(textAlignment:.left,location:ceil(labelWidth+numberWidth)+24*scale)]
        let primaryTextColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .white : .black}
        detail.font = font
        detail.attributedStringValue = NSAttributedString(string:usage.details,attributes:[.font:font,.foregroundColor:primaryTextColor,.paragraphStyle:paragraph])
        [heading,source,amount,arrow,detail].forEach {addSubview($0)}
    }
    required init?(coder:NSCoder) {fatalError()}
    @discardableResult func arrange(width:CGFloat) -> CGFloat {
        let height = arrange(width:width,placing:false)
        // 先确定容器的完整尺寸，再摆放 TextKit 子视图；后续原生布局也使用同一组几何。
        frame.size = NSSize(width:width,height:height)
        _ = arrange(width:width,placing:true)
        return height
    }
    private func arrange(width:CGFloat,placing:Bool) -> CGFloat {
        let side = 22*scale,gap = 8*scale
        let headingHeight = ceil(heading.fittingSize.height),sourceHeight = ceil(source.fittingSize.height)
        let labelHeight = headingHeight+2*scale+sourceHeight, amountHeight = max(side,ceil(amount.fittingSize.height))
        let amountWidth = min(ceil(amount.fittingSize.width),max(1,width-side-gap))
        let labelWidth = max(heading.fittingSize.width,source.fittingSize.width)
        let wrapped = labelWidth+amountWidth+side+2*gap > width
        let rowHeight = max(labelHeight,amountHeight)
        let amountY = wrapped ? labelHeight+4*scale : (rowHeight-amountHeight)/2
        var height = wrapped ? amountY+amountHeight : rowHeight
        if placing {
            let labelWidth = wrapped ? width : width-amountWidth-side-2*gap
            heading.frame = NSRect(x:0,y:0,width:labelWidth,height:headingHeight)
            source.frame = NSRect(x:0,y:headingHeight+2*scale,width:labelWidth,height:sourceHeight)
            amount.frame = NSRect(x:width-side-gap-amountWidth,y:amountY,width:amountWidth,height:amountHeight)
            arrow.frame = NSRect(x:width-side,y:amountY+(amountHeight-side)/2,width:side,height:side)
        }
        if expanded {
            let detailHeight = detail.height(for:width)
            if placing {detail.frame = NSRect(x:0,y:height+8*scale,width:width,height:detailHeight)}
            height += detailHeight+12*scale
        }
        return height
    }
    override func layout() {super.layout(); _ = arrange(width:bounds.width,placing:true)}
    @objc private func toggle() {onToggle()}
}
