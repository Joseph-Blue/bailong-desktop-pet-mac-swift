import AppKit

// 额度与历史共用可选择的 TextKit 明细，汇总触发区复用独立的 TokenDisclosureControl。
final class QuotaTokenUsageView:NSView {
    override var isFlipped:Bool {true}
    private let heading = NSTextField(labelWithString:"今日用量")
    private let source = NSTextField(labelWithString:"（本机日志）")
    private let disclosure = TokenDisclosureControl(frame:.zero)
    private let detail = SelectableRichText(frame:.zero)
    private let scale:CGFloat, expanded:Bool
    var onToggle:() -> Void = {}
    init(usage:TokenUsage,expanded:Bool,scale:CGFloat,fontScale:CGFloat) {
        self.scale = scale; self.expanded = expanded
        super.init(frame:.zero)
        autoresizesSubviews = false
        let primaryTextColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .white : .black}
        heading.font = .systemFont(ofSize:12*fontScale,weight:.medium); heading.textColor = .labelColor
        source.font = .systemFont(ofSize:11*fontScale); source.textColor = .labelColor
        let amountFont = NSFont.monospacedDigitSystemFont(ofSize:13*fontScale,weight:.semibold)
        disclosure.scale = scale
        disclosure.baseFont = amountFont
        disclosure.chevronTint = primaryTextColor.withAlphaComponent(0.82)
        disclosure.expanded = expanded
        disclosure.accessibilityTitle = "今日 Token 明细"
        disclosure.attributedTitle = NSAttributedString(string:TokenUsage.amount(usage.total),attributes:[.font:amountFont,.foregroundColor:primaryTextColor])
        disclosure.onToggle = { [weak self] in self?.onToggle() }
        detail.isHidden = !expanded
        let font = NSFont.monospacedDigitSystemFont(ofSize:12*fontScale,weight:.regular)
        let labels = ["输入","缓存命中","输出"], numbers = [usage.input,usage.cachedInput,usage.output].map(TokenUsage.formatted)
        let labelWidth = labels.map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
        let numberWidth = numbers.map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3*scale
        paragraph.tabStops = [NSTextTab(textAlignment:.left,location:ceil(labelWidth)+12*scale),NSTextTab(textAlignment:.left,location:ceil(labelWidth+numberWidth)+24*scale)]
        detail.font = font
        detail.attributedStringValue = NSAttributedString(string:usage.details,attributes:[.font:font,.foregroundColor:primaryTextColor,.paragraphStyle:paragraph])
        [heading,source,disclosure,detail].forEach {addSubview($0)}
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
        let gap = 8*scale
        let headingHeight = ceil(heading.fittingSize.height),sourceHeight = ceil(source.fittingSize.height)
        let labelHeight = headingHeight+2*scale+sourceHeight
        let controlSize = disclosure.preferredSize(maxWidth:width)
        let labelWidth = max(heading.fittingSize.width,source.fittingSize.width)
        let wrapped = labelWidth+controlSize.width+gap > width
        let rowHeight = max(labelHeight,controlSize.height)
        let controlY = wrapped ? labelHeight+4*scale : (rowHeight-controlSize.height)/2
        var height = wrapped ? controlY+controlSize.height : rowHeight
        if placing {
            let actualLabelWidth = wrapped ? width : max(1,width-controlSize.width-gap)
            heading.frame = NSRect(x:0,y:0,width:actualLabelWidth,height:headingHeight)
            source.frame = NSRect(x:0,y:headingHeight+2*scale,width:actualLabelWidth,height:sourceHeight)
            disclosure.frame = NSRect(x:width-controlSize.width,y:controlY,width:controlSize.width,height:controlSize.height)
        }
        if expanded {
            let detailHeight = detail.height(for:width)
            if placing {detail.frame = NSRect(x:0,y:height+8*scale,width:width,height:detailHeight)}
            height += detailHeight+12*scale
        }
        return height
    }
    override func layout() {super.layout(); _ = arrange(width:bounds.width,placing:true)}
}
