import AppKit

// 只登记用户界面窗口的打开生命周期，控制器持有对象不等于窗口仍打开。
final class InterfaceWindows:NSObject {
    static let shared = InterfaceWindows()
    private let opened = NSHashTable<NSWindow>.weakObjects()
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(willClose(_:)),name:NSWindow.willCloseNotification,object:nil)
    }
    func opened(_ window:NSWindow) {
        opened.add(window)
        if NSApp.activationPolicy() != .regular {NSApp.setActivationPolicy(.regular)}
        NSApp.addWindowsItem(window,title:window.title,filename:false)
    }
    func closed(_ window:NSWindow) {
        opened.remove(window); NSApp.removeWindowsItem(window)
        // willClose 在 AppKit 完成关闭之前发出，下一次主队列检查避免关闭中切换策略。
        DispatchQueue.main.async { [weak self] in
            guard let self,self.opened.allObjects.isEmpty,NSApp.activationPolicy() != .accessory else {return}
            NSApp.setActivationPolicy(.accessory)
        }
    }
    @objc private func willClose(_ note:Notification) {
        guard let window = note.object as? NSWindow,opened.contains(window) else {return}
        closed(window)
    }
    var frontmost:NSWindow? {
        let ordered = NSApp.orderedWindows + opened.allObjects
        return ordered.first {opened.contains($0) && $0.isVisible && !$0.isMiniaturized}
            ?? ordered.first {opened.contains($0) && $0.isMiniaturized}
            ?? opened.allObjects.first
    }
    func recall() {
        guard let window = frontmost else {return}
        if window.isMiniaturized {window.deminiaturize(nil)}
        window.makeKeyAndOrderFront(nil)
    }
}
