import AppKit

final class MessageEditor: AppTextView {
    var onFocusChange: () -> Void = {}
    override func becomeFirstResponder() -> Bool {let result = super.becomeFirstResponder(); onFocusChange(); return result}
    override func resignFirstResponder() -> Bool {let result = super.resignFirstResponder(); onFocusChange(); return result}
    var send: () -> Void = {}
    var onTextChange: () -> Void = {}
    var placeholder = PetPreferences.shared.fixedText("主人，把想做的事告诉我吧…") {didSet {needsDisplay = true}}
    override func didChangeText() {super.didChangeText(); needsDisplay = true; onTextChange()}
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(in:NSRect(x:textContainerOrigin.x+5,y:textContainerOrigin.y,width:max(0,bounds.width-textContainerOrigin.x-14),height:bounds.height-textContainerOrigin.y),withAttributes:[.font:font ?? NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.placeholderTextColor])
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
