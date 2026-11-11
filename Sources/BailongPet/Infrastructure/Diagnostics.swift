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
            } else { result.memoryError = "系统未返回进程换入计数" }
        } else { result.memoryError = "task_info 错误 \(memoryStatus)" }
        return result
    }
    static func systemSwapText() -> String {
        var swap = xsw_usage()
        var size = MemoryLayout.size(ofValue: swap)
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else {
            return "不可用（vm.swapusage errno \(errno)）"
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
        let architecture = "x86_64 / Intel 指令集"
        #else
        let architecture = "未知编译架构"
        #endif
        let info = ProcessInfo.processInfo
        let gpu = MTLCreateSystemDefaultDevice()
        return "版本 \(Paths.version) · \(architecture)\n进程 \(info.processName) · PID \(info.processIdentifier)\nCPU \(systemString("machdep.cpu.brand_string") ?? "型号不可用") · \(systemString("hw.machine") ?? "架构不可用") · \(info.processorCount) 核\nGPU \(gpu?.name ?? "不可用") · \(gpu?.architecture.name ?? "架构不可用")\nmacOS \(info.operatingSystemVersionString)"
    }()
}

final class DiagnosticsPanel: NSObject, NSWindowDelegate {
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
        let container = NSView()
        window.contentView = container
        let rows = [
            ("更新 FPS", fpsValue), ("CPU 总体", cpuValue), ("运行内存 (RAM)", ramValue),
            ("GPU（应用组）", gpuValue), ("本段缺帧等待", underflowValue)
        ]
        let grid = NSGridView(views: rows.map { name, value in
            let title = NSTextField(labelWithString: name)
            title.textColor = .secondaryLabelColor
            value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            value.alignment = .right
            value.setAccessibilityLabel(name)
            return [title, value]
        })
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 1).width = 124
        grid.columnSpacing = 20
        grid.rowSpacing = 0
        for row in 0..<grid.numberOfRows { grid.row(at: row).height = 27 }
        container.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = ActionButton("关闭") { [weak self] in self?.window.performClose(nil) }
        let copyButton = ActionButton("拷贝完整诊断") {}
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "拷贝")
        copyButton.imagePosition = .imageLeading; copyButton.emphasize()
        CopyFeedback.attach(to:copyButton) { [weak self] in self?.copyInformation() }
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
        InterfaceWindows.shared.opened(window)
        if timer == nil {
            beginSampling(); placeTopLeft()
        }
        if takeFocus && window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.addWindowsItem(window, title: window.title, filename: false)
        if takeFocus { if !NSApp.isActive {NSApp.activate(ignoringOtherApps:true)}; window.makeKeyAndOrderFront(nil) }
        else if !window.isVisible && !window.isMiniaturized { window.orderFront(nil) }
    }
    private func beginSampling() {
        timer?.invalidate()
        sampledAt = ProcessInfo.processInfo.systemUptime; frames = PlaybackStatistics(time:sampledAt)
        pet?.playbackScheduling = PlaybackSchedulingStatistics()
        previous = ProcessStatistics.read(); swapinRate = nil; reading = Reading()
        switch GPUStatistics.read() {
        case .success(let snapshot): previousGPU = snapshot; gpuStatus = "等待采样"
        case .failure(let error): previousGPU = nil; gpuStatus = error.message
        }
        updateMetrics()
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.sample() }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func resetStatistics() { if timer != nil { beginSampling() } }
    func stop() {
        timer?.invalidate(); timer = nil; previousGPU = nil
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
                gpuStatus = "应用组 \(snapshot.coalition)"
            } else { gpuStatus = "重新建立采样基线" }
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
        update(ramValue, previous.footprint.map(memoryText) ?? "不可用")
        update(gpuValue, reading.gpu.map { String(format: "%.2f%%", $0) } ?? (previousGPU == nil ? "不可用" : "—"))
        let underflows = pet?.animation?.stream?.statistics().underflows
        update(underflowValue, underflows.map { "\($0) 次" } ?? "—")
    }
    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
    private func copyInformation() -> String {
        guard let pet else { return window.title }
        let count = pet.animation?.frameCount ?? 0
        let index = pet.animation?.stream?.current?.index ?? pet.frameIndex
        let resolution = pet.currentFrame?.image.width ?? pet.animationResolution(for:pet.current)
        let automatic = pet.preferences.usesAutomaticAnimationResolution ? "自动 · " : ""
        let limit = pet.preferences.string("animationFPSLimit") == "full" ? "满帧 (≥ 24 FPS)" : pet.preferences.string("animationFPSLimit") + " FPS"
        let state = pet.hidden ? "隐藏" : pet.loading ? "解码中" : "播放"
        let preloadEnabled = pet.preferences.bool("preloadWholeAnimation")
        var playback = "\(preloadEnabled ? "整段预加载" : "流式播放") · \(pet.current.title) · \(state) · \(String(format: "%.2f", pet.playbackRate))×\n画质 \(automatic)\(resolution)×\(resolution) · 上限 \(limit)\n帧 \(count == 0 ? 0 : index + 1)/\(count) · 累计 \(frames.total) · 图层更新 \(number(reading.draws))/s"
        func milliseconds(_ value: Double?) -> String { value.map { String(format:"%.1f ms",$0 * 1000) } ?? "—" }
        playback += "\n最长图像更新间隔（本次统计）\(milliseconds(frames.longestFrameHold))"
        let scheduling = pet.playbackScheduling
        playback += "\n调度 \(number(scheduling.callbackRate))/s · 回调延后：平均 \(milliseconds(scheduling.averageDelay)) · 最长 \(milliseconds(scheduling.longestDelay)) · ≥ 一帧 \(scheduling.overdueFrames) 次"
        if let timing = pet.animation?.loadTiming {
            playback += "\n本段加载：请求→首帧 \(milliseconds(timing.firstFrameAt - timing.requestedAt)) · 起播准备 \(milliseconds(timing.readyAt - timing.firstFrameAt))"
            playback += "\n准备→交接 \(milliseconds(timing.handedAt.map { $0 - timing.readyAt })) · 交接→图层 \(milliseconds(timing.submittedAt.flatMap { displayed in timing.handedAt.map { displayed - $0 } }))"
            playback += "\n请求→图层 \(milliseconds(timing.submittedAt.map { $0 - timing.requestedAt }))"
        }
        let cache = pet.decoder.residentFrameStatistics()
        var preloadText: String
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
            preloadText = "流式缓冲 \(buffer.buffered)/\(stream.capacity) 帧\n本段缺帧等待 \(buffer.underflows) 次 · 最长 \(milliseconds(buffer.longestUnderflow))\n本段读取 \(buffer.decoded) 帧 · 像素处理 \(buffer.converted) 帧 · 跳过 \(buffer.skipped) 帧\n本段回调跨过可用帧 \(buffer.expired) 帧\n整段预加载：关闭"
            if let startup = stream.startup {
                preloadText += "\n起播 \(startup.frames) 帧 · 余量 \(milliseconds(startup.seconds))"
                if startup.reused > 0 {
                    let continuation = buffer.continued.map { $0 ? "缺帧前接续" : "缺帧后接续" } ?? "接续准备中"
                    preloadText += " · 复用 \(startup.reused) 帧 · \(continuation)\n缓存区间重读 \(buffer.replayed) 个样本，跳过像素处理"
                }
            }
        } else {
            preloadText = "流式缓冲：准备中"
        }
        if pet.preferences.bool("animationOpeningCache"), !preloadEnabled {
            preloadText += "\n开头缓存 \(memoryText(UInt64(cache.openingBytes))) / 24 MiB · \(cache.openingClips) 段 · 累计命中 \(cache.hits) 次"
        }
        let swapinText = previous.swapins.map { $0 > 0 ? "累计 \(memoryText($0))" : "未观察到换入" }
            ?? previous.memoryError ?? "不可用"
        let swapRateText = swapinRate.map { " · \(memoryText(UInt64($0.rounded())))/s" } ?? ""
        let resources = "CPU 总体 \(number(totalCPU))% · 单核基准 \(number(reading.cpu))%\n"
            + "运行内存 (RAM) \(previous.footprint.map(memoryText) ?? previous.memoryError ?? "不可用")\n"
            + "GPU（应用组）\(reading.gpu.map { String(format: "%.2f%%", $0) } ?? gpuStatus)\n"
            + "本进程压缩 \(previous.compressed.map(memoryText) ?? "不可用") · 系统 Swap \(ProcessStatistics.systemSwapText())\n"
            + "本进程 Swap-in：\(swapinText)\(swapRateText)\n"
            + "帧像素合计 \(memoryText(UInt64(cache.bytes))) · \(cache.frames) 帧 · 已发布 \(cache.clips) 段\n"
            + "\(preloadText)\n动画磁盘缓存 0 B"
        let desktop = NSWorkspace.shared.runningApplications.filter { ["com.openai.codex", "com.openai.chat"].contains($0.bundleIdentifier ?? "") }
        let desktopText = desktop.isEmpty ? "未运行" : desktop.map { "\($0.localizedName ?? "桌面应用") · PID \($0.processIdentifier)" }.joined(separator: "、")
        let connections = "桌面端  \(desktopText)\n只读同步  \(pet.syncDiagnostics())\nCLI  \(pet.cliDiagnostics())"
        let frameRates = "更新 FPS \(number(reading.fps)) · HI \(number(frames.high)) · LO \(number(frames.low))"
        return [window.title, frameRates, playback, resources, DeviceIdentity.text, connections].joined(separator: "\n\n")
    }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
}
