import AppKit

extension NSAttributedString.Key {
    static let transcriptActions = NSAttributedString.Key("BailongTranscriptActions")
}

// 只属于显示层；按钮、完成时间和用量共用一条可换行的原生底栏。
final class TranscriptActions:NSObject {
    let id:String, text:String, threadID:String?, side:CGFloat, font:NSFont
    let status:String?, completedAt:Date?, usage:TokenUsage?, usageError:String?, showsActions:Bool
    init(id:String,text:String,threadID:String?,font:NSFont,status:String? = nil,completedAt:Date? = nil,
         usage:TokenUsage? = nil,usageError:String? = nil,showsActions:Bool = true) {
        self.id = id; self.text = text; self.threadID = threadID; self.font = .systemFont(ofSize:max(11,font.pointSize-1))
        side = max(28,font.pointSize+12); self.status = status; self.completedAt = completedAt
        self.usage = usage; self.usageError = usageError; self.showsActions = showsActions
    }
    var ended:String? {["completed":"完成","failed":"失败","interrupted":"中断","cancelled":"停止","canceled":"停止"][status ?? ""]}
    var completion:String {
        guard let ended else {return ""}
        let time = completedAt.map {$0.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))} ?? "时间未提供"
        return ended+" · "+time
    }
    override func isEqual(_ object:Any?) -> Bool {
        guard let other = object as? TranscriptActions else {return false}
        return id == other.id && text == other.text && threadID == other.threadID && font == other.font &&
            status == other.status && completedAt == other.completedAt && usage == other.usage && usageError == other.usageError && showsActions == other.showsActions
    }
    override var hash:Int {id.hashValue}
    func placeholder() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = side; paragraph.maximumLineHeight = side; paragraph.paragraphSpacing = 12
        // 末尾不附加换行，否则 TextKit 的额外空行会再次继承整个底栏高度。
        return NSAttributedString(string:"\u{200B}",attributes:[.font:font,.paragraphStyle:paragraph,.transcriptActions:self])
    }
}

// 使用自身 TextKit 排版与选择，避免 NSTextField 切换共享 field editor 时丢失制表位。
private final class TranscriptTokenText:AppTextView {
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

final class TranscriptActionBar:NSView {
    override var isFlipped:Bool {true}
    var content:TranscriptActions {didSet {configure()}}
    var expanded = false {didSet {configure()}}
    var onToggle:(() -> Void)?
    private let copyButton = HoverIconButton(symbol:"doc.on.doc",label:"拷贝")
    private let codexButton = HoverIconButton(symbol:"arrow.up.forward",label:"转到 Codex")
    private let completion = NSTextField(wrappingLabelWithString:"")
    private let tokenGroup = NSView()
    private let tokens = TranscriptTokenText(frame:.zero)
    private let disclosure = HoverIconButton(symbol:"chevron.right",label:"展开用量明细")
    private var tokenTextWidth:CGFloat = 0
    private let detail = TranscriptTokenText(frame:.zero)
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
        disclosure.target = self; disclosure.action = #selector(toggle)
        tokenGroup.addSubview(tokens); tokenGroup.addSubview(disclosure)
        for view in [completion,tokenGroup,detail] {addSubview(view)}
        completion.isSelectable = true; tokens.isSelectable = true; detail.isSelectable = true
        configure()
    }
    required init?(coder:NSCoder) {fatalError()}
    private func configure() {
        copyButton.isHidden = !content.showsActions; codexButton.isHidden = !content.showsActions
        copyButton.isEnabled = !content.text.isEmpty
        completion.font = content.font
        let text = NSMutableAttributedString(string:content.completion,attributes:[.font:content.font,.foregroundColor:NSColor.secondaryLabelColor])
        if let ended = content.ended {text.addAttribute(.foregroundColor,value:AppAccent.color,range:NSRange(location:0,length:(ended as NSString).length))}
        completion.attributedStringValue = text; completion.isHidden = content.ended == nil
        let font = NSFont.monospacedDigitSystemFont(ofSize:content.font.pointSize,weight:.regular)
        let paragraph = NSMutableParagraphStyle()
        let labelWidth = ["本轮","输入","缓存命中","输出"].map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
        let counts = content.usage.map {[$0.total,$0.input,$0.cachedInput,$0.output]} ?? []
        let numberWidth = counts.map {(TokenUsage.formatted($0) as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0
        let valueTab = ceil(labelWidth)+12, unitTab = valueTab+ceil(numberWidth)+12
        paragraph.tabStops = [NSTextTab(textAlignment:.left,location:valueTab),NSTextTab(textAlignment:.left,location:unitTab)]
        paragraph.lineSpacing = 3
        let heading = "本轮\t"+(content.usage.map {TokenUsage.formatted($0.total)+"\tTokens"} ?? (content.usageError == nil ? "Tokens 未提供" : "Tokens 读取失败"))
        tokens.attributedStringValue = NSAttributedString(string:heading,attributes:[.font:font,.paragraphStyle:paragraph,.foregroundColor:NSColor.labelColor])
        tokenTextWidth = content.usage == nil ? valueTab+(heading.components(separatedBy:"\t").last! as NSString).size(withAttributes:[.font:font]).width+4 : unitTab+("Tokens" as NSString).size(withAttributes:[.font:font]).width+4
        tokenGroup.isHidden = content.ended == nil
        disclosure.isHidden = content.usage == nil && content.usageError == nil
        disclosure.image = NSImage(systemSymbolName:expanded ? "chevron.down" : "chevron.right",accessibilityDescription:nil)
        disclosure.setAccessibilityLabel(expanded ? "收起用量明细" : "展开用量明细")
        detail.attributedStringValue = NSAttributedString(string:content.usage?.details ?? content.usageError ?? "",attributes:[
            .font:font,.paragraphStyle:content.usage == nil ? NSParagraphStyle.default : paragraph,.foregroundColor:NSColor.secondaryLabelColor])
        detail.isHidden = !expanded || disclosure.isHidden
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
        if content.showsActions {place(NSSize(width:side*2+8,height:side)) {r in
            copyButton.frame = NSRect(x:r.minX,y:r.minY,width:side,height:side)
            codexButton.frame = NSRect(x:r.minX+side+8,y:r.minY,width:side,height:side)
        }}
        if content.ended != nil {
            let natural = ceil(completion.attributedStringValue.size().width)+4
            let size = completion.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:min(width,natural),height:10000))
            place(NSSize(width:min(width,natural),height:max(content.showsActions ? side : 0,size.height))) {r in
                completion.frame = r.insetBy(dx:0,dy:max(0,(r.height-size.height)/2))
            }
            let arrowWidth:CGFloat = disclosure.isHidden ? 0 : side+4
            let tokenWidth = min(width,tokenTextWidth+arrowWidth)
            let labelWidth = max(1,tokenWidth-arrowWidth)
            let labelHeight = tokens.height(for:labelWidth)
            let tokenHeight = max(side,labelHeight)
            tokenOrigin = place(NSSize(width:tokenWidth,height:tokenHeight)) {rect in
                tokenGroup.frame = rect
                tokens.frame = NSRect(x:0,y:(tokenHeight-labelHeight)/2,width:labelWidth,height:labelHeight)
                disclosure.frame = NSRect(x:labelWidth+4,y:(tokenHeight-side)/2,width:side,height:side)
                disclosure.frame.origin.y = tokens.convert(NSPoint(x:0,y:tokens.firstLineCenter),to:tokenGroup).y-side/2
            }.minX
        }
        if placing,content.showsActions,content.ended != nil,completion.frame.minX > 0 {
            InlineStatusLayout.align(copyButton,to:completion,side:side)
            InlineStatusLayout.align(codexButton,to:completion,side:side)
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
            AppAccent.color.setFill(); rect.fill(using:.sourceIn)
            return true
        }
        image.cacheMode = .never; image.accessibilityDescription = description
        let attachment = NSTextAttachment(); attachment.image = image
        attachment.bounds = NSRect(x:0,y:(font.capHeight-side)/2,width:side,height:side)
        let result = NSMutableAttributedString(attributedString:NSAttributedString(attachment:attachment))
        result.append(NSAttributedString(string:" ",attributes:[.font:font]))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 6
        result.addAttributes([.font:font,.foregroundColor:AppAccent.color,.paragraphStyle:paragraph],range:NSRange(location:0,length:result.length))
        return result
    }
}
