import AppKit

// 消息只呈现已收到的正文快照；内容更新、几何测量和阅读位置分别处理。
final class MessageTextView: LinkTextView {
    // NSTextView 的便利初始化会再次进入指定初始化；按首次使用创建，避免覆盖已分配的 Swift 存储。
    private lazy var fileEditPresentation = FileEditPresentation()
    var onContentLayoutChange:(() -> Void)?
    private var measuredWidth:CGFloat = -1
    private var measuredHeight:CGFloat = 0
    private var codeToolbars = [Int:CodeBlockToolbar]()
    private var transcriptToolbars = [Int:TranscriptActionBar]()
    private var fileDisclosures = [String:(control:DisclosureControl,range:NSRange,size:NSSize)]()
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:PetPreferences.didChange,object:nil)
        guard window != nil else {return}
        NotificationCenter.default.addObserver(self,selector:#selector(tokenPreferenceChanged(_:)),name:PetPreferences.didChange,object:PetPreferences.shared)
        if !transcriptToolbars.isEmpty {updateTokenLayout()}
    }
    @objc private func tokenPreferenceChanged(_ note:Notification) {
        guard let keys = note.userInfo?["keys"] as? [String],keys.contains(PetPreferences.tokenDetailsKey) || keys.contains(TokenCountFormat.key),
              !transcriptToolbars.isEmpty else {return}
        let sender = note.userInfo?["sender"] as? TranscriptActionBar
        guard let sender,sender.superview === self else {updateTokenLayout(); return}
        DisclosureMotion.update(in:self,animatesLayout:false) {
            updateTokenLayout()
            if sender.expanded {
                layoutSubtreeIfNeeded()
                let font = sender.content.font
                let height = ceil(font.ascender-font.descender+font.leading)+8
                scrollToVisible(NSRect(x:0,y:max(0,sender.frame.maxY-height),width:1,height:height))
            }
        }
    }
    private func updateTokenLayout() {
        prepareInlineControls(width:bounds.width)
        measuredWidth = -1; invalidateCodeLayout()
        if isVerticallyResizable {sizeToFit()}
        onContentLayoutChange?()
    }
    private var preparingInlineControls = false
    private var resizingFrame = false
    private var codeLayoutDirty = true
    private var codeLayoutWidth:CGFloat = -1
    var hasTruncatedText:Bool {
        guard let container = textContainer,let manager = layoutManager else {return false}
        return manager.hasTruncatedText(in:container)
    }
    private func invalidateCodeLayout() {codeLayoutDirty = true; needsLayout = true}
    override func setFrameSize(_ newSize:NSSize) {
        resizingFrame = true
        defer {resizingFrame = false}
        super.setFrameSize(newSize)
    }
    @discardableResult override func scrollToVisible(_ rect:NSRect) -> Bool {
        // NSTextView 随 clip 尺寸更新自身高度时会把插入点滚入视口；只读正文不随容器排版自动跳动。
        guard !resizingFrame else {return false}
        return super.scrollToVisible(rect)
    }
    override func layout() {
        prepareInlineControls(width:bounds.width)
        super.layout()
        guard codeLayoutDirty || codeLayoutWidth != bounds.width else {return}
        guard let storage = textStorage,let manager = layoutManager else {return}
        codeLayoutDirty = false; codeLayoutWidth = bounds.width
        for (control,range,size) in fileDisclosures.values {
            manager.ensureLayout(forCharacterRange:range)
            let glyphs = manager.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            guard glyphs.length > 0 else {continue}
            let line = manager.lineFragmentRect(forGlyphAt:glyphs.location,effectiveRange:nil)
            let textX = line.minX+textContainerOrigin.x+(textContainer?.lineFragmentPadding ?? 0)
            let x = max(bounds.minX,textX-control.textLeadingInset)
            control.frame = NSRect(origin:NSPoint(x:x,y:line.minY+textContainerOrigin.y),size:size)
        }
        var seen = Set<Int>()
        storage.enumerateAttribute(.codeBlockHeader,in:NSRange(location:0,length:storage.length)) {value,range,_ in
            guard let content = value as? CodeBlockContent,
                  let paragraph = storage.attribute(.paragraphStyle,at:range.location,effectiveRange:nil) as? NSParagraphStyle,
                  !paragraph.textBlocks.isEmpty else {return}
            seen.insert(range.location)
            let toolbar = codeToolbars[range.location] ?? CodeBlockToolbar(content)
            toolbar.content = content
            if toolbar.superview == nil {addSubview(toolbar); codeToolbars[range.location] = toolbar}
            manager.ensureLayout(forCharacterRange:range)
            let glyphs = manager.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            let line = manager.lineFragmentRect(forGlyphAt:glyphs.location,effectiveRange:nil)
            let side = content.headerHeight
            // 原生表格的 boundsRect 在绘制前可为空；标题行片段已经包含单元格内边距。
            toolbar.frame = NSRect(x:line.maxX+textContainerOrigin.x-side,
                y:line.midY+textContainerOrigin.y-side/2,width:side,height:side)
        }
        for key in Array(codeToolbars.keys) where !seen.contains(key) {codeToolbars.removeValue(forKey:key)?.removeFromSuperview()}
        var seenActions = Set<Int>()
        storage.enumerateAttribute(.transcriptActions,in:NSRange(location:0,length:storage.length)) {value,range,_ in
            guard value is TranscriptActions else {return}
            seenActions.insert(range.location)
            guard let toolbar = transcriptToolbars[range.location] else {return}
            manager.ensureLayout(forCharacterRange:range)
            let glyphs = manager.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            guard glyphs.length > 0 else {return}
            let line = manager.lineFragmentRect(forGlyphAt:glyphs.location,effectiveRange:nil)
            toolbar.frame = NSRect(x:line.minX+textContainerOrigin.x+(textContainer?.lineFragmentPadding ?? 0),
                y:line.minY+textContainerOrigin.y,width:footerWidth(bounds.width),height:toolbar.arrange(width:footerWidth(bounds.width)))
            toolbar.needsLayout = true
        }
        for key in Array(transcriptToolbars.keys) where !seenActions.contains(key) {transcriptToolbars.removeValue(forKey:key)?.removeFromSuperview()}
    }

    private func footerWidth(_ width:CGFloat) -> CGFloat {
        max(1,width-2*textContainerInset.width-2*(textContainer?.lineFragmentPadding ?? 0))
    }
    private func prepareInlineControls(width:CGFloat) {
        guard !preparingInlineControls,let storage = textStorage else {return}
        preparingInlineControls = true; defer {preparingInlineControls = false}
        let width = footerWidth(width)
        prepareFileDisclosures(in:storage,width:width)
        var entries = [(TranscriptActions,NSRange)]()
        storage.enumerateAttribute(.transcriptActions,in:NSRange(location:0,length:storage.length)) {value,range,_ in
            if let content = value as? TranscriptActions {entries.append((content,range))}
        }
        let locations = Set(entries.map {$0.1.location})
        for key in Array(transcriptToolbars.keys) where !locations.contains(key) {transcriptToolbars.removeValue(forKey:key)?.removeFromSuperview()}
        guard !entries.isEmpty else {return}
        let expanded = PetPreferences.shared.bool(PetPreferences.tokenDetailsKey)
        let format = PetPreferences.shared.tokenCountFormat
        for (content,range) in entries {
            let toolbar = transcriptToolbars[range.location] ?? TranscriptActionBar(content)
            if toolbar.content !== content {toolbar.content = content}
            if toolbar.expanded != expanded {toolbar.expanded = expanded}
            if toolbar.countFormat != format {toolbar.countFormat = format}
            if toolbar.superview == nil {addSubview(toolbar); transcriptToolbars[range.location] = toolbar}
            toolbar.onToggle = { [weak toolbar] in
                guard let toolbar else {return}
                PetPreferences.shared.set(!toolbar.expanded,for:PetPreferences.tokenDetailsKey,from:toolbar)
            }
            reserveInlineHeight(toolbar.arrange(width:width),at:range,in:storage)
        }
    }
    private func prepareFileDisclosures(in storage:NSTextStorage,width:CGFloat) {
        var entries = [(section:FileEditSection,range:NSRange,expanded:Bool)]()
        storage.enumerateAttribute(.fileEditDisclosure,in:NSRange(location:0,length:storage.length)) {value,range,_ in
            guard let expanded = value as? Bool,
                  let section = storage.attribute(.fileEditSection,at:range.location,effectiveRange:nil) as? FileEditSection else {return}
            entries.append((section,range,expanded))
        }
        let ids = Set(entries.map {$0.section.id})
        for id in Array(fileDisclosures.keys) where !ids.contains(id) {fileDisclosures.removeValue(forKey:id)?.control.removeFromSuperview()}
        for (section,range,expanded) in entries {
            let id = section.id
            let control = fileDisclosures[id]?.control ?? DisclosureControl(frame:.zero)
            if control.superview == nil {
                control.accessibilityTitle = "文件列表"
                control.onToggle = { [weak self] in self?.toggleFileDisclosure(id) }
                addSubview(control)
            }
            let extraCount = section.edits.count-FileEditRendering.previewCount
            let title = expanded ? "收起文件列表" : "再显示 \(extraCount) 个文件"
            if control.expanded != expanded {control.expanded = expanded}
            control.setAccessibilityValue(expanded ? nil : "\(extraCount) 个文件")
            let font = NSFont.monospacedDigitSystemFont(ofSize:max(11,section.font.pointSize-1),weight:.regular)
            control.setInlineTitle(title,font:font)
            let leadingSpace = textContainerInset.width+(textContainer?.lineFragmentPadding ?? 0)
            let size = control.preferredSize(maxWidth:width+min(leadingSpace,control.textLeadingInset))
            fileDisclosures[id] = (control,range,size)
            reserveInlineHeight(size.height,at:range,in:storage)
        }
    }
    private func reserveInlineHeight(_ height:CGFloat,at range:NSRange,in storage:NSTextStorage) {
        let previous = storage.attribute(.paragraphStyle,at:range.location,effectiveRange:nil) as? NSParagraphStyle
        guard previous?.minimumLineHeight != height else {return}
        let paragraph = (previous?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.minimumLineHeight = height; paragraph.maximumLineHeight = height
        storage.addAttribute(.paragraphStyle,value:paragraph,range:range)
        measuredWidth = -1; codeLayoutDirty = true
    }

    var linkBaseDirectory: (() -> URL?)?
    override func clicked(onLink link: Any, at charIndex: Int) {
        if MessageFileLink.reveal(link,relativeTo:linkBaseDirectory?()) {return}
        super.clicked(onLink:link,at:charIndex)
    }
    @discardableResult func setContent(_ value:NSAttributedString,reset:Bool = false) -> Bool {
        if !(layoutManager is MarkdownLayoutManager) {MarkdownLayoutManager.install(in:self)}
        // 保留链接自身的语义颜色：普通链接强调色，文件列表仍区分目录与文件名。
        linkTextAttributes = [.cursor:NSCursor.pointingHand]
        return applyContent(fileEditPresentation.content(value),reset:reset)
    }
    func releaseRenderedContent() {
        setContent(NSAttributedString(),reset:true)
        // NSTextView 清空后仍保留插入点属性；不能让它继续引用表格和完整文件列表。
        typingAttributes = [.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.labelColor]
        for toolbar in codeToolbars.values {toolbar.removeFromSuperview()}
        codeToolbars.removeAll()
        for toolbar in transcriptToolbars.values {toolbar.removeFromSuperview()}
        transcriptToolbars.removeAll()
        // 清空正文不足以回收长文本的字形容量；保留容器和视图，替换只属于显示层的排版器。
        MarkdownLayoutManager.install(in:self)
        measuredWidth = -1; measuredHeight = 0; codeLayoutWidth = -1
        invalidateCodeLayout()
    }
    func revealFileEdits(matching query:String) {
        if let value = fileEditPresentation.revealMatches(query) {applyDisclosure(value)}
    }
    private func toggleFileDisclosure(_ id:String) {
        DisclosureMotion.update(in:self,animatesLayout:false) {applyDisclosure(fileEditPresentation.toggle(id))}
    }
    private func applyDisclosure(_ value:NSAttributedString) {
        let origin = enclosingScrollView?.contentView.bounds.origin
        setSelectedRange(NSRange(location:0,length:0))
        applyContent(value,reset:false)
        if isVerticallyResizable {sizeToFit()}
        onContentLayoutChange?()
        layoutSubtreeIfNeeded()
        if let scroll = enclosingScrollView,let origin {
            scroll.contentView.scroll(to:scroll.contentView.constrainBoundsRect(NSRect(origin:origin,size:scroll.contentView.bounds.size)).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    @discardableResult private func applyContent(_ value:NSAttributedString,reset:Bool) -> Bool {
        guard reset || !attributedString().isEqual(to:value) else {return false}
        let hadSelection = !reset && selectedRange().length > 0
        if reset {textStorage?.setAttributedString(value)}
        else {replaceChangedSuffix(with:value)}
        measuredWidth = -1; invalidateCodeLayout()
        prepareInlineControls(width:bounds.width)
        if !hadSelection {setSelectedRange(NSRange(location:0,length:0))}
        return true
    }
    // 使用实际 TextKit 布局，宽度不受滚动条显隐影响；只在正文或宽度改变后测量。
    func contentHeight(for width:CGFloat) -> CGFloat {
        prepareInlineControls(width:width)
        guard measuredWidth != width else {return measuredHeight}
        guard let container = textContainer,let manager = layoutManager else {return 0}
        if frame.width != width {frame.size.width = width}
        container.containerSize = NSSize(width:max(0,width-2*textContainerInset.width),height:.greatestFiniteMagnitude)
        manager.ensureLayout(for:container)
        measuredWidth = width
        measuredHeight = string.isEmpty ? 0 : ceil(manager.usedRect(for:container).maxY+2*textContainerInset.height)
        return measuredHeight
    }
    // 保留完全相同的富文本前缀，只让 TextKit 重排发生变化的尾部。
    private func replaceChangedSuffix(with value:NSAttributedString) {
        guard let storage = textStorage else {return}
        let prefix = (storage.string as NSString).commonPrefix(with:value.string,options:.literal)
        var length = (prefix as NSString).length
        if length > 0 {
            let range = (storage.string as NSString).rangeOfComposedCharacterSequence(at:length-1)
            if NSMaxRange(range) > length {length = range.location}
        }
        var offset = 0
        while offset < length {
            var oldRange = NSRange(), newRange = NSRange()
            let old = storage.attributes(at:offset,effectiveRange:&oldRange)
            let new = value.attributes(at:offset,effectiveRange:&newRange)
            guard NSDictionary(dictionary:old).isEqual(to:new) else {length = offset; break}
            offset = min(length,NSMaxRange(oldRange),NSMaxRange(newRange))
        }
        storage.replaceCharacters(in:NSRange(location:length,length:storage.length-length),
                                  with:value.attributedSubstring(from:NSRange(location:length,length:value.length-length)))
    }
}
