import AppKit

extension NSAttributedString.Key {
    static let transcriptActions = NSAttributedString.Key("BailongTranscriptActions")
}

// 仅附着于历史显示文本，不进入历史数据或模型上下文。
final class TranscriptActions:NSObject {
    let id:String, text:String, threadID:String?, side:CGFloat
    init(id:String,text:String,threadID:String?,font:NSFont) {
        self.id = id; self.text = text; self.threadID = threadID; side = max(28,font.pointSize+12)
    }
    override func isEqual(_ object:Any?) -> Bool {
        guard let other = object as? TranscriptActions else {return false}
        return id == other.id && text == other.text && threadID == other.threadID && side == other.side
    }
    override var hash:Int {id.hashValue}
    func placeholder() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = side; paragraph.maximumLineHeight = side
        paragraph.paragraphSpacing = 12
        return NSAttributedString(string:"\u{200B}\n",attributes:[
            .font:NSFont.systemFont(ofSize:11),.paragraphStyle:paragraph,.transcriptActions:self])
    }
}

final class TranscriptActionBar:NSView {
    var content:TranscriptActions {didSet {copyButton.isEnabled = !content.text.isEmpty}}
    private let copyButton = HoverIconButton(symbol:"doc.on.doc",label:"拷贝")
    private let codexButton = HoverIconButton(symbol:"arrow.up.forward",label:"转到 Codex")
    init(_ content:TranscriptActions) {
        self.content = content
        super.init(frame:.zero)
        for button in [copyButton,codexButton] {
            button.isBordered = false; button.bezelStyle = .inline
            button.contentTintColor = .secondaryLabelColor; addSubview(button)
        }
        copyButton.hoverHelp = "拷贝"; copyButton.isEnabled = !content.text.isEmpty
        CopyFeedback.attach(to:copyButton) { [weak self] in self?.content.text }
        codexButton.image = AppIcons.openAI; codexButton.hoverHelp = "转到 Codex"
        codexButton.target = self; codexButton.action = #selector(openCodex)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func layout() {
        super.layout()
        copyButton.frame = NSRect(x:0,y:0,width:content.side,height:content.side)
        codexButton.frame = NSRect(x:content.side+8,y:0,width:content.side,height:content.side)
    }
    @objc private func openCodex() {CodexConnection.openConversation(content.threadID)}
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
