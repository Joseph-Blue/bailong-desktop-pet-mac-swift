import AppKit
import Darwin
import Metal

struct PlaybackSchedulingStatistics {
    private let beganAt = ProcessInfo.processInfo.systemUptime
    private(set) var callbacks = 0
    private(set) var overdueFrames = 0
    private(set) var longestDelay = 0.0
    private var totalDelay = 0.0
    var averageDelay: Double? { callbacks > 0 ? totalDelay / Double(callbacks) : nil }
    var callbackRate: Double? {
        let elapsed = ProcessInfo.processInfo.systemUptime - beganAt
        return elapsed > 0 ? Double(callbacks)/elapsed : nil
    }
    mutating func record(deadline: Double, actual: Double, frameInterval: Double) {
        let delay = max(0,actual-deadline)
        callbacks += 1; totalDelay += delay; longestDelay = max(longestDelay,delay)
        if delay >= frameInterval { overdueFrames += 1 }
    }
}

// Only collects while the developer window is enabled. Frame changes are counted
// when SpriteView updates layer contents; this is not screen presentation timing.
struct PlaybackStatistics {
    private(set) var total = 0
    private var intervalFrames = 0
    private var intervalDraws = 0
    private var lastImage: ObjectIdentifier?
    private var lastTime: Double
    private var lastFrameChange: Double?
    private(set) var longestFrameHold = 0.0
    private(set) var high: Double?
    private(set) var low: Double?
    init(time: Double) { lastTime = time }
    mutating func record(image: ObjectIdentifier) {
        intervalDraws += 1
        if image != lastImage {
            let now = ProcessInfo.processInfo.systemUptime
            if let lastFrameChange { longestFrameHold = max(longestFrameHold, now - lastFrameChange) }
            lastFrameChange = now
            total += 1; intervalFrames += 1; lastImage = image
        }
    }
    mutating func pausePresentationClock() { lastFrameChange = nil; lastImage = nil }
    mutating func sample(time: Double) -> (fps: Double, draws: Double) {
        let elapsed = max(0.001, time - lastTime)
        let fps = Double(intervalFrames) / elapsed
        let draws = Double(intervalDraws) / elapsed
        if let lastFrameChange { longestFrameHold = max(longestFrameHold, time - lastFrameChange) }
        high = max(high ?? fps, fps); low = min(low ?? fps, fps)
        intervalFrames = 0; intervalDraws = 0; lastTime = time
        return (fps, draws)
    }
}

private struct ProcessStatistics {
    var cpuSeconds: Double?
    var footprint: UInt64?
    var compressed: UInt64?
    var swapins: UInt64?
    var memoryError: String?
    static func read() -> Self {
        var result = Self()
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            result.cpuSeconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        var memory = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: memory) / MemoryLayout<integer_t>.size)
        let memoryStatus = withUnsafeMutablePointer(to: &memory) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if memoryStatus == KERN_SUCCESS {
            result.footprint = memory.phys_footprint; result.compressed = memory.compressed
            let swapinsEnd = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_swapins)! + MemoryLayout<Int64>.size
            if Int(count) * MemoryLayout<integer_t>.size >= swapinsEnd, memory.ledger_swapins >= 0 {
                result.swapins = UInt64(memory.ledger_swapins)
            } else { result.memoryError = L10n.text(.diagnostics,"diagnostics.read.text") }
        } else { result.memoryError = L10n.format(.diagnostics,"diagnostics.read.text.2",String(describing:memoryStatus)) }
        return result
    }
    static func systemSwapText() -> String {
        var swap = xsw_usage()
        var size = MemoryLayout.size(ofValue: swap)
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else {
            return L10n.format(.diagnostics,"diagnostics.systemSwapText.text",String(describing:errno))
        }
        return memoryText(swap.xsu_used)
    }
}

private func memoryText(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}

private enum DeviceIdentity {
    static func systemString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
    static let text: String = {
        #if arch(arm64)
        let architecture = "arm64 / Apple Silicon"
        #elseif arch(x86_64)
        let architecture = L10n.text(.diagnostics,"diagnostics.architecture")
        #else
        let architecture = L10n.text(.diagnostics,"diagnostics.architecture.2")
        #endif
        let info = ProcessInfo.processInfo
        let gpu = MTLCreateSystemDefaultDevice()
        let commit = Paths.localBuildCommit.map { " · \($0.prefix(8))" } ?? ""
        return L10n.format(.diagnostics,"diagnostics.systemString.text",String(describing:Paths.version),String(describing:commit),String(describing:architecture),String(describing:info.processName),String(describing:info.processIdentifier),String(describing:systemString("machdep.cpu.brand_string") ?? L10n.text(.diagnostics,"diagnostics.systemString.text.2")),String(describing:systemString("hw.machine") ?? L10n.text(.diagnostics,"diagnostics.systemString.text.3")),String(describing:info.processorCount),String(describing:gpu?.name ?? L10n.text(.diagnostics,"diagnostics.systemString.text.4")),String(describing:gpu?.architecture.name ?? L10n.text(.diagnostics,"diagnostics.systemString.text.3")),String(describing:info.operatingSystemVersionString))
    }()
}

final class DiagnosticsPanel: NSObject, NSWindowDelegate {
    private static let underflowTitle = L10n.text(.diagnostics,"diagnostics.underflowTitle")

    private struct Reading {
        var fps: Double?
        var draws: Double?
        var cpu: Double?
        var gpu: Double?
    }

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 376, height: 210),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    private weak var pet: PetController?
    private let pinSwitch = AccentSwitch()
    private var closing = false
    private let fpsValue = NSTextField(labelWithString: "—")
    private let cpuValue = NSTextField(labelWithString: "—")
    private let ramValue = NSTextField(labelWithString: "—")
    private let gpuValue = NSTextField(labelWithString: "—")
    private let underflowValue = NSTextField(labelWithString: "—")
    private var timer: Timer?
    private var frames = PlaybackStatistics(time: ProcessInfo.processInfo.systemUptime)
    private var previous = ProcessStatistics()
    private var reading = Reading()
    private var previousGPU: GPUStatistics.Snapshot?
    private var gpuStatus = L10n.text(.diagnostics,"diagnostics.gpuStatus")
    private var swapinRate: Double?
    private var sampledAt = ProcessInfo.processInfo.systemUptime
    init(pet: PetController) {
        self.pet = pet
        super.init()
        window.title = L10n.text(.diagnostics,"diagnostics.title"); window.isReleasedWhenClosed = false; window.delegate = self
        window.hidesOnDeactivate = false
        updatePin()
        window.isExcludedFromWindowsMenu = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let container = NSView()
        window.contentView = container
        let rows = [
            (L10n.text(.diagnostics,"diagnostics.text"), fpsValue), (L10n.text(.diagnostics,"diagnostics.text.2"), cpuValue), (L10n.text(.diagnostics,"diagnostics.text.3"), ramValue),
            (L10n.text(.diagnostics,"diagnostics.text.4"), gpuValue), (Self.underflowTitle, underflowValue)
        ]
        let grid = NSGridView(views: rows.map { name, value -> [NSView] in
            let title = NSTextField(labelWithString: name)
            title.textColor = .secondaryLabelColor
            value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            value.alignment = .right
            value.setAccessibilityLabel(name)
            guard value === underflowValue else { return [title, value] }

            let titleWithHelp = title.withHoverHelpIcon(L10n.text(.diagnostics,"diagnostics.titleWithHelp"))
            return [titleWithHelp, value]
        })
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 1).width = 124
        grid.columnSpacing = 20
        grid.rowSpacing = 0
        for row in 0..<grid.numberOfRows { grid.row(at: row).height = 27 }
        container.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = ActionButton(L10n.text(.diagnostics,"diagnostics.closeButton")) { [weak self] in self?.window.performClose(nil) }
        let copyButton = ActionButton(L10n.text(.diagnostics,"diagnostics.copyButton")) {}
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L10n.text(.diagnostics,"diagnostics.accessibilityDescription"))
        copyButton.imagePosition = .imageLeading; copyButton.emphasize()
        CopyFeedback.attach(to:copyButton,didCopy:{ [weak window] text in
            if let window {Self.showCopiedInformation(text,for:window)}
        }) { [weak self] in self?.copyInformation() }
        let actions = NSStackView(views: [closeButton, copyButton]); actions.orientation = .horizontal; actions.spacing = 8
        container.addSubview(actions); actions.translatesAutoresizingMaskIntoConstraints = false
        let pinIcon = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: L10n.text(.diagnostics,"diagnostics.pinIcon"))!)
        pinIcon.contentTintColor = .secondaryLabelColor
        pinIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        pinIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let pinLabel = NSTextField(labelWithString: L10n.text(.diagnostics,"diagnostics.pinLabel")); pinLabel.font = .systemFont(ofSize: 12)
        pinSwitch.controlSize = .small; pinSwitch.target = self; pinSwitch.action = #selector(togglePin)
        pinSwitch.setAccessibilityLabel(L10n.text(.diagnostics,"diagnostics.pinLabel"))
        let pinControls = NSStackView(views: [pinIcon, pinLabel, pinSwitch])
        pinControls.orientation = .horizontal; pinControls.alignment = .centerY; pinControls.spacing = 6
        container.addSubview(pinControls); pinControls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            actions.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            actions.centerYAnchor.constraint(equalTo: container.bottomAnchor, constant: -23),
            pinControls.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            pinControls.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            pinControls.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -12)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(keepOnScreen), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    func updatePin() {
        let pinned = pet?.preferences.bool("diagnosticsPinned") ?? true
        pinSwitch.state = pinned ? .on : .off
        window.level = pinned ? .floating : .normal
    }
    @objc private func togglePin() {
        pet?.preferences.set(pinSwitch.state == .on, for: "diagnosticsPinned")
    }
    func show(takeFocus: Bool = true) {
        if timer == nil {
            beginSampling(); placeTopLeft()
        }
        if takeFocus {
            InterfaceWindows.shared.focus(window)
        } else {
            InterfaceWindows.shared.opened(window)
            if !window.isVisible && !window.isMiniaturized { window.orderFront(nil) }
        }
    }
    private func beginSampling() {
        timer?.invalidate()
        sampledAt = ProcessInfo.processInfo.systemUptime; frames = PlaybackStatistics(time:sampledAt)
        pet?.playbackScheduling = PlaybackSchedulingStatistics()
        previous = ProcessStatistics.read(); swapinRate = nil; reading = Reading()
        switch GPUStatistics.read() {
        case .success(let snapshot): previousGPU = snapshot; gpuStatus = L10n.text(.diagnostics,"diagnostics.gpuStatus")
        case .failure(let error): previousGPU = nil; gpuStatus = error.message
        }
        updateMetrics()
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.sample() }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func resetStatistics() { if timer != nil { beginSampling() } }
    func stop() {
        timer?.invalidate(); timer = nil; previousGPU = nil
        if let sheet = window.attachedSheet {window.endSheet(sheet)}
        window.orderOut(nil); InterfaceWindows.shared.closed(window)
    }
    func shutdown() {
        stop()
        if !closing { window.close() }
    }
    func windowWillClose(_ notification: Notification) {
        closing = true; stop()
        if let pet, pet.preferences.bool("showDiagnostics") { pet.preferences.set(false, for: "showDiagnostics") }
    }
    func record(_ image: CGImage) {
        guard timer != nil else { return }
        frames.record(image: ObjectIdentifier(image))
    }
    func pausePresentationClock() { frames.pausePresentationClock() }
    private func placeTopLeft() {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        window.setFrameTopLeftPoint(NSPoint(x: area.minX + 16, y: area.maxY - 16))
    }
    @objc private func keepOnScreen() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { placeTopLeft() }
    }
    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - sampledAt
        let current = ProcessStatistics.read(), sample = frames.sample(time: now)
        var cpu: Double?, gpu: Double?
        if let a = current.cpuSeconds, let b = previous.cpuSeconds, a >= b { cpu = (a - b) / elapsed * 100 }
        switch GPUStatistics.read() {
        case .success(let snapshot):
            if let last = previousGPU, last.coalition == snapshot.coalition, snapshot.nanoseconds >= last.nanoseconds {
                gpu = Double(snapshot.nanoseconds - last.nanoseconds) / 1_000_000_000 / elapsed * 100
                gpuStatus = L10n.format(.diagnostics,"diagnostics.sample.text",String(describing:snapshot.coalition))
            } else { gpuStatus = L10n.text(.diagnostics,"diagnostics.sample.text.2") }
            previousGPU = snapshot
        case .failure(let error): previousGPU = nil; gpuStatus = error.message
        }
        if let a = current.swapins, let b = previous.swapins, a >= b { swapinRate = Double(a - b) / elapsed }
        else { swapinRate = nil }
        sampledAt = now; previous = current
        reading = Reading(fps: sample.fps, draws: sample.draws, cpu: cpu, gpu: gpu)
        updateMetrics()
    }
    private var totalCPU: Double? {
        reading.cpu.map { $0 / Double(ProcessInfo.processInfo.processorCount) }
    }
    private func updateMetrics() {
        func update(_ field: NSTextField, _ value: String) {
            if field.stringValue != value { field.stringValue = value }
        }
        update(fpsValue, number(reading.fps))
        update(cpuValue, totalCPU.map { number($0) + "%" } ?? "—")
        update(ramValue, previous.footprint.map(memoryText) ?? L10n.text(.diagnostics,"diagnostics.systemString.text.4"))
        update(gpuValue, reading.gpu.map { String(format: "%.2f%%", $0) } ?? (previousGPU == nil ? L10n.text(.diagnostics,"diagnostics.systemString.text.4") : "—"))
        let underflows = pet?.animation?.stream?.statistics().underflows
        update(underflowValue, underflows.map { L10n.format(.diagnostics,"diagnostics.update.text",String(describing:$0)) } ?? "—")
    }
    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
    static func showCopiedInformation(_ text:String,for parent:NSWindow) {
        let alert = NSAlert()
        alert.messageText = L10n.text(.diagnostics,"diagnostics.showCopiedInformation.messageText")
        let symbol = NSImage(systemSymbolName:"chart.xyaxis.line",accessibilityDescription:L10n.text(.diagnostics,"diagnostics.title"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:36,weight:.semibold).applying(.init(paletteColors:[.white])))
        alert.icon = NSImage(size:NSSize(width:64,height:64),flipped:false) { rect in
            AppAccent.color.setFill()
            NSBezierPath(roundedRect:rect.insetBy(dx:2,dy:2),xRadius:14,yRadius:14).fill()
            if let symbol {
                let size = symbol.size
                symbol.draw(in:NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height))
            }
            return true
        }
        let scroll = GutterScrollView(frame:NSRect(x:0,y:0,width:450,height:230))
        let body = SelectableRichText(frame:.zero)
        body.attributedStringValue = NSAttributedString(string:text,attributes:[
            .font:NSFont.monospacedSystemFont(ofSize:12,weight:.regular),.foregroundColor:NSColor.labelColor
        ])
        body.setAccessibilityLabel(L10n.text(.diagnostics,"diagnostics.showCopiedInformation.text"))
        scroll.hasVerticalScroller = true
        scroll.documentView = body
        let box = MessageTextBoxSurface(scroll:scroll)
        alert.accessoryView = box
        alert.addButton(withTitle:L10n.text(.diagnostics,"diagnostics.showCopiedInformation.button"))
        alert.applyAccent()
        box.layoutSubtreeIfNeeded()
        let width = scroll.documentLayoutWidth
        let viewport = NSSize(width:width,height:scroll.contentSize.height)
        let documentHeight = max(viewport.height,body.height(for:width))
        body.setSelectedRange(NSRange(location:0,length:0))
        // AppKit 在 sheet 建立焦点时会居中正文的 frame。先用首屏范围接收焦点，
        // 再同步展开已排好的文档，手动滚动和文字选择继续由系统处理。
        body.frame = NSRect(origin:.zero,size:viewport)
        alert.beginSheetModal(for:parent)
        body.setFrameSize(NSSize(width:width,height:documentHeight))
    }
    private func copyInformation() -> String {
        guard let pet else { return window.title }
        let count = pet.animation?.frameCount ?? 0
        let index = pet.animation?.stream?.current?.index ?? pet.frameIndex
        let resolution = pet.currentFrame?.image.width ?? pet.animationResolution(for:pet.current)
        let automatic = pet.preferences.usesAutomaticAnimationResolution ? L10n.text(.diagnostics,"diagnostics.automatic") : ""
        let limit = pet.preferences.string("animationFPSLimit") == "full" ? L10n.text(.diagnostics,"diagnostics.limit") : pet.preferences.string("animationFPSLimit") + " FPS"
        let state = pet.hidden ? L10n.text(.diagnostics,"diagnostics.state") : pet.loading ? L10n.text(.diagnostics,"diagnostics.state.2") : L10n.text(.diagnostics,"diagnostics.state.3")
        let preloadEnabled = pet.preferences.bool("preloadWholeAnimation")
        var playback = L10n.format(.diagnostics,"diagnostics.playback",String(describing:preloadEnabled ? L10n.text(.diagnostics,"diagnostics.playback.2") : L10n.text(.diagnostics,"diagnostics.playback.3")),String(describing:pet.current.title),String(describing:state),String(describing:String(format: "%.2f", pet.playbackRate)),String(describing:automatic),String(describing:resolution),String(describing:resolution),String(describing:limit),String(describing:count == 0 ? 0 : index + 1),String(describing:count),String(describing:frames.total),String(describing:number(reading.draws)))
        func milliseconds(_ value: Double?) -> String { value.map { String(format:"%.1f ms",$0 * 1000) } ?? "—" }
        playback += L10n.format(.diagnostics,"diagnostics.milliseconds.text",String(describing:milliseconds(frames.longestFrameHold)))
        let scheduling = pet.playbackScheduling
        playback += L10n.format(.diagnostics,"diagnostics.milliseconds.text.2",String(describing:number(scheduling.callbackRate)),String(describing:milliseconds(scheduling.averageDelay)),String(describing:milliseconds(scheduling.longestDelay)),String(describing:scheduling.overdueFrames))
        if let timing = pet.animation?.loadTiming {
            playback += L10n.format(.diagnostics,"diagnostics.milliseconds.text.3",String(describing:milliseconds(timing.firstFrameAt - timing.requestedAt)),String(describing:milliseconds(timing.readyAt - timing.firstFrameAt)))
            playback += L10n.format(.diagnostics,"diagnostics.milliseconds.text.4",String(describing:milliseconds(timing.handedAt.map { $0 - timing.readyAt })),String(describing:milliseconds(timing.submittedAt.flatMap { displayed in timing.handedAt.map { displayed - $0 } })))
            playback += L10n.format(.diagnostics,"diagnostics.milliseconds.text.5",String(describing:milliseconds(timing.submittedAt.map { $0 - timing.requestedAt })))
        }
        let cache = pet.decoder.residentFrameStatistics(additionalImages: pet.view.transitionImage.map { [$0] } ?? [])
        var preloadText: String
        if preloadEnabled {
            if let progress = pet.decoder.preloadingStatistics() {
                let title = pet.catalog.all.first { $0.id == progress.id }?.title ?? progress.id
                preloadText = L10n.format(.diagnostics,"diagnostics.milliseconds.text.6",String(describing:title),String(describing:progress.frames),String(describing:progress.total))
            } else if pet.loading {
                preloadText = L10n.text(.diagnostics,"diagnostics.milliseconds.text.7")
            } else {
                preloadText = L10n.format(.diagnostics,"diagnostics.milliseconds.text.8",String(describing:pet.current.title),String(describing:count))
            }
        } else if let stream = pet.animation?.stream {
            let buffer = stream.statistics()
            preloadText = L10n.format(.diagnostics,"diagnostics.milliseconds.text.9",String(describing:buffer.buffered),String(describing:stream.capacity),String(describing:Self.underflowTitle),String(describing:buffer.underflows),String(describing:milliseconds(buffer.longestUnderflow)),String(describing:buffer.decoded),String(describing:buffer.converted),String(describing:buffer.skipped),String(describing:buffer.expired))
            if let startup = stream.startup {
                preloadText += L10n.format(.diagnostics,"diagnostics.milliseconds.text.10",String(describing:startup.frames),String(describing:milliseconds(startup.seconds)))
                if startup.reused > 0 {
                    let continuation = buffer.continued.map { $0 ? L10n.text(.diagnostics,"diagnostics.milliseconds.text.11") : L10n.text(.diagnostics,"diagnostics.milliseconds.text.12") } ?? L10n.text(.diagnostics,"diagnostics.milliseconds.text.13")
                    preloadText += L10n.format(.diagnostics,"diagnostics.milliseconds.text.14",String(describing:startup.reused),String(describing:continuation),String(describing:buffer.replayed))
                }
            }
        } else {
            preloadText = L10n.text(.diagnostics,"diagnostics.milliseconds.text.15")
        }
        if pet.preferences.bool("animationOpeningCache"), !preloadEnabled {
            preloadText += L10n.format(.diagnostics,"diagnostics.milliseconds.text.16",String(describing:memoryText(UInt64(cache.openingBytes))),String(describing:cache.openingClips),String(describing:cache.hits))
        }
        let transition = !pet.preferences.bool("animationSmoothTransition") ? L10n.text(.diagnostics,"diagnostics.closeButton") :
            (!pet.preferences.bool("bubbleMotion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) ? L10n.text(.diagnostics,"diagnostics.milliseconds.text.17") :
            pet.view.transitionImage == nil ? L10n.text(.diagnostics,"diagnostics.milliseconds.text.18") : L10n.text(.diagnostics,"diagnostics.milliseconds.text.19")
        preloadText += L10n.format(.diagnostics,"diagnostics.milliseconds.text.20",String(describing:transition),String(describing:pet.preferences.bool("animationEdgeCleanup") ? L10n.text(.diagnostics,"diagnostics.milliseconds.text.21") : L10n.text(.diagnostics,"diagnostics.closeButton")))
        let swapinText = previous.swapins.map { $0 > 0 ? L10n.format(.diagnostics,"diagnostics.milliseconds.text.22",String(describing:memoryText($0))) : L10n.text(.diagnostics,"diagnostics.milliseconds.text.23") }
            ?? previous.memoryError ?? L10n.text(.diagnostics,"diagnostics.systemString.text.4")
        let swapRateText = swapinRate.map { " · \(memoryText(UInt64($0.rounded())))/s" } ?? ""
        let resources = L10n.format(.diagnostics,"diagnostics.resources",String(describing:number(totalCPU)),String(describing:number(reading.cpu)))
            + L10n.format(.diagnostics,"diagnostics.milliseconds.text.24",String(describing:previous.footprint.map(memoryText) ?? previous.memoryError ?? L10n.text(.diagnostics,"diagnostics.systemString.text.4")))
            + L10n.format(.diagnostics,"diagnostics.milliseconds.text.25",String(describing:reading.gpu.map { String(format: "%.2f%%", $0) } ?? gpuStatus))
            + L10n.format(.diagnostics,"diagnostics.milliseconds.text.26",String(describing:previous.compressed.map(memoryText) ?? L10n.text(.diagnostics,"diagnostics.systemString.text.4")),String(describing:ProcessStatistics.systemSwapText()))
            + L10n.format(.diagnostics,"diagnostics.milliseconds.text.27",String(describing:swapinText),String(describing:swapRateText))
            + L10n.format(.diagnostics,"diagnostics.milliseconds.text.28",String(describing:memoryText(UInt64(cache.bytes))),String(describing:cache.frames),String(describing:cache.clips))
            + L10n.format(.diagnostics,"diagnostics.milliseconds.text.29",String(describing:preloadText))
        let connections = L10n.format(.diagnostics,"diagnostics.connections",String(describing:CodexConnection.desktopDiagnostics),String(describing:pet.syncDiagnostics()),String(describing:pet.cliDiagnostics()))
        let frameRates = L10n.format(.diagnostics,"diagnostics.frameRates",String(describing:number(reading.fps)),String(describing:number(frames.high)),String(describing:number(frames.low)))
        return [window.title, frameRates, playback, resources, DeviceIdentity.text, connections].joined(separator: "\n\n")
    }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
}
