import AppKit
import UniformTypeIdentifiers

final class SettingsAction: NSObject {
    let body: (NSControl) -> Void
    init(_ body: @escaping (NSControl) -> Void) {self.body = body}
    @objc func invoke(_ sender: NSControl) {body(sender)}
}

// 设置分组承载同类选项；不叠加阴影或玻璃效果。
final class SettingsSectionBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.045) : NSColor.black.withAlphaComponent(0.025)).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:12,yRadius:12).fill()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}
final class GlassOpacitySlider: NSSlider {
    var tracking = false
    var ended: () -> Void = {}
    override func mouseDown(with event:NSEvent) {tracking = true; super.mouseDown(with:event); tracking = false; ended()}
    override func scrollWheel(with event:NSEvent) {
        guard isEnabled else {super.scrollWheel(with:event); return}
        doubleValue = min(maxValue,max(minValue,doubleValue + Double(event.scrollingDeltaY)*0.01))
        sendAction(action,to:target); ended()
    }
}

// 仅“称呼与个性”页使用；高亮是显示属性，偏好和剪贴板始终保留纯文本。
enum SettingsTemplateTokens {
    private static func ink(_ light:(CGFloat,CGFloat,CGFloat), _ dark:(CGFloat,CGFloat,CGFloat)) -> NSColor {
        NSColor(name:nil) {appearance in
            let rgb = appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed:rgb.0,green:rgb.1,blue:rgb.2,alpha:1)
        }
    }
    static let items: [(title:String, token:String, color:NSColor)] = [
        ("插入特定称呼：", "{特定称呼}", ink((0.12,0.34,0.68),(0.45,0.73,1))),
        ("插入用户名：", "{用户名}", ink((0.48,0.22,0.62),(0.83,0.62,1))),
        ("插入桌宠名：", "{桌宠名}", ink((0.62,0.27,0.02),(1,0.72,0.40)))
    ]
    static func ranges(in text:String, apply:(NSRange,NSColor)->Void) {
        let value = text as NSString
        for item in items {
            var start = 0
            while start < value.length {
                let range = value.range(of:item.token,range:NSRange(location:start,length:value.length-start))
                guard range.location != NSNotFound else {break}
                apply(range,item.color); start = NSMaxRange(range)
            }
        }
    }
}
final class SettingsTemplateField: NSTextField {
    var allowsTokens = true
    func refreshHighlight() {
        if let editor = currentEditor() as? SettingsTemplateEditor {editor.refreshHighlight(); return}
        let value = NSMutableAttributedString(string:stringValue,attributes:[.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.labelColor])
        if allowsTokens {SettingsTemplateTokens.ranges(in:stringValue) {range,color in
            value.addAttributes([.foregroundColor:color,.backgroundColor:color.withAlphaComponent(0.13)],range:range)
        }
        }
        attributedStringValue = value
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refreshHighlight()}
}
final class SettingsTemplateEditor: AppTextView, TemplateContextMenu {
    var allowsTokens = true
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            // 点击聚焦尚未修改文字；等 AppKit 完成 field editor 的内容装载再高亮。
            DispatchQueue.main.async { [weak self] in
                guard let self,self.window?.firstResponder === self else {return}
                self.refreshHighlight()
            }
        }
        return accepted
    }
    override func menu(for event:NSEvent) -> NSMenu? {
        let menu = NSMenu(); menu.allowsContextMenuPlugIns = false
        for (title,action) in [("剪切",#selector(NSText.cut(_:))),("拷贝",#selector(NSText.copy(_:))),("粘贴",#selector(NSText.paste(_:))),("全选",#selector(NSResponder.selectAll(_:)))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item)
        }
        guard allowsTokens else {return menu}
        menu.addItem(.separator())
        let font = NSFont.menuFont(ofSize:0)
        let tab = SettingsTemplateTokens.items.map {($0.title as NSString).size(withAttributes:[.font:font]).width}.max()! + 20
        let paragraph = NSMutableParagraphStyle(); paragraph.tabStops = [NSTextTab(textAlignment:.left,location:tab)]
        for entry in SettingsTemplateTokens.items {
            let title = entry.title+"\t"+entry.token
            let item = NSMenuItem(title:title,action:#selector(insertTemplateToken(_:)),keyEquivalent:"")
            item.attributedTitle = NSAttributedString(string:title,attributes:[.font:font,.paragraphStyle:paragraph])
            item.representedObject = entry.token; item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func insertTemplateToken(_ sender:NSMenuItem) {
        guard let token = sender.representedObject as? String else {return}
        insertText(token,replacementRange:selectedRange())
    }
    override func paste(_ sender:Any?) {pasteAsPlainText(sender)}
    override func didChangeText() {super.didChangeText(); refreshHighlight()}
    func refreshHighlight() {
        guard !hasMarkedText(), let layoutManager else {return}
        let whole = NSRange(location:0,length:(string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor,forCharacterRange:whole)
        layoutManager.removeTemporaryAttribute(.backgroundColor,forCharacterRange:whole)
        guard allowsTokens else {return}
        SettingsTemplateTokens.ranges(in:string) {range,color in
            layoutManager.addTemporaryAttributes([.foregroundColor:color,.backgroundColor:color.withAlphaComponent(0.13)],forCharacterRange:range)
        }
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refreshHighlight()}
}
