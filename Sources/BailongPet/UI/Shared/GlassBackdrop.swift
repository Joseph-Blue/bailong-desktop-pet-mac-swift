import AppKit

// 玻璃放在独立、无键盘焦点的窗口；正文窗口保留文本选择与编辑。
private final class GlassBackdropPanel:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}

final class GlassBackdrop {
    private weak var host:NSWindow?
    private let panel:GlassBackdropPanel
    private let originalShadow:Bool
    private var observers = [NSObjectProtocol]()
    init(host:NSWindow,effect:NSView) {
        self.host = host; originalShadow = host.hasShadow
        panel = GlassBackdropPanel(contentRect:host.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true; panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none; panel.hasShadow = originalShadow
        effect.removeFromSuperview(); panel.contentView = effect
        host.hasShadow = false
        for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification,NSWindow.didChangeScreenNotification,NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:host,queue:.main) { [weak self] _ in self?.synchronize() })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:host,queue:.main) { [weak self] _ in self?.panel.orderOut(nil) })
    }
    func synchronize() {
        guard let host else {panel.orderOut(nil); return}
        if panel.frame != host.frame {panel.setFrame(host.frame,display:true)}
        panel.alphaValue = host.alphaValue
        panel.level = host.level; panel.collectionBehavior = host.collectionBehavior
        panel.appearance = host.appearance
        if host.isVisible && !NSApp.isHidden {
            panel.order(.below,relativeTo:host.windowNumber)
        } else {panel.orderOut(nil)}
    }
    deinit {
        panel.orderOut(nil); panel.contentView = nil
        host?.hasShadow = originalShadow
        for observer in observers {NotificationCenter.default.removeObserver(observer)}
        observers.removeAll(); panel.close()
    }
}
