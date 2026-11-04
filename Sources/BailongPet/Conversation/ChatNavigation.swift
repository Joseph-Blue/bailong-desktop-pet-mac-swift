import AppKit

// 浏览／输入目标切换，不停止任务，不触发发送。实际运行身份仍由 ChatController.running 持有。
extension ChatController {
    func selectConversation(_ key:String,entry:ChatEntry) {
        guard let conversation = allConversations.first(where:{$0.key == key}) else {return}
        if entry == .history {selected = conversation}
        else {
            composerSelection = conversation; composerKind = conversation.kind
            recentComposerTargets[conversation.kind] = key
        }
        loadModels(entry:entry); refresh(); refreshDesktopSettingsIfNeeded()
    }
    func selectComposerMode(_ kind:ConversationKind) {
        composerKind = kind
        let choices = allConversations.filter {$0.kind == kind}
        if let remembered = choices.first(where:{$0.key == recentComposerTargets[kind]}) {
            selectConversation(remembered.key,entry:.composer)
        } else if let latest = choices.max(by:{$0.lastActivity < $1.lastActivity}) {
            selectConversation(latest.key,entry:.composer)
        } else if kind == .persona {newConversation(entry:.composer)}
        else {composerSelection = nil; refresh()}
    }
    func newConversation(cwd:String? = nil,entry:ChatEntry = .history) {
        guard running == nil && !store.isReadOnly else {return}
        let current = entry == .composer ? composerSelection : selected
        let conversation = Conversation()
        conversation.cwd = cwd ?? (current?.external == false ? current?.cwd : nil) ?? LocalStorage.workspace.path
        unstartedConversations.append(conversation)
        selectConversation(conversation.key,entry:entry)
    }
    func chooseFolder(entry:ChatEntry = .history) {
        let target = entry == .composer ? composerSelection : selected
        guard running == nil,!store.isReadOnly,let target,!target.external else {return}
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:target.cwd); panel.prompt = "选择工作区"
        ui.presentingFolderPicker = true
        let parent:NSWindow = entry == .composer ? ui.composer : ui.history
        if entry == .history && !parent.isVisible {ui.openHistory()}
        PanelPresentation.present(panel,relativeTo:parent) { [weak self] response in
            guard let self else {return}; self.ui.presentingFolderPicker = false
            guard response == .OK,let url = panel.url,self.running == nil else {return}
            if target.threadID == nil && target.turns.isEmpty {
                target.cwd = url.path
                self.loadModels(entry:entry,force:true); self.refresh()
            } else {self.newConversation(cwd:url.path,entry:entry)}
        }
    }
    func showHistory(_ key:String?) {
        if let key {selectConversation(key,entry:.history)}
        refresh(); ui.openHistory(); loadModels(entry:.history); refreshDesktopSettingsIfNeeded()
    }
    func loadVisibleModels() {loadModels(entry:.history); loadModels(entry:.composer)}
    func loadModels(entry:ChatEntry,force:Bool = false) {
        let conversation = entry == .composer ? composerSelection : selected
        guard !closing,let conversation,!conversation.external else {return}
        let settings = ui.modelSettings(entry); settings.activate(conversation.key)
        modelLoaders[entry]?.load(directory:conversation.cwd,settings:settings,force:force)
    }
}
