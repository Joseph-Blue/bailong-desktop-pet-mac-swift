import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: PetController?, chat: ChatController?, sync: DesktopSync?
    var instanceFD: Int32 = -1
    var localEvents: Any?
    var terminationSignals = [DispatchSourceSignal]()
    var quitReady = false
    var terminationRequested = false
    let revealName = Notification.Name("com.bailongpet.appkit.reveal.\(getuid())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.apply()
        if let icon = AppIcons.application {NSApp.applicationIconImage = icon}
        installTerminationSignals()
        installMenuBar()
        NotificationCenter.default.addObserver(self,selector:#selector(updateNames),name:PetPreferences.didChange,object:nil)
        do {
            try FileManager.default.createDirectory(at:Paths.data,withIntermediateDirectories:true)
            instanceFD = open(Paths.data.appendingPathComponent("instance.lock").path,O_CREAT | O_RDWR,0o600)
            guard instanceFD >= 0 else {throw PetFailure(message:"无法创建桌宠实例锁。")}
            if flock(instanceFD,LOCK_EX | LOCK_NB) != 0 {
                if ProcessInfo.processInfo.environment["BAILONG_DEV_RUN"] == "1" {
                    fputs("已有桌宠正在运行，请先从其菜单退出，再运行开发脚本。\n",stderr)
                } else {
                    DistributedNotificationCenter.default().postNotificationName(revealName,object:nil,userInfo:nil,deliverImmediately:true)
                }
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
                pet.syncStatus = { [weak sync] in sync?.status ?? "任务同步已停止，当前不会读取新的任务状态。" }
            } catch {showError("无法读取会话历史，原文件已保留",error)}
        } catch {showError(PetPreferences.shared.appName+"无法启动",error); NSApp.terminate(nil)}
    }
    func installTerminationSignals() {
        // 在主队列走正常退出流程；不能在 POSIX 信号处理函数中调用 AppKit。
        for number in [SIGINT,SIGTERM] {
            signal(number,SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal:number,queue:.main)
            source.setEventHandler { [weak self] in
                guard let self, !self.terminationRequested else{return}
                self.terminationRequested = true
                if ProcessInfo.processInfo.environment["BAILONG_DEV_RUN"] == "1" {print("正在退出并回收桌宠子进程…")}
                self.quitFromMenu()
            }
            terminationSignals.append(source); source.resume()
        }
    }
    func installMenuBar() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu; bar.addItem(appItem)
        let about = NSMenuItem(title:"关于"+PetPreferences.shared.appName,action:#selector(showAbout),keyEquivalent:""); about.target = self; about.tag = 101; appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title:"设置…",action:#selector(showSettings),keyEquivalent:","); settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title:"退出"+PetPreferences.shared.appName,action:#selector(quitFromMenu),keyEquivalent:"q"); quit.target = self; quit.tag = 102; quit.image = NSImage(systemSymbolName:"rectangle.portrait.and.arrow.right",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular)); appMenu.addItem(quit)
        let editItem = NSMenuItem(title:"编辑",action:nil,keyEquivalent:""); let edit = NSMenu(title:"编辑"); editItem.submenu = edit; bar.addItem(editItem)
        for (title,action,key) in [("撤销","undo:","z"),("重做","redo:","Z"),("剪切","cut:","x"),("拷贝","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:NSSelectorFromString(action),keyEquivalent:key))
        }
        let conversation = NSMenuItem(title:"对话",action:nil,keyEquivalent:""); let commands = NSMenu(title:"对话"); conversation.submenu = commands; bar.addItem(conversation)
        commands.addItem(MenuAction("打开对话",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        commands.addItem(MenuAction("新对话") { [weak self] in self?.chat?.newConversation(); self?.chat?.showHistory(nil) })
        commands.addItem(MenuAction("选择任务文件夹…") { [weak self] in self?.chat?.chooseFolder() })
        commands.addItem(MenuAction("历史对话",symbol:"clock") { [weak self] in self?.chat?.showHistory(nil) })
        NSApp.mainMenu = bar
    }
    @objc func updateNames() {
        let name = PetPreferences.shared.appName
        let menu = NSApp.mainMenu?.items.first?.submenu
        menu?.item(withTag:101)?.title = "关于"+name
        menu?.item(withTag:102)?.title = "退出"+name
    }
    @objc func showSettings() {pet?.showSettings()}
    @objc func showAbout() {AppIcons.showAbout()}
    @objc func quitFromMenu() {UserDefaults.standard.set(true,forKey:"manualQuit"); NSApp.terminate(nil)}
    @objc func reveal() {pet?.reveal()}
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        chat?.showHistory(nil); return false
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(MenuAction("历史对话",symbol:"clock") { [weak self] in self?.chat?.showHistory(nil) })
        menu.addItem(MenuAction("打开对话",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        return menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitReady || chat == nil {return .terminateNow}
        sync?.close()
        if chat?.running == nil {chat?.shutdown {}; return .terminateNow}
        chat?.shutdown { [weak self] in self?.quitReady = true; NSApp.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        sync?.close(); pet?.close(); NotificationCenter.default.removeObserver(self); DistributedNotificationCenter.default().removeObserver(self)
        if let localEvents {NSEvent.removeMonitor(localEvents)}
        if instanceFD >= 0 {close(instanceFD)}
    }
}
if CommandLine.arguments.contains("--follow") {FollowLauncher.run()}
else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
