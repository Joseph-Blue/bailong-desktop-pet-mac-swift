import AppKit

// 只登记用户界面窗口的打开生命周期，控制器持有对象不等于窗口仍打开。
final class InterfaceWindows:NSObject {
    static let shared = InterfaceWindows()
    private let opened = NSHashTable<NSWindow>.weakObjects()
    private var focusGeneration = 0
    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self,selector:#selector(willClose(_:)),name:NSWindow.willCloseNotification,object:nil)
        center.addObserver(self,selector:#selector(didBecomeKey(_:)),name:NSWindow.didBecomeKeyNotification,object:nil)
        center.addObserver(self,selector:#selector(didDeminiaturize(_:)),name:NSWindow.didDeminiaturizeNotification,object:nil)
    }
    func opened(_ window:NSWindow) {
        opened.add(window)
        if NSApp.activationPolicy() != .regular {NSApp.setActivationPolicy(.regular)}
        NSApp.addWindowsItem(window,title:window.title,filename:false)
    }
    func focus(_ window:NSWindow) {
        opened(window)
        PopoverDismissal.closeAll()
        if let key = NSApp.keyWindow,key !== window,key.styleMask.contains(.nonactivatingPanel) {
            key.resignKey()
        }
        if NSApp.isHidden {NSApp.unhide(nil)}
        if window.isMiniaturized {window.deminiaturize(nil)}
        // 非激活面板曾取得 key 时 NSApp.isActive 可为 true，而进程并未真正前台激活；显式聚焦一律执行应用激活。
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        focusGeneration += 1
        let generation = focusGeneration
        DispatchQueue.main.async { [weak self,weak window] in
            guard let self,self.focusGeneration == generation,
                  let window,self.opened.contains(window),
                  window.isVisible,!window.isMiniaturized else {return}
            if !NSRunningApplication.current.isActive || !window.isKeyWindow {
                NSApp.activate(ignoringOtherApps:true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
    func closed(_ window:NSWindow) {
        opened.remove(window); NSApp.removeWindowsItem(window)
        // willClose 在 AppKit 完成关闭之前发出，下一次主队列检查避免关闭中切换策略。
        DispatchQueue.main.async { [weak self] in
            guard let self,self.opened.allObjects.isEmpty,NSApp.activationPolicy() != .accessory else {return}
            NSApp.setActivationPolicy(.accessory)
        }
    }
    func isOpen(_ window:NSWindow) -> Bool {opened.contains(window)}
    @objc private func willClose(_ note:Notification) {
        guard let window = note.object as? NSWindow,opened.contains(window) else {return}
        closed(window)
    }
    @objc private func didBecomeKey(_ note:Notification) {
        guard let window = note.object as? NSWindow,opened.contains(window),
              !window.styleMask.contains(.nonactivatingPanel),
              !NSRunningApplication.current.isActive else {return}
        PopoverDismissal.closeAll()
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func didDeminiaturize(_ note:Notification) {
        guard let window = note.object as? NSWindow,opened.contains(window),
              !NSRunningApplication.current.isActive || !window.isKeyWindow else {return}
        focus(window)
    }
    var frontmost:NSWindow? {
        let ordered = NSApp.orderedWindows + opened.allObjects
        return ordered.first {opened.contains($0) && $0.isVisible && !$0.isMiniaturized}
            ?? ordered.first {opened.contains($0) && $0.isMiniaturized}
            ?? opened.allObjects.first
    }
    func recall() {
        guard let window = frontmost else {return}
        focus(window)
    }
}
