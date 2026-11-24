import AppKit
import QuartzCore

private final class PetSpritePanel: PetWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // PetController 已约束逻辑画布，透明绘制边距可伸到菜单栏背后。
        frameRect
    }
}

// CADisplayLink 保留 target；通过弱引用避免与控制器形成循环。
private final class PetMotionDisplayTarget: NSObject {
    weak var pet: PetController?
    init(_ pet: PetController) {self.pet = pet}
    @objc func refresh(_ link: CADisplayLink) {pet?.updateGeometry()}
}

final class MenuAction: NSMenuItem {
    let callback: () -> Void
    init(_ title: String, checked: Bool? = nil, symbol: String? = nil, _ callback: @escaping () -> Void) {
        self.callback = callback; super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self; if let checked { state = checked ? .on : .off }
        if let symbol {
            image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            image?.isTemplate = true
        }
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func run() { callback() }
}
final class PetController: NSObject, NSMenuDelegate {
    static let defaultCanvasSize:CGFloat = 256
    let catalog: Catalog
    let window: PetWindow
    let view = SpriteView()
    let decoder = Decoder()
    let bubble = Bubble()
    private let progressBubble = Bubble()
    private struct ToastSnapshot:Equatable {
        let turnKey:String?
        let start:Date?
        let content:TaskActivity.ProgressToast
    }
    private var toastActivities = [String:ToastSnapshot]()
    private var progressToastKey:String?
    var diagnostics: DiagnosticsPanel?
    var syncDiagnostics: () -> String = { L10n.text(.diagnostics,"pet.toastSnapshot.text") }
    var cliDiagnostics: () -> String = { L10n.text(.diagnostics,"pet.toastSnapshot.text.2") }
    let settings: SettingsPanel
    let preferences: PetPreferences
    let defaults: UserDefaults
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var onComposer: () -> Void = {}
    var onDismissComposer: () -> Void = {}
    var onReply: (String) -> Void = {_ in}
    var onHistory: (String?) -> Void = { _ in }
    var onWorkspace:() -> Void = {}
    var workspaceFrame:() -> CGRect? = {nil}
    var workspaceProvider:(String) -> (conversation:Conversation,executing:Bool)? = {_ in nil} {
        didSet {bubble.workspaceProvider = workspaceProvider; progressBubble.workspaceProvider = workspaceProvider}
    }
    func refreshWorkspaceBars() {
        bubble.refreshWorkspace()
        progressBubble.suppressWorkspace(bubble.visible && bubble.hasWorkspaceContext && bubble.relatedConversation == progressBubble.relatedConversation)
        progressBubble.refreshWorkspace()
    }
    var onCodex: (String?) -> Void = { _ in CodexConnection.openDesktop() }
    var onQuota: () -> Void = {}
    var onQuit: () -> Void = {}
    var onVisibility: (Bool) -> Void = { _ in }
    var onGeometry: () -> Void = {}
    var onPreferencesChanged: () -> Void = {}
    var syncStatus: () -> String = { L10n.text(.diagnostics,"pet.refreshWorkspaceBars.text") }
    var current: Clip
    var animation: Animation?
    var frameIndex = 0
    var playbackRate = 1.0
    var activityOrigin = CGPoint.zero
    var wasQuiet = false
    var currentFrame: Frame? { animation.flatMap { $0.stream?.current?.frame ?? $0.frames[min(frameIndex, $0.frames.count - 1)] } }
    var mode = "idle"
    var began = ProcessInfo.processInfo.systemUptime
    var loading = false
    var pending: (Clip, String)?
    var startup: NSPanel?
    var baseBounds: CGRect?
    private var sideDockOutline: SideDockGeometry.Outline?
    private var sideDockAnchor: (left:Bool,exposure:CGFloat,bounds:CGRect)?
    var dock: String?
    private var windowDock: WindowDock?
    private var windowDockMonitor: Any?
    private var windowDockObservers = [NSObjectProtocol]()
    private var lastWindowDockSample: TimeInterval = 0
    var isDocked: Bool {dock != nil || windowDock != nil}
    var clipsDockedSprite: Bool {dock == "notch" || windowDock != nil}
    var dockProgress = 0.0, dockFrom = 0.0, dockTarget = 0.0, dockBegan = 0.0
    var dockAnimating = false {didSet {updateMotionDisplayLink()}}
    var dockRestore = CGPoint.zero
    var dockRecallOrigin = CGPoint.zero
    var notchDockArea:CGRect?
    var notchDockDisplayID:String?
    var motion: (CGPoint, CGPoint)? {didSet {updateMotionDisplayLink()}}
    var activeTasks = Set<String>()
    var quotaActive = false
    var manualHidden = false, fullscreenHidden = false, sleeping = false
    var menuOpen = false, settingsOpen = false
    var composerVisible = false {didSet {if composerVisible {progressBubble.hide()}}}
    var composerFrame:() -> CGRect? = {nil}
    private var greetingPending = true
    private var exiting = false
    var pauseTime: Double?
    private var gestures = PetGestureState()
    private var dragModifiers: NSEvent.ModifierFlags = []
    private var dragTilt: PetDragTilt?
    private var throwMotion: PetThrowMotion? {
        didSet {if (oldValue == nil) != (throwMotion == nil) {updateMotionDisplayLink()}}
    }
    var isThrowing: Bool {throwMotion != nil}
    var isDragTilting: Bool {dragTilt != nil}
    private var dragPadding: CGSize {dragTilt?.padding ?? .zero}
    private var canvasFrame: CGRect {window.frame.insetBy(dx:dragPadding.width,dy:dragPadding.height)}
    private var canvasBounds: CGRect {CGRect(origin:.zero,size:canvasFrame.size)}
    var timer: Timer?, desktopTimer: Timer?
    var playbackScheduling = PlaybackSchedulingStatistics()
    private var motionDisplayLink: CADisplayLink?
    private var visibleActivity: NSObjectProtocol?
    private struct BubbleAnchor: Equatable {
        let frame: CGRect
        let screen: CGRect
        let dock: String?
    }
    private var bubbleAnchor: BubbleAnchor?
    private lazy var visibilityFade = WindowFade(window:window,preferences:preferences)
    var lastInteraction = ProcessInfo.processInfo.systemUptime
    var nextLeisure = ProcessInfo.processInfo.systemUptime + 15, movementReady = 0.0
    var nextMovement = false
    var observationTokens = [NSObjectProtocol]()
    var sound: NSSound?
    var petPercent: Int { get { defaults.object(forKey: "petPercent") as? Int ?? 100 } set { defaults.set(newValue, forKey: "petPercent") } }
    var bubblePercent: Int { get { defaults.object(forKey: "bubblePercent") as? Int ?? 100 } set { defaults.set(newValue, forKey: "bubblePercent") } }
    var soundEnabled: Bool { get { defaults.object(forKey: "soundEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "soundEnabled") } }
    var taskBubbles: Bool { get { defaults.object(forKey: "taskBubbles") as? Bool ?? true } set { defaults.set(newValue, forKey: "taskBubbles") } }
    var autoMove: Bool { get { defaults.object(forKey: "autoMove") as? Bool ?? true } set { defaults.set(newValue, forKey: "autoMove") } }
    var autoFullscreen: Bool { get { defaults.object(forKey: "autoFullscreen") as? Bool ?? true } set { defaults.set(newValue, forKey: "autoFullscreen") } }
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var size: Double { canvasFrame.width }
    var screen: NSScreen {
        let connected = NSScreen.screens
        if let windowDock {
            let outline = screenRect(for:windowDock.outline)
            if let display = connected.first(where:{$0.frame.contains(outline.center)}) {return display}
        }
        if isDragTilting, let display = connected.first(where:{$0.frame.contains(canvasFrame.center)}) {return display}
        // 屏幕变更通知到达时，窗口仍可保留旧归属；只使用当前连接列表中的屏幕对象。
        if let current = window.screen,
           let display = connected.first(where:{PetPreferences.displayID($0) == PetPreferences.displayID(current)}) {return display}
        return connected.first(where:{$0.frame.intersects(canvasFrame)}) ?? connected[0]
    }
    var preferredScreen: NSScreen? {
        let id = preferences.string("preferredDisplay")
        return NSScreen.screens.first {PetPreferences.displayID($0) == id}
    }
    var hidden: Bool { exiting || manualHidden || fullscreenHidden || sleeping }
    // 控制器采用与作者 Qt 相同的全局向下坐标；只在窗口边界转换成 AppKit 坐标。
    var top: Double { NSScreen.screens[0].frame.maxY }
    var position: CGPoint { CGPoint(x: canvasFrame.minX, y: top - canvasFrame.maxY) }
    func area(_ screen: NSScreen) -> CGRect { let r = screen.visibleFrame; return CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
    func move(_ p: CGPoint) { window.setFrameOrigin(CGPoint(x: p.x-dragPadding.width, y: top-p.y-size-dragPadding.height)); placeBubble() }
    func constrained(_ p: CGPoint, screen: NSScreen) -> CGPoint {
        let a = area(screen); return CGPoint(x: max(a.minX,min(p.x,a.maxX-size)), y: max(a.minY,min(p.y,a.maxY-size)))
    }
    var drawRect: CGRect {
        let scale = current.renderScale ?? 1, offset = current.renderOffset ?? [0,0]
        return CGRect(x: (size - size * scale)/2 + size * offset[0], y: size - size * scale + size * offset[1], width: size * scale, height: size * scale)
    }
    var transform: CGAffineTransform {
        let rotation = isDocked ? dockTransform : (dragTilt?.rotation ?? .identity)
        return rotation.concatenating(CGAffineTransform(translationX:dragPadding.width,y:dragPadding.height))
    }
    private var dockTransform: CGAffineTransform {
        if let windowDock {return windowDockTransform(edge:windowDock.edge,progress:dockProgress)}
        guard let dock, baseBounds != nil else { return .identity }
        let reference = stableLocalBounds
        if dock == "notch",notchDockArea != nil {
            return NotchDockGeometry.transform(reference:reference,size:size,maximumSize:Self.defaultCanvasSize,exposure:preferences.number("notchExposurePercent")/100,progress:dockProgress)
        }
        return SideDockGeometry.transform(reference:reference,size:size,exposure:preferences.number("sideExposurePercent")/100,
                                          progress:dockProgress,left:dock == "left")
    }
    init(catalog: Catalog, defaults: UserDefaults = SettingsStorage.defaults) {
        self.defaults = defaults; self.catalog = catalog; current = catalog.idle
        preferences = defaults === SettingsStorage.defaults ? .shared : PetPreferences(defaults:defaults)
        settings = SettingsPanel(preferences:preferences,catalog:catalog)
        window = PetSpritePanel(contentRect: NSRect(x: 0,y: 0,width: Self.defaultCanvasSize,height: Self.defaultCanvasSize), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        decoder.configure(bufferCapacity:preferences.animationBufferFrames,preloadWhole:preferences.bool("preloadWholeAnimation"))
        updateOpeningCachePreference()
        // 脚本与打包版共用初始化；首次将两个 100% 写入偏好，之后保留用户选择。
        for key in ["petPercent","bubblePercent"] where defaults.object(forKey:key) == nil {
            defaults.set(100,forKey:key)
        }
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = preferences.bool("petShadow")
        window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        window.contentView = view; view.pet = self
        window.setContentSize(NSSize(width: Self.defaultCanvasSize * Double(petPercent)/100, height: Self.defaultCanvasSize * Double(petPercent)/100))
        let target = preferredScreen ?? screen
        let a = target.visibleFrame
        let remember = preferences.bool("rememberPosition")
        let initial = CGPoint(x:a.minX+a.width*0.85-size/2,y:a.minY+a.height*0.23-size/2)
        window.setFrameOrigin(CGPoint(x:remember ? defaults.object(forKey:"x") as? Double ?? initial.x : initial.x,
                                      y:remember ? defaults.object(forKey:"y") as? Double ?? initial.y : initial.y))
        move(constrained(position, screen: target)); activityOrigin = position
        playbackRate = preferences.speed(current.id); wasQuiet = preferences.isQuiet(); nextLeisure = now + preferences.activityInterval
        bubble.preferences = preferences
        progressBubble.preferences = preferences
        sound = NSSound(contentsOf: Paths.resources.appendingPathComponent("sounds/click.wav"), byReference: true)
        status.button?.image = AppIcons.petTemplate
        status.button?.title = AppIcons.petTemplate == nil ? PetPreferences.productName : ""
        status.button?.imagePosition = .imageOnly
        status.button?.imageScaling = .scaleProportionallyDown
        status.button?.hoverHelp = preferences.appName; refreshMenu()
        bubble.onClose = { [weak self] in self?.quotaActive = false }
        bubble.onVisibilityChange = { [weak self] in self?.refreshWorkspaceBars() }
        progressBubble.onVisibilityChange = { [weak self] in self?.refreshWorkspaceBars() }
        progressBubble.onCardLayout = { [weak self] in self?.placeBubble() }
        settings.onPreview = { [weak self] clip in self?.preview(clip) }
        settings.onLinePreview = { [weak self] clip,line in self?.preview(clip,line:line) }
        settings.onMessagePreview = { [weak self] purpose in self?.showSizePreview(purpose:purpose,userRequested:true) }
        settings.onPreviewDetails = { [weak self] in self?.onHistory(nil) }
        observationTokens.append(NotificationCenter.default.addObserver(forName:PetPreferences.didChange,object:preferences,queue:.main) { [weak self] note in self?.settingsChanged(note.userInfo?["keys"] as? [String] ?? []) })
        settings.onClose = { [weak self] in
            guard let self else { return }; self.settingsOpen = false
            if self.bubble.kind == "preview" { self.bubble.hide() }; self.interaction()
        }
        configureAnimationTimer()
        desktopTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkDesktop() }
        let center = NSWorkspace.shared.notificationCenter
        observationTokens.append(center.addObserver(forName:NSWorkspace.didLaunchApplicationNotification,object:nil,queue:.main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.openai.codex" else {return}
            self?.preferences.refreshDesktopVersion()
        })
        observationTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleeping = true; self?.applyVisibility() })
        observationTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else {return}
            let wasWindowDocked = self.windowDock != nil
            self.sleeping = false; self.motion = nil; self.interaction(); self.keepOnScreen(); self.checkDesktop(); self.applyVisibility()
            if !wasWindowDocked || self.windowDock != nil {self.idle()}
        })
        observationTokens.append(center.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            self?.refreshWindowDock()
        })
        observationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.keepOnScreen() })
        let startup = NSPanel(contentRect:NSRect(x:0,y:0,width:440,height:108),styleMask:[.titled],backing:.buffered,defer:false)
        startup.title = preferences.appName; startup.isReleasedWhenClosed = false; startup.hidesOnDeactivate = false
        let heading = label(preferences.fixedText(L10n.text(.dialogue,"dialogue.loadingPet"))); heading.frame = NSRect(x:24,y:60,width:392,height:24)
        let progress = NSProgressIndicator(frame:NSRect(x:24,y:28,width:392,height:16)); progress.isIndeterminate = true; progress.style = .bar; progress.startAnimation(nil)
        startup.contentView?.addSubview(heading); startup.contentView?.addSubview(progress)
        startup.center(); if !hidden {startup.orderFrontRegardless()}; self.startup = startup
        play(catalog.idle, "idle")
        updateDiagnostics()
    }
    func interaction() { lastInteraction = now; nextLeisure = now + preferences.activityInterval; nextMovement = false }
    func soundOnce() { if soundEnabled && !preferences.isQuiet() { sound?.play() } }
    func animationResolution(for clip: Clip) -> Int {
        let points = Self.defaultCanvasSize * Double(petPercent)/100 * (clip.renderScale ?? 1)
        return preferences.animationResolution(points:points,backingScale:window.backingScaleFactor)
    }
    private func updateOpeningCachePreference() {
        decoder.setOpeningCacheEnabled(preferences.bool("animationOpeningCache") && !preferences.bool("preloadWholeAnimation"))
    }
    func play(_ clip: Clip, _ mode: String) {
        if self.motion != nil { movementReady = now + 10 }; motion = nil
        loading = true
        // 气泡生命周期由自身计时和明确关闭控制，不随动作切换清空。
        // 自动画质只在新动作请求时取样，拖动跨屏或调整尺寸不重启在播动作。
        let resolution = animationResolution(for:clip)
        if preferences.bool("preloadWholeAnimation"), current.id == clip.id,
           let animation, animation.stream == nil, animation.frames.count > 1, animation.frames.first?.image.width == resolution {
            decoder.cancel(); loading = false; self.mode = mode
            playbackRate = preferences.speed(clip.id); began = now; frameIndex = 0
            configureAnimationTimer(); return
        }
        let cacheOpening = !hidden && (catalog.idles.contains {$0.id == clip.id} ||
            [catalog.dragAnimation.id,catalog.landingAnimation.id,catalog.quotaAnimation.id].contains(clip.id))
        decoder.load(clip,resolution:resolution,fpsLimit:Double(preferences.string("animationFPSLimit")),
                     playbackRate:preferences.speed(clip.id),cacheOpening:cacheOpening,
                     cleanIsolatedPixels:preferences.bool("animationEdgeCleanup"),framesReady: { [weak self] in
            guard let self, !self.hidden else { return }
            self.tick()
        },first: { [weak self] frame in
            guard let self, !self.exiting else { return }
            if clip.id == self.catalog.idle.id && self.baseBounds == nil {
                self.baseBounds = frame.bounds
                self.sideDockOutline = SideDockGeometry.Outline(frame:frame,rect:AnimationTransition.rect(for:clip))
            }
            if self.animation == nil {
                self.current = clip; self.mode = mode; self.playbackRate = self.preferences.speed(clip.id); self.began = self.now
                self.animation = Animation([frame]); self.frameIndex = 0; self.view.refreshFrame()
                self.updateVisibleActivity()
                if !self.hidden {
                    self.view.displayIfNeeded()
                    self.visibilityFade.setVisible(true)
                }
            }
            self.greetOnFirstAppearance()
        }, completion: { [weak self] result in
            guard let self, !self.exiting else { return }; self.loading = false
            switch result {
            case .success(let animation):
                RecoveryWindow.resolve("animation-initialization")
                self.startup?.orderOut(nil); self.startup = nil
                // 像素、时间轴和清单校准一起切换，不能用新动作倍率绘制旧帧。
                if TerminalMonitor.active?.showsAnimation == true {
                    let previous = self.animation?.loadTiming == nil ? L10n.text(.diagnostics,"pet.previous") : TerminalMonitor.clip(self.current.id)
                    var summary = previous+" → "+TerminalMonitor.clip(clip.id)
                    if let stats = self.animation?.stream?.statistics(),stats.underflows > 0 {
                        summary += L10n.format(.diagnostics,"pet.play.text",String(describing:stats.underflows))+TerminalMonitor.milliseconds(stats.longestUnderflow)
                    }
                    animation.loadTiming?.monitorTransition = summary
                }
                self.view.prepareTransition(to:animation.frames[0],clip:clip)
                self.current = clip; self.mode = mode; self.playbackRate = self.preferences.speed(clip.id)
                self.animation = animation; self.frameIndex = 0; self.began = self.now
                self.updateVisibleActivity()
                self.configureAnimationTimer()
                self.pauseTime = self.hidden ? self.now : nil
                self.view.refreshFrame()
                if clip.id == self.catalog.idle.id {
                    let icon = NSImage(cgImage: animation.frames[0].image, size: NSSize(width: 128,height: 128))
                    NSApp.applicationIconImage = AppIcons.application ?? icon
                }
                if self.mode == "move" { self.planMotion(manual: true) }
                self.greetOnFirstAppearance()
            case .failure(let error):
                TerminalMonitor.active?.write(.animation,TerminalMonitor.clip(clip.id)+L10n.text(.app,"pet.error.text")+TerminalMonitor.errorCode(error),.error)
                self.startup?.orderOut(nil); self.startup = nil
                self.began = self.now
                if self.animation == nil {
                    self.timer?.invalidate(); self.timer = nil
                    self.updateVisibleActivity()
                    RecoveryWindow.show(id:"animation-initialization",report:RecoveryReport(title:L10n.text(.diagnostics,"pet.play.title"),message:L10n.text(.diagnostics,"pet.play.message"),module:L10n.text(.diagnostics,"pet.play.text.2"),operation:L10n.text(.diagnostics,"pet.play.text.3"),error:error),actionTitle:L10n.text(.diagnostics,"pet.play.actionTitle")) { [weak self] in self?.play(clip,mode) }
                    return
                }
                self.bubble.showFailure(AppFailure.animation(error),scale:Double(self.bubblePercent)/100,
                    retry:{ [weak self] in self?.play(clip,mode) })
                self.placeBubble()

            }
        })
    }
    func idle() {
        if isDocked {play(preferences.choose(catalog.idles,previous:current.id,selection:.docked) ?? catalog.idle,"idle"); return}
        if !activeTasks.isEmpty {
            let work = catalog.work.filter {$0.id != "work01" && $0.id != current.id && preferences.weight($0.id) > 0}
            let idles = catalog.idles.filter {$0.id != current.id && preferences.weight($0.id) > 0}
            let pool = !work.isEmpty && (idles.isEmpty || Double.random(in:0..<1) < 0.35) ? work : idles
            // 若用户只启用当前这一段，则继续默认待机，避免停在结束帧。
            play(preferences.choose(pool,previous:nil,selection:.task) ?? catalog.idle,"working")
            return
        }
        if leisureAllowed() {
            if nextMovement && autoMove && !preferences.isQuiet() && preferences.string("movementRange") != "still" && now >= movementReady {
                let eligible = catalog.movementAnimations.filter {route($0) != nil}
                if let clip = preferences.choose(eligible,previous:current.id) {nextMovement = false; nextLeisure = now + preferences.activityInterval; play(clip,"move"); return}
            }
            nextLeisure = now + preferences.activityInterval
            if let clip = preferences.choose(catalog.extras,previous:current.id) {nextMovement = autoMove; play(clip,"extra"); return}
            nextMovement = autoMove
        }
        play(preferences.choose(catalog.idles,previous:current.id,selection:.idle) ?? catalog.idle,"idle")
    }
    func leisureAllowed() -> Bool { !hidden && !isDocked && !isThrowing && activeTasks.isEmpty && !(quotaActive && bubble.kind == "quotaLoading") && !gestures.isPressed && !menuOpen && now >= max(nextLeisure,lastInteraction+preferences.activityInterval) }
    func route(_ clip: Clip) -> CGPoint? {
        guard preferences.string("movementRange") != "still" else {return nil}
        let a = area(screen)
        var bounds = CGRect(x:a.minX,y:a.minY,width:max(0,a.width-size),height:max(0,a.height-size))
        if preferences.string("movementRange") == "nearby" {
            let radius = size * 1.25
            bounds = bounds.intersection(CGRect(x:activityOrigin.x-radius,y:activityOrigin.y-radius,width:radius*2,height:radius*2))
            guard !bounds.isNull else {return nil}
        }
        return movementTarget(origin:position,bounds:bounds,size:size,clip:clip)
    }
    func planMotion(manual: Bool) { motion = (position, route(current) ?? position) }
    private func configureAnimationTimer() {
        animation?.stream?.setPlaybackRate(playbackRate,fpsLimit:Double(preferences.string("animationFPSLimit")))
        armAnimationTimer(at:now)
    }
    private func armAnimationTimer(at deadline: Double) {
        timer?.invalidate()
        guard !hidden else { timer = nil; return }
        timer = Timer(fire:Date().addingTimeInterval(max(0,deadline-now)),interval:0,repeats:false) { [weak self] _ in
            self?.tick(scheduledFor:deadline)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func scheduleAnimationTick(after tickTime: Double) {
        let reference = max(now,tickTime)
        let interval = 1 / preferences.animationFPS(native:(animation?.fps ?? 24)*playbackRate)
        // 档位节拍锚定动作时间轴；回调晚到不把下一帧继续往后推。
        let nextSlot = began + (floor(max(0,reference-began)/interval + 0.000001) + 1) * interval
        var deadline = nextSlot
        if let animation {
            let duration = current.durationMs/1000, elapsed = max(0,(reference-began)*playbackRate)
            let cycle = mode == "landing" ? 0 : floor(elapsed/duration)*duration
            let next: Double?
            if let stream = animation.stream { next = stream.nextFrameTime }
            else { next = frameIndex + 1 < animation.frames.count ? Double(frameIndex+1)*duration/Double(animation.frames.count) : nil }
            if let next, mode != "landing" || elapsed < duration {
                let frameDeadline = began + (cycle+next)/playbackRate
                deadline = preferences.string("animationFPSLimit") == "full" ? max(reference,frameDeadline) : max(nextSlot,frameDeadline)
            }
            // 等待解码或末帧期间保留原档位频率的鼠标命中检查，不忙等空队列。
            deadline = min(deadline,reference+interval)
            let end = began + duration/playbackRate
            if !loading, gestures.allowsMovement, end > reference { deadline = min(deadline,end) }
        }
        if let recall = gestures.recallDeadline { deadline = min(deadline,max(reference,recall)) }
        armAnimationTimer(at:deadline)
    }
    private func updateMotionDisplayLink() {
        let active = !hidden && (dockAnimating || isThrowing || dragTilt?.isMoving == true || motion != nil && gestures.allowsMovement)
        if active && motionDisplayLink == nil {
            let link = view.displayLink(target:PetMotionDisplayTarget(self),selector:#selector(PetMotionDisplayTarget.refresh(_:)))
            link.add(to:.main,forMode:.common)
            motionDisplayLink = link
        }
        motionDisplayLink?.isPaused = !active
    }
    // 每次刷新只变换位置和角度；动作结束时沿用原有的下一动作切换。
    fileprivate func updateGeometry() {
        guard !hidden else {updateMotionDisplayLink(); return}
        let wasDockAnimating = dockAnimating
        if dockAnimating {
            let t = min(1,(now-dockBegan)/0.3), remaining = pow(1-t,3)
            // 作者展开公式：起始进度 × (1 - 时间进度)^3，连续衰减到零。
            dockProgress = dockTarget == 1 ? dockFrom+(1-dockFrom)*(1-remaining) : dockFrom*remaining
            let destination = windowDock?.destination ?? (dockTarget == 0 ? constrained(dockRestore,screen:screen) : nil)
            if let destination {
                let next = CGPoint(x:destination.x+(dockRecallOrigin.x-destination.x)*remaining,
                                   y:destination.y+(dockRecallOrigin.y-destination.y)*remaining)
                if next != position {move(next)}
            }
            if t >= 1 { dockAnimating = false; dockProgress = dockTarget
                if dockTarget == 0 { dock = nil; notchDockArea = nil; notchDockDisplayID = nil; move(constrained(dockRestore,screen:screen))
                    savePosition()
                    if let pending { self.pending = nil; play(pending.0,pending.1) }
                    else { play(catalog.idle,"idle") }
                }
            }
        }
        if var flight = throwMotion {
            flight.advance(at:now)
            if flight.position != position {move(flight.position); updateMouseHit()}
            if flight.isMoving {throwMotion = flight}
            else {landAfterThrow()}
        } else if motion != nil, gestures.allowsMovement {
            updateMovement(at:(now-began)*playbackRate)
        }
        if var tilt = dragTilt, tilt.isMoving {
            let previousAngle = tilt.angle, dragging = gestures.isDragging
            tilt.advance(to:position,at:now,dragging:dragging)
            dragTilt = tilt
            if !dragging && !tilt.isMoving { resetDragTilt() }
            else {
                if tilt.angle != previousAngle {
                    view.refreshFrame()
                    if !dragging {updateMouseHit()}
                }
                if !tilt.isMoving {updateMotionDisplayLink()}
            }
        }
        if wasDockAnimating {
            view.refreshFrame()
            if bubbleAnchor != BubbleAnchor(frame:bubbleAttachmentFrame,screen:screen.visibleFrame,dock:dock) { placeBubble() }
        }
    }
    private func updateMovement(at elapsed: Double) {
        guard let (origin,target) = motion else {return}
        let start = current.moveStartMs ?? 0, stop = current.moveStopMs ?? current.durationMs
        let f = max(0,min(1,(elapsed*1000-start)/(stop-start)))
        let next = CGPoint(x:origin.x+(target.x-origin.x)*f,y:origin.y+(target.y-origin.y)*f)
        if next != position {move(next)}
    }
    func tick(scheduledFor deadline: Double? = nil) {
        let actual = now, tickTime = max(actual,deadline ?? actual)
        if let deadline {
            playbackScheduling.record(deadline:deadline,actual:actual,
                frameInterval:1/preferences.animationFPS(native:(animation?.fps ?? 24)*playbackRate))
        }
        defer { if !hidden { scheduleAnimationTick(after:tickTime) } }
        // 吸边单击沿用作者的 250ms 判定；到期仅召回，不执行普通单击动作。
        if gestures.recallDue(at:now) {undock()}
        if !hidden, let animation {
            let elapsed = (tickTime-began)*playbackRate, duration = current.durationMs/1000
            if elapsed >= duration && !loading && gestures.allowsMovement {
                if motion != nil {updateMovement(at:elapsed); movementReady = now + 10; motion = nil}
                if isThrowing || mode == "drag" && gestures.isDragging { began = now; selectFrame(at: 0, animation: animation) }
                else if mode == "opening" && !activeTasks.isEmpty, let clip = preferences.choose(catalog.work.filter({$0.id != "work01"}),previous:nil,selection:.task) { play(clip,"working") }
                else { idle() }
            } else {
                // 落地是一次性动作；下一段准备期间停在末帧，不绕回下蹲的开头。
                let playback = mode == "landing" ? min(max(0,elapsed),duration)
                    : max(0,elapsed).truncatingRemainder(dividingBy:duration)
                selectFrame(at: playback, animation: animation)
            }
        }
        if !hidden {
            view.refreshFrame()
            if bubbleAnchor != BubbleAnchor(frame:bubbleAttachmentFrame,screen:screen.visibleFrame,dock:dock) { placeBubble() }
            updateMouseHit()
        }
    }
    private func updateMouseHit() {
        if gestures.isPressed { window.ignoresMouseEvents = false; return }
        let local = view.convert(window.convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
        let point = local.applying(transform.inverted()), rect = drawRect
        let hit = view.bounds.contains(local) && rect.contains(point) &&
            (currentFrame?.alpha(x:Int((point.x-rect.minX)/rect.width*512),y:Int((point.y-rect.minY)/rect.height*512)) ?? 0) > 0
        window.ignoresMouseEvents = !hit
    }
    private func selectFrame(at time: Double, animation: Animation) {
        if let stream = animation.stream {
            stream.request(time); frameIndex = stream.current?.index ?? 0
        } else {
            frameIndex = min(animation.frames.count-1, Int(time / (current.durationMs/1000) * Double(animation.frames.count)))
        }
    }
    func mouseDown(_ event: NSEvent) {
        if event.modifierFlags.contains(.control) {rightMouseDown(event); return}
        interaction()
        dragModifiers = []
        let caught = isThrowing
        if motion != nil || caught {throwMotion = nil; idle()}
        if let gesture = gestures.begin(at:NSEvent.mouseLocation, petOrigin:position, docked:dock != nil,caught:caught,
                                        clickCount:event.clickCount, now:now) {
            performGesture(gesture)
        }
        updateMotionDisplayLink()
    }
    func forceClick() {
        if let gesture = gestures.forceClick() {performGesture(gesture)}
    }
    func mouseDragged(to point:CGPoint, modifiers: NSEvent.ModifierFlags) {
        switch gestures.drag(to:point) {
        case .recall: undock()
        case let .move(target, grabbedAt):
            dragModifiers = modifiers
            if let grabbedAt {
                clearWindowDock()
                beginDragTilt(at:grabbedAt)
                pending = nil; play(catalog.dragAnimation,"drag")
            }
            let screen = preferredScreen ?? NSScreen.screens.first(where:{$0.frame.contains(point)}) ?? self.screen
            let next = constrained(target,screen:screen)
            if next != position {
                move(next)
                if dragTilt?.isMoving == false {dragTilt?.wake(at:now); updateMotionDisplayLink()}
            }
        case nil: break
        }
    }
    private func beginDragTilt(at point: CGPoint) {
        let range = PetPreferences.dragTiltIntensityRange
        let intensity = min(preferences.number("dragTiltIntensity"),range.upperBound)
        guard intensity > 0, preferences.bool("dragTiltEnabled"), preferences.bool("bubbleMotion"),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {return}
        let canvas = canvasFrame
        let pivot = CGPoint(x:point.x-canvas.minX,y:canvas.maxY-point.y)
        dragTilt = PetDragTilt(pivot:pivot,center:stableLocalBounds.center,size:size,strength:intensity/100,position:position,time:now)
        let backingFrame = canvas.insetBy(dx:-dragPadding.width,dy:-dragPadding.height)
        if window.frame != backingFrame {window.setFrame(backingFrame,display:false)}
        view.refreshFrame()
        updateMotionDisplayLink()
    }
    func mouseUp(_ event: NSEvent) {
        let lastDragModifiers = dragModifiers
        dragModifiers = []
        guard let release = gestures.release(docked:dock != nil, now:now) else {return}
        interaction()
        switch release {
        case let .click(gesture): performGesture(gesture)
        case .finishDrag:
            if !snapToWindow(at:NSEvent.mouseLocation,modifiers:event.modifierFlags,lastDragModifiers:lastDragModifiers), !snap() {
                let time = now
                // position 通过透明边距读取 dragTilt，先取坐标，再修改倾斜状态。
                let releasePosition = position
                let velocity = dragTilt?.release(at:releasePosition,time:time)
                if dragTilt?.isMoving == false {resetDragTilt()}
                if let velocity {
                    let display = preferredScreen ?? screen
                    throwMotion = PetThrowMotion(position:releasePosition,velocity:velocity,area:area(display),size:size,time:time)
                } else {play(catalog.landingAnimation,"landing")}
            }
        case .handled: break
        }
        activityOrigin = position; savePosition(); updateMotionDisplayLink()
    }
    func landAfterThrow() {
        guard isThrowing else {return}
        throwMotion = nil
        activityOrigin = position; savePosition()
        if !hidden {play(catalog.landingAnimation,"landing")}
    }
    func resetDragTilt() {
        guard isDragTilting else {return}
        let canvas = canvasFrame
        dragTilt = nil
        window.setFrame(canvas,display:false)
        if !hidden {view.refreshFrame(); updateMouseHit()}
        updateMotionDisplayLink()
    }
    private var windowDockAreas: [CGRect] {
        (preferredScreen.map {[$0]} ?? NSScreen.screens).map { area($0) }
    }
    private var allowsWindowDockMotion: Bool {
        preferences.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private func windowDockTransform(edge: BubblePlacement.Side, progress: CGFloat) -> CGAffineTransform {
        WindowDock.transform(edge:edge,reference:stableLocalBounds,size:size,
                             exposure:preferences.number("sideExposurePercent")/100,progress:progress)
    }
    private func windowDockOutline(edge: BubblePlacement.Side) -> CGRect {
        if edge == .left || edge == .right, let local = sideDockBubbleBounds(left:edge == .right,progress:1) {return local}
        return stableLocalBounds.applying(windowDockTransform(edge:edge,progress:1)).intersection(canvasBounds)
    }
    private func snapToWindow(at point: CGPoint, modifiers: NSEvent.ModifierFlags, lastDragModifiers: NSEvent.ModifierFlags) -> Bool {
        guard !composerVisible, baseBounds != nil, preferences.bool("windowDockEnabled"),
              let modifier = WindowDockModifier(rawValue:preferences.string(WindowDockModifier.key)),
              modifier.matchesRelease(modifiers,lastDragModifiers:lastDragModifiers),
              let snapshot = WindowDockTarget.snapshot() else {return false}
        let windows = windowDockCandidates(in:snapshot)
        guard !windows.isEmpty else {return false}
        let p = position, body = stableLocalBounds.offsetBy(dx:p.x,dy:p.y)
        let outlines = Dictionary(uniqueKeysWithValues:BubblePlacement.Side.allCases.map {($0,windowDockOutline(edge:$0))})
        guard let attachment = WindowDock.nearest(to:body,cursor:CGPoint(x:point.x,y:top-point.y),windows:windows,
                                                   areas:windowDockAreas,outlines:outlines,size:size) else {return false}
        resetDragTilt()
        dockRestore = constrained(position,screen:preferredScreen ?? screen)
        dockRecallOrigin = position; dockProgress = 0; dockFrom = 0; dockTarget = 1; dockBegan = now
        windowDock = attachment; dockAnimating = true
        if !allowsWindowDockMotion {finishWindowDockMotion()}
        startWindowDockMonitoring()
        play(catalog.idle,"idle")
        return true
    }
    func finishWindowDockMotion() {
        guard !hidden, dockAnimating, let windowDock else {return}
        dockProgress = 1; dockAnimating = false
        move(windowDock.destination)
        view.refreshFrame(); updateMouseHit()
    }
    private func startWindowDockMonitoring() {
        guard !hidden, let target = windowDock?.target, windowDockMonitor == nil, windowDockObservers.isEmpty else {return}
        if target.owner == ProcessInfo.processInfo.processIdentifier,
           let local = NSApp.window(withWindowNumber:Int(target.number)) {
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification,
                         NSWindow.willCloseNotification,NSWindow.didMiniaturizeNotification] {
                let observer = center.addObserver(forName:name,object:local,queue:.main) { [weak self] note in
                    guard let self, self.windowDock?.target == target else {return}
                    if note.name == NSWindow.willCloseNotification || note.name == NSWindow.didMiniaturizeNotification {
                        self.dropFromWindow()
                    } else if self.now-self.lastWindowDockSample >= 1.0/30 {
                        self.refreshWindowDock()
                    }
                }
                windowDockObservers.append(observer)
            }
            return
        }
        windowDockMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDragged,.leftMouseUp]) { [weak self] event in
            guard let self, self.windowDock?.target == target,
                  event.type == .leftMouseUp || self.now-self.lastWindowDockSample >= 1.0/30 else {return}
            self.refreshWindowDock()
        }
    }
    private func stopWindowDockMonitoring() {
        if let windowDockMonitor {NSEvent.removeMonitor(windowDockMonitor); self.windowDockMonitor = nil}
        for observer in windowDockObservers {NotificationCenter.default.removeObserver(observer)}
        windowDockObservers.removeAll()
    }
    private func refreshWindowDock(recalculateOutline: Bool = false) {
        guard !hidden, let windowDock else {return}
        lastWindowDockSample = now
        guard let snapshot = WindowDockTarget.snapshot(through:windowDock.target.number) else {return}
        followWindowDock(in:snapshot,recalculateOutline:recalculateOutline)
    }
    private func windowDockCandidates(in snapshot: [[String:Any]]) -> [WindowDockTarget] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return WindowDockTarget.visibleWindows(in:snapshot).filter { target in
            if target.identity.owner != pid {return true}
            guard let local = NSApp.window(withWindowNumber:Int(target.identity.number)) else {return false}
            return InterfaceWindows.shared.isOpen(local)
        }
    }
    private func followWindowDock(in snapshot: [[String:Any]], recalculateOutline: Bool = false) {
        guard var attachment = windowDock else {return}
        let previous = attachment
        let windows = windowDockCandidates(in:snapshot)
        if recalculateOutline {attachment.outline = windowDockOutline(edge:attachment.edge)}
        guard attachment.follow(windows,areas:windowDockAreas,size:size) else {dropFromWindow(); return}
        windowDock = attachment
        if !dockAnimating, attachment.destination != position {move(attachment.destination)}
        else if recalculateOutline || attachment.targetFrame != previous.targetFrame {placeBubble()}
        if recalculateOutline {view.refreshFrame()}
        if !dockAnimating, attachment.destination != previous.destination {updateMouseHit()}
    }
    private func clearWindowDock() {
        guard windowDock != nil else {return}
        stopWindowDockMonitoring()
        windowDock = nil; dockProgress = 0; dockAnimating = false
    }
    private func dropFromWindow() {
        guard windowDock != nil else {return}
        let display = preferredScreen ?? screen
        clearWindowDock()
        interaction(); move(constrained(position,screen:display))
        activityOrigin = position; savePosition()
        guard !hidden else {return}
        view.refreshFrame(); updateMouseHit()
        if let pending {self.pending = nil; play(pending.0,pending.1)}
        else {play(catalog.landingAnimation,"landing")}
    }
    func snap() -> Bool {
        guard !composerVisible else { return false }
        if snapToNotch(on:screen) {return true}
        guard preferences.bool("sideDockEnabled") else {return false}
        let display = screen, visibleFrame = display.visibleFrame, p = position
        let left = abs(p.x-visibleFrame.minX), right = abs(visibleFrame.maxX-p.x-size)
        guard min(left,right) <= 24 else { return false }
        resetDragTilt()
        let dockLeft = left <= right
        dockRestore = p; dock = dockLeft ? "left" : "right"
        move(CGPoint(x:SideDockGeometry.originX(frame:display.frame,visibleFrame:visibleFrame,size:size,left:dockLeft),y:p.y))
        dockProgress = 0; dockFrom = 0; dockTarget = 1; dockBegan = now; dockAnimating = true
        play(catalog.idle,"idle"); return true
    }
    func undock() {
        gestures.cancelRecall()
        if windowDock != nil {dropFromWindow(); return}
        guard dock != nil else {return}
        dockRecallOrigin = position; dockFrom = dockProgress; dockTarget = 0; dockBegan = now; dockAnimating = true; interaction()
    }
    func preview(_ clip: Clip, taskOverview:Bool = false, line:String? = nil) {
        throwMotion = nil
        interaction(); soundOnce()
        let wasHidden = hidden
        manualHidden = false
        if wasHidden != hidden { applyVisibility() }
        let mode = catalog.movementAnimations.contains(where:{$0.id == clip.id}) ? "move" : "interaction"
        if isDocked { pending = (clip,mode); undock() } else { play(clip,mode) }
        let showsOverview = taskOverview && preferences.bool("showTaskOverview")
        let title = showsOverview && bubble.taskProvider().tasks.contains(where:{$0.active})
            ? preferences.workingOverviewLine()
            : line ?? preferences.line(for:clip) ?? preferences.statusLine("greetingTemplate")
        say(title,kind:"interaction",personalizeTitle:false,taskOverview:showsOverview,userRequested:true)
    }
    func dismissBubblesForComposer() {
        quotaActive = false
        if bubble.visible {bubble.hide()}
        if progressBubble.visible {progressBubble.hide()}
    }
    func say(_ title: String, body: String = "", kind: String = "interaction", thread: String? = nil, resetText: Bool = false, purpose: MessagePurpose? = nil, personalizeTitle: Bool = true, animateHeading: Bool = false, attentionAction: Bool = false, timing: TaskTiming? = nil, question: QuestionPresentation? = nil, messageID:String? = nil, taskOverview:Bool = false,selectCard:Bool = false,approval:ApprovalPresentation? = nil,fileEdits:[FileEditSummary] = [],isUserInput:Bool = false,completionFooter:TurnCompletion? = nil,failure:AppFailure? = nil,userRequested:Bool = false,retainsQuestionDraft:Bool = false) {
        let purpose = purpose ?? (kind.hasPrefix("quota") ? .quota : kind == "task" ? .progress : .interaction)
        guard !hidden && preferences.allows(purpose) else { return }
        if [.attention,.result,.quota].contains(purpose) {progressBubble.hide()}
        let transientInteraction = purpose == .interaction && !taskOverview && thread == nil && timing == nil && question == nil && !attentionAction
        if transientInteraction && !bubble.acceptsTransientInteraction {return}
        if !kind.hasPrefix("quota") && bubble.kind.hasPrefix("quota") { quotaActive = false }
        if kind.hasPrefix("quota") || transientInteraction {
            bubble.onQuestionSubmit = nil; bubble.onQuestionsSkipped = nil
            bubble.show(title:personalizeTitle ? preferences.fixedText(title) : title,body:body,kind:kind,scale:Double(bubblePercent)/100,seconds:kind == "quotaLoading" ? 0 : preferences.duration(purpose,text:body),animateHeading:animateHeading || kind == "quotaLoading")
            bubble.purpose = purpose
        } else {
            // 只有明确标记的实时任务概览复用卡片，不能按 interaction 类型合并普通消息。
            let identity = taskOverview ? "task-overview" : (timing?.key.map {key in (thread ?? "")+":"+key+":"+String(timing?.start?.timeIntervalSince1970 ?? 0)+":"+(messageID ?? "status")} ?? UUID().uuidString)
            let reply:(() -> Void)? = thread.flatMap {key in attentionAction ? nil : { [weak self] in self?.onReply(key) }}
            bubble.onCardLayout = { [weak self] in self?.placeBubble() }
            let content = BubbleContent(title:personalizeTitle ? preferences.fixedText(title) : title,body:body,kind:kind,
                animateHeading:animateHeading,timing:timing,conversation:thread,failure:failure)
            let displayed = bubble.present(BubbleCard(id:identity,content:content,purpose:purpose,resetText:resetText,
                attentionAction:attentionAction,question:question,
                details:{ [weak self] in self?.onHistory(thread) },codex:{ [weak self] in self?.onCodex(thread) },reply:reply,approval:approval,fileEdits:fileEdits,showsTaskOverview:taskOverview,isUserInput:isUserInput,completionFooter:completionFooter,
                retainsQuestionDraft:retainsQuestionDraft),select:selectCard)
            if !displayed {return}
        }
        if userRequested && composerVisible {onDismissComposer()}
        placeBubble()
    }
    var stableLocalBounds: CGRect {
        let b = baseBounds ?? CGRect(x:128,y:64,width:256,height:448)
        return CGRect(x:b.minX*size/512,y:b.minY*size/512,width:b.width*size/512,height:b.height*size/512)
    }
    var visiblePetFrame: CGRect {
        if let windowDock {
            let local = BubblePlacement.interpolatedAnchor(from:stableLocalBounds.intersection(canvasBounds),
                                                           to:windowDock.outline,progress:dockProgress)
            return screenRect(for:local)
        }
        let local = stableLocalBounds.applying(dockTransform).intersection(canvasBounds)
        return local.isNull ? canvasFrame : screenRect(for:local)
    }
    private func screenRect(for local: CGRect) -> CGRect {
        window.convertToScreen(view.convert(local.offsetBy(dx:dragPadding.width,dy:dragPadding.height),to:nil))
    }
    private var bubbleAttachmentFrame: CGRect {
        if let dock,dock == "left" || dock == "right",let local = sideDockBubbleBounds(left:dock == "left") {
            return screenRect(for:local)
        }
        guard dock == "notch",dockAnimating,notchDockArea != nil,baseBounds != nil else {return visiblePetFrame}
        let local = NotchDockGeometry.bubbleAnchor(reference:stableLocalBounds,size:size,
            maximumSize:Self.defaultCanvasSize,exposure:preferences.number("notchExposurePercent")/100,progress:dockProgress)
        return screenRect(for:local)
    }
    private func sideDockBubbleBounds(left:Bool,progress:CGFloat? = nil) -> CGRect? {
        guard let baseBounds,let sideDockOutline else {return nil}
        let exposure = CGFloat(preferences.number("sideExposurePercent"))/100
        if sideDockAnchor?.left != left || sideDockAnchor?.exposure != exposure {
            let reference = baseBounds.applying(CGAffineTransform(scaleX:1.0/512,y:1.0/512))
            let transform = SideDockGeometry.transform(reference:reference,size:1,exposure:exposure,progress:1,left:left)
            sideDockAnchor = (left,exposure,sideDockOutline.dockedBounds(transform:transform))
        }
        guard let bounds = sideDockAnchor?.bounds,!bounds.isNull else {return nil}
        let docked = bounds.applying(CGAffineTransform(scaleX:size,y:size))
        return BubblePlacement.interpolatedAnchor(from:stableLocalBounds.intersection(canvasBounds),to:docked,progress:progress ?? dockProgress)
    }
    func showProgressToast(_ activity:TaskActivity?,key:String,timing:TaskTiming,thread:String? = nil) {
        guard let activity,activity.kind != .reply else {
            if progressToastKey == key {progressBubble.hide(); progressToastKey = nil}; return
        }
        let content = activity.progressToast
        let snapshot = ToastSnapshot(turnKey:timing.activityKey ?? timing.key,start:timing.start,content:content)
        if activity.isToolFailure && preferences.bool("hideToolFailures") {
            if progressToastKey == key {progressBubble.hide(); progressToastKey = nil}
            return
        }
        if activity.kind == .status {
            if progressToastKey == key {progressBubble.hide(); progressToastKey = nil}
            guard !hidden,!composerVisible,!bubble.blocksProgressToast,!bubble.kind.hasPrefix("quota"),preferences.allows(.progress) else {return}
            guard activity.isReconnecting || toastActivities[key] != snapshot else {return}
            toastActivities[key] = snapshot
            if bubble.refreshActivity(timing:timing) {return}
            say(preferences.statusLine("taskProgressTemplate"),kind:"task",thread:thread,purpose:.progress,personalizeTitle:false,timing:timing,messageID:"connection-status")
            return
        }
        guard !hidden,!composerVisible,!bubble.blocksProgressToast,!bubble.kind.hasPrefix("quota"),
              preferences.bool("progressToastEnabled"),activity.visible,content.heading.visible,preferences.allows(.progress) else {return}
        guard toastActivities[key] != snapshot else {return}
        toastActivities[key] = snapshot
        progressToastKey = key; progressBubble.showProgressToast(content,timing:timing,conversation:thread); placeBubble()
    }
    func placeBubble() {
        let anchor = bubbleAttachmentFrame
        bubbleAnchor = BubbleAnchor(frame:anchor,screen:screen.visibleFrame,dock:dock)
        // 输入位置先确定；后台到达的消息主动避让，不移动正在编辑的窗口。
        onGeometry()
        let attachedWindow = windowDock.map { dock in
            let frame = dock.targetFrame
            return CGRect(x:frame.minX,y:top-frame.maxY,width:frame.width,height:frame.height)
        }
        let obstacles = [composerVisible ? composerFrame() : nil,workspaceFrame(),attachedWindow].compactMap {$0}
        if bubble.visible {bubble.place(near:anchor,screen:screen,dock:dock,avoiding:obstacles)}
        if progressBubble.visible {
            if bubble.blocksProgressToast || composerVisible {progressBubble.hide(); return}
            progressBubble.place(near:anchor,screen:screen,dock:dock,avoiding:obstacles)
            if bubble.visible && progressBubble.targetFrame.intersects(bubble.targetFrame) {progressBubble.hide()}
        }
    }
    func resize(_ p: Int, _ b: Int) {
        resetDragTilt()
        let old = window.frame
        petPercent = p; bubblePercent = b; interaction()
        let side = Self.defaultCanvasSize * Double(p)/100
        window.setFrame(NSRect(x:old.midX-side/2,y:old.minY,width:side,height:side),display:true)
        keepOnScreen()
        activityOrigin = position; savePosition()
    }
    func showSizePreview(purpose: MessagePurpose = .preview,userRequested:Bool = false) {
        guard !hidden else{return}
        quotaActive = false
        // 作者 size_preview 本身是空白框；按用户要求，改用 chat_ui.py 的普通对话文案填充预览。
        bubble.onDetails = { [weak self] in self?.onHistory(nil) }
        bubble.onCodex = { [weak self] in self?.onCodex(nil) }
        bubble.show(title:preferences.petName,body:preferences.statusLine("greetingTemplate"),kind:"preview",scale:Double(bubblePercent)/100,seconds:preferences.duration(purpose,text:preferences.statusLine("greetingTemplate")),details:true)
        bubble.purpose = purpose
        if userRequested && composerVisible {onDismissComposer()}
        placeBubble()
    }
    func keepOnScreen() {
        motion = nil
        if windowDock != nil {refreshWindowDock(recalculateOutline:true); return}
        if let display = preferredScreen {
            let id = PetPreferences.displayID(display)
            if id != PetPreferences.displayID(screen) || (dock == "notch" && id != notchDockDisplayID) {
                applyPreferredDisplay(); return
            }
        }
        if dock == "notch" {repositionNotchDock(); return}
        let display = screen
        var origin = constrained(position,screen:display)
        if let dock {origin.x = SideDockGeometry.originX(frame:display.frame,visibleFrame:display.visibleFrame,size:size,left:dock == "left")}
        move(origin)
        landAfterThrow()
    }
    func taskStarted(_ key: String) { let first = activeTasks.isEmpty; activeTasks.insert(key); interaction()
        if preferences.bool("taskOpening") && first && !hidden && !isDocked && !isThrowing && !gestures.isPressed, let clip = catalog.work.first(where:{$0.id == "work01"}) { play(clip,"opening") }
    }
    func stopObservingTask(_ key:String) {
        toastActivities.removeValue(forKey:key)
        if progressToastKey == key {progressBubble.hide(); progressToastKey = nil}
        activeTasks.remove(key)
        if activeTasks.isEmpty && !hidden && !isDocked && !isThrowing && !gestures.isPressed {idle()}
    }
    func taskEnded(_ key: String, status: String) {
        toastActivities.removeValue(forKey:key)
        if progressToastKey == key {progressBubble.hide(); progressToastKey = nil}
        bubble.finishTask(key,status:status); activeTasks.remove(key); interaction()
        if status == "completed" { soundOnce() }
        guard !hidden && !isDocked && !isThrowing && !gestures.isPressed else { return }
        if status == "completed" && preferences.bool("taskCelebration"), let clip = catalog.variants.first(where:{$0.id == "18"}) { play(clip,"celebration") }
        else if activeTasks.isEmpty { idle() }
    }
    var fullCandidate = false, fullCandidateSince = 0.0
    private var fullscreenRevealOverride = false
    func checkDesktop() {
        let quiet = preferences.isQuiet()
        if quiet != wasQuiet {wasQuiet = quiet; interaction(); if quiet && motion != nil {idle()}; if !preferences.allows(bubble.purpose) {bubble.hide()}; if !preferences.allows(.progress) {progressBubble.hide()}}
        var full = false
        let front = autoFullscreen ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        let checksFullscreen = front != nil && front != ProcessInfo.processInfo.processIdentifier
        let windows = checksFullscreen || (!hidden && windowDock != nil) ? WindowDockTarget.snapshot() : nil
        if checksFullscreen, let front, let windows {
            full = windows.contains { item in
                guard (item[kCGWindowOwnerPID as String] as? Int32) == front, (item[kCGWindowLayer as String] as? Int) == 0,
                      let b = item[kCGWindowBounds as String] as? [String:Any], let rect = CGRect(dictionaryRepresentation:b as CFDictionary) else { return false }
                return NSScreen.screens.contains { screen in
                    let a = screen.frame, r = CGRect(x:a.minX,y:top-a.maxY,width:a.width,height:a.height)
                    return rect.minX <= r.minX+2 && rect.minY <= r.minY+2 && rect.maxX >= r.maxX-2 && rect.maxY >= r.maxY-2
                }
            }
        }
        // 明确重新打开应用时先召回；退出当前全屏环境后恢复自动隐藏。
        if !full {fullscreenRevealOverride = false}
        full = full && !fullscreenRevealOverride
        if full != fullCandidate { fullCandidate = full; fullCandidateSince = now }
        if fullscreenHidden != full && now-fullCandidateSince >= (full ? 0.25 : 0.75) { fullscreenHidden = full; applyVisibility() }
        if let windows, !hidden, windowDock != nil {followWindowDock(in:windows)}
    }
    private func updateVisibleActivity() {
        // 仅在桌宠可见播放时阻止 App Nap 合并帧定时器；不阻止显示器休眠或系统空闲睡眠，隐藏／休眠／退出时立即释放。
        let active = !hidden && animation != nil
        if active {
            if visibleActivity == nil {
                visibleActivity = ProcessInfo.processInfo.beginActivity(options:[.userInitiatedAllowingIdleSystemSleep],reason:"Visible desktop pet animation")
            }
        } else if let visibleActivity {
            ProcessInfo.processInfo.endActivity(visibleActivity)
            self.visibleActivity = nil
        }
    }
    func applyVisibility() {
        updateVisibleActivity()
        if hidden {
            view.cancelTransition()
            stopWindowDockMonitoring()
            landAfterThrow()
            animation?.stream?.pauseObservation(); diagnostics?.pausePresentationClock()
            decoder.discardOpeningCache()
            timer?.invalidate(); timer = nil
        }
        if hidden {
            gestures = PetGestureState()
            dragModifiers = []
            if pauseTime == nil {pauseTime = now}
            window.ignoresMouseEvents = true
            visibilityFade.hide { [weak self] in
                guard let self, self.hidden else {return}
                self.resetDragTilt()
                self.view.releaseDisplayTracking()
            }
            bubble.hide(); progressBubble.hide(); quotaActive = false; onVisibility(false)
        } else {
            if let pauseTime {began += now-pauseTime; resetDragTilt()}
            pauseTime = nil
            refreshWindowDock()
            if !allowsWindowDockMotion {finishWindowDockMotion()}
            startWindowDockMonitoring()
            if animation != nil {view.refreshFrame(); visibilityFade.setVisible(true)}
            interaction()
            onVisibility(true)
        }
        if !hidden { configureAnimationTimer() }
        updateMotionDisplayLink(); refreshMenu(); greetOnFirstAppearance()
    }
    private func greetOnFirstAppearance() {
        // 等首段素材完成初始化再切换问候动作，不能从首帧回调取消仍在加载的待机素材。
        guard greetingPending,!hidden,!loading,animation != nil else {return}
        greetingPending = false
        guard preferences.allows(.interaction),activeTasks.isEmpty,!bubble.visible,!composerVisible else {return}
        say(preferences.petName,body:preferences.statusLine("greetingTemplate"),kind:"greeting",purpose:.interaction,personalizeTitle:false)
        if let greeting = catalog.variants.first(where:{$0.id == "01"}) {play(greeting,"interaction")}
    }
    func reveal() { manualHidden = false; keepOnScreen(); applyVisibility() }
    func revealFromReopen() {
        fullscreenRevealOverride = true
        fullscreenHidden = false; fullCandidate = false; fullCandidateSince = now
        reveal(); undock()
        // 系统隐藏不改变 WindowFade 的 shown 状态，显式召回仍需重新前置原窗口。
        if !hidden {
            if animation != nil {window.orderFrontRegardless()}
            else {startup?.orderFrontRegardless()}
        }
    }
    private func randomAnimation(taskOverview:Bool = false) {
        if let clip = preferences.choose(catalog.variants+catalog.work,previous:current.id) {preview(clip,taskOverview:taskOverview)}
    }
    private func performGesture(_ gesture: PetGesture) {
        switch preferences.string(gesture.setting.key) {
        case "chat": soundOnce(); onComposer()
        case "quota": soundOnce(); onQuota()
        case "history": soundOnce(); onHistory(nil)
        case "workspace": soundOnce(); onWorkspace()
        case "random": randomAnimation(taskOverview:true)
        case "randomAnimation": randomAnimation()
        default: break
        }
    }
    func rightMouseDown(_ event: NSEvent) {
        interaction()
        if motion != nil || isThrowing {throwMotion = nil; idle()}
        // Control 点按可由 AppKit 直接分派到右键入口，菜单跟踪需采样实际按下的键。
        let button = event.modifierFlags.contains(.control) && NSEvent.pressedMouseButtons & 1 != 0 ? 0 : event.buttonNumber
        let interval = NSEvent.doubleClickInterval
        switch gestures.contextDown(button:button, at:NSEvent.mouseLocation, time:event.timestamp, interval:interval) {
        case .menu: showContextMenu(button:button,deadline:event.timestamp + interval)
        case .doubleClick: performGesture(.rightDoubleClick)
        case .handled: break
        }
    }
    private func showContextMenu(button:Int, deadline:TimeInterval) {
        let menu = makeMenu(); menu.update()
        let cursor = NSEvent.mouseLocation
        let target = NSScreen.screens.first(where:{$0.frame.contains(cursor)}) ?? screen
        let frame = MenuPlacement.frame(size:menu.size,cursor:cursor,screen:target.visibleFrame,pet:visiblePetFrame)
        // NSMenu 的嵌套事件循环不会经过本地事件监视器。
        // 只在本次双击识别时间内读取按键状态，不延迟菜单显示，不申请全局输入权限。
        var doubleClicked = false
        func captureSecondPress() {
            let pressed = NSEvent.pressedMouseButtons & (1 << button) != 0
            if gestures.sampleMenuButton(button, pressed:pressed, control:NSEvent.modifierFlags.contains(.control),
                                         at:NSEvent.mouseLocation, time:now) {
                doubleClicked = true
                menu.cancelTrackingWithoutAnimation()
            }
        }
        let tracking = Timer(timeInterval:1/120,repeats:true) { timer in
            if ProcessInfo.processInfo.systemUptime > deadline {timer.invalidate(); return}
            captureSecondPress()
        }
        RunLoop.main.add(tracking,forMode:.eventTracking)
        defer {tracking.invalidate()}
        menu.popUp(positioning:nil,at:NSPoint(x:frame.minX,y:frame.maxY),in:nil)
        // 原生菜单可能先消费第二次按下并退出；返回时也处理该按下。
        captureSecondPress()
        tracking.invalidate()
        if doubleClicked {performGesture(.rightDoubleClick)}
    }
    func makeMenu() -> NSMenu {PetMenu.make(for:self,random:{ [weak self] in self?.randomAnimation() })}
    func savePosition() {
        guard preferences.bool("rememberPosition") else {return}
        // 刘海收纳不作为下次启动位置，保存正常展开时的位置。
        let canvas = canvasFrame
        let useRestoredPosition = dock == "notch" || windowDock != nil
        defaults.set(useRestoredPosition ? dockRestore.x : canvas.minX,forKey:"x")
        defaults.set(useRestoredPosition ? top-dockRestore.y-size : canvas.minY,forKey:"y")
    }
    func applyPreferredDisplay() {
        if windowDock != nil {refreshWindowDock(); return}
        guard let display = preferredScreen else {return}
        resetDragTilt()
        dock = nil; dockProgress = 0; dockAnimating = false; motion = nil
        notchDockArea = nil; notchDockDisplayID = nil; view.refreshFrame()
        move(constrained(position,screen:display)); activityOrigin = position; savePosition()
        landAfterThrow()
    }
    func showSettings(section:SettingsSection? = nil,groupTitle:String? = nil) {
        if composerVisible { onDismissComposer() }
        settingsOpen = true; interaction(); settings.show(section:section,groupTitle:groupTitle)
    }
    func showDiagnostics() {
        if !preferences.bool("showDiagnostics") {preferences.set(true,for:"showDiagnostics")}
        diagnostics?.show(takeFocus:true)
    }
    func updateDiagnostics() {
        if preferences.bool("showDiagnostics") {
            if diagnostics == nil {
                diagnostics = DiagnosticsPanel(pet:self)
                diagnostics?.show(takeFocus:false)
            }
        } else {
            let old = diagnostics; diagnostics = nil
            old?.shutdown()
        }
    }
    func settingsChanged(_ keys: [String]) {
        if keys.allSatisfy({$0 == PetPreferences.tokenDetailsKey || $0 == TokenCountFormat.key || $0 == GitStatusStyle.key}),!keys.isEmpty {return}
        if (keys.contains("dragTiltEnabled") && !preferences.bool("dragTiltEnabled")) ||
            (keys.contains("dragTiltIntensity") && preferences.number("dragTiltIntensity") == 0) ||
            (keys.contains("bubbleMotion") && !preferences.bool("bubbleMotion")) {resetDragTilt(); landAfterThrow()}
        if keys.contains("windowDockEnabled"), !preferences.bool("windowDockEnabled") {dropFromWindow()}
        if keys.contains("bubbleMotion"), !preferences.bool("bubbleMotion") {finishWindowDockMotion()}
        if !Set(keys).isDisjoint(with:["animationSmoothTransition","bubbleMotion"]),
           !preferences.bool("animationSmoothTransition") || !preferences.bool("bubbleMotion") {view.cancelTransition()}
        if keys == ["animationSmoothTransition"] {return}
        if keys == ["dragTiltEnabled"] || keys == ["dragTiltIntensity"] || keys == ["windowDockEnabled"] || keys == [WindowDockModifier.key] {return}
        if keys.contains("notchExposurePercent") {
            if dock == "notch" {view.refreshFrame(); placeBubble()}
            if keys.count == 1 {return}
        }
        if keys.contains("sideExposurePercent") {
            if dock == "left" || dock == "right" {view.refreshFrame(); placeBubble()}
            if windowDock?.edge == .left || windowDock?.edge == .right {refreshWindowDock(recalculateOutline:true)}
            if keys.count == 1 {return}
        }
        if keys.contains("sideDockEnabled"),!preferences.bool("sideDockEnabled"),dock == "left" || dock == "right" {undock()}
        if keys.contains("notchDockEnabled"),!preferences.bool("notchDockEnabled"),dock == "notch" {undock()}
        if keys.contains("petShadow") {
            window.hasShadow = preferences.bool("petShadow")
            view.refreshFrame()
            if keys.count == 1 {return}
        }
        if keys.contains("appearanceMode") {AppAppearance.apply()}
        // 连续拖动材质滑块只刷新气泡背景，不触发任务同步与桌宠调度。
        if !keys.isEmpty && Set(keys).isSubset(of:["bubbleMaterial","glassFollowsSystem","glassOpacity","bubbleMotion"]) {return}
        if keys.contains("approvalButtonOrder") {_ = bubble.refreshAppearance(); placeBubble()}
        if keys.contains("showDiagnostics") { updateDiagnostics() }
        if keys.contains("diagnosticsPinned") { diagnostics?.updatePin() }
        if !Set(keys).isDisjoint(with:["animationOpeningCache","preloadWholeAnimation"]) { updateOpeningCachePreference() }
        if !Set(keys).isDisjoint(with:["animationQuality","animationFPSLimit","playbackSpeed","animationSpeeds","animationEdgeCleanup"]) { decoder.discardOpeningCache() }
        let fixedQualityChanged = keys.contains("animationQuality") && !preferences.usesAutomaticAnimationResolution
        if fixedQualityChanged || !Set(keys).isDisjoint(with:["animationBufferFrames","preloadWholeAnimation","animationEdgeCleanup"]) {
            view.cancelTransition()
            let clip = current, playbackMode = mode
            let heldFrame = currentFrame, sourceFPS = animation?.fps ?? 24
            animation = heldFrame.map { Animation([$0],fps:sourceFPS) }; frameIndex = 0
            decoder.configure(bufferCapacity:preferences.animationBufferFrames,preloadWhole:preferences.bool("preloadWholeAnimation"))
            play(clip, playbackMode)
        }
        if keys.contains("animationFPSLimit") { configureAnimationTimer() }
        if keys.contains("playbackSpeed") || keys.contains("animationSpeeds") {
            let reference = pauseTime ?? now, elapsed = max(0,(reference-began)*playbackRate)
            playbackRate = preferences.speed(current.id); began = reference-elapsed/playbackRate
            configureAnimationTimer()
        }
        if !Set(keys).isDisjoint(with:["animationFPSLimit","animationQuality","animationBufferFrames","preloadWholeAnimation","playbackSpeed","animationSpeeds","animationOpeningCache","animationEdgeCleanup"]) {
            playbackScheduling = PlaybackSchedulingStatistics(); diagnostics?.resetStatistics()
        }
        if !Set(keys).isDisjoint(with:["petPercent","bubblePercent","messageFontSize","bubbleAspectEnabled","bubbleAspectRatio"]) {
            resize(Int(preferences.number("petPercent")),Int(preferences.number("bubblePercent")))
            if !bubble.refreshAppearance(),settingsOpen {showSizePreview()}
        }
        if !Set(keys).isDisjoint(with:["progressToastEnabled","showThinkingProgress","showToolProgress","hideToolFailures"]) {progressBubble.hide()}
        if keys.contains("progressToastSeconds") {progressBubble.refreshDuration()}
        if !Set(keys).isDisjoint(with:["petPercent","bubblePercent","messageFontSize","bubbleAspectEnabled","bubbleAspectRatio","bubbleMaterial","glassFollowsSystem","glassOpacity","bubbleMotion","appearanceMode"]) {_ = progressBubble.refreshAppearance(); placeBubble()}
        if keys.contains("preferredDisplay") {applyPreferredDisplay()}
        if keys.contains("rememberPosition") {savePosition()}
        if !Set(keys).isDisjoint(with:["autoMove","movementRange","quietCompanion","quietSchedule","quietStart","quietEnd"]) {
            if motion != nil {idle()}; activityOrigin = position
        }
        if keys.contains("accentStyle") || keys.contains("accentRGB") {NotificationCenter.default.post(name:AppAccent.didChange,object:nil)}
        if !preferences.allows(bubble.purpose) {bubble.hide()}; if !preferences.allows(.progress) {progressBubble.hide()}
        if !Set(keys).isDisjoint(with:["bubbleCardLimit","recentTaskCount","showTaskOverview"]) {bubble.refreshCardPreferences()}
        if !Set(keys).isDisjoint(with:["interactionSeconds","progressSeconds","resultSeconds","quotaSeconds","autoReadTime"]) {bubble.refreshDuration()}
        interaction(); checkDesktop(); refreshMenu(); onPreferencesChanged()
    }
    func refreshMenu() { status.menu = PetMenu.make(for:self,includeVisibility:true,random:{ [weak self] in self?.randomAnimation() }) }
    func menuNeedsUpdate(_ menu:NSMenu) {
        PetMenu.refreshVisibility(in:menu,pet:self)
    }
    func menuWillOpen(_ menu: NSMenu) {
        gestures.cancelRecall(); menuOpen = true; interaction()
        if motion != nil || isThrowing {throwMotion = nil; idle()}
    }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; interaction() }
    deinit {
        stopWindowDockMonitoring()
        motionDisplayLink?.invalidate()
        if let visibleActivity {ProcessInfo.processInfo.endActivity(visibleActivity)}
    }
    func prepareForExit(_ completion: @escaping () -> Void) {
        exiting = true
        landAfterThrow()
        stopWindowDockMonitoring()
        updateVisibleActivity()
        view.cancelTransition()
        timer?.invalidate(); timer = nil; desktopTimer?.invalidate(); desktopTimer = nil
        motionDisplayLink?.invalidate(); motionDisplayLink = nil
        decoder.cancel(); startup?.orderOut(nil)
        window.ignoresMouseEvents = true
        bubble.hide(); progressBubble.hide(); onVisibility(false)
        visibilityFade.hide(completion:completion)
    }
    func close() {
        stopWindowDockMonitoring()
        if let visibleActivity {ProcessInfo.processInfo.endActivity(visibleActivity); self.visibleActivity = nil}
        diagnostics?.stop(); visibilityFade.stop(); view.releaseDisplayTracking()
        motionDisplayLink?.invalidate(); motionDisplayLink = nil
        startup?.orderOut(nil); timer?.invalidate(); desktopTimer?.invalidate(); gestures.cancelRecall(); decoder.close(); bubble.hide(); progressBubble.hide(); settings.window.orderOut(nil)
        for token in observationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
        NSStatusBar.system.removeStatusItem(status); window.orderOut(nil)
    }
}

extension CGRect { var center: CGPoint { CGPoint(x:midX,y:midY) } }
