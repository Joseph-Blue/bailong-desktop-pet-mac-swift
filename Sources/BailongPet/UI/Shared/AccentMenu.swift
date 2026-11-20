import AppKit

// 菜单生命周期、快捷键和子菜单由 NSMenu 管理，只有手动选色时才提供行视图。
final class AccentMenuRows: NSObject, NSMenuDelegate {
    static let shared = AccentMenuRows()

    static func menu(title:String = "") -> NSMenu {
        let menu = NSMenu(title:title)
        menu.delegate = shared
        return menu
    }

    func menuNeedsUpdate(_ menu:NSMenu) {
        prepare(menu)
    }
    func prepare(_ menu:NSMenu,picker:NSPopUpButton? = nil) {
        let custom = AppAccent.selection != "system"
        let hasImages = menu.items.contains {$0.image != nil}
        for item in menu.items where !item.isSeparatorItem {
            if let row = item.view as? AccentMenuRow {
                if custom {row.picker = picker; row.needsDisplay = true} else {item.view = nil}
            } else if custom && item.view == nil {
                item.view = AccentMenuRow(item:item,font:menu.font ?? .menuFont(ofSize:0),hasImages:hasImages,picker:picker)
            }
        }
    }

    func menu(_ menu:NSMenu,willHighlight item:NSMenuItem?) {
        menu.highlightedItem?.view?.needsDisplay = true
        item?.view?.needsDisplay = true
    }
}

class AccentPopUpButton:NSPopUpButton,NSMenuDelegate {
    override init(frame:NSRect = .zero,pullsDown:Bool = false) {
        super.init(frame:frame,pullsDown:pullsDown)
        menu?.delegate = self
    }
    required init?(coder:NSCoder) {fatalError()}
    func menuNeedsUpdate(_ menu:NSMenu) {AccentMenuRows.shared.prepare(menu,picker:self)}
    func menu(_ menu:NSMenu,willHighlight item:NSMenuItem?) {AccentMenuRows.shared.menu(menu,willHighlight:item)}
}

private final class AccentMenuRow: NSView {
    private static let iconSide:CGFloat = 15
    private let hasImages:Bool
    weak var picker:NSPopUpButton?

    init(item:NSMenuItem,font:NSFont,hasImages:Bool,picker:NSPopUpButton?) {
        self.hasImages = hasImages; self.picker = picker
        let titleWidth = Self.title(for:item,font:font).size().width
        let shortcut = Self.shortcut(for:item)
        let trailing = shortcut.isEmpty ? 20 : (shortcut as NSString).size(withAttributes:[.font:font]).width + 22
        let width = ceil(24 + (hasImages ? Self.iconSide + 7 : 0) + titleWidth + trailing)
        super.init(frame:NSRect(x:0,y:0,width:width,height:ceil(font.ascender-font.descender)+7))
        autoresizingMask = [.width]
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) {
        hasImages = coder.decodeBool(forKey:"hasImages")
        super.init(coder:coder)
    }
    override func encode(with coder:NSCoder) {
        super.encode(with:coder)
        coder.encode(hasImages,forKey:"hasImages")
    }

    private static func title(for item:NSMenuItem,font:NSFont) -> NSAttributedString {
        if let title = item.attributedTitle,title.length > 0 {return title}
        return NSAttributedString(string:item.title,attributes:[.font:font])
    }
    private static func shortcut(for item:NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else {return ""}
        let modifiers = item.keyEquivalentModifierMask
        var value = ""
        for (flag,symbol) in [(NSEvent.ModifierFlags.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")] where modifiers.contains(flag) {
            value += symbol
        }
        return value + item.keyEquivalent.uppercased()
    }

    override func draw(_ dirtyRect:NSRect) {
        guard let item = enclosingMenuItem else {return}
        let selected = item.isEnabled && item.isHighlighted
        let color:NSColor
        if selected {
            let fill = AppAccent.color
            fill.setFill()
            NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:0),xRadius:5,yRadius:5).fill()
            color = AppAccent.textOnFill
        } else {color = item.isEnabled ? .labelColor : .disabledControlTextColor}
        let font = item.menu?.font ?? .menuFont(ofSize:0)
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
        func drawText(_ title:NSAttributedString,x:CGFloat) {
            title.draw(at:NSPoint(x:x,y:floor(bounds.midY-title.size().height/2)))
        }
        func symbol(_ name:String,x:CGFloat,size:CGFloat) {
            let configuration = NSImage.SymbolConfiguration(pointSize:size,weight:.semibold).applying(.init(paletteColors:[color]))
            guard let image = NSImage(systemSymbolName:name,accessibilityDescription:nil)?.withSymbolConfiguration(configuration) else {return}
            image.draw(at:NSPoint(x:x,y:floor(bounds.midY-image.size.height/2)),from:.zero,operation:.sourceOver,fraction:1)
        }
        if item.state != .off {symbol(item.state == .mixed ? "minus" : "checkmark",x:7,size:10)}
        var x:CGFloat = 23
        if hasImages {
            if let icon = item.image {
                let side = Self.iconSide
                let ratio = min(side/max(1,icon.size.width),side/max(1,icon.size.height))
                let size = NSSize(width:icon.size.width*ratio,height:icon.size.height*ratio)
                let frame = NSRect(x:x+(side-size.width)/2,y:bounds.midY-size.height/2,width:size.width,height:size.height)
                if icon.isTemplate {
                    // 在独立图层内着色，保留原图之外的菜单背景。
                    let tinted = NSImage(size:size,flipped:false) { rect in
                        icon.draw(in:rect); color.setFill(); rect.fill(using:.sourceIn); return true
                    }
                    tinted.draw(in:frame)
                } else {icon.draw(in:frame)}
            }
            x += Self.iconSide + 7
        }
        let title = NSMutableAttributedString(attributedString:Self.title(for:item,font:font))
        title.addAttribute(.foregroundColor,value:color,range:NSRange(location:0,length:title.length))
        drawText(title,x:x)
        if item.submenu != nil {symbol("chevron.right",x:bounds.maxX-15,size:10)}
        else {
            let shortcut = NSAttributedString(string:Self.shortcut(for:item),attributes:attributes)
            drawText(shortcut,x:bounds.maxX-shortcut.size().width-9)
        }
    }

    // 子菜单整行交给 NSMenu 的原生跟踪区处理。
    override func hitTest(_ point:NSPoint) -> NSView? {
        enclosingMenuItem?.submenu == nil ? super.hitTest(point) : nil
    }
    override func mouseUp(with event:NSEvent) {
        guard bounds.contains(convert(event.locationInWindow,from:nil)),let item = enclosingMenuItem,
              item.isEnabled,let menu = item.menu else {return}
        let index = menu.index(of:item)
        menu.cancelTracking()
        if let picker {
            picker.select(item)
            picker.sendAction(picker.action,to:picker.target)
        } else {menu.performActionForItem(at:index)}
    }
}
