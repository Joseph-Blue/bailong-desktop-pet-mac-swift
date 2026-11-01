import AppKit

// 主应用与独立监测器只共享这一组退出标记；不读取 Codex 设置或凭证。
enum FollowSessions {
    static let identifiers: Set<String> = ["com.openai.codex", "com.openai.chat"]
    static let domain = "com.bailongpet.appkit" as CFString
    static let key = "followSuppressedSessions" as CFString
    static func token(identifier: String, pid: pid_t, launched: Date) -> String {
        "\(identifier):\(pid):\(launched.timeIntervalSince1970)"
    }
    static func running() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, identifiers.contains(id), let date = app.launchDate else { return nil }
            return token(identifier: id, pid: app.processIdentifier, launched: date)
        })
    }
    static func suppressed() -> Set<String> {
        CFPreferencesAppSynchronize(domain)
        return Set(CFPreferencesCopyAppValue(key, domain) as? [String] ?? [])
    }
    static func markManualExit() { setSuppressed(Array(running())) }
    static func clearManualExit() { setSuppressed([]) }
    private static func setSuppressed(_ sessions: [String]) {
        CFPreferencesSetAppValue(key, sessions as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

struct FollowTransitions {
    private var previous = Set<String>()
    mutating func shouldLaunch(current: Set<String>, suppressed: Set<String>) -> Bool {
        defer { previous = current }
        // 分别追踪每次应用启动；ChatGPT 常驻时，重新打开 Codex 也能触发。
        return !current.subtracting(previous).subtracting(suppressed).isEmpty
    }
}

final class FollowMonitor {
    private let applicationURL: URL
    private var transitions = FollowTransitions()
    private var tokens = [NSObjectProtocol]()
    private var timer: Timer?
    private var opening = false
    init(applicationURL: URL) { self.applicationURL = applicationURL }

    private func scan() {
        guard transitions.shouldLaunch(current: FollowSessions.running(), suppressed: FollowSessions.suppressed()), !opening else { return }
        opening = true
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        // 旧 --follow 进程可能仍以主应用身份注册；由桌宠自身的文件锁处理唯一实例。
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.opening = false
                if let error { NSLog("白龙桌宠Swift跟随启动失败：%@", error.localizedDescription) }
            }
        }
    }
    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scan() })
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        scan()
    }
    static func run(applicationURL: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let monitor = FollowMonitor(applicationURL: applicationURL)
        // AppKit 事件循环负责刷新工作区应用状态；不是只运行一个 Foundation 计时器。
        DispatchQueue.main.async { monitor.start() }
        withExtendedLifetime(monitor) { app.run() }
    }
}
