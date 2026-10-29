import AppKit

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
final class SpriteView: NSView {
    weak var pet: PetController?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {true}
    override func draw(_ dirtyRect: NSRect) {
        guard let pet, let frame = pet.currentFrame else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.transformStruct = NSAffineTransformStruct(m11: pet.transform.a, m12: pet.transform.b, m21: pet.transform.c, m22: pet.transform.d, tX: pet.transform.tx, tY: pet.transform.ty)
        transform.concat()
        NSImage(cgImage: frame.image, size: NSSize(width: 512, height: 512)).draw(in: pet.drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) { pet?.mouseDown(event) }
    override func mouseDragged(with event: NSEvent) { pet?.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { pet?.mouseUp(event) }
    override func rightMouseDown(with event: NSEvent) { pet?.rightMouseDown(event) }
    override func rightMouseUp(with event: NSEvent) {}
}

final class PetController: NSObject, NSMenuDelegate {
    let catalog: Catalog
    let window: PetWindow
    let view = SpriteView()
    let decoder = Decoder()
    let bubble = Bubble()
    let settings: SettingsPanel
    let preferences: PetPreferences
    let defaults: UserDefaults
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var onComposer: () -> Void = {}
    var onHistory: (String?) -> Void = { _ in }
    var onQuota: () -> Void = {}
    var onQuit: () -> Void = {}
    var onVisibility: (Bool) -> Void = { _ in }
    var onGeometry: () -> Void = {}
    var onPreferencesChanged: () -> Void = {}
    var onAutostart: () -> Void = {}
    var syncStatus: () -> String = { "正在准备读取本机 Codex 的任务记录。" }
    var current: Clip
    var animation: Animation?
    var frameIndex = 0
    var playbackRate = 1.0
    var activityOrigin = CGPoint.zero
    var wasQuiet = false
    var currentFrame: Frame? { animation?.frames[frameIndex] }
    var mode = "idle"
    var began = ProcessInfo.processInfo.systemUptime
    var loading = false
    private var warmed = false
    var pending: (Clip, String)?
    var startup: NSPanel?
    var baseBounds: CGRect?
    var dock: String?
    var dockProgress = 0.0, dockFrom = 0.0, dockTarget = 0.0, dockBegan = 0.0
    var dockAnimating = false
    var dockRestore = CGPoint.zero
    var motion: (CGPoint, CGPoint)?
    var activeTasks = Set<String>()
    var quotaActive = false
    var manualHidden = false, fullscreenHidden = false, sleeping = false
    var menuOpen = false, settingsOpen = false
    var composerVisible = false
    var pauseTime: Double?
    var press: CGPoint?, pressOrigin = CGPoint.zero
    var dragged = false, dragFromDock = false
    var dockRecallAt: Double?
    var dockDoubleClick = false
    var leftDoubleClick = false
    var timer: Timer?, desktopTimer: Timer?
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
    var size: Double { window.frame.width }
    var screen: NSScreen { window.screen ?? NSScreen.main ?? NSScreen.screens[0] }
    var hidden: Bool { manualHidden || fullscreenHidden || sleeping }
    // 控制器采用与作者 Qt 相同的全局向下坐标；只在窗口边界转换成 AppKit 坐标。
    var top: Double { NSScreen.screens[0].frame.maxY }
    var position: CGPoint { CGPoint(x: window.frame.minX, y: top - window.frame.maxY) }
    func area(_ screen: NSScreen) -> CGRect { let r = screen.visibleFrame; return CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
    func move(_ p: CGPoint) { window.setFrameOrigin(CGPoint(x: p.x, y: top - p.y - size)); placeBubble(); onGeometry() }
    func constrained(_ p: CGPoint, screen: NSScreen) -> CGPoint {
        let a = area(screen); return CGPoint(x: max(a.minX,min(p.x,a.maxX-size)), y: max(a.minY,min(p.y,a.maxY-size)))
    }
    var drawRect: CGRect {
        let scale = current.renderScale ?? 1, offset = current.renderOffset ?? [0,0]
        return CGRect(x: (size - size * scale)/2 + size * offset[0], y: size - size * scale + size * offset[1], width: size * scale, height: size * scale)
    }
    var transform: CGAffineTransform {
        guard let dock, let baseBounds else { return .identity }
        let center = CGPoint(x: size/2, y: size/2)
        let rotation = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: (dock == "left" ? 1 : -1) * .pi/4 * dockProgress).translatedBy(x: -center.x, y: -center.y)
        let reference = CGRect(x: baseBounds.minX * size/512, y: baseBounds.minY * size/512, width: baseBounds.width * size/512, height: baseBounds.height * size/512)
        let bounds = reference.applying(rotation), exposure = 1 - 0.45 * dockProgress
        let dx = dock == "left" ? exposure * bounds.width - bounds.maxX : size - exposure * bounds.width - bounds.minX
        return rotation.concatenating(CGAffineTransform(translationX: dx * dockProgress, y: 0))
    }
    init(catalog: Catalog, defaults: UserDefaults = .standard) {
        self.defaults = defaults; self.catalog = catalog; current = catalog.idle
        preferences = defaults === UserDefaults.standard ? .shared : PetPreferences(defaults:defaults)
        settings = SettingsPanel(preferences:preferences,catalog:catalog)
        window = PetWindow(contentRect: NSRect(x: 0,y: 0,width: 256,height: 256), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        // 脚本与打包版共用初始化；首次将两个 100% 写入偏好，之后保留用户选择。
        for key in ["petPercent","bubblePercent"] where defaults.object(forKey:key) == nil {
            defaults.set(100,forKey:key)
        }
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        window.contentView = view; view.pet = self
        window.setContentSize(NSSize(width: 256 * Double(petPercent)/100, height: 256 * Double(petPercent)/100))
        let target = NSScreen.screens.first {PetPreferences.displayID($0) == preferences.string("preferredDisplay")} ?? screen
        let a = target.visibleFrame
        let remember = preferences.bool("rememberPosition")
        window.setFrameOrigin(CGPoint(x: remember ? defaults.object(forKey:"x") as? Double ?? a.maxX-size-24 : a.maxX-size-24, y: remember ? defaults.object(forKey:"y") as? Double ?? a.minY+24 : a.minY+24))
        move(constrained(position, screen: target)); activityOrigin = position
        manualHidden = !preferences.bool("showOnLaunch"); playbackRate = preferences.speed(current.id); wasQuiet = preferences.isQuiet(); nextLeisure = now + preferences.activityInterval
        bubble.preferences = preferences
        sound = NSSound(contentsOf: Paths.resources.appendingPathComponent("sounds/click.wav"), byReference: true)
        status.button?.title = PetPreferences.productName; status.button?.toolTip = preferences.appName; refreshMenu()
        bubble.onClose = { [weak self] in self?.quotaActive = false }
        settings.onPreview = { [weak self] clip in self?.preview(clip) }
        settings.onMessagePreview = { [weak self] purpose in self?.showSizePreview(purpose:purpose) }
        observationTokens.append(NotificationCenter.default.addObserver(forName:PetPreferences.didChange,object:preferences,queue:.main) { [weak self] note in self?.settingsChanged(note.userInfo?["keys"] as? [String] ?? []) })
        settings.onClose = { [weak self] in
            guard let self else { return }; self.settingsOpen = false
            if self.bubble.kind == "preview" { self.bubble.hide() }; self.interaction()
        }
        timer = Timer(timeInterval: 1/30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        desktopTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkDesktop() }
        let center = NSWorkspace.shared.notificationCenter
        observationTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleeping = true; self?.applyVisibility() })
        observationTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.sleeping = false; self.motion = nil; self.interaction(); self.keepOnScreen(); self.checkDesktop(); self.applyVisibility(); self.idle()
        })
        observationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.keepOnScreen(); self?.applyPreferredDisplay() })
        let startup = NSPanel(contentRect:NSRect(x:0,y:0,width:440,height:108),styleMask:[.titled],backing:.buffered,defer:false)
        startup.title = preferences.appName; startup.isReleasedWhenClosed = false; startup.hidesOnDeactivate = false
        let heading = label(preferences.fixedText("主人，等我整理好裙摆和小翅膀，马上就来…")); heading.frame = NSRect(x:24,y:60,width:392,height:24)
        let progress = NSProgressIndicator(frame:NSRect(x:24,y:28,width:392,height:16)); progress.isIndeterminate = true; progress.style = .bar; progress.startAnimation(nil)
        startup.contentView?.addSubview(heading); startup.contentView?.addSubview(progress)
        startup.center(); if !hidden {startup.orderFrontRegardless()}; self.startup = startup
        if !hidden {window.orderFrontRegardless()}; play(catalog.idle, "idle")
    }
    func interaction() { lastInteraction = now; nextLeisure = now + preferences.activityInterval; nextMovement = false }
    func soundOnce() { if soundEnabled && !preferences.isQuiet() { sound?.play() } }
    func play(_ clip: Clip, _ mode: String) {
        if self.motion != nil { movementReady = now + 10 }; motion = nil
        loading = true
        if bubble.kind == "interaction" { bubble.hide() }
        if mode == "interaction", let line = preferences.line(for:clip) { say(line, kind:"interaction",personalizeTitle:false) }
        if current.id == clip.id, let animation, animation.frames.count > 1 {
            decoder.cancel(); loading = false; self.mode = mode; playbackRate = preferences.speed(clip.id); began = now; frameIndex = 0
            return
        }
        decoder.load(clip, first: { [weak self] frame in
            guard let self else { return }
            if self.animation == nil {
                self.current = clip; self.mode = mode; self.playbackRate = self.preferences.speed(clip.id); self.began = self.now
                self.animation = Animation([frame]); self.frameIndex = 0; self.view.needsDisplay = true
            }
            if clip.id == self.catalog.idle.id && self.baseBounds == nil { self.baseBounds = frame.bounds }
        }, completion: { [weak self] result in
            guard let self else { return }; self.loading = false
            switch result {
            case .success(let animation):
                self.startup?.orderOut(nil); self.startup = nil
                // 像素、时间轴和清单校准一起切换，不能用新动作倍率绘制旧帧。
                self.current = clip; self.mode = mode; self.playbackRate = self.preferences.speed(clip.id)
                self.animation = animation; self.frameIndex = 0; self.began = self.now
                self.pauseTime = self.hidden || self.press != nil && !self.dragged ? self.now : nil
                self.view.needsDisplay = true
                if clip.id == self.catalog.idle.id {
                    let icon = NSImage(cgImage: animation.frames[0].image, size: NSSize(width: 128,height: 128))
                    NSApp.applicationIconImage = AppIcons.application ?? icon
                    if self.status.button?.image == nil {self.status.button?.image = AppIcons.petSilhouette(animation.frames[0])}
                    self.status.button?.title = ""
                }
                if self.mode == "move" { self.planMotion(manual: true) }
                if !self.warmed {
                    self.warmed = true
                    self.decoder.warm([self.catalog.dragAnimation,self.catalog.landingAnimation]+Array(self.catalog.idles.dropFirst()))
                }
            case .failure(let error):
                self.startup?.orderOut(nil); self.startup = nil
                self.began = self.now
                self.bubble.showFailure(AppFailure.animation(error),scale:Double(self.bubblePercent)/100,
                    retry:{ [weak self] in self?.play(clip,mode) })
                self.placeBubble()

            }
        })
    }
    func idle() {
        if dock != nil {play(preferences.choose(catalog.idles,previous:current.id) ?? catalog.idle,"idle"); return}
        if !activeTasks.isEmpty {
            let pool = Double.random(in:0..<1) < 0.35 ? catalog.work.filter {$0.id != "work01"} : catalog.idles
            play(preferences.choose(pool,previous:current.id) ?? preferences.choose(catalog.idles,previous:current.id) ?? catalog.idle,"working")
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
        play(preferences.choose(catalog.idles,previous:current.id) ?? catalog.idle,"idle")
    }
    func leisureAllowed() -> Bool { !hidden && dock == nil && activeTasks.isEmpty && !quotaActive && press == nil && !menuOpen && !settingsOpen && now >= max(nextLeisure,lastInteraction+preferences.activityInterval) }
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
    func tick() {
        // 吸边单击沿用作者的 250ms 判定；到期仅召回，不执行普通单击动作。
        if let deadline = dockRecallAt, now >= deadline, press == nil {
            dockRecallAt = nil; undock()
        }
        if dockAnimating {
            let t = min(1, (now-dockBegan)/0.3)
            // 作者展开公式：起始进度 × (1 - 时间进度)^3，连续衰减到零。
            dockProgress = dockTarget == 1 ? dockFrom + (1-dockFrom)*(1-pow(1-t,3)) : dockFrom*pow(1-t,3)
            if t >= 1 { dockAnimating = false; dockProgress = dockTarget
                if dockTarget == 0 { dock = nil; move(constrained(dockRestore,screen:screen)); play(catalog.idle,"idle")
                    savePosition()
                    if let pending { self.pending = nil; play(pending.0,pending.1) }
                }
            }
        }
        if !hidden && (press == nil || dragged), let animation {
            let elapsed = (now-began)*playbackRate, duration = current.durationMs/1000
            if let (origin,target) = motion {
                let start = current.moveStartMs ?? 0, stop = current.moveStopMs ?? current.durationMs
                let f = max(0,min(1,(elapsed*1000-start)/(stop-start)))
                move(CGPoint(x:origin.x+(target.x-origin.x)*f,y:origin.y+(target.y-origin.y)*f))
            }
            if elapsed >= duration && !loading {
                if motion != nil {movementReady = now + 10; motion = nil}
                if mode == "drag" { began = now }
                else if mode == "opening" && !activeTasks.isEmpty, let clip = preferences.choose(catalog.work.filter({$0.id != "work01"}),previous:current.id) { play(clip,"working") }
                else { idle() }
            } else {
                let playback = max(0,elapsed).truncatingRemainder(dividingBy:duration)
                frameIndex = min(animation.frames.count-1,Int(playback/duration*Double(animation.frames.count)))
            }
        }
        if !hidden {
            view.needsDisplay = true; placeBubble()
            if press != nil { window.ignoresMouseEvents = false }
            else {
                let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation),from:nil).applying(transform.inverted())
                let rect = drawRect
                let hit = rect.contains(point) && (currentFrame?.alpha(x:Int((point.x-rect.minX)/rect.width*512),y:Int((point.y-rect.minY)/rect.height*512)) ?? 0) > 0
                window.ignoresMouseEvents = !hit
            }
        }
    }
    func mouseDown(_ event: NSEvent) {
        // 只有吸边状态保留召回判定期；普通点击仍立即响应。
        leftDoubleClick = dock == nil && event.clickCount > 1 && event.clickCount % 2 == 0
        dockDoubleClick = dock != nil && dockRecallAt.map {now <= $0} == true
        dockRecallAt = nil
        interaction()
        if motion != nil { idle() }
        press = NSEvent.mouseLocation; pressOrigin = position; dragged = false; dragFromDock = dock != nil
        pauseTime = now
        if dockDoubleClick {performGesture(preferences.string("doubleClickAction"))}
    }
    func mouseDragged(_ event: NSEvent) {
        guard let press else {return}
        let p = NSEvent.mouseLocation, delta = CGPoint(x:p.x-press.x,y:press.y-p.y)
        if !dragged && abs(delta.x)+abs(delta.y) >= 8 {
            leftDoubleClick = false; dockDoubleClick = false
            dragged = true; pauseTime = nil
            if dragFromDock {
                // 吸边拖动与召回一致，不切换到跟随鼠标的拖拽动作。
                undock(); return
            }
            pending = nil; bubble.hide(); play(catalog.dragAnimation,"drag")
        }
        if dragged && !dragFromDock {
            let screen = NSScreen.screens.first(where:{$0.frame.contains(p)}) ?? self.screen
            move(constrained(CGPoint(x:pressOrigin.x+delta.x,y:pressOrigin.y+delta.y),screen:screen))
            if !loading, let animation {frameIndex = Int(((now-began)*playbackRate).truncatingRemainder(dividingBy:current.durationMs/1000)/(current.durationMs/1000)*Double(animation.frames.count)); view.needsDisplay = true}
        }
    }
    func mouseUp(_ event: NSEvent) {
        guard press != nil else {return}; press = nil; interaction()
        if !dragged, let pauseTime {began += now-max(pauseTime,began)}; pauseTime = nil
        if dragged {
            dragged = false
            if !dragFromDock && !snap() {play(catalog.landingAnimation,"landing")}
        } else if dockDoubleClick {
            dockDoubleClick = false
        } else if dragFromDock {
            if dock != nil {dockRecallAt = now + 0.25}
        } else if leftDoubleClick {
            leftDoubleClick = false; performGesture(preferences.string("doubleClickAction"))
        } else {performGesture(preferences.string("singleClickAction"))}
        activityOrigin = position; savePosition()
    }
    func snap() -> Bool {
        guard !composerVisible else { return false }
        let a = area(screen), p = position, left = abs(p.x-a.minX), right = abs(a.maxX-p.x-size)
        guard min(left,right) <= 24 else { return false }
        dockRestore = p; dock = left <= right ? "left" : "right"
        move(CGPoint(x:dock == "left" ? a.minX : a.maxX-size,y:p.y))
        dockProgress = 0; dockFrom = 0; dockTarget = 1; dockBegan = now; dockAnimating = true
        bubble.hide(); play(catalog.idle,"idle"); return true
    }
    func undock() { dockRecallAt = nil; guard dock != nil else { return }; dockFrom = dockProgress; dockTarget = 0; dockBegan = now; dockAnimating = true; interaction() }
    func preview(_ clip: Clip) {
        interaction(); soundOnce(); manualHidden = false; applyVisibility()
        let mode = catalog.movementAnimations.contains(where:{$0.id == clip.id}) ? "move" : "interaction"
        if dock != nil { pending = (clip,mode); undock() } else { play(clip,mode) }
    }
    func say(_ title: String, body: String = "", kind: String = "interaction", thread: String? = nil, followsText: Bool = true, resetText: Bool = false, purpose: MessagePurpose? = nil, personalizeTitle: Bool = true) {
        let purpose = purpose ?? (kind.hasPrefix("quota") ? .quota : kind == "task" ? .progress : .interaction)
        guard !hidden && preferences.allows(purpose) else { return }
        if !kind.hasPrefix("quota") && bubble.kind.hasPrefix("quota") { quotaActive = false }
        bubble.onDetails = { [weak self] in self?.onHistory(thread) }
        bubble.show(title:personalizeTitle ? preferences.fixedText(title) : title,body:body,kind:kind,scale:Double(bubblePercent)/100,seconds:kind == "quotaLoading" ? 0 : preferences.duration(purpose,text:body),details:thread != nil,followsText:followsText,resetText:resetText)
        bubble.purpose = purpose; bubble.relatedConversation = thread
        placeBubble()
    }
    var stableLocalBounds: CGRect {
        let b = baseBounds ?? CGRect(x:128,y:64,width:256,height:448)
        return CGRect(x:b.minX*size/512,y:b.minY*size/512,width:b.width*size/512,height:b.height*size/512)
    }
    var visiblePetFrame: CGRect {
        let local = stableLocalBounds.applying(transform).intersection(view.bounds)
        return local.isNull ? window.frame : window.convertToScreen(view.convert(local,to:nil))
    }
    func placeBubble() {
        guard bubble.visible else{return}
        bubble.place(near:visiblePetFrame,screen:screen,dock:dock)
    }
    func resize(_ p: Int, _ b: Int) {
        let old = window.frame, bubbleChanged = bubblePercent != b
        petPercent = p; bubblePercent = b; interaction()
        let side = 256 * Double(p)/100
        window.setFrame(NSRect(x:old.midX-side/2,y:old.minY,width:side,height:side),display:true)
        keepOnScreen()
        activityOrigin = position; savePosition()
        if bubbleChanged || bubble.kind == "preview" {showSizePreview()}
    }
    func showSizePreview(purpose: MessagePurpose = .preview) {
        guard !hidden else{return}
        quotaActive = false
        // 作者 size_preview 本身是空白框；按用户要求，改用 chat_ui.py 的普通对话文案填充预览。
        bubble.onDetails = { [weak self] in self?.onHistory(nil) }
        bubble.show(title:preferences.petName,body:preferences.template(preferences.string("greetingTemplate")),kind:"preview",scale:Double(bubblePercent)/100,seconds:preferences.duration(purpose,text:preferences.template(preferences.string("greetingTemplate"))),details:true)
        bubble.purpose = purpose
        placeBubble()
    }
    func keepOnScreen() { motion = nil; move(constrained(position,screen:screen)); if dock != nil { let a = area(screen); move(CGPoint(x:dock == "left" ? a.minX : a.maxX-size,y:position.y)) } }
    func taskStarted(_ key: String) { let first = activeTasks.isEmpty; activeTasks.insert(key); interaction()
        if preferences.bool("taskOpening") && first && !hidden && dock == nil && press == nil, let clip = catalog.work.first(where:{$0.id == "work01"}) { play(clip,"opening") }
    }
    func taskEnded(_ key: String, status: String) {
        activeTasks.remove(key); interaction()
        if status == "completed" { soundOnce() }
        guard !hidden && dock == nil && press == nil else { return }
        if status == "completed" && preferences.bool("taskCelebration"), let clip = catalog.variants.first(where:{$0.id == "18"}) { play(clip,"celebration") }
        else if activeTasks.isEmpty { idle() }
    }
    var fullCandidate = false, fullCandidateSince = 0.0
    func checkDesktop() {
        let quiet = preferences.isQuiet()
        if quiet != wasQuiet {wasQuiet = quiet; interaction(); if quiet && motion != nil {idle()}; if !preferences.allows(bubble.purpose) {bubble.hide()}}
        var full = false
        if autoFullscreen, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] {
            full = windows.contains { item in
                guard (item[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier, (item[kCGWindowLayer as String] as? Int) == 0,
                      let b = item[kCGWindowBounds as String] as? [String:Any], let rect = CGRect(dictionaryRepresentation:b as CFDictionary) else { return false }
                return NSScreen.screens.contains { screen in
                    let a = screen.frame, r = CGRect(x:a.minX,y:top-a.maxY,width:a.width,height:a.height)
                    return rect.minX <= r.minX+2 && rect.minY <= r.minY+2 && rect.maxX >= r.maxX-2 && rect.maxY >= r.maxY-2
                }
            }
        }
        if full != fullCandidate { fullCandidate = full; fullCandidateSince = now }
        if fullscreenHidden != full && now-fullCandidateSince >= (full ? 0.25 : 0.75) { fullscreenHidden = full; applyVisibility() }
    }
    func applyVisibility() {
        if hidden { dockRecallAt = nil; dockDoubleClick = false; leftDoubleClick = false; press = nil; dragged = false; if pauseTime == nil { pauseTime = now }; window.orderOut(nil); bubble.hide(); quotaActive = false; onVisibility(false) }
        else { if let pauseTime { began += now-pauseTime }; pauseTime = nil; window.orderFrontRegardless(); interaction() }
        refreshMenu()
    }
    func reveal() { manualHidden = false; keepOnScreen(); applyVisibility() }
    func performGesture(_ action: String) {
        switch action {
        case "chat": soundOnce(); onComposer()
        case "quota": soundOnce(); onQuota()
        case "history": soundOnce(); onHistory(nil)
        case "random": if let clip = preferences.choose(catalog.variants+catalog.work,previous:current.id) {preview(clip)}
        default: break
        }
    }
    func rightMouseDown(_ event: NSEvent) {
        dockRecallAt = nil
        interaction()
        if motion != nil {idle()}
        if event.clickCount > 1 && event.clickCount % 2 == 0 {
            performGesture(preferences.string("rightDoubleClickAction"))
        } else {showContextMenu(firstClick:event)}
    }
    func showContextMenu(firstClick: NSEvent) {
        let menu = makeMenu(); menu.update()
        let cursor = NSEvent.mouseLocation
        let target = NSScreen.screens.first(where:{$0.frame.contains(cursor)}) ?? screen
        let frame = MenuPlacement.frame(size:menu.size,cursor:cursor,screen:target.visibleFrame,pet:visiblePetFrame)
        // NSMenu 的嵌套事件循环不会经过本地事件监视器。
        // 只在本次双击识别时间内读取按键状态，不延迟菜单显示，不申请全局输入权限。
        var wasPressed = true, doubleClicked = false
        let deadline = firstClick.timestamp + NSEvent.doubleClickInterval
        func captureSecondPress() {
            guard ProcessInfo.processInfo.systemUptime <= deadline else {return}
            let pressed = NSEvent.pressedMouseButtons & 2 != 0
            let point = NSEvent.mouseLocation
            if pressed && !wasPressed && hypot(point.x-cursor.x,point.y-cursor.y) <= 8 {
                doubleClicked = true; menu.cancelTrackingWithoutAnimation()
            }
            wasPressed = pressed
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
        if doubleClicked {performGesture(preferences.string("rightDoubleClickAction"))}
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(MenuAction(manualHidden ? "显示桌宠" : "隐藏桌宠") { [weak self] in guard let self else{return}; self.manualHidden.toggle(); self.applyVisibility() })
        menu.addItem(MenuAction("打开对话",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.onComposer() })
        menu.addItem(MenuAction("历史对话",symbol:"clock") { [weak self] in self?.onHistory(nil) })
        menu.addItem(MenuAction("查询额度") { [weak self] in self?.soundOnce(); self?.onQuota() })
        menu.addItem(.separator())
        for (name,clips) in [("待机动作",catalog.idles+catalog.extras),("互动动作",catalog.variants),("工作动作",catalog.work),("移动动作",catalog.movementAnimations)] {
            let item = NSMenuItem(title:name,action:nil,keyEquivalent:""); let sub = NSMenu()
            for clip in clips { sub.addItem(MenuAction(clip.title) { [weak self] in self?.preview(clip) }) }; item.submenu = sub; menu.addItem(item)
        }
        menu.addItem(MenuAction("自主移动",checked:autoMove) { [weak self] in guard let self else{return}; self.preferences.set(!self.autoMove,for:"autoMove") })
        menu.addItem(MenuAction("播放音效",checked:soundEnabled) { [weak self] in guard let self else {return}; self.preferences.set(!self.soundEnabled,for:"soundEnabled") })
        menu.addItem(MenuAction("任务气泡提醒",checked:taskBubbles) { [weak self] in guard let self else{return}; self.preferences.set(!self.taskBubbles,for:"taskBubbles") })
        menu.addItem(MenuAction("全屏时自动隐藏",checked:autoFullscreen) { [weak self] in guard let self else {return}; self.preferences.set(!self.autoFullscreen,for:"autoFullscreen") })
        menu.addItem(MenuAction("随 Codex 启动设置…") { [weak self] in self?.onAutostart() })
        menu.addItem(MenuAction("任务同步状态…") { [weak self] in guard let self else{return}; let a = NSAlert(); a.messageText = "Codex 任务同步状态"; a.informativeText = self.syncStatus(); a.icon = NSImage(systemSymbolName:"arrow.triangle.2.circlepath",accessibilityDescription:"任务同步"); a.addButton(withTitle:"知道了"); a.applyAccent(); a.runModal() })
        menu.addItem(MenuAction("设置…",symbol:"gearshape") { [weak self] in self?.showSettings() })
        menu.addItem(.separator())
        menu.addItem(MenuAction("关于"+preferences.appName+"…") {AppIcons.showAbout()})
        menu.addItem(MenuAction("退出"+preferences.appName,symbol:"rectangle.portrait.and.arrow.right") { [weak self] in self?.onQuit() })
        return menu
    }
    func savePosition() {
        guard preferences.bool("rememberPosition") else {return}
        defaults.set(window.frame.minX,forKey:"x"); defaults.set(window.frame.minY,forKey:"y")
    }
    func applyPreferredDisplay() {
        guard let display = NSScreen.screens.first(where:{PetPreferences.displayID($0) == preferences.string("preferredDisplay")}) else {return}
        dock = nil; dockProgress = 0; dockAnimating = false; motion = nil
        move(constrained(position,screen:display)); activityOrigin = position; savePosition()
    }
    func showSettings() { settingsOpen = true; interaction(); settings.show()}
    func settingsChanged(_ keys: [String]) {
        if keys.contains("playbackSpeed") || keys.contains("animationSpeeds") {
            let reference = pauseTime ?? now, elapsed = max(0,(reference-began)*playbackRate)
            playbackRate = preferences.speed(current.id); began = reference-elapsed/playbackRate
        }
        if !Set(keys).isDisjoint(with:["petPercent","bubblePercent","messageFontSize"]) {
            resize(Int(preferences.number("petPercent")),Int(preferences.number("bubblePercent"))); if settingsOpen {showSizePreview()}
        }
        if keys.contains("preferredDisplay") {applyPreferredDisplay()}
        if keys.contains("rememberPosition") {savePosition()}
        if !Set(keys).isDisjoint(with:["autoMove","movementRange","quietCompanion","quietSchedule","quietStart","quietEnd"]) {
            if motion != nil {idle()}; activityOrigin = position
        }
        if keys.contains("appearanceMode") {AppAppearance.apply()}
        if keys.contains("accentStyle") || keys.contains("accentRGB") {NotificationCenter.default.post(name:AppAccent.didChange,object:nil)}
        if !preferences.allows(bubble.purpose) {bubble.hide()}
        if keys.contains("typingEffect") && !preferences.bool("typingEffect") {bubble.finishTyping()}
        if !Set(keys).isDisjoint(with:["interactionSeconds","progressSeconds","resultSeconds","quotaSeconds","autoReadTime"]) {bubble.refreshDuration()}
        interaction(); checkDesktop(); refreshMenu(); onPreferencesChanged()
    }
    func refreshMenu() { status.menu = makeMenu() }
    func menuWillOpen(_ menu: NSMenu) { dockRecallAt = nil; menuOpen = true; interaction(); if motion != nil {idle()} }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; interaction() }
    func close() {
        startup?.orderOut(nil); timer?.invalidate(); desktopTimer?.invalidate(); dockRecallAt = nil; decoder.close(); bubble.hide(); settings.window.orderOut(nil)
        for token in observationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
        NSStatusBar.system.removeStatusItem(status); window.orderOut(nil)
    }
}

extension CGRect { var center: CGPoint { CGPoint(x:midX,y:midY) } }
