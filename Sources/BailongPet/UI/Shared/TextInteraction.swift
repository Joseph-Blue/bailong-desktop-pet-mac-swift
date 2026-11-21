import AppKit

// 仅个性页的模板编辑器保留变量菜单。
protocol TemplateContextMenu {}

enum TextContextMenu {
    private static let commands = [("剪切",#selector(NSText.cut(_:)),"x","scissors"),("拷贝",#selector(NSText.copy(_:)),"c","doc.on.doc"),("粘贴",#selector(NSText.paste(_:)),"v","doc.on.clipboard"),("全选",#selector(NSResponder.selectAll(_:)),"a","")]
    static func menu(for target: NSTextView) -> NSMenu {
        let menu = NSMenu(); menu.allowsContextMenuPlugIns = false
        for (title,action,key,symbol) in commands {
            if action == #selector(NSResponder.selectAll(_:)) {menu.addItem(.separator())}
            let item = NSMenuItem(title:title,action:action,keyEquivalent:key)
            item.keyEquivalentModifierMask = .command
            if !symbol.isEmpty {
                item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            }
            item.target = target; menu.addItem(item)
        }
        menu.showProvidedImages()
        return menu
    }
    static func performKeyEquivalent(_ event:NSEvent,in window:NSWindow) -> Bool {
        guard window.isKeyWindow,
              event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command,
              let text = window.firstResponder as? NSTextView,text.isSelectable || text.isEditable,
              let command = commands.first(where:{$0.2 == event.charactersIgnoringModifiers?.lowercased()}) else {return false}
        let item = NSMenuItem(title:command.0,action:command.1,keyEquivalent:command.2)
        if text.validateUserInterfaceItem(item) {NSApp.sendAction(command.1,to:text,from:item)}
        return true
    }
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else {return}
        // 原生文本框共用系统 field editor；不替换安全文本框的 editor 或改写 AppKit 方法。
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.rightMouseDown,.leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  let content = event.window?.contentView else {return event}
            var hit = content.hitTest(content.convert(event.locationInWindow,from:nil))
            var inputAncestor = hit
            while let view = inputAncestor {
                if let editor = view as? MessageEditor,!editor.usesCompactContextMenu {return event}
                inputAncestor = view.superview
            }
            while let view = hit {
                if view is TemplateContextMenu {return event}
                if let text = view as? NSTextView, text.isEditable || text.isSelectable {
                    let context = (text as? AppTextView)?.menu(for:event) ?? menu(for:text)
                    NSMenu.popUpContextMenu(context,with:event,for:text); return nil
                }
                if let field = view as? NSTextField, field.isSelectable || field.isEditable {
                    if field.currentEditor() == nil {field.selectText(nil)}
                    guard let editor = field.currentEditor() as? NSTextView else {return event}
                    if editor is TemplateContextMenu {return event}
                    NSMenu.popUpContextMenu(menu(for:editor),with:event,for:field); return nil
                }
                hit = view.superview
            }
            return event
        }
    }
}

class AccentTextView:NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:AppAccent.didChange,object:nil)
        guard window != nil else {return}
        NotificationCenter.default.addObserver(self,selector:#selector(refreshTextAccent),name:AppAccent.didChange,object:nil)
        refreshTextAccent()
    }
    @objc private func refreshTextAccent() {
        insertionPointColor = AppAccent.insertionPoint
        selectedTextAttributes[.backgroundColor] = AppAccent.selectedTextBackground
        needsDisplay = true
    }
}

class AppTextView: AccentTextView {
    override func menu(for event: NSEvent) -> NSMenu? {TextContextMenu.menu(for:self)}
}

// 使用自身 TextKit 排版与选择，避免 NSTextField 切换共享 field editor 时丢失富文本格式。
final class SelectableRichText:AppTextView {
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
        container.containerSize = NSSize(width:max(1,width-2*textContainerInset.width),height:.greatestFiniteMagnitude)
        manager.ensureLayout(for:container)
        return ceil(manager.usedRect(for:container).maxY+2*textContainerInset.height)
    }
    override var firstBaselineOffsetFromTop:CGFloat {
        guard let manager = layoutManager,manager.numberOfGlyphs > 0 else {return super.firstBaselineOffsetFromTop}
        let line = manager.lineFragmentRect(forGlyphAt:0,effectiveRange:nil)
        return textContainerOrigin.y+line.minY+manager.location(forGlyphAt:0).y
    }
}

// 多行输入和只读富文本共用同一外框，编辑器的焦点与键盘行为由各自入口管理。
final class MessageTextBoxSurface: NSBox {
    init(scroll: NSScrollView) {
        super.init(frame:scroll.frame)
        boxType = .custom
        borderColor = .separatorColor
        fillColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .textBackgroundColor : .white}
        cornerRadius = 8; borderWidth = 0.5; contentViewMargins = NSSize(width:6,height:6)
        scroll.borderType = .noBorder; scroll.focusRingType = .none; scroll.drawsBackground = false
        if let text = scroll.documentView as? NSTextView {
            text.drawsBackground = false
            text.textContainerInset = NSSize(width:4,height:4)
            text.textContainer?.lineFragmentPadding = 0
        }
        let content = contentView!
        content.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:content.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:content.topAnchor),scroll.bottomAnchor.constraint(equalTo:content.bottomAnchor)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}
}

final class MessageInputBox: NSView {
    private let surface:MessageTextBoxSurface
    let scroll: NSScrollView
    private let editor:MessageEditor
    var contentHeight:CGFloat {editor.contentHeight+max(0,bounds.height-contentSize.height)}
    var fillColor:NSColor {get {surface.fillColor} set {surface.fillColor = newValue}}
    var contentSize:NSSize {scroll.contentSize}
    init(scroll:NSScrollView,editor:MessageEditor) {
        self.scroll = scroll; self.editor = editor
        surface = MessageTextBoxSurface(scroll:scroll)
        super.init(frame:.zero)
        addSubview(surface); surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([surface.leadingAnchor.constraint(equalTo:leadingAnchor,constant:4),surface.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-4),surface.topAnchor.constraint(equalTo:topAnchor,constant:4),surface.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-4)])
        editor.focusRingType = .none
        TextInputFocusRing(surface:surface,input:editor,in:self)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func layout() {
        super.layout()
        scroll.layoutSubtreeIfNeeded()
        let size = contentSize
        if editor.minSize.height != size.height {editor.minSize.height = size.height}
        let editorSize = NSSize(width:size.width,height:max(editor.frame.height,size.height))
        if editor.frame.size != editorSize {editor.setFrameSize(editorSize)}
    }
}
