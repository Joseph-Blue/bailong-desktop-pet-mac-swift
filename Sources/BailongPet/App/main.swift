import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: PetController?, chat: ChatController?, sync: DesktopSync?
    var instanceFD: Int32 = -1
    var localEvents: Any?
    var terminationSignals = [DispatchSourceSignal]()
    var quitReady = false
    var terminationRequested = false
    var explicitQuit = false
    let lifecycle = RunLifecycle()
    var ownsInstance = false
    var unfinishedRun: RunLifecycle.UnfinishedRun?
    let revealName = Notification.Name("com.bailongpet.appkit.reveal.\(getuid())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        TextContextMenu.install()
        AppAppearance.apply()
        if let icon = AppIcons.application {NSApp.applicationIconImage = icon}
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(systemWillTerminate),name:NSWorkspace.willPowerOffNotification,object:nil)
        installTerminationSignals()
        installMenuBar()
        NotificationCenter.default.addObserver(self,selector:#selector(updateNames),name:PetPreferences.didChange,object:nil)
        RecoveryWindow.quit = { [weak self] in self?.quitFromMenu() }
        startApplication()
    }
    private func startApplication() {
        do {
            _ = try Paths.readVersion()
            try PetPreferences.shared.validatePlayback()
            if !ownsInstance {
                try FileManager.default.createDirectory(at:Paths.data,withIntermediateDirectories:true)
                instanceFD = open(Paths.data.appendingPathComponent("instance.lock").path,O_CREAT | O_RDWR,0o600)
                guard instanceFD >= 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
                if flock(instanceFD,LOCK_EX | LOCK_NB) != 0 {
                    let code = errno; close(instanceFD); instanceFD = -1
                    guard code == EWOULDBLOCK else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))}
                    DistributedNotificationCenter.default().postNotificationName(revealName,object:nil,userInfo:nil,deliverImmediately:true)
                    explicitQuit = true; NSApp.terminate(nil); return
                }
                ownsInstance = true; unfinishedRun = lifecycle.begin(version:Paths.version)
            }
            FollowSessions.clearManualExit()
            LoginLauncher.refreshExistingRegistration()
            FollowLauncher.refreshExistingRegistration()
            let pet = PetController(catalog:try Catalog.load()); self.pet = pet
            pet.onQuit = { [weak self] in self?.quitFromMenu() }
            localEvents = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown,.scrollWheel]) { [weak self, weak pet] event in
                if event.type == .keyDown, event.charactersIgnoringModifiers?.lowercased() == "q",
                   event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command {
                    self?.closeInterface(); return nil
                }
                pet?.interaction(); return event
            }
            DistributedNotificationCenter.default().addObserver(self,selector:#selector(reveal),name:revealName,object:nil)
            loadChat()
            RecoveryWindow.resolve("startup")
            if let previous = unfinishedRun {
                unfinishedRun = nil
                let started = previous.started?.formatted(date:.numeric,time:.standard) ?? "未记录"
                RecoveryWindow.show(id:"previous-run",report:RecoveryReport(title:"上次运行未正常结束",message:"应用已重新启动。请检查任务状态；未完成的任务不会自动重新执行。",module:"运行状态",operation:"检查上次退出记录",facts:["上次版本："+previous.version,"上次启动："+started,"退出原因：未记录正常退出，无法据此区分崩溃、强制退出或断电。"]),actionTitle:"继续使用") {RecoveryWindow.resolve("previous-run")}
            }
            if PetPreferences.shared.bool("automaticallyCheckUpdates") {UpdateChecker.shared.check(automatically:true)}
        } catch {
            RecoveryWindow.show(id:"startup",report:RecoveryReport(title:"应用初始化未完成",message:"请确认数据目录可写、应用资源完整，然后重新初始化。现有设置和历史不会被清空。",module:"应用启动",operation:"初始化数据目录与素材",error:error),actionTitle:"重新初始化") { [weak self] in self?.startApplication() }
        }
    }
    private func loadChat() {
        guard let pet,chat == nil else {return}
        do {
            let chat = try ChatController(pet:pet); self.chat = chat
            let sync = DesktopSync(chat:chat); self.sync = sync
            pet.settings.onClearLocalData = { [weak chat,weak sync] in
                guard let chat,let sync else {throw PetFailure(message:"数据管理已停止。")}
                try chat.clearLocalData(); sync.clearLocalProjection()
            }
            pet.syncDiagnostics = { [weak sync] in sync?.diagnostics ?? "已停止" }
            pet.syncStatus = { [weak sync] in sync?.status ?? "任务同步已停止，当前不会读取新的任务状态。" }
            RecoveryWindow.resolve("history-load")
        } catch {
            pet.onHistory = { [weak self] _ in self?.loadChat(); RecoveryWindow.revealAll() }
            pet.onComposer = { [weak self] in self?.loadChat(); RecoveryWindow.revealAll() }
            RecoveryWindow.show(id:"history-load",report:RecoveryReport(title:"对话数据未能加载",message:"历史原文件保留，对话和任务同步尚未启动。修复文件格式或读取权限后，可重新读取。",module:"会话数据",operation:"读取历史与初始化任务目录",error:error),actionTitle:"重新读取") { [weak self] in self?.loadChat() }
        }
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
        appMenu.addItem(MenuAction("检查更新…",symbol:"arrow.triangle.2.circlepath") {UpdateWindow.show()})
        let settings = NSMenuItem(title:"设置…",action:#selector(showSettings),keyEquivalent:","); settings.target = self
        settings.image = NSImage(systemSymbolName:"gearshape",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let close = NSMenuItem(title:"关闭当前窗口",action:#selector(closeInterface),keyEquivalent:"q"); close.target = self; appMenu.addItem(close)
        let quit = NSMenuItem(title:"退出"+PetPreferences.shared.appName,action:#selector(quitFromMenu),keyEquivalent:""); quit.target = self; quit.tag = 102; quit.image = NSImage(systemSymbolName:"rectangle.portrait.and.arrow.right",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular)); appMenu.addItem(quit)
        let editItem = NSMenuItem(title:"编辑",action:nil,keyEquivalent:""); let edit = NSMenu(title:"编辑"); editItem.submenu = edit; bar.addItem(editItem)
        for (title,action,key) in [("撤销","undo:","z"),("重做","redo:","Z"),("剪切","cut:","x"),("拷贝","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:NSSelectorFromString(action),keyEquivalent:key))
        }
        let conversation = NSMenuItem(title:"对话",action:nil,keyEquivalent:""); let commands = NSMenu(title:"对话"); conversation.submenu = commands; bar.addItem(conversation)
        commands.addItem(MenuAction("打开对话",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        commands.addItem(MenuAction("新对话") { [weak self] in self?.chat?.newConversation(); self?.chat?.showHistory(nil) })
        commands.addItem(MenuAction("选择任务文件夹…") { [weak self] in self?.chat?.chooseFolder() })
        commands.addItem(MenuAction("历史对话",symbol:"clock") { [weak self] in self?.chat?.showHistory(nil) })
        let windowsItem = NSMenuItem(title:"窗口",action:nil,keyEquivalent:"")
        let windows = NSMenu(title:"窗口"); windowsItem.submenu = windows; bar.addItem(windowsItem)
        windows.addItem(MenuAction("应用性能信息统计",symbol:"chart.xyaxis.line") { [weak self] in self?.pet?.showDiagnostics() })
        windows.addItem(MenuAction("错误与恢复",symbol:"exclamationmark.triangle") {RecoveryWindow.revealAll()})
        windows.addItem(NSMenuItem(title:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        windows.addItem(.separator()); NSApp.windowsMenu = windows
        NSApp.mainMenu = bar
    }
    @objc func updateNames() {
        let name = PetPreferences.shared.appName
        let menu = NSApp.mainMenu?.items.first?.submenu
        menu?.item(withTag:101)?.title = "关于"+name
        menu?.item(withTag:102)?.title = "退出"+name
    }
    @objc func showSettings() {pet?.showSettings()}
    @objc func showAbout() {pet?.showSettings(section:.about)}
    @objc func systemWillTerminate() {explicitQuit = true}
    @objc func quitFromMenu() {explicitQuit = true; FollowSessions.markManualExit(); NSApp.terminate(nil)}
    @objc func closeInterface() {
        // 原生模态窗口与 sheet 均走取消路径，不触发确认或危险操作。
        if let modal = NSApp.modalWindow {
            if let panel = modal as? NSSavePanel {panel.cancel(nil)}
            else {NSApp.abortModal(); modal.orderOut(nil)}
            return
        }
        let windows = NSApp.orderedWindows + NSApp.windows
        let candidate = NSApp.keyWindow ?? NSApp.mainWindow ?? windows.first {
            $0.canBecomeKey && ($0.isVisible || $0.isMiniaturized)
        }
        guard let window = candidate else {return}
        if let sheet = window.attachedSheet ?? (window.isSheet ? window : nil) {
            if let panel = sheet as? NSSavePanel {panel.cancel(nil)}
            else {sheet.sheetParent?.endSheet(sheet,returnCode:.cancel); sheet.orderOut(nil)}
        } else if window === chat?.ui.composer {chat?.ui.hideComposer()}
        else if window.styleMask.contains(.closable) {window.performClose(nil)}
        else if window.canBecomeKey {window.close()}
    }
    @objc func reveal() {pet?.reveal()}
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock 召回先沿用当前窗口，不因设置窗口存在就切走历史／更新／统计。
        if let current = NSApp.keyWindow,current.isVisible {return false}
        if let visible = NSApp.orderedWindows.first(where:{$0.isVisible && !$0.isMiniaturized && $0.canBecomeKey}) {
            visible.makeKeyAndOrderFront(nil)
        }
        else if let minimized = NSApp.windows.first(where: {$0.isMiniaturized && $0.canBecomeKey}) {
            minimized.deminiaturize(nil); minimized.makeKeyAndOrderFront(nil)
        }
        else if pet?.preferences.bool("showDiagnostics") == true { pet?.showDiagnostics() }
        else if RecoveryWindow.hasIssues {RecoveryWindow.revealAll()}
        else { chat?.showHistory(nil) }
        return false
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(MenuAction("设置…",symbol:"gearshape") { [weak self] in self?.pet?.showSettings() })
        menu.addItem(MenuAction("应用性能信息统计") { [weak self] in self?.pet?.showDiagnostics() })
        menu.addItem(MenuAction("历史对话",symbol:"clock") { [weak self] in self?.chat?.showHistory(nil) })
        if RecoveryWindow.hasIssues {menu.addItem(MenuAction("错误与恢复") {RecoveryWindow.revealAll()})}
        menu.addItem(MenuAction("打开对话",symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        return menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Dock 的系统“退出”只关闭界面；完整退出必须来自桌宠的显式退出入口。
        if !explicitQuit {closeInterface(); return .terminateCancel}
        UpdateChecker.shared.cancel()
        if quitReady || chat == nil {return .terminateNow}
        sync?.close()
        if chat?.running == nil {chat?.shutdown {}; return .terminateNow}
        chat?.shutdown { [weak self] in self?.quitReady = true; NSApp.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        if ownsInstance {lifecycle.finish()}
        sync?.close(); pet?.close(); NotificationCenter.default.removeObserver(self); DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let localEvents {NSEvent.removeMonitor(localEvents)}
        if instanceFD >= 0 {close(instanceFD)}
    }
}
if CommandLine.arguments.contains("--follow") {FollowLauncher.run()}
else {
    // AppKit 原生 tooltip 的延迟单位为毫秒；仅写当前应用域。
    UserDefaults.standard.set(200,forKey:"NSInitialToolTipDelay")
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
