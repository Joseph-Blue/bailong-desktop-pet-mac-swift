import AppKit

// 链接按钮与整行跳转控件，供非激活面板保留其原生手形光标。
protocol LinkCursorControl:AnyObject {var isEnabled:Bool {get}}

// 仅提供超链接外观与命中区域；导航、文件定位和展开动作仍由调用方处理。
enum LinkAppearance {
    static var attributes:[NSAttributedString.Key:Any] {
        [.foregroundColor:AppAccent.color,.underlineStyle:NSUnderlineStyle.single.rawValue,.cursor:NSCursor.pointingHand]
    }
    static func attributes(for url:URL) -> [NSAttributedString.Key:Any] {
        var value = attributes; value[.link] = url; return value
    }
    static func addCursorRect(_ rect:NSRect,to view:NSView) {
        view.addCursorRect(rect,cursor:.pointingHand)
    }
    static func addCursorRects(to text:NSTextView) {
        guard let storage = text.textStorage,let manager = text.layoutManager,let container = text.textContainer,
              storage.length > 0 else {return}
        let origin = text.textContainerOrigin
        let visible = text.visibleRect.offsetBy(dx:-origin.x,dy:-origin.y)
        let glyphs = manager.glyphRange(forBoundingRect:visible,in:container)
        let characters = manager.characterRange(forGlyphRange:glyphs,actualGlyphRange:nil)
        // 只处理当前视口，不为每条链接创建视图、tracking area 或常驻矩形缓存。
        storage.enumerateAttribute(.link,in:characters) {value,range,_ in
            guard value != nil else {return}
            let linkedGlyphs = manager.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            manager.enumerateEnclosingRects(forGlyphRange:linkedGlyphs,withinSelectedGlyphRange:NSRange(location:NSNotFound,length:0),in:container) {rect,_ in
                let hit = rect.offsetBy(dx:origin.x,dy:origin.y).intersection(text.visibleRect)
                if !hit.isEmpty {addCursorRect(hit,to:text)}
            }
        }
    }
    static func link(at point:NSPoint,in text:NSTextView) -> (value:Any,index:Int)? {
        guard text.visibleRect.contains(point),let storage = text.textStorage,storage.length > 0,
              let manager = text.layoutManager,let container = text.textContainer else {return nil}
        manager.ensureLayout(for:container)
        let local = NSPoint(x:point.x-text.textContainerOrigin.x,y:point.y-text.textContainerOrigin.y)
        let glyph = manager.glyphIndex(for:local,in:container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange:NSRange(location:glyph,length:1),in:container).contains(local) else {return nil}
        let index = manager.characterIndexForGlyph(at:glyph)
        guard index < storage.length,let value = storage.attribute(.link,at:index,effectiveRange:nil) else {return nil}
        return (value,index)
    }
}

// 非激活消息窗、可选择历史正文和不可选择的关于页共用原生链接光标。
class LinkTextView:AppTextView {
    override func resetCursorRects() {
        super.resetCursorRects()
        LinkAppearance.addCursorRects(to:self)
    }
    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for:self)
    }
}
