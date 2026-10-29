import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: PetController?, chat: ChatController?, sync: DesktopSync?
    var instanceFD: Int32 = -1
    var localEvents: Any?
    var quitReady = false
    let revealName = Notification.Name("com.bailongpet.appkit.reveal.\(getuid())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at:Paths.data,withIntermediateDirectories:true)
            instanceFD = open(Paths.data.appendingPathComponent("instance.lock").path,O_CREAT | O_RDWR,0o600)
            guard instanceFD >= 0 else {throw PetFailure(message:"无法创建桌宠实例锁。")}
            if flock(instanceFD,LOCK_EX | LOCK_NB) != 0 {
                DistributedNotificationCenter.default().postNotificationName(revealName,object:nil,userInfo:nil,deliverImmediately:true)
                NSApp.terminate(nil); return
            }
            UserDefaults.standard.set(false,forKey:"manualQuit")
            let pet = PetController(catalog:try Catalog.load()); self.pet = pet
            pet.onQuit = {UserDefaults.standard.set(true,forKey:"manualQuit"); NSApp.terminate(nil)}
            pet.onAutostart = {FollowLauncher.configure()}
            localEvents = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown,.scrollWheel]) { [weak pet] event in
                pet?.interaction(); return event
            }
            DistributedNotificationCenter.default().addObserver(self,selector:#selector(reveal),name:revealName,object:nil)
            do {
                let chat = try ChatController(pet:pet); self.chat = chat
                let sync = DesktopSync(chat:chat); self.sync = sync
                pet.syncStatus = { [weak sync] in sync?.status ?? "任务观察已停止" }
            } catch {showError("无法读取会话历史，原文件已保留",error)}
        } catch {showError("白龙桌宠无法启动",error); NSApp.terminate(nil)}
    }
    @objc func reveal() {pet?.reveal()}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitReady || chat == nil {return .terminateNow}
        sync?.close()
        if chat?.running == nil {chat?.shutdown {}; return .terminateNow}
        chat?.shutdown { [weak self] in self?.quitReady = true; NSApp.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        sync?.close(); pet?.close(); DistributedNotificationCenter.default().removeObserver(self)
        if let localEvents {NSEvent.removeMonitor(localEvents)}
        if instanceFD >= 0 {close(instanceFD)}
    }
}
if CommandLine.arguments.contains("--follow") {FollowLauncher.run()}
else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
