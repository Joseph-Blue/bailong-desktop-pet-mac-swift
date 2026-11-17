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
            while let view = hit {
                if view is TemplateContextMenu {return event}
                if let text = view as? NSTextView, text.isEditable || text.isSelectable {
                    NSMenu.popUpContextMenu(menu(for:text),with:event,for:text); return nil
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

class AppTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {TextContextMenu.menu(for:self)}
}

// NSBox 会把 addSubview 重定向到 contentView；焦点层必须与 NSBox 同级。
final class MessageInputBox: NSView {
    private let surface = NSBox()
    let scroll: NSScrollView
    var fillColor:NSColor {get {surface.fillColor} set {surface.fillColor = newValue}}
    var contentSize:NSSize {
        var size = scroll.contentSize
        if let scroll = scroll as? GutterScrollView {size.width = scroll.documentLayoutWidth}
        return size
    }
    init(scroll:NSScrollView,editor:MessageEditor) {
        self.scroll = scroll; super.init(frame:.zero)
        surface.boxType = .custom; surface.borderColor = .separatorColor; surface.fillColor = .textBackgroundColor
        surface.cornerRadius = 8; surface.borderWidth = 0.5; surface.contentViewMargins = NSSize(width:8,height:8)
        addSubview(surface); surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([surface.leadingAnchor.constraint(equalTo:leadingAnchor,constant:4),surface.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-4),surface.topAnchor.constraint(equalTo:topAnchor,constant:4),surface.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-4)])
        let content = surface.contentView!
        scroll.borderType = .noBorder; scroll.focusRingType = .none
        content.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:content.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:content.trailingAnchor),scroll.topAnchor.constraint(equalTo:content.topAnchor),scroll.bottomAnchor.constraint(equalTo:content.bottomAnchor)])
        EditorFocusRing.attach(to:self,editor:editor,radius:8)
    }
    required init?(coder:NSCoder) {fatalError()}
}

// 原生 focus-ring 绘制独立于正文，只对焦点层应用本应用的颜色映射。
final class EditorFocusRing: NSView {
    private weak var editor: MessageEditor?
    private var radius: CGFloat = 8
    static func attach(to container: NSView, editor: MessageEditor, radius: CGFloat) {
        let ring = EditorFocusRing(frame:.zero)
        ring.editor = editor; ring.radius = radius
        ring.focusRingType = .none; container.addSubview(ring)
        // NSBox 及滚动容器初始尺寸尚未确定，不能从零尺寸 frame 推导 autoresizing。
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([ring.leadingAnchor.constraint(equalTo:container.leadingAnchor),ring.trailingAnchor.constraint(equalTo:container.trailingAnchor),ring.topAnchor.constraint(equalTo:container.topAnchor),ring.bottomAnchor.constraint(equalTo:container.bottomAnchor)])
        editor.focusRingType = .none
        editor.onFocusChange = { [weak ring] in ring?.needsDisplay = true }
        for name in [NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification,AppAccent.didChange] {
            NotificationCenter.default.addObserver(ring,selector:#selector(ring.refresh),name:name,object:nil)
        }
        ring.refresh()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {nil}
    @objc private func refresh() {NativeAccentTint.apply(to:self); needsDisplay = true}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refresh()}
    override func draw(_ dirtyRect:NSRect) {
        guard let editor, editor.isEditable, window?.isKeyWindow == true, window?.firstResponder === editor else {return}
        NSGraphicsContext.saveGraphicsState()
        NSFocusRingPlacement.only.set()
        NSBezierPath(roundedRect:bounds.insetBy(dx:4,dy:4),xRadius:radius,yRadius:radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
