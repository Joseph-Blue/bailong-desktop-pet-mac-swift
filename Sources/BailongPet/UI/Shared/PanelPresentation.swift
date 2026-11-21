import AppKit

// 仅负责原生辅助窗口的呈现；文件选择、导入导出和颜色写入仍由调用方处理。
enum PanelPresentation {
    static func screen(for parent:NSWindow?) -> NSScreen? {
        parent?.screen ?? NSScreen.screens.first {$0.frame.contains(NSEvent.mouseLocation)} ?? NSScreen.main
    }

    static func setAnchoredWindowLevel(_ window:NSWindow) {
        if window.level < .statusBar {window.level = .statusBar}
    }

    static func center(_ window:NSWindow,on screen:NSScreen?) {
        guard let screen else {return}
        let available = screen.visibleFrame
        let size = NSSize(width:min(window.frame.width,available.width),height:min(window.frame.height,available.height))
        window.isMovable = true
        window.setFrame(NSRect(x:available.midX-size.width/2,y:available.midY-size.height/2,width:size.width,height:size.height),display:window.isVisible)
    }

    static func present(_ panel:NSSavePanel,relativeTo parent:NSWindow?,completion:(NSApplication.ModalResponse) -> Void) {
        let target = screen(for:parent)
        center(panel,on:target)
        // 原生文件面板在显示阶段完成布局；首次取得焦点时按最终尺寸定位一次。
        var positioned = false
        let observer = NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:panel,queue:.main) { _ in
            guard !positioned else {return}
            positioned = true
            center(panel,on:target)
        }
        let response = panel.runModal()
        NotificationCenter.default.removeObserver(observer)
        completion(response)
    }
}

final class AnchoredPopover:NSPopover {
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(didShow(_:)),name:NSPopover.didShowNotification,object:self)
    }
    required init?(coder:NSCoder) {fatalError()}

    @objc private func didShow(_ notification:Notification) {
        if let window = contentViewController?.view.window {PanelPresentation.setAnchoredWindowLevel(window)}
    }
}

final class CenteredColorWell:NSColorWell {
    override func activate(_ exclusive:Bool) {
        let target = PanelPresentation.screen(for:window)
        super.activate(exclusive)
        // 只在用户打开颜色面板时定位，颜色变化继续走 NSColorWell 的原生 target/action。
        PanelPresentation.center(NSColorPanel.shared,on:target)
    }
}

// 非激活面板上的 transient Popover 同步监听应用内外点击，并在打开普通窗口前可立即收起。
final class PopoverDismissal {
    private static let active = NSHashTable<NSPopover>.weakObjects()
    private var insideClickMonitor:Any?
    private var outsideClickMonitor:Any?
    static func closeAll() {
        for popover in active.allObjects where popover.isShown {
            popover.close()
        }
    }
    func start(for popover:NSPopover,anchor:NSView? = nil) {
        stop()
        guard popover.isShown else {return}
        Self.active.add(popover)
        let events:NSEvent.EventTypeMask = [.leftMouseDown,.rightMouseDown,.otherMouseDown]
        insideClickMonitor = NSEvent.addLocalMonitorForEvents(matching:events) { [weak self,weak popover,weak anchor] event in
            guard let popover,popover.isShown else {self?.stop(); return event}
            let popoverWindow = popover.contentViewController?.view.window
            if let target = event.window {
                if target === popoverWindow || target.parent === popoverWindow || target.sheetParent === popoverWindow || target.level >= .popUpMenu {
                    return event
                }
                if let anchor,target === anchor.window,anchor.bounds.contains(anchor.convert(event.locationInWindow,from:nil)) {
                    return event
                }
            }
            popover.performClose(nil)
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching:events) { [weak popover] _ in
            popover?.performClose(nil)
        }
    }
    func stop() {
        if let insideClickMonitor {NSEvent.removeMonitor(insideClickMonitor)}
        if let outsideClickMonitor {NSEvent.removeMonitor(outsideClickMonitor)}
        insideClickMonitor = nil
        outsideClickMonitor = nil
    }
    deinit {stop()}
}
