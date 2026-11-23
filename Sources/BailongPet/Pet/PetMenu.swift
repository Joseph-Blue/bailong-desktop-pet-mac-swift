import AppKit

// 菜单只装配现有动作，不拥有动画、手势或任务状态。
enum PetMenu {
    static func make(for pet:PetController,includeVisibility:Bool = false,random:@escaping () -> Void) -> NSMenu {
        let menu = NSMenu(); menu.delegate = pet
        func visibilityItem() -> NSMenuItem {
            let visibility = MenuAction("") { [weak pet] in
                guard let pet else {return}
                if pet.hidden || NSApp.isHidden {
                    if NSApp.isHidden {NSApp.unhideWithoutActivation()}
                    pet.revealFromReopen()
                } else {pet.manualHidden = true; pet.applyVisibility()}
            }
            visibility.identifier = .init("petVisibility")
            return visibility
        }
        if includeVisibility {
            menu.addItem(visibilityItem()); menu.addItem(.separator())
        }
        func submenu(_ title:String,symbol:String) -> NSMenu {
            let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
            item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            item.image?.isTemplate = true
            let child = NSMenu(title:title); item.submenu = child; menu.addItem(item); return child
        }
        menu.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem.2"),symbol:"bubble.left.and.bubble.right") { [weak pet] in pet?.onComposer() })
        menu.addItem(MenuAction(L10n.text(.app,"menu.history"),symbol:"book") { [weak pet] in pet?.onHistory(nil) })
        menu.addItem(MenuAction(L10n.text(.app,"menu.checkUsage"),symbol:AppIcons.quotaSymbol) { [weak pet] in pet?.soundOnce(); pet?.onQuota() })
        let codex = MenuAction(L10n.text(.app,"menu.openCodex")) {CodexConnection.openDesktop()}
        codex.image = AppIcons.openAI?.copy() as? NSImage
        codex.image?.size = NSSize(width:16,height:16)
        menu.addItem(codex)
        menu.addItem(.separator())
        menu.addItem(MenuAction(L10n.text(.app,"menu.randomAnimation"),symbol:"shuffle") {random()})
        let animations = submenu(L10n.text(.app,"menu.playAnimation"),symbol:"play.rectangle")
        for (name,clips,symbol) in [(L10n.text(.app,"menu.idleAnimations"),pet.catalog.idles+pet.catalog.extras,"figure.stand"),(L10n.text(.app,"menu.interactionAnimations"),pet.catalog.variants,"figure.play"),(L10n.text(.app,"menu.workAnimations"),pet.catalog.work,"briefcase"),(L10n.text(.app,"menu.movementAnimations"),pet.catalog.movementAnimationsForDisplay,"figure.walk.motion")] {
            let item = NSMenuItem(title:name,action:nil,keyEquivalent:""), group = NSMenu(title:name)
            item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
            item.image?.isTemplate = true
            for clip in clips {group.addItem(MenuAction(clip.title) { [weak pet] in pet?.preview(clip) })}
            item.submenu = group; animations.addItem(item)
        }
        let switches = submenu(L10n.text(.app,"menu.quickToggles"),symbol:"switch.2")
        switches.autoenablesItems = false
        switches.addItem(MenuAction(L10n.text(.app,"menu.autoMove"),checked:pet.autoMove,symbol:"figure.walk.motion") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.autoMove,for:"autoMove") })
        switches.addItem(MenuAction(L10n.text(.app,"menu.soundEffects"),checked:pet.soundEnabled,symbol:"speaker.wave.2") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.soundEnabled,for:"soundEnabled") })
        switches.addItem(MenuAction(L10n.text(.app,"menu.taskAlerts"),checked:pet.taskBubbles,symbol:"bell.badge") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.taskBubbles,for:"taskBubbles") })
        let progressToast = MenuAction(L10n.text(.app,"menu.progressToast"),checked:pet.preferences.bool("progressToastEnabled"),symbol:"bubble.left") { [weak pet] in
            guard let pet else {return}
            pet.preferences.set(!pet.preferences.bool("progressToastEnabled"),for:"progressToastEnabled")
        }
        progressToast.isEnabled = pet.taskBubbles && pet.preferences.bool("progressBubbles")
        switches.addItem(progressToast)
        let workspace = MenuAction("") { [weak pet] in pet?.onWorkspace() }
        workspace.identifier = .init("workspaceStatus")
        workspace.image = GitIcons.git; switches.addItem(workspace)
        switches.addItem(MenuAction(L10n.text(.app,"menu.hideInFullScreen"),checked:pet.autoFullscreen,symbol:"square.arrowtriangle.4.outward") { [weak pet] in guard let pet else{return}; pet.preferences.set(!pet.autoFullscreen,for:"autoFullscreen") })
        switches.addItem(.separator())
        switches.addItem(MenuAction(L10n.text(.app,"menu.startupSettings"),symbol:"power") { [weak pet] in pet?.showSettings(section:.general) })
        switches.addItem(.separator())
        switches.addItem(visibilityItem())
        menu.addItem(.separator())
        menu.addItem(MenuAction(L10n.text(.app,"menu.resize"),symbol:"textformat.size") { [weak pet] in pet?.showSettings(section:.appearance) })
        menu.addItem(MenuAction(L10n.text(.app,"menu.namesAndDialogue"),symbol:"person.text.rectangle") { [weak pet] in pet?.showSettings(section:.identity) })
        menu.addItem(MenuAction(L10n.text(.app,"application.settings"),symbol:"gearshape") { [weak pet] in pet?.showSettings() })
        let tools = submenu(L10n.text(.app,"menu.toolsAndHelp"),symbol:"questionmark.circle")
        tools.addItem(MenuAction(L10n.text(.app,"menu.taskSyncStatus"),symbol:"arrow.triangle.2.circlepath") { [weak pet] in guard let pet else{return}; let a = NSAlert(); a.messageText = L10n.text(.app,"menu.taskSyncTitle"); a.informativeText = pet.syncStatus(); a.icon = NSImage(systemSymbolName:"arrow.triangle.2.circlepath",accessibilityDescription:L10n.text(.app,"menu.taskSyncAccessibility")); a.addButton(withTitle:L10n.text(.app,"menu.gotIt")); a.applyAccent(); a.runModal() })
        tools.addItem(MenuAction(L10n.text(.app,"menu.diagnostics"),symbol:"chart.xyaxis.line") { [weak pet] in pet?.showDiagnostics() })
        tools.addItem(.separator())
        tools.addItem(MenuAction(L10n.text(.app,"application.installMenuBar.menuItem"),symbol:"arrow.down.circle") {UpdateWindow.show()})
        tools.addItem(MenuAction(L10n.text(.app,"application.about")+pet.preferences.appName+"…",symbol:"info.circle") { [weak pet] in pet?.showSettings(section:.about) })
        menu.addItem(.separator())
        menu.addItem(MenuAction(L10n.text(.app,"application.quit")+pet.preferences.appName,symbol:"rectangle.portrait.and.arrow.right") { [weak pet] in pet?.onQuit() })
        refreshVisibility(in:menu,pet:pet)
        menu.showProvidedImages()
        switches.showProvidedImages()
        return menu
    }
    static func refreshVisibility(in menu:NSMenu,pet:PetController) {
        let show = pet.hidden || NSApp.isHidden
        let workspaceTitle = pet.preferences.bool("gitWindowEnabled") ? L10n.text(.app,"menu.hideWorkspaceStatus") : L10n.text(.app,"menu.showWorkspaceStatus")
        let petTitle = show ? L10n.text(.app,"menu.showPet") : L10n.text(.app,"menu.hidePet")
        let petIcon = NSImage(systemSymbolName:show ? "eye" : "eye.slash",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:14,weight:.regular))
        petIcon?.isTemplate = true
        let items = menu.items + menu.items.compactMap(\.submenu).flatMap(\.items)
        for item in items {
            switch item.identifier?.rawValue {
            case "workspaceStatus": item.title = workspaceTitle
            case "petVisibility": item.title = petTitle; item.image = petIcon
            default: break
            }
        }
    }
}
