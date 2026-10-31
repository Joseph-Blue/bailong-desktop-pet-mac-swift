import AppKit

// 桌宠显隐只改变透明度，不干预拖拽位置和素材播放时钟。
final class WindowFade: NSObject {
    private weak var window: NSWindow?
    private let preferences: PetPreferences
    private var timer: Timer?
    private var shown = false
    init(window: NSWindow, preferences: PetPreferences) {
        self.window = window; self.preferences = preferences
        super.init()
        window.animationBehavior = .none
        NotificationCenter.default.addObserver(self,selector:#selector(settingsChanged),name:PetPreferences.didChange,object:preferences)
    }
    func setVisible(_ visible: Bool) {
        guard let window, shown != visible else {return}
        shown = visible; timer?.invalidate(); timer = nil
        if visible {
            if !window.isVisible {window.alphaValue = 0}
            window.orderFrontRegardless()
        }
        guard preferences.bool("bubbleMotion"), window.isVisible else {finish(); return}
        let from = window.alphaValue, target: CGFloat = visible ? 1 : 0
        let started = ProcessInfo.processInfo.systemUptime, duration = visible ? 0.16 : 0.12
        let tick = Timer(timeInterval:1.0/60,repeats:true) { [weak self] timer in
            guard let self, let window = self.window else {timer.invalidate(); return}
            let t = min(1,(ProcessInfo.processInfo.systemUptime-started)/duration)
            window.alphaValue = from+(target-from)*(1-pow(1-t,3))
            if t >= 1 {self.finish()}
        }
        timer = tick; RunLoop.main.add(tick,forMode:.common)
    }
    @objc private func settingsChanged() {if !preferences.bool("bubbleMotion") {finish()}}
    private func finish() {
        timer?.invalidate(); timer = nil
        if !shown {window?.orderOut(nil)}
        window?.alphaValue = 1
    }
    func stop() {shown = false; finish()}
    deinit {timer?.invalidate(); NotificationCenter.default.removeObserver(self)}
}
