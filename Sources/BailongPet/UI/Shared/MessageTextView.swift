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
    private var expandedUsage = Set<String>()
    private var preparingFooters = false
    private var codeLayoutDirty = true
    private var codeLayoutWidth:CGFloat = -1
    private func invalidateCodeLayout() {codeLayoutDirty = true; needsLayout = true}
    override func layout() {
        prepareFooters(width:bounds.width)
        super.layout()
        guard codeLayoutDirty || codeLayoutWidth != bounds.width else {return}
        guard let storage = textStorage,let manager = layoutManager else {return}
        codeLayoutDirty = false; codeLayoutWidth = bounds.width
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
    private func prepareFooters(width:CGFloat) {
        guard !preparingFooters,let storage = textStorage else {return}
        preparingFooters = true; defer {preparingFooters = false}
        var entries = [(TranscriptActions,NSRange)]()
        storage.enumerateAttribute(.transcriptActions,in:NSRange(location:0,length:storage.length)) {value,range,_ in
            if let content = value as? TranscriptActions {entries.append((content,range))}
        }
        expandedUsage.formIntersection(Set(entries.map {$0.0.id}))
        let locations = Set(entries.map {$0.1.location})
        for key in Array(transcriptToolbars.keys) where !locations.contains(key) {transcriptToolbars.removeValue(forKey:key)?.removeFromSuperview()}
        for (content,range) in entries {
            let toolbar = transcriptToolbars[range.location] ?? TranscriptActionBar(content)
            if toolbar.content !== content {toolbar.content = content}
            if toolbar.expanded != expandedUsage.contains(content.id) {toolbar.expanded = expandedUsage.contains(content.id)}
            if toolbar.superview == nil {addSubview(toolbar); transcriptToolbars[range.location] = toolbar}
            toolbar.onToggle = { [weak self] in
                guard let self else {return}
                if !self.expandedUsage.insert(content.id).inserted {self.expandedUsage.remove(content.id)}
                self.prepareFooters(width:self.bounds.width)
                self.measuredWidth = -1; self.invalidateCodeLayout()
                if self.isVerticallyResizable {self.sizeToFit()}
                self.onContentLayoutChange?()
            }
            let height = toolbar.arrange(width:footerWidth(width))
            let previous = storage.attribute(.paragraphStyle,at:range.location,effectiveRange:nil) as? NSParagraphStyle
            if previous?.minimumLineHeight != height {
                let paragraph = (previous?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                paragraph.minimumLineHeight = height; paragraph.maximumLineHeight = height
                storage.addAttribute(.paragraphStyle,value:paragraph,range:range)
                measuredWidth = -1; codeLayoutDirty = true
            }
        }
    }

    var linkBaseDirectory: (() -> URL?)?
    override func clicked(onLink link: Any, at charIndex: Int) {
        if (link as? URL) == FileEditRendering.disclosureLink,
           let section = textStorage?.attribute(.fileEditSection,at:charIndex,effectiveRange:nil) as? FileEditSection {
            applyDisclosure(fileEditPresentation.toggle(section.id)); return
        }
        if MessageFileLink.reveal(link,relativeTo:linkBaseDirectory?()) {return}
        super.clicked(onLink:link,at:charIndex)
    }
    @discardableResult func setContent(_ value:NSAttributedString,reset:Bool = false) -> Bool {
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
        let manager = NSLayoutManager()
        if let previous = layoutManager {
            manager.usesFontLeading = previous.usesFontLeading
            manager.allowsNonContiguousLayout = previous.allowsNonContiguousLayout
        }
        textContainer?.replaceLayoutManager(manager)
        measuredWidth = -1; measuredHeight = 0; codeLayoutWidth = -1
        invalidateCodeLayout()
    }
    func revealFileEdits(matching query:String) {
        if let value = fileEditPresentation.revealMatches(query) {applyDisclosure(value)}
    }
    private func applyDisclosure(_ value:NSAttributedString) {
        let origin = enclosingScrollView?.contentView.bounds.origin
        setSelectedRange(NSRange(location:0,length:0))
        applyContent(value,reset:false)
        if isVerticallyResizable {sizeToFit()}
        onContentLayoutChange?()
        if let scroll = enclosingScrollView,let origin {
            scroll.contentView.scroll(to:scroll.contentView.constrainBoundsRect(NSRect(origin:origin,size:scroll.contentView.bounds.size)).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    @discardableResult private func applyContent(_ value:NSAttributedString,reset:Bool) -> Bool {
        guard reset || !attributedString().isEqual(to:value) else {return false}
        if reset {setSelectedRange(NSRange(location:0,length:0)); textStorage?.setAttributedString(value)}
        else {replaceChangedSuffix(with:value)}
        measuredWidth = -1; invalidateCodeLayout()
        prepareFooters(width:bounds.width)
        return true
    }
    // 使用实际 TextKit 布局，宽度不受滚动条显隐影响；只在正文或宽度改变后测量。
    func contentHeight(for width:CGFloat) -> CGFloat {
        prepareFooters(width:width)
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
