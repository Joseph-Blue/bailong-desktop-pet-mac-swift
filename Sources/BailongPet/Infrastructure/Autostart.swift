import AppKit

final class FollowLauncher {
    static let label = "com.bailongpet.appkit.follow"
    static let plist = URL(fileURLWithPath: NSHomeDirectory()+"/Library/LaunchAgents/"+label+".plist")
    static var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/BailongFollow.app/Contents/MacOS/BailongFollow")
    }
    private static var expectedArguments: [String] { [helper.path, Bundle.main.bundleURL.path] }
    private static var service: String { "gui/\(getuid())/\(label)" }
    private static func launchctl(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private static func command(_ arguments: [String]) throws {
        let result = try launchctl(arguments)
        guard result.status == 0 else {
            throw PetFailure(message: "launchctl 执行失败（\(result.status)）\n\(result.output)")
        }
    }
    static var statusText: String {
        guard FileManager.default.fileExists(atPath: plist.path) else { return "打开 Codex 或 ChatGPT 时启动桌宠" }
        do {
            let config = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
            let arguments = config?["ProgramArguments"] as? [String] ?? []
            if arguments.contains(where: { $0.contains("/AppTranslocation/") }) { return "需要修复：旧配置指向临时运行位置" }
            if arguments != expectedArguments { return "需要更新：启动项指向旧版本或其他位置" }
            let result = try launchctl(["print", service])
            return result.status == 0 ? "已启用跟随启动" : "需要修复：监测器未加载（\(result.status)）"
        } catch { return "无法读取启动状态：\(error.localizedDescription)" }
    }
    static func configure() {
        let exists = FileManager.default.fileExists(atPath: plist.path)
        let alert = NSAlert(); alert.messageText = "随 Codex 启动"
        alert.informativeText = exists
            ? statusText+"。修复／更新会将启动项重新绑定到当前版本；停用后不再自动启动桌宠。"
            : "启用后会在登录时运行用户级监测器，打开 Codex 或 ChatGPT 时启动桌宠。手动退出后，同一次应用运行期间不会反复启动。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: exists ? "修复／更新" : "启用")
        if exists { alert.addButton(withTitle: "停用") }
        alert.applyAccent(primary:1,keyboardDefault:1)
        let response = alert.runModal()
        guard response != .alertFirstButtonReturn else { return }
        do {
            if response == .alertThirdButtonReturn { try disable() }
            else { try install() }
        } catch { showError("跟随启动设置失败", error) }
    }
    private static func disable() throws {
        if try launchctl(["print", service]).status == 0 { try command(["bootout", service]) }
        if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
    }
    private static func install() throws {
        guard Bundle.main.bundleURL.pathExtension == "app", FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw PetFailure(message: "请从构建完整的 .app 设置跟随启动。")
        }
        guard !Bundle.main.bundleURL.path.contains("/AppTranslocation/") else {
            throw PetFailure(message: "当前应用正在系统临时位置运行。请退出桌宠，在访达中将 .app 拖到“应用程序”等固定位置，再从那里打开并设置跟随启动。")
        }
        let manager = FileManager.default
        let oldData = manager.fileExists(atPath: plist.path) ? try Data(contentsOf: plist) : nil
        let loaded = try launchctl(["print", service]).status == 0
        if loaded { try command(["bootout", service]) }
        do {
            let config: [String: Any] = ["Label": label, "ProgramArguments": expectedArguments,
                "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10, "ProcessType": "Background"]
            try manager.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0).write(to: plist, options: .atomic)
            try command(["bootstrap", "gui/\(getuid())", plist.path])
            FollowSessions.clearManualExit()
        } catch {
            let failure = error
            // 重新注册失败时还原用户原来的设置，错误仍明确显示。
            do {
                if let oldData {
                    try oldData.write(to: plist, options: .atomic)
                    if loaded { try command(["bootstrap", "gui/\(getuid())", plist.path]) }
                } else if manager.fileExists(atPath: plist.path) { try manager.removeItem(at: plist) }
            } catch {
                throw PetFailure(message: "\(failure.localizedDescription)\n还原旧启动项也失败：\(error.localizedDescription)")
            }
            throw failure
        }
    }
    // 已注册的旧 --follow 入口仍能运行新监测逻辑，界面提示用户更新到独立 helper。
    static func run() { FollowMonitor.run(applicationURL: Bundle.main.bundleURL) }
}
