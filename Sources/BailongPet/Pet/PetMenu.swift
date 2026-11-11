import AppKit

// 菜单只装配现有动作，不拥有动画、手势或任务状态。
enum PetMenu {
    static func make(for pet:PetController,includeVisibility:Bool = false,random:@escaping () -> Void) -> NSMenu {
        let menu = NSMenu(); menu.delegate = pet
        if includeVisibility {
            let visibility = MenuAction("") { [weak pet] in
                guard let pet else {return}
                if pet.hidden || NSApp.isHidden {
                    if NSApp.isHidden {NSApp.unhideWithoutActivation()}
                    pet.revealFromReopen()
                } else {pet.manualHidden = true; pet.applyVisibility()}
            }
            visibility.identifier = .init("petVisibility")
            menu.addItem(visibility); menu.addItem(.separator())
            refreshVisibility(in:menu,pet:pet)
        }
        func submenu(_ title:String,symbol:String) -> NSMenu {
            let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
            item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            item.image?.isTemplate = true
            let child = NSMenu(title:title); item.submenu = child; menu.addItem(item); return child
        }
        menu.addItem(MenuAction("打开对话",symbol:"bubble.left.and.bubble.right") { [weak pet] in pet?.onComposer() })
        menu.addItem(MenuAction("历史会话",symbol:"book") { [weak pet] in pet?.onHistory(nil) })
        menu.addItem(MenuAction("查询额度",symbol:"dollarsign") { [weak pet] in pet?.soundOnce(); pet?.onQuota() })
        let codex = MenuAction("跳转到 Codex") {CodexConnection.openDesktop()}
        codex.image = AppIcons.openAI?.copy() as? NSImage
        codex.image?.size = NSSize(width:16,height:16)
        menu.addItem(codex)
        menu.addItem(.separator())
        menu.addItem(MenuAction("播放随机动画",symbol:"shuffle") {random()})
        let animations = submenu("播放动作",symbol:"play.rectangle")
        for (name,clips,symbol) in [("待机动作",pet.catalog.idles+pet.catalog.extras,"figure.stand"),("互动动作",pet.catalog.variants,"figure.play"),("工作动作",pet.catalog.work,"briefcase"),("移动动作",pet.catalog.movementAnimations,"figure.walk.motion")] {
            let item = NSMenuItem(title:name,action:nil,keyEquivalent:""), group = NSMenu(title:name)
            item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            item.image?.isTemplate = true
            for clip in clips {group.addItem(MenuAction(clip.title) { [weak pet] in pet?.preview(clip) })}
            item.submenu = group; animations.addItem(item)
        }
        let switches = submenu("快捷开关",symbol:"switch.2")
        switches.addItem(MenuAction("自主移动",checked:pet.autoMove,symbol:"figure.walk") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.autoMove,for:"autoMove") })
        switches.addItem(MenuAction("播放音效",checked:pet.soundEnabled,symbol:"speaker.wave.2") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.soundEnabled,for:"soundEnabled") })
        switches.addItem(MenuAction("任务气泡提醒",checked:pet.taskBubbles,symbol:"bell.badge") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.taskBubbles,for:"taskBubbles") })
        switches.addItem(MenuAction("全屏时自动隐藏",checked:pet.autoFullscreen,symbol:"eye.slash") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.autoFullscreen,for:"autoFullscreen") })
        switches.addItem(.separator())
        switches.addItem(MenuAction("启动设置…",symbol:"power") { [weak pet] in pet?.showSettings(section:.general) })
        menu.addItem(.separator())
        menu.addItem(MenuAction("更改桌宠、气泡与文字大小…",symbol:"textformat.size") { [weak pet] in pet?.showSettings(section:.appearance) })
        menu.addItem(MenuAction("更改桌宠称呼和台词…",symbol:"person.text.rectangle") { [weak pet] in pet?.showSettings(section:.identity) })
        menu.addItem(MenuAction("设置…",symbol:"gearshape") { [weak pet] in pet?.showSettings() })
        let tools = submenu("工具与帮助",symbol:"questionmark.circle")
        tools.addItem(MenuAction("任务同步状态…",symbol:"arrow.triangle.2.circlepath") { [weak pet] in guard let pet else{return}; let a = NSAlert(); a.messageText = "Codex 任务同步状态"; a.informativeText = pet.syncStatus(); a.icon = NSImage(systemSymbolName:"arrow.triangle.2.circlepath",accessibilityDescription:"任务同步"); a.addButton(withTitle:"知道了"); a.applyAccent(); a.runModal() })
        tools.addItem(MenuAction("性能统计…",symbol:"chart.xyaxis.line") { [weak pet] in pet?.showDiagnostics() })
        tools.addItem(.separator())
        tools.addItem(MenuAction("检查更新…",symbol:"arrow.down.circle") {UpdateWindow.show()})
        tools.addItem(MenuAction("关于"+pet.preferences.appName+"…",symbol:"info.circle") { [weak pet] in pet?.showSettings(section:.about) })
        menu.addItem(.separator())
        menu.addItem(MenuAction("退出"+pet.preferences.appName,symbol:"rectangle.portrait.and.arrow.right") { [weak pet] in pet?.onQuit() })
        menu.showProvidedImages()
        return menu
    }
    static func refreshVisibility(in menu:NSMenu,pet:PetController) {
        guard let item = menu.items.first,item.identifier?.rawValue == "petVisibility" else {return}
        let show = pet.hidden || NSApp.isHidden
        item.title = show ? "显示桌宠" : "隐藏桌宠"
        item.image = NSImage(systemSymbolName:show ? "eye" : "eye.slash",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        item.image?.isTemplate = true
    }
}
