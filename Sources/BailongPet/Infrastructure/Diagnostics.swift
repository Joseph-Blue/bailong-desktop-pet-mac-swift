import AppKit
import Darwin
import Metal

// Only collects while the developer window is enabled. Frame changes are counted
// after SpriteView.draw, not from the 30 Hz scheduling timer.
struct PlaybackStatistics {
    private(set) var total = 0
    private var intervalFrames = 0
    private var intervalDraws = 0
    private var lastImage: ObjectIdentifier?
    private var lastTime: Double
    private(set) var high: Double?
    private(set) var low: Double?
    init(time: Double) { lastTime = time }
    mutating func record(image: ObjectIdentifier) {
        intervalDraws += 1
        if image != lastImage { total += 1; intervalFrames += 1; lastImage = image }
    }
    mutating func sample(time: Double) -> (fps: Double, draws: Double) {
        let elapsed = max(0.001, time - lastTime)
        let fps = Double(intervalFrames) / elapsed
        let draws = Double(intervalDraws) / elapsed
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
    var systemSwapUsed: UInt64?
    var memoryError: String?
    var swapError: String?
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
            } else { result.memoryError = "系统未返回进程换入计数" }
        } else { result.memoryError = "task_info 错误 \(memoryStatus)" }
        var swap = xsw_usage(); var swapSize = MemoryLayout.size(ofValue: swap)
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { result.systemSwapUsed = swap.xsu_used }
        else { result.swapError = "vm.swapusage errno \(errno)" }
        return result
    }
}

private enum DeviceIdentity {
    static func systemString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
    static var text: String {
        #if arch(arm64)
        let architecture = "arm64 / Apple Silicon"
        #elseif arch(x86_64)
        let architecture = "x86_64 / Intel 指令集"
        #else
        let architecture = "未知编译架构"
        #endif
        let info = ProcessInfo.processInfo
        let gpu = MTLCreateSystemDefaultDevice()
        return "版本 \(Paths.version) · \(architecture)\n进程 \(info.processName) · PID \(info.processIdentifier)\nCPU \(systemString("machdep.cpu.brand_string") ?? "型号不可用") · \(systemString("hw.machine") ?? "架构不可用") · \(info.processorCount) 核\nGPU \(gpu?.name ?? "不可用") · \(gpu?.architecture.name ?? "架构不可用")\nmacOS \(info.operatingSystemVersionString)"
    }
}

private final class FPSGraph: NSView {
    var values = [Double]()
    func append(_ value: Double) {
        values.append(value); if values.count > 60 { values.removeFirst(values.count - 60) }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let plot = bounds.insetBy(dx: 12, dy: 18)
        let ceiling = max(30, ((values.max() ?? 0) / 10).rounded(.up) * 10)
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath()
        for step in 0...2 {
            let y = plot.minY + plot.height * Double(step) / 2
            grid.move(to: NSPoint(x: plot.minX, y: y)); grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        grid.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        "\(Int(ceiling)) FPS".draw(at: NSPoint(x: plot.minX, y: bounds.maxY - 15), withAttributes: attributes)
        "最近 60 次采样 · 每秒一次".draw(at: NSPoint(x: plot.minX, y: 2), withAttributes: attributes)
        guard !values.isEmpty else { return }
        let line = NSBezierPath(); line.lineWidth = 2
        for (index, value) in values.enumerated() {
            let point = NSPoint(x: plot.minX + plot.width * Double(index) / 59, y: plot.minY + plot.height * value / ceiling)
            if index == 0 { line.move(to: point) } else { line.line(to: point) }
        }
        AppAccent.color.setStroke(); line.stroke()
    }
}

final class DiagnosticsPanel: NSObject, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    private weak var pet: PetController?
    private let graph = FPSGraph()
    private let contentStack = NSStackView()
    private let viewport = NSScrollView()
    private let footerHeight = 46.0
    private let pinSwitch = AccentSwitch()
    private var fittingWindow = false
    private var closing = false
    private let identity = NSTextField(wrappingLabelWithString: DeviceIdentity.text)
    private let playback = NSTextField(wrappingLabelWithString: "等待采样…")
    private let resources = NSTextField(wrappingLabelWithString: "等待采样…")
    private let connections = NSTextField(wrappingLabelWithString: "")
    private let fpsValue = NSTextField(labelWithString: "—")
    private let highValue = NSTextField(labelWithString: "—")
    private let lowValue = NSTextField(labelWithString: "—")
    private var timer: Timer?
    private var frames = PlaybackStatistics(time: ProcessInfo.processInfo.systemUptime)
    private var previous = ProcessStatistics()
    private var previousGPU: GPUStatistics.Snapshot?
    private var gpuStatus = "等待采样"
    private var swapinRate: Double?
    private var sampledAt = ProcessInfo.processInfo.systemUptime
    init(pet: PetController) {
        self.pet = pet
        super.init()
        window.title = "应用性能信息统计"; window.isReleasedWhenClosed = false; window.delegate = self
        window.hidesOnDeactivate = false
        updatePin()
        window.isExcludedFromWindowsMenu = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = NSSize(width: 440, height: 360)
        viewport.hasVerticalScroller = true; viewport.autohidesScrollers = true; viewport.drawsBackground = false
        let container = NSView(); window.contentView = container
        container.addSubview(viewport); viewport.translatesAutoresizingMaskIntoConstraints = false
        let closeButton = ActionButton("关闭") { [weak self] in self?.window.performClose(nil) }
        let copyButton = ActionButton("拷贝信息") { [weak self] in self?.copyInformation() }
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "拷贝")
        copyButton.imagePosition = .imageLeading; copyButton.emphasize()
        let actions = NSStackView(views: [closeButton, copyButton]); actions.orientation = .horizontal; actions.spacing = 8
        container.addSubview(actions); actions.translatesAutoresizingMaskIntoConstraints = false
        let pinIcon = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "置顶")!)
        pinIcon.contentTintColor = .secondaryLabelColor
        pinIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        pinIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let pinLabel = NSTextField(labelWithString: "置顶显示"); pinLabel.font = .systemFont(ofSize: 12)
        pinSwitch.controlSize = .small; pinSwitch.target = self; pinSwitch.action = #selector(togglePin)
        pinSwitch.setAccessibilityLabel("置顶显示")
        let pinControls = NSStackView(views: [pinIcon, pinLabel, pinSwitch])
        pinControls.orientation = .horizontal; pinControls.alignment = .centerY; pinControls.spacing = 6
        container.addSubview(pinControls); pinControls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewport.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            viewport.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            viewport.topAnchor.constraint(equalTo: container.topAnchor),
            viewport.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -footerHeight),
            actions.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            actions.centerYAnchor.constraint(equalTo: container.bottomAnchor, constant: -footerHeight / 2),
            pinControls.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            pinControls.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            pinControls.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -12)
        ])
        let root = TopDownView(); viewport.documentView = root
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: viewport.contentView.leadingAnchor), root.topAnchor.constraint(equalTo: viewport.contentView.topAnchor), root.widthAnchor.constraint(equalTo: viewport.contentView.widthAnchor)])
        let stack = contentStack; stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)])
        for field in [identity, playback, resources, connections] {
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular); field.isSelectable = true
            field.setContentHuggingPriority(.required, for: .vertical)
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        let metrics = NSStackView(); metrics.orientation = .horizontal; metrics.distribution = .fillEqually; metrics.spacing = 12
        for (title, value, size, color) in [("FPS", fpsValue, 42.0, NSColor.labelColor), ("HI", highValue, 32.0, NSColor.systemGreen), ("LO", lowValue, 32.0, NSColor.systemOrange)] {
            let name = NSTextField(labelWithString: title); name.font = .systemFont(ofSize: 11, weight: .semibold); name.textColor = .secondaryLabelColor
            value.font = .monospacedDigitSystemFont(ofSize: size, weight: .bold); value.textColor = color; value.isSelectable = true
            value.setAccessibilityLabel(title)
            let column = NSStackView(views: [name, value]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 0
            metrics.addArrangedSubview(column)
        }
        graph.heightAnchor.constraint(equalToConstant: 90).isActive = true
        func add(_ view: NSView) {
            stack.addArrangedSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for view in [metrics, graph, playback] { add(view) }
        for view in [resources, identity, connections] {
            let separator = NSBox(); separator.boxType = .separator; add(separator); add(view)
        }
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
        NSApp.setActivationPolicy(.regular)
        if timer == nil {
            sampledAt = ProcessInfo.processInfo.systemUptime; frames = PlaybackStatistics(time: sampledAt)
            previous = ProcessStatistics.read(); swapinRate = nil; graph.values.removeAll(); graph.needsDisplay = true
            switch GPUStatistics.read() {
            case .success(let snapshot): previousGPU = snapshot; gpuStatus = "等待采样"
            case .failure(let error): previousGPU = nil; gpuStatus = error.message
            }
            placeTopLeft(); updateText(fps: nil, draws: nil, cpu: nil, gpu: nil, process: previous)
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.addWindowsItem(window, title: window.title, filename: false)
        if takeFocus { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { window.orderFront(nil) }
    }
    func stop() {
        timer?.invalidate(); timer = nil; previousGPU = nil
        window.orderOut(nil); NSApp.removeWindowsItem(window)
    }
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }
    func windowDidEndLiveResize(_ notification: Notification) { fitToContent() }
    private func fitToContent() {
        guard !fittingWindow, !window.inLiveResize, !window.isMiniaturized else { return }
        fittingWindow = true; defer { fittingWindow = false }
        window.contentView?.layoutSubtreeIfNeeded()
        let width = max(1, viewport.contentView.bounds.width - 24)
        for field in [identity, playback, resources, connections] {
            if field.preferredMaxLayoutWidth != width {
                field.preferredMaxLayoutWidth = width; field.invalidateIntrinsicContentSize()
            }
        }
        viewport.layoutSubtreeIfNeeded()
        let height = contentStack.fittingSize.height + 24 + footerHeight
        let screen = window.screen ?? NSScreen.screens.first
        let maxHeight = (screen?.visibleFrame.height ?? 800) - 32
        let target = min(maxHeight, window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: viewport.bounds.width, height: height)).height)
        if abs(window.frame.height - target) > 1 {
            let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - target, width: window.frame.width, height: target)
            window.setFrame(frame, display: true)
        }
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
    private func placeTopLeft() {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        if window.frame.height > area.height - 32 { window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: window.frame.width, height: area.height - 32), display: false) }
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
                gpuStatus = "应用组 \(snapshot.coalition)"
            } else { gpuStatus = "重新建立采样基线" }
            previousGPU = snapshot
        case .failure(let error): previousGPU = nil; gpuStatus = error.message
        }
        if let a = current.swapins, let b = previous.swapins, a >= b { swapinRate = Double(a - b) / elapsed }
        else { swapinRate = nil }
        graph.append(sample.fps)
        updateText(fps: sample.fps, draws: sample.draws, cpu: cpu, gpu: gpu, process: current)
        sampledAt = now; previous = current
    }
    private func updateText(fps: Double?, draws: Double?, cpu: Double?, gpu: Double?, process: ProcessStatistics) {
        guard let pet else { return }
        func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
        func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
        fpsValue.stringValue = number(fps); highValue.stringValue = number(frames.high); lowValue.stringValue = number(frames.low)
        let count = pet.animation?.frameCount ?? 0
        let index = pet.animation?.stream?.current?.index ?? pet.frameIndex
        let resolution = pet.currentFrame?.image.width ?? pet.preferences.animationResolution
        let limit = pet.preferences.string("animationFPSLimit") == "full" ? "满帧 (≥ 24 FPS)" : pet.preferences.string("animationFPSLimit") + " FPS"
        let state = pet.hidden ? "隐藏" : pet.loading ? "解码中" : pet.press != nil && !pet.dragged ? "暂停" : "播放"
        let preloadEnabled = pet.preferences.bool("preloadWholeAnimation")
        playback.stringValue = "\(preloadEnabled ? "整段预加载" : "流式播放") · \(pet.current.title) · \(state) · \(String(format: "%.2f", pet.playbackRate))×\n画质 \(resolution)×\(resolution) · 上限 \(limit)\n帧 \(count == 0 ? 0 : index + 1)/\(count) · 累计 \(frames.total) · 绘制 \(number(draws))/s"
        let cache = pet.decoder.residentFrameStatistics()
        let preloadText: String
        if preloadEnabled {
            if let progress = pet.decoder.preloadingStatistics() {
                let title = pet.catalog.all.first { $0.id == progress.id }?.title ?? progress.id
                preloadText = "整段预加载：\(title) · \(progress.frames)/\(progress.total) 帧"
            } else if pet.loading {
                preloadText = "整段预加载：准备中"
            } else {
                preloadText = "整段预加载：\(pet.current.title) · \(count) 帧"
            }
        } else if let stream = pet.animation?.stream {
            let buffer = stream.statistics()
            preloadText = "流式缓冲 \(buffer.buffered)/\(stream.capacity) 帧\n整段预加载：关闭"
        } else {
            preloadText = "流式缓冲：准备中"
        }
        let swapinText = process.swapins.map { $0 > 0 ? "累计 \(bytes($0))" : "未观察到换入" } ?? "不可用"
        let swapRateText = swapinRate.map { " · \(bytes(UInt64($0.rounded())))/s" } ?? ""
        resources.stringValue = "CPU 总体 \(number(cpu.map { $0 / Double(ProcessInfo.processInfo.processorCount) }))% · 单核基准 \(number(cpu))%\n运行内存 (RAM) \(process.footprint.map(bytes) ?? "不可用")\nGPU（应用组）\(gpu.map { String(format: "%.2f%%", $0) } ?? gpuStatus)\n本进程压缩 \(process.compressed.map(bytes) ?? "不可用") · 系统 Swap \(process.systemSwapUsed.map(bytes) ?? "不可用")\n本进程 Swap-in：\(swapinText)\(swapRateText)\n帧缓存 \(bytes(UInt64(cache.bytes))) · \(cache.clips) 段 / \(cache.frames) 帧\n\(preloadText)\n动画磁盘缓存 0 B"
        let desktop = NSWorkspace.shared.runningApplications.filter { ["com.openai.codex", "com.openai.chat"].contains($0.bundleIdentifier ?? "") }
        let desktopText = desktop.isEmpty ? "未运行" : desktop.map { "\($0.localizedName ?? "桌面应用") · PID \($0.processIdentifier)" }.joined(separator: "、")
        connections.stringValue = "桌面端  \(desktopText)\n只读同步  \(pet.syncDiagnostics())\nCLI  \(pet.cliDiagnostics())"
        fitToContent()
    }
    private func copyInformation() {
        let text = ([window.title, "FPS \(fpsValue.stringValue) · HI \(highValue.stringValue) · LO \(lowValue.stringValue)",
                     playback.stringValue, resources.stringValue, identity.stringValue, connections.stringValue]).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
}
