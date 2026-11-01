import AppKit
import ServiceManagement

enum StartupLocation {
    static func validate() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw PetFailure(message:"请从构建完整的 .app 设置启动项。")
        }
        guard !Bundle.main.bundleURL.path.contains("/AppTranslocation/") else {
            throw PetFailure(message:"当前应用位于系统临时运行位置。请在访达中移到你选择的固定目录，从那里打开后设置启动项。")
        }
    }
    static func isOlder(than recorded:String?) -> Bool {
        guard let recorded,let previous = SemanticVersion(recorded),let current = SemanticVersion(Paths.version) else {return false}
        return current < previous
    }
}

// 启用意图和绑定位置属于本机启动注册，不导入／导出为普通设置。
enum LoginLauncher {
    private static let requestedKey = "loginLaunchRequested"
    private static let pathKey = "loginLaunchBundlePath"
    private static let versionKey = "loginLaunchVersion"
    private static var defaults:UserDefaults {PetPreferences.shared.defaults}
    private(set) static var lastError:String?
    static var statusText:String {
        if let lastError {return "启动项更新失败："+lastError}
        switch SMAppService.mainApp.status {
        case .enabled: return "已启用，打开新版时自动更新启动项"
        case .requiresApproval: return "等待系统批准"
        default: return "未启用"
        }
    }
    private static func rememberRegistration() {
        defaults.set(true,forKey:requestedKey)
        defaults.set(Bundle.main.bundleURL.path,forKey:pathKey)
        defaults.set(Paths.version,forKey:versionKey)
        lastError = nil
    }
    static func setEnabled(_ enabled:Bool) throws {
        try StartupLocation.validate()
        if enabled {
            try SMAppService.mainApp.register(); rememberRegistration()
        } else {
            try SMAppService.mainApp.unregister()
            defaults.set(false,forKey:requestedKey); defaults.removeObject(forKey:pathKey); defaults.removeObject(forKey:versionKey)
            lastError = nil
        }
    }
    static func refreshExistingRegistration() {
        guard Bundle.main.bundleURL.pathExtension == "app",!StartupLocation.isOlder(than:defaults.string(forKey:versionKey)) else {return}
        let status = SMAppService.mainApp.status
        // requiresApproval 同时表示系统设置中撤销了许可，不能自动重新启用。
        guard status != .requiresApproval else {return}
        if status == .enabled {defaults.set(true,forKey:requestedKey)}
        guard defaults.bool(forKey:requestedKey) else {return}
        let changed = defaults.string(forKey:pathKey) != Bundle.main.bundleURL.path || defaults.string(forKey:versionKey) != Paths.version
        if status == .notRegistered && !changed {defaults.set(false,forKey:requestedKey); return}
        guard changed || status == .notFound else {return}
        do {
            try StartupLocation.validate()
            if status == .enabled {try SMAppService.mainApp.unregister()}
            try SMAppService.mainApp.register(); rememberRegistration()
        } catch {lastError = error.localizedDescription}
    }
}

final class FollowLauncher {
    private(set) static var lastUpdateError:String?
    static let didChange = Notification.Name("BailongFollowRegistrationDidChange")
    private static let updateQueue = DispatchQueue(label:"白龙桌宠跟随启动维护")
    private static var updating = false
    private struct CommandFailure:LocalizedError {
        let operation:String, status:Int32, output:String
        var errorDescription:String? {"launchctl \(operation) 执行失败（\(status)）\n\(output)"}
    }
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
            throw CommandFailure(operation:arguments[0],status:result.status,output:result.output)
        }
    }
    static var statusText: String {
        if updating {return "正在更新跟随启动项…"}
        if let lastUpdateError {return "启动项更新失败："+lastUpdateError}
        guard FileManager.default.fileExists(atPath: plist.path) else { return "打开 Codex 或 ChatGPT 时启动桌宠" }
        do {
            if SMAppService.statusForLegacyPlist(at:plist) == .requiresApproval {return "请在系统登录项中允许跟随启动"}
            let config = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
            let arguments = config?["ProgramArguments"] as? [String] ?? []
            if arguments.contains(where: { $0.contains("/AppTranslocation/") }) { return "需要修复：旧配置指向临时运行位置" }
            if arguments != expectedArguments { return "需要更新：启动项指向旧版本或其他位置" }
            let result = try launchctl(["print", service])
            return result.status == 0 ? "已启用跟随启动" : "需要修复：监测器未加载（\(result.status)）"
        } catch { return "无法读取启动状态：\(error.localizedDescription)" }
    }
    static func refreshExistingRegistration() {
        guard Bundle.main.bundleURL.pathExtension == "app",FileManager.default.fileExists(atPath:plist.path) else {return}
        // 仅维护已经存在的用户启动项；系统撤销许可时不重新加载。
        guard SMAppService.statusForLegacyPlist(at:plist) != .requiresApproval else {return}
        do {
            guard let config = try PropertyListSerialization.propertyList(from:Data(contentsOf:plist),format:nil) as? [String:Any],
                  config["Label"] as? String == label,let arguments = config["ProgramArguments"] as? [String] else {
                throw PetFailure(message:"跟随启动配置格式错误。请在通用设置中修复。")
            }
            guard config["Disabled"] as? Bool != true else {return}
            let version = config["BailongVersion"] as? String
            guard !StartupLocation.isOlder(than:version),arguments != expectedArguments || version != Paths.version else {return}
            beginUpdate(enabled:true,automatic:true)
        } catch {lastUpdateError = error.localizedDescription}
    }
    static func configure() {
        guard !updating else {return}
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
        beginUpdate(enabled:response != .alertThirdButtonReturn,automatic:false)
    }
    private static func beginUpdate(enabled:Bool,automatic:Bool) {
        guard !updating else {return}
        updating = true; lastUpdateError = nil
        NotificationCenter.default.post(name:didChange,object:nil)
        updateQueue.async {
            let result = Result<Void,Error> {
                if !enabled {try disable(); return}
                do {try install()}
                catch let failure as CommandFailure where failure.operation == "bootstrap" && failure.status == 5 {
                    // 用户已观察到第二次配置可成功；仅对这项加载错误补一次延后更新。
                    NSLog("跟随启动首次加载失败，稍后重试一次：%@",failure.localizedDescription)
                    Thread.sleep(forTimeInterval:1)
                    guard SMAppService.statusForLegacyPlist(at:plist) != .requiresApproval else {throw failure}
                    try install()
                }
            }
            DispatchQueue.main.async {
                updating = false
                if case .failure(let error) = result {
                    lastUpdateError = error.localizedDescription
                    if !automatic {showError("跟随启动设置失败",error)}
                }
                NotificationCenter.default.post(name:didChange,object:nil)
            }
        }
    }
    private static func removeLoadedService() throws {
        try command(["bootout",service])
        let deadline = ProcessInfo.processInfo.systemUptime+5
        while true {
            let result = try launchctl(["print",service])
            if result.status == 113 {return} // launchd：服务已不存在。
            if result.status != 0 {throw CommandFailure(operation:"确认旧监测器退出",status:result.status,output:result.output)}
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw PetFailure(message:"旧监测器尚未退出，跟随启动项未更新。")
            }
            Thread.sleep(forTimeInterval:0.1)
        }
    }
    private static func disable() throws {
        if try launchctl(["print", service]).status == 0 {try removeLoadedService()}
        if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
    }
    private static func install() throws {
        try StartupLocation.validate()
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw PetFailure(message: "请从构建完整的 .app 设置跟随启动。")
        }
        let manager = FileManager.default
        let oldData = manager.fileExists(atPath: plist.path) ? try Data(contentsOf: plist) : nil
        let loaded = try launchctl(["print", service]).status == 0
        if loaded {try removeLoadedService()}
        do {
            let config: [String: Any] = ["Label": label, "ProgramArguments": expectedArguments,
                "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10, "ProcessType": "Background", "BailongVersion": Paths.version]
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
