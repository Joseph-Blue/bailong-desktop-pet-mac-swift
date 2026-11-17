import AppKit

// 短状态按实际行数显示，长报错在独立区域内滚动，保留完整文本及复制能力。
final class ComposerStatusView:GutterScrollView {
    private let text = AppTextView()
    private var heightConstraint:NSLayoutConstraint!
    override init(frame:NSRect) {
        super.init(frame:frame)
        drawsBackground = false; borderType = .noBorder; hasVerticalScroller = true
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.drawsBackground = false; text.font = .systemFont(ofSize:11)
        text.textColor = .secondaryLabelColor; text.alignment = .right
        text.textContainerInset = .zero; text.textContainer?.lineFragmentPadding = 0
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.minSize = .zero; text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        documentView = text
        heightConstraint = heightAnchor.constraint(equalToConstant:16); heightConstraint.isActive = true
        isHidden = true
    }
    required init?(coder:NSCoder) {fatalError()}
    func update(_ value:String) {
        if text.string != value {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
            paragraph.lineBreakMode = .byWordWrapping
            text.textStorage?.setAttributedString(NSAttributedString(string:value,attributes:[
                .font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph]))
            text.scrollToBeginningOfDocument(nil)
        }
        isHidden = value.isEmpty
    }
    func measure(width:CGFloat) {
        guard let container = text.textContainer,let layout = text.layoutManager else {return}
        let documentWidth = max(1,Self.documentWidth(for:width))
        text.setFrameSize(NSSize(width:documentWidth,height:text.frame.height))
        container.containerSize = NSSize(width:documentWidth,height:CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for:container)
        let height = max(16,layout.usedRect(for:container).height.rounded(.up))
        text.setFrameSize(NSSize(width:documentWidth,height:height))
        heightConstraint.constant = min(96,height)
    }
}
