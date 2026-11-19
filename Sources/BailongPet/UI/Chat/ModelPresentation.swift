import AppKit

enum ModelPresentation {
    static func name(_ id:String,displayName:String? = nil) -> String {
        if let displayName,!displayName.isEmpty {return displayName}
        guard id.hasPrefix("gpt-") else {return id}
        // 只规范显示大小写，原模型 ID 继续用于读取及发送。
        return id.split(separator:"-",omittingEmptySubsequences:false).enumerated().map {index,part in
            index == 0 ? "GPT" : part.prefix(1).uppercased()+part.dropFirst()
        }.joined(separator:"-")
    }
    static func provider(_ id:String?,name:String? = nil,usesChatGPTAccount:Bool = false) -> String? {
        if id == "openai",usesChatGPTAccount {return nil}
        if let name,!name.isEmpty {return name}
        switch id?.lowercased() {
        case "openai":return "OpenAI"
        case "amazonbedrock","amazon-bedrock","bedrock":return "Bedrock"
        case "gcp","google","vertex","vertexai":return "Vertex AI"
        default:return id
        }
    }
    static func summary(model:String,displayName:String? = nil,effort:String,provider:String? = nil) -> String {
        [provider,name(model,displayName:displayName),effort].compactMap {$0}.joined(separator:" · ")
    }
}

enum ModelSummaryLayout {
    static let maximumModelWidth:CGFloat = 320
    static let minimumModelWidth:CGFloat = 180
    static let maximumStatusFraction:CGFloat = 0.55

    static func arrange(available:CGFloat,statusWidth:CGFloat,desiredModelWidth:CGFloat) -> (modelWidth:CGFloat,statusInline:Bool) {
        let usable = max(1,available)
        let desired = max(1,min(maximumModelWidth,desiredModelWidth))
        guard statusWidth > 0 else {return (desired,false)}
        let minimum = min(minimumModelWidth,desired)
        let canInline = statusWidth <= floor(usable*maximumStatusFraction) && statusWidth+minimum <= usable
        guard canInline else {return (desired,false)}
        return (max(minimum,min(desired,usable-statusWidth)),true)
    }
}

// 两类会话共用原生模型字段的尺寸、字体和轮廓；交互能力由各子类决定。
class ModelSummaryButton:NSButton {
    private var summaryText:String?
    private var showsLightning = false
    private var providerIcon:NSImage?
    private var widthLimit:NSLayoutConstraint!
    var preservesProviderIconColor:Bool {false}
    private var separateProviderIcon:NSImage? {
        guard preservesProviderIconColor,let providerIcon,!providerIcon.isTemplate else {return nil}
        return providerIcon
    }
    var maximumLayoutWidth:CGFloat = ModelSummaryLayout.maximumModelWidth {
        didSet {
            let value = max(1,min(ModelSummaryLayout.maximumModelWidth,maximumLayoutWidth))
            if abs(value-maximumLayoutWidth) > 0.5 {maximumLayoutWidth = value; return}
            guard abs(value-oldValue) > 0.5 else {return}
            widthLimit?.constant = value
            invalidateIntrinsicContentSize()
            superview?.needsLayout = true
        }
    }
    var naturalLayoutWidth:CGFloat {min(ModelSummaryLayout.maximumModelWidth,intrinsicContentSize.width.rounded(.up))}
    var layoutWidth:CGFloat {min(maximumLayoutWidth,intrinsicContentSize.width.rounded(.up))}

    @discardableResult func setSummary(_ text:String,lightning:Bool,providerIcon:NSImage? = nil) -> Bool {
        guard summaryText != text || showsLightning != lightning || self.providerIcon !== providerIcon else {return false}
        summaryText = text; showsLightning = lightning; self.providerIcon = providerIcon
        title = text
        setAccessibilityValue((lightning ? "快速模式 · " : "")+text)
        applySummaryIcons()
        invalidateIntrinsicContentSize()
        needsDisplay = true
        superview?.needsLayout = true
        return true
    }
    override var font:NSFont? {
        didSet {
            guard oldValue != font else {return}
            applySummaryIcons()
            invalidateIntrinsicContentSize()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySummaryIcons()
    }
    private func applySummaryIcons() {
        guard let text = summaryText,providerIcon != nil || showsLightning else {return}
        let font = font ?? .systemFont(ofSize:13)
        let side = font.pointSize
        let foreground = NSColor(cgColor:AppAppearance.resolvedColor(.labelColor,for:effectiveAppearance)) ?? .labelColor
        let value = NSMutableAttributedString(string:"")
        func append(_ image:NSImage?) {
            let square = NSSize(width:side,height:side)
            let icon = NSImage(size:square,flipped:false) { rect in
                guard let image else {return true}
                image.draw(in:ModelSummaryButton.imageRect(for:image,in:rect))
                if image.isTemplate {foreground.setFill(); rect.fill(using:.sourceIn)}
                return true
            }
            let attachment = NSTextAttachment(); attachment.image = icon
            attachment.bounds = NSRect(x:0,y:(font.capHeight-side)/2,width:side,height:side)
            value.append(NSAttributedString(attachment:attachment))
            value.append(NSAttributedString(string:" ",attributes:[.font:font]))
        }
        // 标题为独立绘制的供应商图标保留同样的宽度。
        if let providerIcon {append(separateProviderIcon == nil ? providerIcon : nil)}
        if showsLightning,let bolt = NSImage(systemSymbolName:"bolt",accessibilityDescription:"快速模式") {append(bolt)}
        value.append(NSAttributedString(string:text,attributes:[.font:font]))
        attributedTitle = value
    }
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        guard let icon = separateProviderIcon,let cell else {return}
        let titleRect = cell.titleRect(forBounds:bounds)
        let side = font?.pointSize ?? 13
        guard titleRect.width >= side else {return}
        let lineWidth = min(titleRect.width,attributedTitle.size().width)
        let slot = NSRect(x:titleRect.midX-lineWidth/2,y:titleRect.midY-side/2,width:side,height:side)
        icon.draw(in:Self.imageRect(for:icon,in:slot))
    }
    private static func imageRect(for image:NSImage,in rect:NSRect) -> NSRect {
        let size = image.size
        let scale = min(rect.width/size.width,rect.height/size.height)
        let width = size.width*scale, height = size.height*scale
        return NSRect(x:rect.midX-width/2,y:rect.midY-height/2,width:width,height:height)
    }
    override init(frame:NSRect) {
        super.init(frame:frame)
        bezelStyle = .rounded; font = .systemFont(ofSize:13)
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        setContentHuggingPriority(.required,for:.horizontal)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        widthLimit = widthAnchor.constraint(lessThanOrEqualToConstant:ModelSummaryLayout.maximumModelWidth)
        widthLimit.isActive = true
    }
    required init?(coder:NSCoder) {fatalError()}
}
