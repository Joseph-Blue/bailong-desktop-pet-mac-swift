import AppKit

final class MenuAction: NSMenuItem {
    let callback: () -> Void
    init(_ title: String, checked: Bool? = nil, _ callback: @escaping () -> Void) {
        self.callback = callback; super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self; if let checked { state = checked ? .on : .off }
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func run() { callback() }
}
final class SpriteView: NSView {
    weak var pet: PetController?
    override var isFlipped: Bool { true }
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
    override func rightMouseDown(with event: NSEvent) { if let pet { NSMenu.popUpContextMenu(pet.makeMenu(), with: event, for: self) } }
}

final class PetController: NSObject, NSMenuDelegate {
    let catalog: Catalog
    let window: PetWindow
    let view = SpriteView()
    let decoder = Decoder()
    let bubble = Bubble()
    let settings = SettingsPanel()
    let defaults = UserDefaults.standard
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var onComposer: () -> Void = {}
    var onHistory: (String?) -> Void = { _ in }
    var onQuota: () -> Void = {}
    var onQuit: () -> Void = {}
    var onVisibility: (Bool) -> Void = { _ in }
    var onGeometry: () -> Void = {}
    var onAutostart: () -> Void = {}
    var syncStatus: () -> String = { "等待观察本机任务" }
    var current: Clip
    var animation: Animation?
    var frameIndex = 0
    var currentFrame: Frame? { animation?.frames[frameIndex] }
    var mode = "idle"
    var began = ProcessInfo.processInfo.systemUptime
    var loading = false
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
    var clickTimer: Timer?
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
    init(catalog: Catalog) {
        self.catalog = catalog; current = catalog.idle
        window = PetWindow(contentRect: NSRect(x: 0,y: 0,width: 256,height: 256), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        window.contentView = view; view.pet = self
        window.setContentSize(NSSize(width: 256 * Double(petPercent)/100, height: 256 * Double(petPercent)/100))
        let a = screen.visibleFrame
        window.setFrameOrigin(CGPoint(x: defaults.object(forKey: "x") as? Double ?? a.maxX-size-24, y: defaults.object(forKey: "y") as? Double ?? a.minY+24))
        move(constrained(position, screen: screen))
        sound = NSSound(contentsOf: Paths.resources.appendingPathComponent("sounds/click.wav"), byReference: true)
        status.button?.title = "白龙"; refreshMenu()
        bubble.onClose = { [weak self] in self?.quotaActive = false }
        settings.onChange = { [weak self] p,b in self?.resize(p,b) }
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
        observationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.keepOnScreen() })
        let startup = NSPanel(contentRect:NSRect(x:0,y:0,width:340,height:120),styleMask:[.titled],backing:.buffered,defer:false)
        startup.title = "白龙桌宠"; startup.isReleasedWhenClosed = false
        let heading = label("正在准备透明动画…"); heading.frame = NSRect(x:24,y:70,width:290,height:24)
        let progress = NSProgressIndicator(frame:NSRect(x:24,y:40,width:290,height:18)); progress.isIndeterminate = true; progress.style = .bar; progress.startAnimation(nil)
        startup.contentView?.addSubview(heading); startup.contentView?.addSubview(progress)
        startup.center(); startup.orderFrontRegardless(); self.startup = startup
        window.orderFrontRegardless(); play(catalog.idle, "idle")
    }
    func interaction() { lastInteraction = now; nextLeisure = now + 15; nextMovement = false }
    func soundOnce() { if soundEnabled { sound?.play() } }
    func play(_ clip: Clip, _ mode: String) {
        if self.motion != nil { movementReady = now + 10 }; motion = nil
        current = clip; self.mode = mode; loading = true
        if bubble.kind == "interaction" { bubble.hide() }
        if mode == "interaction", let line = clip.line { say(line, kind: "interaction") }
        decoder.load(clip, first: { [weak self] frame in
            guard let self else { return }
            if self.animation == nil { self.animation = Animation([frame]); self.frameIndex = 0; self.view.needsDisplay = true }
            if clip.id == self.catalog.idle.id && self.baseBounds == nil { self.baseBounds = frame.bounds }
        }, completion: { [weak self] result in
            guard let self else { return }; self.loading = false
            switch result {
            case .success(let animation):
                self.startup?.orderOut(nil); self.startup = nil
                self.animation = animation; self.frameIndex = 0; self.began = self.now
                self.pauseTime = self.hidden ? self.now : nil; self.view.needsDisplay = true
                if clip.id == self.catalog.idle.id {
                    let icon = NSImage(cgImage: animation.frames[0].image, size: NSSize(width: 128,height: 128))
                    NSApp.applicationIconImage = icon
                    let mini = icon.copy() as! NSImage; mini.size = NSSize(width: 22,height: 22)
                    self.status.button?.image = mini; self.status.button?.title = ""
                }
                if self.mode == "move" { self.planMotion(manual: true) }
            case .failure(let error):
                self.startup?.orderOut(nil); self.startup = nil
                let alert = NSAlert(); alert.messageText = "动画读取失败"; alert.informativeText = error.localizedDescription
                alert.addButton(withTitle:"重试"); alert.addButton(withTitle:"关闭提示")
                if alert.runModal() == .alertFirstButtonReturn { self.play(clip,mode) }
            }
        })
    }
    func idle() {
        if dock != nil { play(Double.random(in: 0..<1) < 0.7 ? catalog.idles[0] : catalog.idles[1], "idle"); return }
        if !activeTasks.isEmpty {
            let pool = Double.random(in: 0..<1) < 0.35 ? catalog.work.filter { $0.id != "work01" } : catalog.idles
            if let choice = pool.filter({ $0.id != current.id }).randomElement() { play(choice, "working") }
            return
        }
        if leisureAllowed() {
            if nextMovement && autoMove && now >= movementReady {
                for clip in catalog.movementAnimations.shuffled() {
                    if route(clip) != nil { nextMovement = false; nextLeisure = now + 15; play(clip,"move"); return }
                }
            }
            if let clip = catalog.extras.randomElement() { nextMovement = autoMove; nextLeisure = now + 15; play(clip,"extra"); return }
        }
        play(Double.random(in: 0..<1) < 0.8 ? catalog.idles[0] : catalog.idles[1], "idle")
    }
    func leisureAllowed() -> Bool { !hidden && dock == nil && activeTasks.isEmpty && !quotaActive && press == nil && clickTimer == nil && !menuOpen && !settingsOpen && now >= max(nextLeisure,lastInteraction+15) }
    func route(_ clip: Clip) -> CGPoint? {
        let a = area(screen)
        return movementTarget(origin: position, bounds: CGRect(x:a.minX,y:a.minY,width:max(0,a.width-size),height:max(0,a.height-size)), size: size, clip: clip)
    }
    func planMotion(manual: Bool) { motion = (position, route(current) ?? position) }
    func tick() {
        if dockAnimating {
            let t = min(1, (now-dockBegan)/0.3)
            let eased = dockTarget == 1 ? 1-pow(1-t,3) : pow(1-t,3)
            dockProgress = dockTarget == 1 ? dockFrom + (1-dockFrom)*eased : dockFrom*eased
            if t >= 1 { dockAnimating = false; dockProgress = dockTarget
                if dockTarget == 0 { dock = nil; move(constrained(dockRestore,screen:screen)); play(catalog.idle,"idle")
                    if let pending { self.pending = nil; play(pending.0,pending.1) }
                }
            }
        }
        if !hidden && !loading && (press == nil || dragged), let animation {
            let elapsed = now-began, duration = current.durationMs/1000
            if let (origin,target) = motion {
                let start = current.moveStartMs ?? 0, stop = current.moveStopMs ?? current.durationMs
                let f = max(0,min(1,(elapsed*1000-start)/(stop-start)))
                move(CGPoint(x:origin.x+(target.x-origin.x)*f,y:origin.y+(target.y-origin.y)*f))
            }
            if elapsed >= duration {
                if motion != nil {movementReady = now + 10; motion = nil}
                if mode == "drag" { began = now }
                else if mode == "opening" && !activeTasks.isEmpty, let clip = catalog.work.filter({$0.id != "work01"}).randomElement() { play(clip,"working") }
                else { idle() }
            } else { frameIndex = min(animation.frames.count-1,Int(elapsed/duration*Double(animation.frames.count))) }
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
        clickTimer?.invalidate(); clickTimer = nil; interaction()
        if motion != nil { idle() }
        press = NSEvent.mouseLocation; pressOrigin = position; dragged = false; dragFromDock = dock != nil
        pauseTime = now
    }
    func mouseDragged(_ event: NSEvent) {
        guard let press else { return }
        let p = NSEvent.mouseLocation, delta = CGPoint(x:p.x-press.x,y:press.y-p.y)
        if !dragged && abs(delta.x)+abs(delta.y) >= 8 {
            dragged = true; dock = nil; dockAnimating = false; dockProgress = 0
            bubble.hide(); play(catalog.dragAnimation,"drag")
        }
        if dragged {
            let screen = NSScreen.screens.first(where:{$0.frame.contains(p)}) ?? self.screen
            move(constrained(CGPoint(x:pressOrigin.x+delta.x,y:pressOrigin.y+delta.y),screen:screen))
            if !loading, let animation { frameIndex = Int((now-began).truncatingRemainder(dividingBy:current.durationMs/1000)/(current.durationMs/1000)*Double(animation.frames.count)); view.needsDisplay = true }
        }
    }
    func mouseUp(_ event: NSEvent) {
        guard press != nil else { return }; press = nil; interaction()
        if !dragged, let pauseTime { began += now-max(pauseTime,began) }; pauseTime = nil
        if dragged { dragged = false
            if !snap() { if dragFromDock { idle() } else { play(catalog.landingAnimation,"landing") } }
        } else if event.clickCount >= 2 { soundOnce(); onQuota() }
        else {
            clickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                guard let self else { return }; self.clickTimer = nil
                if self.dock != nil { self.undock() }
                else if let clip = (self.catalog.variants+self.catalog.work).filter({$0.id != self.current.id}).randomElement() { self.preview(clip) }
            }
        }
        defaults.set(window.frame.minX,forKey:"x"); defaults.set(window.frame.minY,forKey:"y")
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
    func undock() { guard dock != nil else { return }; dockFrom = dockProgress; dockTarget = 0; dockBegan = now; dockAnimating = true; interaction() }
    func preview(_ clip: Clip) {
        interaction(); soundOnce(); manualHidden = false; applyVisibility()
        let mode = catalog.movementAnimations.contains(where:{$0.id == clip.id}) ? "move" : "interaction"
        if dock != nil { pending = (clip,mode); undock() } else { play(clip,mode) }
    }
    func say(_ title: String, body: String = "", kind: String = "interaction", seconds: Double = 4, thread: String? = nil) {
        guard !hidden && (kind != "task" || taskBubbles) else { return }
        if kind != "quota" && bubble.kind == "quota" { quotaActive = false }
        bubble.onDetails = { [weak self] in self?.onHistory(thread) }
        bubble.show(title:title,body:body,kind:kind,scale:Double(bubblePercent)/100,seconds:seconds,details:thread != nil)
        placeBubble()
    }
    func placeBubble() {
        guard bubble.visible else{return}
        var visible = window.frame
        if let frame = currentFrame {
            let r = drawRect, b = frame.bounds
            let local = CGRect(x:r.minX+b.minX*r.width/512,y:r.minY+b.minY*r.height/512,width:b.width*r.width/512,height:b.height*r.height/512).applying(transform).intersection(view.bounds)
            if !local.isNull {visible = window.convertToScreen(view.convert(local,to:nil))}
        }
        bubble.place(near:visible,screen:screen,dock:dock)
    }
    func resize(_ p: Int, _ b: Int) {
        let old = window.frame; petPercent = p; bubblePercent = b; interaction()
        let side = 256 * Double(p)/100
        window.setFrame(NSRect(x:old.midX-side/2,y:old.minY,width:side,height:side),display:true)
        keepOnScreen(); say("气泡尺寸预览",body:"拖动滑块或输入百分比，立即调整大小。",kind:"preview",seconds:0)
    }
    func keepOnScreen() { motion = nil; move(constrained(position,screen:screen)); if dock != nil { let a = area(screen); move(CGPoint(x:dock == "left" ? a.minX : a.maxX-size,y:position.y)) } }
    func taskStarted(_ key: String) { let first = activeTasks.isEmpty; activeTasks.insert(key); interaction()
        if first && !hidden && dock == nil && press == nil, let clip = catalog.work.first(where:{$0.id == "work01"}) { play(clip,"opening") }
    }
    func taskEnded(_ key: String, status: String) {
        activeTasks.remove(key); interaction()
        if status == "completed" { soundOnce() }
        guard !hidden && dock == nil && press == nil else { return }
        if status == "completed", let clip = catalog.variants.first(where:{$0.id == "18"}) { play(clip,"celebration") }
        else if activeTasks.isEmpty { idle() }
    }
    var fullCandidate = false, fullCandidateSince = 0.0
    func checkDesktop() {
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
        if hidden { if pauseTime == nil { pauseTime = now }; window.orderOut(nil); bubble.hide(); quotaActive = false; onVisibility(false) }
        else { if let pauseTime { began += now-pauseTime }; pauseTime = nil; window.orderFrontRegardless(); interaction() }
        refreshMenu()
    }
    func reveal() { manualHidden = false; keepOnScreen(); applyVisibility() }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(MenuAction(manualHidden ? "显示桌宠" : "隐藏桌宠") { [weak self] in guard let self else{return}; self.manualHidden.toggle(); self.applyVisibility() })
        menu.addItem(MenuAction("打开对话") { [weak self] in self?.onComposer() })
        menu.addItem(MenuAction("历史对话") { [weak self] in self?.onHistory(nil) })
        menu.addItem(MenuAction("查询额度") { [weak self] in self?.soundOnce(); self?.onQuota() })
        menu.addItem(.separator())
        for (name,clips) in [("待机动作",catalog.idles+catalog.extras),("互动动作",catalog.variants),("工作动作",catalog.work),("移动动作",catalog.movementAnimations)] {
            let item = NSMenuItem(title:name,action:nil,keyEquivalent:""); let sub = NSMenu()
            for clip in clips { sub.addItem(MenuAction(clip.title) { [weak self] in self?.preview(clip) }) }; item.submenu = sub; menu.addItem(item)
        }
        menu.addItem(MenuAction("桌宠与气泡大小…") { [weak self] in guard let self else{return}; self.settingsOpen = true; self.settings.show(self.petPercent,self.bubblePercent) })
        menu.addItem(MenuAction("自主移动",checked:autoMove) { [weak self] in guard let self else{return}; self.autoMove.toggle(); self.interaction(); if self.motion != nil {self.idle()}; self.refreshMenu() })
        menu.addItem(MenuAction("播放音效",checked:soundEnabled) { [weak self] in self?.soundEnabled.toggle(); self?.refreshMenu() })
        menu.addItem(MenuAction("任务气泡提醒",checked:taskBubbles) { [weak self] in guard let self else{return}; self.taskBubbles.toggle(); if !self.taskBubbles && self.bubble.kind == "task" {self.bubble.hide()}; self.refreshMenu() })
        menu.addItem(MenuAction("全屏时自动隐藏",checked:autoFullscreen) { [weak self] in self?.autoFullscreen.toggle(); self?.checkDesktop(); self?.refreshMenu() })
        menu.addItem(MenuAction("随 Codex 启动设置…") { [weak self] in self?.onAutostart() })
        menu.addItem(MenuAction("任务同步状态…") { [weak self] in guard let self else{return}; let a = NSAlert(); a.messageText = "任务同步"; a.informativeText = self.syncStatus(); a.runModal() })
        menu.addItem(.separator())
        menu.addItem(MenuAction("关于白龙桌宠…") { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"白龙桌宠",.applicationVersion:Paths.version,.credits:NSAttributedString(string:"Swift + AppKit · 原作 jingh12312-rgb\n本地开发版本，Apple Silicon")]) })
        menu.addItem(MenuAction("退出白龙桌宠") { [weak self] in self?.onQuit() })
        return menu
    }
    func refreshMenu() { status.menu = makeMenu() }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; interaction() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; interaction() }
    func close() {
        startup?.orderOut(nil); timer?.invalidate(); desktopTimer?.invalidate(); clickTimer?.invalidate(); decoder.cancel(); bubble.hide(); settings.window.orderOut(nil)
        for token in observationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
        NSStatusBar.system.removeStatusItem(status); window.orderOut(nil)
    }
}
