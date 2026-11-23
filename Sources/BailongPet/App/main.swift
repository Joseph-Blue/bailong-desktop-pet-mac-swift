import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, WorkspaceStatusSettingsAction {
    var pet: PetController?, chat: ChatController?, sync: DesktopSync?
    var instanceFD: Int32 = -1
    var localEvents: Any?
    var terminationSignals = [DispatchSourceSignal]()
    private var monitorKeyboard:DispatchSourceRead?
    var quitReady = false
    var quitInProgress = false
    var awaitingTerminateReply = false
    var terminationRequested = false
    var explicitQuit = false
    let lifecycle = RunLifecycle()
    var ownsInstance = false
    var unfinishedRun: RunLifecycle.UnfinishedRun?
    let revealName = Notification.Name("com.bailongpet.appkit.reveal.\(getuid())")
    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminalMonitor.active?.start(version:Paths.version)
        monitorKeyboard = TerminalMonitor.keyboard { [weak self] monitor in
            monitor.start(version:Paths.version)
            self?.chat?.connection.reportMonitorState(to:monitor)
            self?.sync?.reportMonitorState(to:monitor)
        }
        TextContextMenu.install()
        AppAppearance.apply()
        if let icon = AppIcons.application {NSApp.applicationIconImage = icon}
        guard RosettaNotice.confirmLaunch() else {quitFromMenu(); return}
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
                    TerminalMonitor.active?.write(.app,L10n.text(.app,"application.startApplication.text"),.warning)
                    DistributedNotificationCenter.default().postNotificationName(revealName,object:nil,userInfo:nil,deliverImmediately:true)
                    explicitQuit = true; NSApp.terminate(nil); return
                }
                ownsInstance = true
                unfinishedRun = lifecycle.begin(version:Paths.version)
            }
            FollowSessions.clearManualExit()
            LoginLauncher.refreshExistingRegistration()
            FollowLauncher.refreshExistingRegistration()
            let catalog:Catalog
            do {catalog = try Catalog.load()}
            catch {
                TerminalMonitor.active?.write(.app,L10n.text(.app,"application.startApplication.text.2")+TerminalMonitor.errorCode(error),.error)
                throw error
            }
            let pet = PetController(catalog:catalog); self.pet = pet
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
                let started = previous.started?.formatted(date:.numeric,time:.standard) ?? L10n.text(.app,"application.started")
                RecoveryWindow.show(id:"previous-run",report:RecoveryReport(title:L10n.text(.diagnostics,"application.startApplication.title"),message:L10n.text(.diagnostics,"application.startApplication.message"),module:L10n.text(.diagnostics,"application.startApplication.text"),operation:L10n.text(.diagnostics,"application.startApplication.text.2"),facts:[L10n.text(.diagnostics,"application.startApplication.text.3")+previous.version,L10n.text(.diagnostics,"application.startApplication.text.4")+started,L10n.text(.diagnostics,"application.startApplication.text.5")]),actionTitle:L10n.text(.diagnostics,"application.startApplication.actionTitle")) {RecoveryWindow.resolve("previous-run")}
            }
            if PetPreferences.shared.bool("automaticallyCheckUpdates") {UpdateChecker.shared.check(automatically:true)}
        } catch {
            RecoveryWindow.show(id:"startup",report:RecoveryReport(title:L10n.text(.diagnostics,"application.startApplication.title.2"),message:L10n.text(.diagnostics,"application.startApplication.message.2"),module:L10n.text(.diagnostics,"application.startApplication.text.6"),operation:L10n.text(.diagnostics,"application.startApplication.text.7"),error:error),actionTitle:L10n.text(.diagnostics,"application.startApplication.actionTitle.2")) { [weak self] in self?.startApplication() }
        }
    }
    private func loadChat() {
        guard let pet,chat == nil else {return}
        do {
            let chat = try ChatController(pet:pet); self.chat = chat
            let sync = DesktopSync(chat:chat); self.sync = sync
            if let monitor = TerminalMonitor.active {chat.connection.reportMonitorState(to:monitor)}
            pet.settings.onClearLocalData = { [weak chat,weak sync] in
                guard let chat,let sync else {throw PetFailure(message:L10n.text(.app,"application.loadChat.message"))}
                try chat.clearLocalData(); sync.clearLocalProjection()
            }
            pet.syncDiagnostics = { [weak sync] in sync?.diagnostics ?? L10n.text(.app,"application.loadChat.text") }
            pet.syncStatus = { [weak sync] in sync?.status ?? L10n.text(.app,"application.loadChat.text.2") }
            RecoveryWindow.resolve("history-load")
        } catch {
            pet.syncDiagnostics = { L10n.text(.app,"application.loadChat.text.3") }
            pet.syncStatus = { L10n.text(.app,"application.loadChat.text.4")+error.localizedDescription }
            pet.bubble.taskProvider = {BubbleTaskOverview(status:L10n.text(.app,"application.loadChat.text.5"))}
            pet.onHistory = { [weak self] _ in self?.loadChat(); RecoveryWindow.revealAll() }
            pet.onComposer = { [weak self] in self?.loadChat(); RecoveryWindow.revealAll() }
            RecoveryWindow.show(id:"history-load",report:RecoveryReport(title:L10n.text(.diagnostics,"application.loadChat.title"),message:L10n.text(.diagnostics,"application.loadChat.message"),module:L10n.text(.diagnostics,"application.loadChat.text"),operation:L10n.text(.diagnostics,"application.loadChat.text.2"),error:error),actionTitle:L10n.text(.diagnostics,"application.loadChat.actionTitle")) { [weak self] in self?.loadChat() }
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
                if ProcessInfo.processInfo.environment["BAILONG_DEV_RUN"] == "1" {print(L10n.text(.app,"application.installTerminationSignals.text"))}
                self.quitFromMenu()
            }
            terminationSignals.append(source); source.resume()
        }
    }
    func installMenuBar() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let appMenu = AccentMenuRows.menu(); appItem.submenu = appMenu; bar.addItem(appItem)
        let about = NSMenuItem(title:L10n.text(.app,"application.about")+PetPreferences.shared.appName,action:#selector(showAbout),keyEquivalent:""); about.target = self; about.tag = 101; appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem"),symbol:"arrow.triangle.2.circlepath") {UpdateWindow.show()})
        let settings = NSMenuItem(title:L10n.text(.app,"application.settings"),action:#selector(showSettings),keyEquivalent:","); settings.target = self
        settings.image = NSImage(systemSymbolName:"gearshape",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let close = NSMenuItem(title:L10n.text(.app,"application.close"),action:#selector(closeInterface),keyEquivalent:"q"); close.target = self; appMenu.addItem(close)
        let closeWindow = NSMenuItem(title:L10n.text(.app,"application.closeWindow"),action:#selector(closeInterface),keyEquivalent:"w"); closeWindow.target = self; appMenu.addItem(closeWindow)
        let quit = NSMenuItem(title:L10n.text(.app,"application.quit")+PetPreferences.shared.appName,action:#selector(quitFromMenu),keyEquivalent:""); quit.target = self; quit.tag = 102; quit.image = NSImage(systemSymbolName:"rectangle.portrait.and.arrow.right",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular)); appMenu.addItem(quit)
        let editItem = NSMenuItem(title:L10n.text(.app,"application.editItem"),action:nil,keyEquivalent:""); let edit = AccentMenuRows.menu(title:L10n.text(.app,"application.editItem")); editItem.submenu = edit; bar.addItem(editItem)
        edit.delegate = self
        TextContextMenu.editMenu = edit
        for (title,action,key) in [(L10n.text(.app,"application.installMenuBar.text"),"undo:","z"),(L10n.text(.app,"application.installMenuBar.text.2"),"redo:","Z"),(L10n.text(.app,"application.installMenuBar.text.3"),"cut:","x"),(L10n.text(.app,"application.installMenuBar.text.4"),"copy:","c"),(L10n.text(.app,"application.installMenuBar.text.5"),"paste:","v"),(L10n.text(.app,"application.installMenuBar.text.6"),"selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:NSSelectorFromString(action),keyEquivalent:key))
        }
        let conversation = NSMenuItem(title:L10n.text(.app,"application.conversation"),action:nil,keyEquivalent:""); let commands = AccentMenuRows.menu(title:L10n.text(.app,"application.conversation")); conversation.submenu = commands; bar.addItem(conversation)
        commands.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.2"),symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        commands.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.3")) { [weak self] in self?.chat?.newConversation(); self?.chat?.showHistory(nil) })
        commands.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.4")) { [weak self] in self?.chat?.chooseFolder() })
        commands.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.5"),symbol:"book") { [weak self] in self?.chat?.showHistory(nil) })
        let windowsItem = NSMenuItem(title:L10n.text(.app,"application.windowsItem"),action:nil,keyEquivalent:"")
        let windows = AccentMenuRows.menu(title:L10n.text(.app,"application.windowsItem")); windowsItem.submenu = windows; bar.addItem(windowsItem)
        windows.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.6"),symbol:"chart.xyaxis.line") { [weak self] in self?.pet?.showDiagnostics() })
        windows.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.7"),symbol:"exclamationmark.triangle") {RecoveryWindow.revealAll()})
        windows.addItem(NSMenuItem(title:L10n.text(.app,"application.installMenuBar.title"),action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        windows.addItem(.separator()); NSApp.windowsMenu = windows
        bar.showProvidedImages(); NSApp.mainMenu = bar
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        TextContextMenu.updateEditMenu(menu,for:NSApp.keyWindow)
        menu.showProvidedImages()
        AccentMenuRows.shared.prepare(menu)
    }
    func menu(_ menu:NSMenu,willHighlight item:NSMenuItem?) {AccentMenuRows.shared.menu(menu,willHighlight:item)}

    @objc func updateNames() {
        let name = PetPreferences.shared.appName
        let menu = NSApp.mainMenu?.items.first?.submenu
        menu?.item(withTag:101)?.title = L10n.text(.app,"application.about")+name
        menu?.item(withTag:102)?.title = L10n.text(.app,"application.quit")+name
    }
    @objc func showSettings() {pet?.showSettings()}
    func showWorkspaceStatusSettings(_ sender:Any?) {
        pet?.showSettings(section:.messages,groupTitle:MessageSettingsPage.workspaceStatusGroupTitle)
    }
    @objc func showAbout() {pet?.showSettings(section:.about)}
    @objc func systemWillTerminate() {explicitQuit = true}
    @objc func quitFromMenu() {explicitQuit = true; FollowSessions.markManualExit(); prepareForTermination()}
    @objc func closeInterface() {
        // 原生模态窗口与 sheet 均走取消路径，不触发确认或危险操作。
        if let modal = NSApp.modalWindow {
            if let panel = modal as? NSSavePanel {panel.cancel(nil)}
            else {NSApp.abortModal(); modal.orderOut(nil)}
            return
        }
        let candidate = [NSApp.keyWindow,NSApp.mainWindow].compactMap {$0}.first {$0.isVisible || $0.isMiniaturized}
            ?? InterfaceWindows.shared.frontmost
        guard let window = candidate else {return}
        if let sheet = window.attachedSheet ?? (window.isSheet ? window : nil) {
            if let panel = sheet as? NSSavePanel {panel.cancel(nil)}
            else {sheet.sheetParent?.endSheet(sheet,returnCode:.cancel); sheet.orderOut(nil)}
        } else if window === chat?.ui.composer {chat?.ui.hideComposer()}
        else if window.styleMask.contains(.closable) {window.performClose(nil)}
        else if window.canBecomeKey {window.close()}
    }
    @objc func reveal() {
        if NSApp.isHidden {NSApp.unhideWithoutActivation()}
        pet?.revealFromReopen()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reveal()
        // 保留已有普通窗口召回，不重新打开已关闭的设置或历史。
        InterfaceWindows.shared.recall()
        return false
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(MenuAction(L10n.text(.app,"application.settings"),symbol:"gearshape") { [weak self] in self?.pet?.showSettings() })
        menu.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.6")) { [weak self] in self?.pet?.showDiagnostics() })
        menu.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.5"),symbol:"book") { [weak self] in self?.chat?.showHistory(nil) })
        if RecoveryWindow.hasIssues {menu.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.7")) {RecoveryWindow.revealAll()})}
        menu.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.2"),symbol:"bubble.left.and.bubble.right") { [weak self] in self?.chat?.toggleComposer() })
        return menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
    private func prepareForTermination() {
        UpdateChecker.shared.cancel()
        if quitReady || (pet == nil && chat == nil) {
            quitReady = true
            finishTermination()
            return
        }
        guard !quitInProgress else {return}
        quitInProgress = true
        sync?.close()
        // 淡出与原任务清理并行；退出等待处于 modalPanel 模式时，DispatchQueue.main 不会被消费。
        let pending = DispatchGroup()
        if let pet {pending.enter(); pet.prepareForExit {pending.leave()}}
        if let chat {pending.enter(); chat.shutdown {pending.leave()}}
        pending.notify(queue:.global(qos:.userInitiated)) { [weak self] in
            RunLoop.main.perform(inModes:[.common,.modalPanel]) {
                guard let self else {return}
                self.quitReady = true
                self.finishTermination()
            }
        }
    }
    private func finishTermination() {
        if awaitingTerminateReply {
            awaitingTerminateReply = false
            NSApp.reply(toApplicationShouldTerminate:true)
        } else {
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Dock 的系统“退出”只关闭界面；完整退出必须来自桌宠的显式退出入口。
        if !explicitQuit {closeInterface(); return .terminateCancel}
        if quitReady || (pet == nil && chat == nil) {return .terminateNow}
        awaitingTerminateReply = true
        prepareForTermination()
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        monitorKeyboard?.cancel(); monitorKeyboard = nil
        TerminalMonitor.active?.write(.app,L10n.text(.app,"application.applicationWillTerminate.text"))
        if ownsInstance {lifecycle.finish()}
        sync?.close(); pet?.close(); NotificationCenter.default.removeObserver(self); DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let localEvents {NSEvent.removeMonitor(localEvents)}
        if instanceFD >= 0 {close(instanceFD)}
    }
}
if Array(CommandLine.arguments.dropFirst()) == ["--codex-permission-request"] {
    // 注册命令以 exec 启动，父进程是发起 Hook 的 Codex。人设与终端 CLI 各走自己的审批。
    if let desktop = try? DesktopQueue.Destination.running(),desktop.belongsToDesktop(getppid()) {
        do {try DesktopPermissionHook.run()}
        catch {FileHandle.standardError.write(Data(L10n.text(.app,"application.applicationWillTerminate.text.2").utf8))}
    }
} else if CommandLine.arguments.contains("--follow") {FollowLauncher.run()}
else {
    // AppKit 原生 tooltip 的延迟单位为毫秒；仅写当前应用域。
    UserDefaults.standard.set(200,forKey:"NSInitialToolTipDelay")
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
