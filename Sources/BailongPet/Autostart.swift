import AppKit

final class FollowLauncher {
    static let label = "com.bailongpet.appkit.follow"
    static let plist = URL(fileURLWithPath:NSHomeDirectory()+"/Library/LaunchAgents/"+label+".plist")
    static func command(_ arguments: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath:"/bin/launchctl"); p.arguments = arguments
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {throw PetFailure(message:"launchctl 执行失败（\(p.terminationStatus)）。")}
    }
    static func configure() {
        let enabled = FileManager.default.fileExists(atPath:plist.path)
        let a = NSAlert(); a.messageText = "随 Codex 启动"
        a.informativeText = enabled ? "当前已启用。停用后不再自动启动桌宠。" : "启用后会在登录时运行用户级监测器，打开 Codex 或 ChatGPT 时启动桌宠。手动退出会保持退出，直到下一次打开周期。"
        a.addButton(withTitle:"取消"); a.addButton(withTitle:enabled ? "停用" : "启用")
        a.applyAccent(primary:1)
        guard a.runModal() == .alertSecondButtonReturn else{return}
        do {
            if enabled {try command(["bootout","gui/\(getuid())/\(label)"]); try FileManager.default.removeItem(at:plist)}
            else {
                guard Bundle.main.bundleURL.pathExtension == "app", let exe = Bundle.main.executableURL else {throw PetFailure(message:"请先从构建好的 .app 启用跟随启动。")}
                let config: [String:Any] = ["Label":label,"ProgramArguments":[exe.path,"--follow"],"RunAtLoad":true,"KeepAlive":true,"ThrottleInterval":10,"ProcessType":"Background"]
                try FileManager.default.createDirectory(at:plist.deletingLastPathComponent(),withIntermediateDirectories:true)
                try PropertyListSerialization.data(fromPropertyList:config,format:.xml,options:0).write(to:plist,options:.atomic)
                UserDefaults.standard.set(false,forKey:"manualQuit")
                try command(["bootstrap","gui/\(getuid())",plist.path])
            }
        } catch {showError("跟随启动设置失败",error)}
    }
    static func run() {
        var previous = false
        let timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { _ in
            let opened = NSWorkspace.shared.runningApplications.contains { app in ["Codex.app","ChatGPT.app"].contains(app.bundleURL?.lastPathComponent ?? "") }
            if !opened && previous {UserDefaults.standard.set(false,forKey:"manualQuit")}
            if opened && !previous && !UserDefaults.standard.bool(forKey:"manualQuit"), let exe = Bundle.main.executableURL {
                let p = Process(); p.executableURL = exe
                do {try p.run()} catch {NSLog("白龙娘跟随启动失败：%@",error.localizedDescription)}
            }
            previous = opened
        }
        RunLoop.main.add(timer,forMode:.common); RunLoop.main.run()
    }
}
