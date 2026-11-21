import AppKit

// 仅个性页的模板编辑器保留变量菜单。
protocol TemplateContextMenu {}

enum BrowserSearchEngine:String, CaseIterable {
    case bing, google, duckDuckGo, yandex, brave, ecosia, startpage, perplexity, sogou, so360, baidu

    static let key = "browserSearchEngine"
    static let defaultEngine = Self.bing
    static let group = "网页搜索"
    static let settingTitle = "搜索引擎"
    static var options:[(String,String)] {allCases.map {($0.rawValue,$0.title)}}

    var title:String {
        switch self {
        case .bing: return "Bing"
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .yandex: return "Yandex"
        case .brave: return "Brave Search"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        case .perplexity: return "Perplexity"
        case .sogou: return "搜狗"
        case .so360: return "360 搜索"
        case .baidu: return "百度"
        }
    }

    func searchURL(for query:String) -> URL? {
        let endpoint:(host:String,path:String,key:String)
        switch self {
        case .bing: endpoint = ("www.bing.com","/search","q")
        case .google: endpoint = ("www.google.com","/search","q")
        case .duckDuckGo: endpoint = ("duckduckgo.com","/","q")
        case .yandex: endpoint = ("yandex.com","/search/","text")
        case .brave: endpoint = ("search.brave.com","/search","q")
        case .ecosia: endpoint = ("www.ecosia.org","/search","q")
        case .startpage: endpoint = ("www.startpage.com","/sp/search","query")
        case .perplexity: endpoint = ("www.perplexity.ai","/search","q")
        case .sogou: endpoint = ("www.sogou.com","/web","query")
        case .so360: endpoint = ("www.so.com","/s","q")
        case .baidu: endpoint = ("www.baidu.com","/s","wd")
        }
        var components = URLComponents()
        components.scheme = "https"; components.host = endpoint.host; components.path = endpoint.path
        var items = [URLQueryItem(name:endpoint.key,value:query)]
        if self == .sogou || self == .so360 || self == .baidu {items.append(URLQueryItem(name:"ie",value:"UTF-8"))}
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B")
        return components.url
    }
}

enum TextContextMenu {
    private static let selectAll = #selector(NSResponder.selectAll(_:))
    private static let startSpeaking = #selector(NSTextView.startSpeaking(_:))
    private static let stopSpeaking = #selector(NSTextView.stopSpeaking(_:))
    private static let startDictation = NSSelectorFromString("startDictation:")
    private static let characterPalette = #selector(NSApplication.orderFrontCharacterPalette(_:))
    private static let dictationIcon: NSImage? = {
        let image = NSImage(systemSymbolName:"mic",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        image?.isTemplate = true
        return image
    }()
    private static let commands = [("剪切",#selector(NSText.cut(_:)),"x","scissors"),("拷贝",#selector(NSText.copy(_:)),"c","doc.on.doc"),("粘贴",#selector(NSText.paste(_:)),"v","doc.on.clipboard"),("全选",selectAll,"a","")]
    static weak var editMenu:NSMenu?

    static func menu(for target:NSTextView,systemMenu:@autoclosure () -> NSMenu?) -> NSMenu {
        let menu = NSMenu(); menu.allowsContextMenuPlugIns = false
        for (title,action,key,symbol) in commands {
            if action == selectAll {
                menu.addItem(.separator())
                undoItems(for:target).forEach {menu.addItem($0)}
            }
            let item = NSMenuItem(title:title,action:action,keyEquivalent:key)
            item.keyEquivalentModifierMask = .command
            item.image = editMenu?.items.first(where:{$0.action == action})?.image
            if item.image == nil,!symbol.isEmpty {
                item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            }
            item.target = target; menu.addItem(item)
        }
        let content = contentItems(for:target,systemMenu:systemMenu())
        if !content.isEmpty {
            menu.addItem(.separator())
            content.forEach {menu.addItem($0)}
        }
        if let editMenu,canInsertText(in:target),target.window?.isKeyWindow == true,target.window?.firstResponder === target {
            let input = systemInputItems(in:editMenu)
            if !input.isEmpty {
                menu.addItem(.separator())
                for item in input {
                    let copy = item.copy() as! NSMenuItem
                    copy.isHidden = false
                    copy.image = item.image
                    menu.addItem(copy)
                }
            }
        }
        menu.showProvidedImages()
        return menu
    }

    static func updateEditMenu(_ menu:NSMenu,for window:NSWindow?) {
        guard let index = menu.items.firstIndex(where:{$0.action == selectAll}) else {return}
        let input = systemInputItems(in:menu)
        for item in menu.items.dropFirst(index+1) {
            // AppKit 还会插入隐藏的系统快捷键项，保留其原生绑定。
            if isSystemInputItem(item) && (item.allowsKeyEquivalentWhenHidden || input.contains(where:{$0 === item})) {continue}
            menu.removeItem(item)
        }
        let text = window?.firstResponder as? NSTextView
        let showInput = text.map {canInsertText(in:$0)} ?? false
        input.forEach {$0.isHidden = !showInput}
        var items:[NSMenuItem] = []
        if let window,let text {
            let content = contentItems(for:text,systemMenu:systemMenuForSelection(in:text,window:window))
            if !content.isEmpty {items = [.separator()] + content}
        }
        if showInput && !input.isEmpty {items.append(.separator())}
        for (offset,item) in items.enumerated() {menu.insertItem(item,at:index+1+offset)}
    }

    private static func undoItems(for target:NSTextView) -> [NSMenuItem] {
        guard canInsertText(in:target),let manager = target.undoManager else {return []}
        let commands:[(Bool,String,Selector,String,NSEvent.ModifierFlags)] = [
            (manager.canUndo,"撤销",#selector(UndoManager.undo),"undo:",.command),
            (manager.canRedo,"重做",#selector(UndoManager.redo),"redo:",[.command,.shift])
        ]
        return commands.compactMap {available,title,action,systemAction,modifiers in
            guard available else {return nil}
            let item = NSMenuItem(title:title,action:action,keyEquivalent:"z")
            item.keyEquivalentModifierMask = modifiers
            item.target = manager
            item.image = editMenu?.items.first(where:{$0.action == NSSelectorFromString(systemAction)})?.image
            return item
        }
    }

    private static func contentItems(for target:NSTextView,systemMenu:@autoclosure () -> NSMenu?) -> [NSMenuItem] {
        guard !target.hasMarkedText(),!(target.delegate is NSSecureTextField) else {return []}
        let range = target.selectedRange()
        let text = target.string
        var items:[NSMenuItem] = []
        let native = systemMenu()
        if range.length > 0,let selection = Range(range,in:text) {
            let query = text[selection].trimmingCharacters(in:.whitespacesAndNewlines)
            if !query.isEmpty {
                let saved = PetPreferences.shared.string(BrowserSearchEngine.key)
                let engine = BrowserSearchEngine(rawValue:saved) ?? .defaultEngine
                items.append(MenuAction("使用 \(engine.title) 网页搜索",symbol:"magnifyingglass") {openSearch(query,using:engine)})
                // AppKit 没有公开翻译项标识。保留系统创建的项及其原生动作。
                if let native,let translation = native.items.first(where:{NSStringFromClass(type(of:$0)) == "RVTranslateMenuItem"}) {
                    native.removeItem(translation)
                    translation.title = "翻译"
                    items.append(translation)
                }
            }
        }
        if let native,let speech = native.items.first(where:{$0.submenu?.items.contains(where:{$0.action == startSpeaking}) == true}),
           let commands = speech.submenu?.items,commands.contains(where:{target.validateMenuItem($0)}) {
            speech.title = "语音"
            for command in commands {
                if command.action == startSpeaking {command.title = "开始朗读"; command.target = target}
                if command.action == stopSpeaking {command.title = "停止朗读"; command.target = target}
            }
            native.removeItem(speech)
            items.append(speech)
        }
        return items
    }

    private static func canInsertText(in text:NSTextView) -> Bool {
        text.isEditable && !text.hasMarkedText() && !(text.delegate is NSSecureTextField)
    }

    static func isSystemInputItem(_ item:NSMenuItem) -> Bool {
        item.action == startDictation || item.action == characterPalette
    }

    private static func systemInputItems(in menu:NSMenu) -> [NSMenuItem] {
        let items = [startDictation,characterPalette].compactMap {action in
            menu.items.first(where:{$0.action == action && !$0.allowsKeyEquivalentWhenHidden})
        }
        // 菜单栏和右键菜单都显式提供听写图标，动作沿用系统菜单项。
        items.first(where:{$0.action == startDictation})?.image = dictationIcon
        return items
    }

    private static func systemMenuForSelection(in text:NSTextView,window:NSWindow) -> NSMenu? {
        let rect = window.convertFromScreen(text.firstRect(forCharacterRange:text.selectedRange(),actualRange:nil))
        let location = NSPoint(x:rect.midX,y:rect.midY)
        guard let event = NSEvent.mouseEvent(with:.rightMouseDown,location:location,modifierFlags:[],timestamp:0,
                                            windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1) else {return nil}
        if let text = text as? AccentTextView {return text.systemContextMenu(for:event)}
        return text.menu(for:event)
    }

    private static func openSearch(_ query:String,using engine:BrowserSearchEngine) {
        guard let url = engine.searchURL(for:query) else {return}
        if !NSWorkspace.shared.open(url) {showError("无法打开浏览器",PetFailure(message:"系统未能打开搜索网址。"))}
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
                    let context = (text as? AccentTextView)?.menu(for:event) ?? menu(for:text,systemMenu:text.menu(for:event))
                    NSMenu.popUpContextMenu(context,with:event,for:text); return nil
                }
                if let field = view as? NSTextField, field.isSelectable || field.isEditable {
                    if field is NSSecureTextField {return event}
                    if field.currentEditor() == nil {field.selectText(nil)}
                    guard let editor = field.currentEditor() as? NSTextView else {return event}
                    if editor is TemplateContextMenu {return event}
                    NSMenu.popUpContextMenu(menu(for:editor,systemMenu:editor.menu(for:event)),with:event,for:field); return nil
                }
                hit = view.superview
            }
            return event
        }
    }
}

class AccentTextView:NSTextView {
    func systemContextMenu(for event:NSEvent) -> NSMenu? {super.menu(for:event)}

    func compactContextMenu(for event:NSEvent) -> NSMenu {
        TextContextMenu.menu(for:self,systemMenu:systemContextMenu(for:event))
    }

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
    override func menu(for event:NSEvent) -> NSMenu? {compactContextMenu(for:event)}
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
