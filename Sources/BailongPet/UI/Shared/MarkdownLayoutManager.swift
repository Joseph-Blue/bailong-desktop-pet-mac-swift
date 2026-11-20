import AppKit

extension NSAttributedString.Key {
    static let inlineCode = NSAttributedString.Key("BailongInlineCode")
}

final class MarkdownLayoutManager:NSLayoutManager {
    static func install(in view:NSTextView) {
        guard let container = view.textContainer,let previous = view.layoutManager else {return}
        let manager = MarkdownLayoutManager()
        manager.usesFontLeading = previous.usesFontLeading
        manager.allowsNonContiguousLayout = previous.allowsNonContiguousLayout
        container.replaceLayoutManager(manager)
    }

    // 按可见行的字形画底色。缩进、换行、两端空白及同一行的普通文字都在范围之外。
    func enumerateInlineCodeRects(for visible:NSRange,using draw:@escaping (NSRect) -> Void) {
        guard visible.length > 0,let storage = textStorage else {return}
        let characters = characterRange(forGlyphRange:visible,actualGlyphRange:nil)
        let text = storage.mutableString
        let nonspace = CharacterSet.whitespacesAndNewlines.inverted
        storage.enumerateAttribute(.inlineCode,in:characters) {value,range,_ in
            guard value != nil else {return}
            let glyphs = self.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            self.enumerateLineFragments(forGlyphRange:glyphs) {_,used,container,line,_ in
                let part = NSIntersectionRange(line,glyphs)
                let span = NSIntersectionRange(range,self.characterRange(forGlyphRange:part,actualGlyphRange:nil))
                let first = text.rangeOfCharacter(from:nonspace,range:span)
                guard first.location != NSNotFound else {return}
                let last = text.rangeOfCharacter(from:nonspace,options:.backwards,range:span)
                let ink = self.glyphRange(forCharacterRange:NSUnionRange(first,last),actualCharacterRange:nil)
                let bounds = self.boundingRect(forGlyphRange:ink,in:container).intersection(used)
                self.enumerateEnclosingRects(forGlyphRange:ink,withinSelectedGlyphRange:NSRange(location:NSNotFound,length:0),in:container) {rect,_ in
                    let background = rect.intersection(bounds)
                    if !background.isEmpty {draw(background)}
                }
            }
        }
    }

    override func drawBackground(forGlyphRange glyphs:NSRange,at origin:NSPoint) {
        NSColor.quaternaryLabelColor.setFill()
        enumerateInlineCodeRects(for:glyphs) {rect in rect.offsetBy(dx:origin.x,dy:origin.y).fill()}
        super.drawBackground(forGlyphRange:glyphs,at:origin)
    }
}
