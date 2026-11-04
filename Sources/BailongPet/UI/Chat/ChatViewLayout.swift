import AppKit

enum ChatViewLayout {
    static func configureSendButton(_ button:ActionButton) {
        button.image = NSImage(systemSymbolName:"arrow.up",accessibilityDescription:nil)
        button.imagePosition = .imageLeading
        button.extraHorizontalPadding = 24
        button.configureFlexible(font:button.font ?? .systemFont(ofSize:13))
        button.setAccessibilityLabel("发送")
    }

    static func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0, verticalInset: CGFloat? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:inset),view.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-inset),view.topAnchor.constraint(equalTo:parent.topAnchor,constant:verticalInset ?? inset),view.bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-(verticalInset ?? inset))])
    }
    static func inputBox(_ editor: MessageEditor) -> MessageInputBox {
        MessageInputBox(scroll:editorScroll(editor),editor:editor)
    }
    static func editorScroll(_ editor: NSTextView) -> NSScrollView {
        let scroll = GutterScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        editor.frame = NSRect(x:0,y:0,width:300,height:100)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true; editor.textContainer?.containerSize = NSSize(width:300,height:CGFloat.greatestFiniteMagnitude)
        editor.font = .systemFont(ofSize:14); editor.textColor = .labelColor; editor.drawsBackground = false
        editor.textContainerInset = NSSize(width:4,height:6); editor.isRichText = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.minSize = .zero; editor.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor
        return scroll
    }
}
