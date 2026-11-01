import AppKit

// 仅逐步显示已收到的文本；不制造内容，也不等待整段回复结束。
final class StreamingTextView: AppTextView {
    private var targetText = NSAttributedString(string:"")
    private var revealTimer: Timer?
    private var followsEnd = true
    private var codeToolbars = [Int:CodeBlockToolbar]()
    private var codeLayoutDirty = true
    private var codeLayoutWidth:CGFloat = -1
    private func invalidateCodeLayout() {codeLayoutDirty = true; needsLayout = true}
    override func layout() {
        super.layout()
        guard codeLayoutDirty || codeLayoutWidth != bounds.width else {return}
        guard let storage = textStorage,let manager = layoutManager,let container = textContainer else {return}
        codeLayoutDirty = false; codeLayoutWidth = bounds.width
        var seen = Set<Int>()
        storage.enumerateAttribute(.codeBlockHeader,in:NSRange(location:0,length:storage.length)) {value,range,_ in
            guard let content = value as? CodeBlockContent else {return}
            seen.insert(range.location)
            let toolbar = codeToolbars[range.location] ?? CodeBlockToolbar(content)
            toolbar.content = content
            if toolbar.superview == nil {addSubview(toolbar); codeToolbars[range.location] = toolbar}
            manager.ensureLayout(forCharacterRange:range)
            let glyphs = manager.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            let rect = manager.boundingRect(forGlyphRange:glyphs,in:container)
            toolbar.frame = NSRect(x:max(textContainerOrigin.x,bounds.width-textContainerInset.width-46),y:rect.minY+textContainerOrigin.y,width:30,height:26)
        }
        for key in Array(codeToolbars.keys) where !seen.contains(key) {codeToolbars.removeValue(forKey:key)?.removeFromSuperview()}
    }
    var automaticallyFollowsEnd = true
    var startsSnapshotsAtTop = false
    var onUserNavigation:() -> Void = {}
    override func keyDown(with event:NSEvent) {
        if [49,115,116,119,121,123,124,125,126].contains(event.keyCode) {onUserNavigation()}
        super.keyDown(with:event)
    }
    override func mouseDown(with event:NSEvent) {onUserNavigation(); super.mouseDown(with:event)}
    var linkBaseDirectory: (() -> URL?)?
    var isRevealing: Bool {revealTimer != nil}
    override func clicked(onLink link: Any, at charIndex: Int) {
        if MessageFileLink.reveal(link,relativeTo:linkBaseDirectory?()) {return}
        super.clicked(onLink:link,at:charIndex)
    }
    func setContent(_ value: NSAttributedString, animated: Bool, reset: Bool = false) {
        if !reset && targetText.isEqual(to:value) {if !animated && isRevealing {finishReveal()}; return}
        defer {invalidateCodeLayout()}
        let follows = automaticallyFollowsEnd && (reset || isAtEnd)
        let origin = enclosingScrollView?.contentView.bounds.origin
        targetText = value
        guard animated && !reset else {
            if startsSnapshotsAtTop && reset {setSelectedRange(NSRange(location:0,length:0))}
            stopReveal()
            if reset {textStorage?.setAttributedString(value)}
            else {replaceChangedSuffix(with:value)}
            if startsSnapshotsAtTop && reset {scrollToBeginningOfDocument(nil)}
            else if !startsSnapshotsAtTop && follows {scrollToEndOfDocument(nil)}
            else if reset {scrollToBeginningOfDocument(nil)}
            else if startsSnapshotsAtTop,let scroll = enclosingScrollView,let origin {
                if scroll.contentView.bounds.origin != origin {
                    scroll.contentView.scroll(to:origin); scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            return
        }
        guard let storage = textStorage else {return}
        // 已显示的前缀不重绘；修订或换段时只替换发生变化的尾部。
        let prefix = (storage.string as NSString).commonPrefix(with:value.string,options:.literal)
        var length = (prefix as NSString).length
        if length > 0 && length < value.length {
            let character = (value.string as NSString).rangeOfComposedCharacterSequence(at:length-1)
            if NSMaxRange(character) > length {length = character.location}
        }
        storage.beginEditing()
        // 标记闭合后，已显示的相同文字也要更新粗体等属性，不重新打字。
        if length > 0 {
            value.enumerateAttributes(in:NSRange(location:0,length:length)) {attributes,range,_ in
                var changed = false
                storage.enumerateAttributes(in:range) {old,_,stop in
                    if !NSDictionary(dictionary:old).isEqual(to:attributes) {changed = true; stop.pointee = true}
                }
                if changed {storage.setAttributes(attributes,range:range)}
            }
        }
        if length < storage.length {storage.deleteCharacters(in:NSRange(location:length,length:storage.length-length))}
        storage.endEditing()
        followsEnd = follows
        if storage.length == value.length {stopReveal(); return}
        if revealTimer == nil {
            let timer = Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in self?.revealNext() }
            revealTimer = timer; RunLoop.main.add(timer,forMode:.common)
        }
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
    private var isAtEnd: Bool {
        guard let clip = enclosingScrollView?.contentView else {return true}
        return clip.bounds.maxY >= bounds.maxY-10
    }
    private func revealNext() {
        guard let storage = textStorage else {stopReveal(); return}
        let remaining = targetText.length-storage.length
        guard remaining > 0 else {stopReveal(); return}
        if followsEnd && !isAtEnd {followsEnd = false}
        // 小块连续追加，大块加快追赶；Unicode 合字、emoji 和中文不从中间切断。
        let count = min(remaining,max(2,Int(ceil(Double(remaining)/5))))
        let text = targetText.string as NSString
        let range = text.rangeOfComposedCharacterSequences(for:NSRange(location:storage.length,length:count))
        storage.append(targetText.attributedSubstring(from:range)); invalidateCodeLayout()
        if followsEnd {scrollToEndOfDocument(nil)}
        if storage.length == targetText.length {stopReveal()}
    }
    func finishReveal() {
        let follows = automaticallyFollowsEnd && isAtEnd; stopReveal()
        guard !attributedString().isEqual(to:targetText) else {return}
        replaceChangedSuffix(with:targetText); invalidateCodeLayout()
        if follows {scrollToEndOfDocument(nil)}
    }
    private func stopReveal() {revealTimer?.invalidate(); revealTimer = nil}
    deinit {revealTimer?.invalidate()}
}
