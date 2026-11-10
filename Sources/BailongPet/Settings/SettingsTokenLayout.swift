import AppKit

// 按整段变量的实际字形范围绘制底色，中文与括号使用不同字体也不分裂背景。
final class SettingsTokenLayoutManager:NSLayoutManager {
    var showsTokens = true
    override func drawBackground(forGlyphRange glyphsToShow:NSRange,at origin:NSPoint) {
        if showsTokens,let storage = textStorage {
            SettingsTemplateTokens.ranges(in:storage.string) {characters,color in
                let glyphs = self.glyphRange(forCharacterRange:characters,actualCharacterRange:nil)
                let visible = NSIntersectionRange(glyphs,glyphsToShow)
                guard visible.length > 0 else {return}
                self.enumerateLineFragments(forGlyphRange:visible) {_,_,container,lineRange,_ in
                    let part = NSIntersectionRange(glyphs,lineRange)
                    guard part.length > 0 else {return}
                    let rect = self.boundingRect(forGlyphRange:part,in:container)
                        .offsetBy(dx:origin.x,dy:origin.y).insetBy(dx:-1,dy:-1)
                    color.withAlphaComponent(0.13).setFill()
                    NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3).fill()
                }
            }
        }
        // 原生选区仍绘制在变量底色之上。
        super.drawBackground(forGlyphRange:glyphsToShow,at:origin)
    }
}

// 非编辑状态沿用 NSTextField 的边框与焦点，仅正文使用与 field editor 相同的排版器。
final class SettingsTokenFieldCell:NSTextFieldCell {
    override func drawInterior(withFrame cellFrame:NSRect,in controlView:NSView) {
        guard let field = controlView as? SettingsTemplateField,field.allowsTokens,
              field.currentEditor() == nil,!stringValue.isEmpty else {
            super.drawInterior(withFrame:cellFrame,in:controlView); return
        }
        let rect = drawingRect(forBounds:cellFrame)
        let storage = NSTextStorage(attributedString:attributedStringValue)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = wraps ? .byWordWrapping : lineBreakMode
        storage.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:storage.length))
        let manager = SettingsTokenLayoutManager()
        let container = NSTextContainer(containerSize:NSSize(width:rect.width,height:CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = field.maximumNumberOfLines
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        manager.ensureLayout(for:container)
        let glyphs = manager.glyphRange(for:container)
        let height = manager.usedRect(for:container).height
        let origin = NSPoint(x:rect.minX,y:rect.minY+(wraps ? 0 : max(0,(rect.height-height)/2)))
        NSGraphicsContext.saveGraphicsState()
        cellFrame.clip()
        manager.drawBackground(forGlyphRange:glyphs,at:origin)
        manager.drawGlyphs(forGlyphRange:glyphs,at:origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
