import AppKit
import ObjectiveC

// 给现有原生按钮附加复制行为，保留调用方的布局、内容来源和按钮样式。
final class CopyFeedback:NSObject {
    private static var association:UInt8 = 0
    private weak var button:NSButton?
    private let value:() -> String?
    private let originalTitle:String, originalHelp:String?
    private let originalImage:NSImage?, originalTint:NSColor?
    private let originalPosition:NSControl.ImagePosition
    private var timer:Timer?

    static func attach(to button:NSButton,value:@escaping () -> String?) {
        let feedback = CopyFeedback(button:button,value:value)
        objc_setAssociatedObject(button,&association,feedback,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        button.target = feedback; button.action = #selector(copyValue)
    }
    private init(button:NSButton,value:@escaping () -> String?) {
        self.button = button; self.value = value
        originalTitle = button.imagePosition == .imageOnly ? "" : button.title; originalHelp = button.hoverHelp
        originalImage = button.image; originalTint = button.contentTintColor; originalPosition = button.imagePosition
        super.init()
        if button.imagePosition != .imageOnly {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant:button.intrinsicContentSize.width).isActive = true
        }
    }
    @objc private func copyValue() {
        guard let button else {return}
        timer?.invalidate()
        let success:Bool
        if let text = value() {
            NSPasteboard.general.clearContents()
            success = NSPasteboard.general.setString(text,forType:.string)
        } else {success = false}
        let status = success ? "已复制" : "复制失败"
        if originalPosition != .imageOnly {button.title = status}
        if originalImage != nil {
            button.image = NSImage(systemSymbolName:success ? "checkmark" : "exclamationmark.triangle",accessibilityDescription:status)
            button.contentTintColor = success ? .systemGreen : .systemOrange
        }
        button.imagePosition = originalPosition
        button.hoverHelp = success ? status : "复制失败，请重试"
        button.setAccessibilityLabel(status)
        button.needsDisplay = true
        let timer = Timer(timeInterval:1.5,repeats:false) { [weak self] _ in self?.restore() }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func restore() {
        guard let button else {return}
        button.title = originalTitle; button.image = originalImage; button.imagePosition = originalPosition; button.contentTintColor = originalTint
        button.hoverHelp = originalHelp
        button.setAccessibilityLabel(originalTitle.isEmpty ? (originalHelp ?? "复制") : originalTitle)
        button.needsDisplay = true; timer = nil
    }
    deinit {timer?.invalidate()}
}
