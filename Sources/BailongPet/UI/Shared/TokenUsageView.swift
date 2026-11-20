import AppKit

enum TokenUsageDetailText {
    static func render(_ usage:TokenUsage,format:TokenCountFormat,font:NSFont,color:NSColor,scale:CGFloat = 1) -> (text:NSAttributedString,width:CGFloat) {
        let rows = usage.detailRows(format:format)
        func columnWidth(_ values:[String]) -> CGFloat {
            ceil(values.map {($0 as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0)
        }
        let valueTab = columnWidth(rows.map(\.label))+12*scale
        let unitTab = valueTab+columnWidth(rows.map(\.number))+12*scale
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3*scale
        paragraph.tabStops = [NSTextTab(textAlignment:.left,location:valueTab),NSTextTab(textAlignment:.left,location:unitTab)]
        let value = rows.map {$0.label+"\t"+$0.number+"\t"+$0.unit}.joined(separator:"\n")
        let text = NSAttributedString(string:value,attributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph])
        return (text,unitTab+columnWidth(rows.map(\.unit)))
    }
}

// 额度汇总复用展开控件，明细继续用可选择的 TextKit 文字。
final class QuotaTokenUsageView:NSView {
    override var isFlipped:Bool {true}
    private let heading = NSTextField(labelWithString:"今日用量")
    private let source = NSTextField(labelWithString:"（本机日志）")
    private let disclosure = DisclosureControl(frame:.zero)
    private let detail = SelectableRichText(frame:.zero)
    private let scale:CGFloat, expanded:Bool
    var onToggle:() -> Void = {}
    var onExpansionChange:(_ reveal:Bool) -> Void = {_ in}
    @objc private func preferenceChanged(_ note:Notification) {
        guard let keys = note.userInfo?["keys"] as? [String],let preferences = note.object as? PetPreferences,
              keys.contains(TokenCountFormat.key) || (keys.contains(PetPreferences.tokenDetailsKey) && preferences.bool(PetPreferences.tokenDetailsKey) != expanded) else {return}
        onExpansionChange(!expanded && note.userInfo?["sender"] as? QuotaTokenUsageView === self)
    }
    init(usage:TokenUsage,expanded:Bool,scale:CGFloat,fontScale:CGFloat,headingText:String = "今日用量",format:TokenCountFormat = .full) {
        self.scale = scale; self.expanded = expanded
        super.init(frame:.zero)
        autoresizesSubviews = false
        heading.stringValue = headingText
        let primaryTextColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .white : .black}
        heading.font = .systemFont(ofSize:12*fontScale,weight:.medium); heading.textColor = .labelColor
        source.font = .systemFont(ofSize:11*fontScale); source.textColor = .labelColor
        let amountFont = NSFont.monospacedDigitSystemFont(ofSize:13*fontScale,weight:.semibold)
        disclosure.scale = scale
        disclosure.baseFont = amountFont
        disclosure.chevronTint = primaryTextColor.withAlphaComponent(0.82)
        disclosure.expanded = expanded
        disclosure.accessibilityTitle = headingText+" Token 明细"
        disclosure.attributedTitle = NSAttributedString(string:TokenUsage.amount(usage.total,format:format),attributes:[.font:amountFont,.foregroundColor:primaryTextColor])
        disclosure.onToggle = { [weak self] in self?.onToggle() }
        detail.isHidden = !expanded
        let font = NSFont.monospacedDigitSystemFont(ofSize:12*fontScale,weight:.regular)
        detail.font = font
        detail.attributedStringValue = TokenUsageDetailText.render(usage,format:format,font:font,color:primaryTextColor,scale:scale).text
        [heading,source,disclosure,detail].forEach {addSubview($0)}
    }
    required init?(coder:NSCoder) {fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:PetPreferences.didChange,object:nil)
        if window != nil {NotificationCenter.default.addObserver(self,selector:#selector(preferenceChanged(_:)),name:PetPreferences.didChange,object:nil)}
    }
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
