import AppKit

// 只在短过渡期间运行；窗口移动使用实时目标，不排队、不追赶桌宠。
final class BubbleMotion: NSObject {
    private weak var window: NSWindow?
    private let preferences: PetPreferences
    private var timer: Timer?
    private var fadeStart = 0.0, fadeDuration = 0.0
    private var alphaFrom = 1.0, alphaTo = 1.0
    private var slide = 0.0
    private var resizeStart = 0.0
    private var resizeFrom: NSSize?
    private(set) var frame: NSRect
    private(set) var presented = false
    var onHidden:(() -> Void)?
    private var pendingHide = false
    var onResize: ((NSSize) -> Void)? {didSet {if let window {onResize?(window.frame.size)}}}
    private var enabled: Bool {preferences.bool("bubbleMotion")}
    private var reduced: Bool {NSWorkspace.shared.accessibilityDisplayShouldReduceMotion}
    init(window: NSWindow, preferences: PetPreferences = .shared) {
        self.window = window; self.preferences = preferences; frame = window.frame
        super.init()
        window.animationBehavior = .none
        NotificationCenter.default.addObserver(self,selector:#selector(settingsChanged),name:PetPreferences.didChange,object:preferences)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(settingsChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
    }
    func show(key: Bool = false) {
        guard let window else {return}
        pendingHide = false
        if !presented {
            let wasVisible = window.isVisible
            presented = true; window.ignoresMouseEvents = false
            alphaFrom = wasVisible ? window.alphaValue : 0; alphaTo = 1
            fadeStart = ProcessInfo.processInfo.systemUptime
            fadeDuration = enabled ? (reduced ? 0.1 : 0.16) : 0
            slide = enabled && !reduced && !wasVisible ? 4 : 0
            render()
            startTimerIfNeeded()
        }
        if key {window.makeKeyAndOrderFront(nil)} else {window.orderFrontRegardless()}
    }
    func hide() {
        guard presented, let window else {return}
        presented = false; window.ignoresMouseEvents = true
        pendingHide = true
        alphaFrom = window.alphaValue; alphaTo = 0; slide = 0
        fadeStart = ProcessInfo.processInfo.systemUptime; fadeDuration = enabled ? 0.12 : 0
        resizeFrom = nil
        render(); startTimerIfNeeded()
    }
    func move(to origin: NSPoint) {
        frame.origin = origin
        render()
    }
    func adoptUserFrame() {
        guard let window else {return}
        resizeFrom = nil; frame = window.frame
    }
    func resize(to size: NSSize) {
        guard let window else {return}
        guard frame.size != size else {onResize?(window.frame.size); return}
        let previous = window.frame.size
        frame.size = size
        if presented && enabled && !reduced && previous.height != size.height {
            resizeFrom = NSSize(width:size.width,height:previous.height)
            resizeStart = ProcessInfo.processInfo.systemUptime
        } else {resizeFrom = nil}
        render(); startTimerIfNeeded()
    }
    private func progress(since start: Double, duration: Double) -> Double {
        guard duration > 0 else {return 1}
        let t = min(1,max(0,(ProcessInfo.processInfo.systemUptime-start)/duration))
        return 1-pow(1-t,3)
    }
    private func render() {
        guard let window else {return}
        let f = progress(since:fadeStart,duration:fadeDuration)
        window.alphaValue = alphaFrom+(alphaTo-alphaFrom)*f
        var displayed = frame
        displayed.origin.y -= slide*(1-f)
        if let from = resizeFrom {
            let r = progress(since:resizeStart,duration:0.14)
            displayed.size.height = from.height+(frame.height-from.height)*r
            if r >= 1 {resizeFrom = nil}
        }
        let sizeChanged = displayed.size != window.frame.size
        if displayed != window.frame {window.setFrame(displayed,display:true)}
        if sizeChanged {onResize?(displayed.size)}
        if f >= 1 && !presented {window.orderOut(nil); window.alphaValue = 1; window.ignoresMouseEvents = false}
        if f >= 1 && resizeFrom == nil {timer?.invalidate(); timer = nil}
        if f >= 1 && !presented && pendingHide {
            pendingHide = false
            onHidden?()
        }
    }
    private func startTimerIfNeeded() {
        guard timer == nil, progress(since:fadeStart,duration:fadeDuration) < 1 || resizeFrom != nil else {return}
        let tick = Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in self?.render() }
        timer = tick; RunLoop.main.add(tick,forMode:.common)
    }
    @objc private func settingsChanged() {
        guard !enabled || reduced else {return}
        fadeDuration = 0; slide = 0; resizeFrom = nil; render()
    }
    deinit {timer?.invalidate(); NotificationCenter.default.removeObserver(self); NSWorkspace.shared.notificationCenter.removeObserver(self)}
}
