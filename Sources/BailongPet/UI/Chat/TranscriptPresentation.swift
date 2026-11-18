import AppKit

extension NSAttributedString.Key {
    static let transcriptActions = NSAttributedString.Key("BailongTranscriptActions")
}

// 只属于显示层；按钮、完成时间和用量共用一条可换行的原生底栏。
final class TranscriptActions:NSObject {
    let result: TurnCompletion
    let text:String, threadID:String?, side:CGFloat, font:NSFont, showsActions:Bool
    var id:String {result.id}
    init(_ completion:TurnCompletion, font:NSFont, text:String = "", threadID:String? = nil, showsActions:Bool = true) {
        result = completion
        self.text = text
        self.threadID = threadID
        self.font = .systemFont(ofSize:max(11,font.pointSize-1))
        side = max(28,font.pointSize+12)
        self.showsActions = showsActions
    }
    var ended:String? {["completed":"完成","failed":"失败","interrupted":"中断","cancelled":"停止","canceled":"停止"][result.status]}
    var completion:String {
        guard let ended else {return ""}
        let time = result.completedAt.map {$0.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))} ?? "时间未提供"
        return ended+" · "+time
    }
    override func isEqual(_ object:Any?) -> Bool {
        guard let other = object as? TranscriptActions else {return false}
        return result == other.result && text == other.text && threadID == other.threadID &&
            font == other.font && showsActions == other.showsActions
    }
    override var hash:Int {id.hashValue}
    func placeholder() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = side; paragraph.maximumLineHeight = side; paragraph.paragraphSpacing = 12
        // 末尾不附加换行，否则 TextKit 的额外空行会再次继承整个底栏高度。
        return NSAttributedString(string:"\u{200B}",attributes:[.font:font,.paragraphStyle:paragraph,.transcriptActions:self])
    }
}

final class TranscriptActionBar:NSView {
    override var isFlipped:Bool {true}
    var content:TranscriptActions {didSet {configure()}}
    var expanded = false {didSet {configure()}}
    var onToggle:(() -> Void)?
    private let copyButton = HoverIconButton(symbol:"doc.on.doc",label:"拷贝")
    private let codexButton = HoverIconButton(symbol:"arrow.up.forward",label:"转到 Codex")
    private let completion = NSTextField(wrappingLabelWithString:"")
    private let tokenDisclosure = TokenDisclosureControl(frame:.zero)
    private let detail = SelectableRichText(frame:.zero)
    init(_ content:TranscriptActions) {
        self.content = content
        super.init(frame:.zero)
        for button in [copyButton,codexButton] {
            button.isBordered = false; button.bezelStyle = .inline
            button.contentTintColor = .secondaryLabelColor; addSubview(button)
        }
        copyButton.hoverHelp = "拷贝"
        CopyFeedback.attach(to:copyButton) { [weak self] in self?.content.text }
        codexButton.image = AppIcons.openAI; codexButton.hoverHelp = "转到 Codex"
        codexButton.target = self; codexButton.action = #selector(openCodex)
        tokenDisclosure.onToggle = { [weak self] in self?.toggle() }
        for view in [completion,tokenDisclosure,detail] {addSubview(view)}
        completion.isSelectable = true; detail.isSelectable = true
        configure()
    }
    required init?(coder:NSCoder) {fatalError()}
    private func configure() {
        copyButton.isHidden = !content.showsActions; codexButton.isHidden = !content.showsActions
        copyButton.isEnabled = !content.text.isEmpty
        completion.font = content.font
        let text = NSMutableAttributedString(string:content.completion,attributes:[.font:content.font,.foregroundColor:NSColor.secondaryLabelColor])
        if let ended = content.ended {text.addAttribute(.foregroundColor,value:AppAccent.foregroundColor,range:NSRange(location:0,length:(ended as NSString).length))}
        completion.attributedStringValue = text; completion.isHidden = content.ended == nil
        let font = NSFont.monospacedDigitSystemFont(ofSize:content.font.pointSize,weight:.regular)
        let paragraph = NSMutableParagraphStyle()
        let labelWidth = ["本轮","输入","缓存命中","输出"].map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
        let counts = content.result.usage.map {[$0.total,$0.input,$0.cachedInput,$0.output]} ?? []
        let numberWidth = counts.map {(TokenUsage.formatted($0) as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0
        let valueTab = ceil(labelWidth)+12, unitTab = valueTab+ceil(numberWidth)+12
        paragraph.tabStops = [NSTextTab(textAlignment:.left,location:valueTab),NSTextTab(textAlignment:.left,location:unitTab)]
        paragraph.lineSpacing = 3
        // 汇总是一句话；只有展开后的明细使用制表位，不让“缓存命中”的列宽撑开汇总。
        let heading = "本轮  "+(content.result.usage.map {TokenUsage.amount($0.total,separator:"\u{00A0}")} ?? (content.result.usageError == nil ? "Tokens 未提供" : "Tokens 读取失败"))
        let canExpand = content.result.usage != nil || content.result.usageError != nil
        let primaryTextColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .white : .black}
        tokenDisclosure.scale = max(0.85,content.font.pointSize/12)
        tokenDisclosure.baseFont = font
        tokenDisclosure.chevronTint = .secondaryLabelColor
        tokenDisclosure.expandable = canExpand
        tokenDisclosure.expanded = expanded
        tokenDisclosure.accessibilityTitle = "用量明细"
        tokenDisclosure.attributedTitle = NSAttributedString(string:heading,attributes:[.font:font,.foregroundColor:primaryTextColor])
        tokenDisclosure.isHidden = content.ended == nil
        detail.attributedStringValue = NSAttributedString(string:content.result.usage?.details ?? content.result.usageError ?? "",attributes:[
            .font:font,.paragraphStyle:content.result.usage == nil ? NSParagraphStyle.default : paragraph,.foregroundColor:NSColor.secondaryLabelColor])
        detail.isHidden = !expanded || !canExpand
        needsLayout = true
    }
    // 按控件组换行，不缩字；测量和摆放共用同一算法。
    @discardableResult func arrange(width:CGFloat,placing:Bool = false) -> CGFloat {
        let width = max(1,width),gap:CGFloat = 12,side = content.side
        var x:CGFloat = 0,y:CGFloat = 0,rowHeight:CGFloat = 0,tokenOrigin:CGFloat = 0
        @discardableResult func place(_ size:NSSize,_ apply:(NSRect) -> Void) -> NSRect {
            let size = NSSize(width:min(width,size.width),height:size.height)
            if x > 0 && x+size.width > width {x = 0; y += rowHeight+4; rowHeight = 0}
            let rect = NSRect(x:x,y:y,width:size.width,height:size.height)
            if placing {apply(rect)}
            rowHeight = max(rowHeight,size.height); x += size.width+gap
            return rect
        }
        if content.ended != nil {
            let natural = ceil(completion.attributedStringValue.size().width)+4
            let size = completion.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:min(width,natural),height:10000))
            let completionSlot = place(NSSize(width:min(width,natural),height:max(content.showsActions ? side : 0,size.height))) {r in
                completion.frame = r.insetBy(dx:0,dy:max(0,(r.height-size.height)/2))
                // NSTextField 的文字内边距不计入正文的左侧对齐线。
                completion.frame.origin.x -= completion.cell!.drawingRect(forBounds:completion.bounds).minX
            }
            let leadingInset = tokenDisclosure.textLeadingInset
            let controlSize = tokenDisclosure.preferredSize(maxWidth:width+leadingInset)
            let tokenHeight = max(side,controlSize.height)
            let tokenSlot = place(NSSize(width:controlSize.width-leadingInset,height:tokenHeight)) {rect in
                var controlY = rect.minY+(tokenHeight-controlSize.height)/2
                if rect.minY == completionSlot.minY {
                    tokenDisclosure.frame = NSRect(x:rect.minX-leadingInset,y:controlY,width:controlSize.width,height:controlSize.height)
                    controlY += InlineStatusLayout.baseline(of:completion)-(tokenDisclosure.frame.minY+tokenDisclosure.firstLineBaseline)
                }
                tokenDisclosure.frame = NSRect(x:rect.minX-leadingInset,y:controlY,width:controlSize.width,height:controlSize.height)
            }
            tokenOrigin = tokenSlot.minX
        }
        if content.showsActions {
            let actionsWidth = side*2+8
            if x > 0 && x+actionsWidth > width {x = 0; y += rowHeight+4; rowHeight = 0}
            x = max(x,width-actionsWidth)
            let actionsSlot = place(NSSize(width:actionsWidth,height:side)) {r in
                copyButton.frame = NSRect(x:r.minX,y:r.minY,width:side,height:side)
                codexButton.frame = NSRect(x:r.minX+side+8,y:r.minY,width:side,height:side)
            }
            if placing,content.ended != nil,actionsSlot.minY == 0 {
                InlineStatusLayout.align(copyButton,to:completion,side:side)
                InlineStatusLayout.align(codexButton,to:completion,side:side)
            }
        }
        var height = y+rowHeight
        if !detail.isHidden {
            let detailWidth = max(1,width-tokenOrigin)
            let h = detail.height(for:detailWidth)
            if placing {detail.frame = NSRect(x:tokenOrigin,y:height+4,width:detailWidth,height:h)}
            height += h+4+max(4,content.font.pointSize/2)
        }
        return height
    }
    override func layout() {super.layout(); arrange(width:bounds.width,placing:true)}
    @objc private func openCodex() {CodexConnection.openConversation(content.threadID)}
    @objc private func toggle() {onToggle?()}
}

enum TranscriptIcon {
    static func render(_ source:NSImage?,font:NSFont,description:String) -> NSAttributedString {
        guard let source else {return NSAttributedString()}
        let side = font.pointSize
        let image = NSImage(size:NSSize(width:side,height:side),flipped:false) {rect in
            source.draw(in:rect)
            AppAccent.foregroundColor.setFill(); rect.fill(using:.sourceIn)
            return true
        }
        image.cacheMode = .never; image.accessibilityDescription = description
        let attachment = NSTextAttachment(); attachment.image = image
        attachment.bounds = NSRect(x:0,y:(font.capHeight-side)/2,width:side,height:side)
        let result = NSMutableAttributedString(attributedString:NSAttributedString(attachment:attachment))
        result.append(NSAttributedString(string:" ",attributes:[.font:font]))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 6
        result.addAttributes([.font:font,.foregroundColor:AppAccent.foregroundColor,.paragraphStyle:paragraph],range:NSRange(location:0,length:result.length))
        return result
    }
}
