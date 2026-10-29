import AppKit

// 仅逐步显示已收到的文本；不制造内容，也不等待整段回复结束。
final class StreamingTextView: NSTextView {
    private var targetText = NSAttributedString(string:"")
    private var revealTimer: Timer?
    private var followsEnd = true
    var automaticallyFollowsEnd = true
    var isRevealing: Bool {revealTimer != nil}
    func setContent(_ value: NSAttributedString, animated: Bool, reset: Bool = false) {
        if !reset && targetText.isEqual(to:value) {if !animated {finishReveal()}; return}
        let follows = automaticallyFollowsEnd && (reset || isAtEnd)
        targetText = value
        guard animated && !reset else {
            stopReveal(); textStorage?.setAttributedString(value)
            if follows {scrollToEndOfDocument(nil)}
            else if reset {scrollToBeginningOfDocument(nil)}
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
        storage.append(targetText.attributedSubstring(from:range))
        if followsEnd {scrollToEndOfDocument(nil)}
        if storage.length == targetText.length {stopReveal()}
    }
    func finishReveal() {
        let follows = automaticallyFollowsEnd && isAtEnd; stopReveal()
        if !attributedString().isEqual(to:targetText) {textStorage?.setAttributedString(targetText)}
        if follows {scrollToEndOfDocument(nil)}
    }
    private func stopReveal() {revealTimer?.invalidate(); revealTimer = nil}
    deinit {revealTimer?.invalidate()}
}
