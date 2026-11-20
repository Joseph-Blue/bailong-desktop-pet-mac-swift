import AppKit

final class MessageEditor: AccentTextView {
    func update(font:NSFont,editable:Bool) {
        let inputFont = NSFontManager.shared.convert(font,toSize:font.pointSize+1)
        if self.font != inputFont {self.font = inputFont}
        if isEditable != editable {isEditable = editable}
    }
    var contentHeight:CGFloat {
        guard let container = textContainer,let manager = layoutManager else {return 0}
        manager.ensureLayout(for:container)
        return ceil(manager.usedRect(for:container).maxY+textContainerInset.height*2)
    }
    var send: () -> Void = {}
    var onTextChange: () -> Void = {}
    var placeholder = PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…") {didSet {if placeholder != oldValue {needsDisplay = true}}}
    override func didChangeText() {super.didChangeText(); needsDisplay = true; onTextChange()}
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(in:NSRect(x:textContainerOrigin.x,y:textContainerOrigin.y,width:max(0,bounds.width-textContainerOrigin.x*2),height:bounds.height-textContainerOrigin.y),withAttributes:[.font:font ?? NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.placeholderTextColor])
        }
    }
    private func handleReturn(_ event: NSEvent) -> Bool {
        guard (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
              let sendNow = PetPreferences.shared.sendShortcut.action(modifiers:event.modifierFlags) else {return false}
        if sendNow {if !event.isARepeat {send()}} else if isEditable {insertNewline(nil)}
        return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 不给窗口默认按钮抢走输入法的确认键；只有本输入框聚焦时消费快捷键。
        guard window?.firstResponder === self else {return super.performKeyEquivalent(with:event)}
        return handleReturn(event) || super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event: NSEvent) {
        if !handleReturn(event) {super.keyDown(with:event)}
    }

}
