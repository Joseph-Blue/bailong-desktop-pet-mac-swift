import AppKit

// 参照作者 chat_backend.PERSONA，仅作用于桌宠创建的任务会话。
let persona = L10n.text(.conversation,"chatController.persona.text")

final class ChatController {
    let pet: PetController
    let store: HistoryStore
    let ui:ChatInterface
    private let workspacePanel = WorkspaceStatusPanel()
    let connection = CodexConnection()
    var selected: Conversation // 历史窗口浏览目标
    var composerSelection:Conversation?
    var composerKind:ConversationKind = .persona
    var recentComposerTargets = [ConversationKind:String]()
    var unstartedConversations = [Conversation]()
    var allConversations:[Conversation] {store.conversations+unstartedConversations}
    var running: (Conversation,Turn)?
    private var clearingWorkspace = false
    var cancelled = false, closing = false
    private var messagesState = TaskMessageAccumulator()
    private var tokenAccumulator = TurnTokenAccumulator()
    var reminderClock:TaskReminderClock?
    private var interruptInFlight = false
    var currentActivity:TaskActivity? {messagesState.currentActivity}
    var saveError: String?
    var updateTimer: Timer?
    var saveTimer: Timer?
    private var shutdownTimer: Timer?
    lazy var requestCoordinator = RequestCoordinator(chat:self)
    private lazy var quotaCoordinator = QuotaCoordinator(pet:pet,connection:connection,
        directory:{ [unowned self] in self.composerSelection?.cwd ?? self.selected.cwd },
        isClosing:{ [unowned self] in self.closing })
    func quota() {quotaCoordinator.query()}
    lazy var modelLoaders:[ChatEntry:ChatModelLoader] = [.composer:ChatModelLoader(connection:connection),.history:ChatModelLoader(connection:connection)]
    var onFinishedShutdown: (() -> Void)?
    var onHistoryDeleted: (Conversation) -> Void = {_ in}
    private let titleQueue = DispatchQueue(label:L10n.text(.conversation,"chatController.titleQueue.label"),qos:.utility)
    private var titleRequests = [String:UUID]()
    private var historyInputPage = [String]()
    private var historyInputRequest = UUID()
    var desktopTaskReadStatus:String? = L10n.text(.conversation,"chatController.quota.text")
    lazy var desktopSession:DesktopConversationSession = {
        let session = DesktopConversationSession(store:store,preferences:pet.preferences,
            canSend:{ [unowned self] in self.running == nil },isClosing:{ [unowned self] in self.closing })
        session.onSubmitted = { [weak self] key,text,entry in
            guard let self else {return}
            let cleared = self.ui.clearSubmittedDraft(key:key,fromComposer:entry == .composer,text:text)
            if cleared && entry == .composer {self.ui.hideComposer()}
        }
        session.onChange = { [weak self] in self?.refresh() }; session.onPersist = { [weak self] in self?.persist() }
        return session
    }()
    func refreshDesktopSettingsIfNeeded() {
        let visible = (ui.history.isVisible ? [selected] : []) + (ui.composerVisible ? [composerSelection].compactMap {$0} : [])
        desktopSession.refreshSettings(visible)
    }
    private func reportHistoryReadFailure(_ error:Error) {
        RecoveryWindow.show(id:"history-read",report:RecoveryReport(title:L10n.text(.conversation,"chatController.reportHistoryReadFailure.title"),message:L10n.text(.conversation,"chatController.reportHistoryReadFailure.message"),module:L10n.text(.conversation,"chatController.reportHistoryReadFailure.text"),operation:L10n.text(.conversation,"chatController.reportHistoryReadFailure.text.2"),error:error),actionTitle:L10n.text(.conversation,"chatController.reportHistoryReadFailure.actionTitle")) { [weak self] in
            guard let self else {return}
            do {try self.reloadHistory(); RecoveryWindow.resolve("history-read")}
            catch {self.reportHistoryReadFailure(error)}
        }
    }
    func reloadHistory() throws {
        guard running == nil && !desktopSession.hasPendingSend else {throw PetFailure(message:L10n.text(.conversation,"chatController.reloadHistory.message"))}
        let key = selected.key, composerKey = composerSelection?.key
        try store.reload(recording:pet.preferences.bool("recordHistory"))
        ui.invalidateHistoryDisplay()
        selected = store.conversations.first(where:{$0.key == key}) ?? store.conversations.last ?? store.create(cwd:pet.preferences.defaultWorkspace.path)
        composerSelection = allConversations.first {$0.key == composerKey}
        refresh(); loadVisibleModels()
    }
    func clearLocalData() throws {
        guard !clearingWorkspace else {throw PetFailure(message:L10n.text(.conversation,"chatController.clearLocalData.message"))}
        guard running == nil && !desktopSession.hasPendingSend else {throw PetFailure(message:L10n.text(.conversation,"chatController.clearLocalData.message.2"))}
        saveTimer?.invalidate(); saveTimer = nil
        try store.clear()
        unstartedConversations.removeAll(); recentComposerTargets.removeAll()
        selected = store.create(cwd:LocalStorage.workspace.path); composerSelection = selected; composerKind = .persona
        UserDefaults.standard.removeObject(forKey:ComposerDestination.defaultsKey)
        modelLoaders.values.forEach {$0.invalidate()}
        ui.clearDrafts(); desktopSession.clear()
        pet.bubble.resolveQuestions(); pet.bubble.discardCards()
        pet.preferences.reset(Array(PetPreferences.defaults.keys))
        persist()
    }
    func clearBuiltInWorkspace(completion:@escaping (Result<Void,Error>) -> Void) {
        guard !clearingWorkspace else {completion(.failure(PetFailure(message:L10n.text(.conversation,"chatController.clearBuiltInWorkspace.message")))); return}
        guard running == nil,pet.activeTasks.isEmpty,!desktopSession.hasPendingSend else {
            completion(.failure(PetFailure(message:L10n.text(.conversation,"chatController.clearBuiltInWorkspace.message.2")))); return
        }
        clearingWorkspace = true
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let result = Result {try LocalStorage.clearBuiltInWorkspace()}
            DispatchQueue.main.async {
                self?.clearingWorkspace = false
                completion(result)
            }
        }
    }
    init(pet: PetController) throws {
        self.pet = pet; store = try HistoryStore(recording:pet.preferences.bool("recordHistory"))
        ui = ChatInterface(models:ChatModelSettings(),preferences:pet.preferences)
        let workspace = Paths.data.appendingPathComponent("Workspace")
        try FileManager.default.createDirectory(at:workspace,withIntermediateDirectories:true)
        selected = store.conversations.last(where:{!$0.external}) ?? store.create(cwd:pet.preferences.defaultWorkspace.path)
        composerSelection = selected; recentComposerTargets[.persona] = selected.key
        if let saved = ComposerDestination(defaults:.standard) {
            composerKind = saved.kind
            composerSelection = saved.resolve(in:store.conversations) ?? (saved.kind == .persona ? selected : nil)
            recentComposerTargets[saved.kind] = composerSelection?.key
        }
        pet.settings.historyRecoveryReason = { [weak self] in self?.store.readOnlyReason }
        pet.settings.onReloadHistory = { [weak self] in try self?.reloadHistory() }
        pet.settings.onClearDefaultWorkspace = { [weak self] completion in
            guard let self else {completion(.failure(PetFailure(message:L10n.text(.conversation,"chatController.message")))); return}
            self.clearBuiltInWorkspace(completion:completion)
        }
        pet.settings.historyExportExtension = { [weak self] in self?.store.exportExtension ?? "json" }
        ui.onReleaseHistory = { [weak self] in
            self?.store.clearBodyCache(); self?.historyInputPage = []; self?.historyInputRequest = UUID()
        }
        ui.onHistoryPage = { [weak self] conversation,turns in self?.loadHistoryInputs(conversation,turns:turns) }
        pet.settings.onExportHistory = { [weak self] url in try self?.store.exportOriginal(to:url) }
        store.onError = { [weak self] error in
            guard let self else{return}
            if self.store.isReadOnly {
                self.refresh()
                TerminalMonitor.active?.write(.history,L10n.text(.conversation,"chatController.self.text")+TerminalMonitor.errorCode(error),.error)
                self.reportHistoryReadFailure(error)
                return
            }
            TerminalMonitor.active?.write(.history,L10n.text(.conversation,"chatController.self.text.2")+TerminalMonitor.errorCode(error),.error)
            self.saveError = error.localizedDescription; self.ui.status.stringValue = L10n.text(.conversation,"chatController.text"); self.ui.status.isHidden = false
            guard !self.closing else {return}
            RecoveryWindow.show(id:"history-save",report:RecoveryReport(title:L10n.text(.conversation,"chatController.title"),message:L10n.text(.conversation,"chatController.message.2"),module:L10n.text(.conversation,"chatController.reportHistoryReadFailure.text"),operation:L10n.text(.conversation,"chatController.text.2"),error:error),actionTitle:L10n.text(.conversation,"chatController.actionTitle")) { [weak self] in self?.store.retrySave() }
        }
        store.onSaved = { [weak self] in
            guard let self,self.saveError != nil else {return}
            TerminalMonitor.active?.write(.history,L10n.text(.conversation,"chatController.self.text.3"),.success)
            self.saveError = nil; RecoveryWindow.resolve("history-save"); self.refresh()
        }
        ui.onSubmit = { [weak self] key,text,entry in self?.submit(text,to:key,entry:entry) }
        ui.onStop = { [weak self] key in
            guard let self else {return}
            if self.desktopSession.preparing(key) {self.desktopSession.cancelPreparation(key)}
            else if self.running?.0.key == key {self.stop()}
        }
        ui.onNew = { [weak self] entry in self?.newConversation(entry:entry) }
        ui.onNewDefault = { [weak self] entry in self?.newDefaultConversation(entry:entry) }
        ui.onFolder = { [weak self] entry in self?.chooseFolder(entry:entry) }
        ui.onMode = { [weak self] mode in self?.selectComposerMode(mode) }
        ui.onComposerSelect = { [weak self] key in self?.selectConversation(key,entry:.composer) }
        ui.onOpenWorkspace = {url in FinderFileReveal.openDirectory(url)}
        ui.onRevealFolder = { [weak self] in
            guard let self else{return}
            FinderFileReveal.openDirectory(URL(fileURLWithPath:self.selected.cwd,isDirectory:true))
        }
        for entry in [ChatEntry.composer,.history] {
            ui.modelSettings(entry).onLoad = { [weak self] force in self?.loadModels(entry:entry,force:force) }
        }
        ui.onGoCodex = { [weak self] in CodexConnection.openConversation(self?.selected.threadID) }
        ui.onCheckDelivery = { [weak self] key,entry in
            guard let self,let conversation = self.allConversations.first(where:{$0.key == key}) else {return}
            self.desktopSession.checkDelivery(conversation,parent:entry == .composer ? self.ui.composer : self.ui.history)
        }
        ui.onRename = { [weak self] key,title in self?.renameHistory(key,title:title) }
        ui.onSyncTitle = { [weak self] key in self?.syncHistoryTitle(key) }
        ui.onDelete = { [weak self] key in self?.deleteHistory(key) }
        ui.onComposerHistory = { [weak self] in
            guard let self else {return}; self.showHistory(self.composerSelection?.key)
        }
        ui.onRetrySettings = { [weak self] entry in
            guard let self,let key = self.ui.targetKey(entry),let conversation = self.allConversations.first(where:{$0.key == key}),conversation.external else {return}
            self.desktopSession.refreshSettings(conversation,force:true); self.refresh()
        }
        ui.onOpenHistory = { [weak self] in self?.loadModels(entry:.history) }
        ui.onComposerResize = { [weak self] in self?.pet.placeBubble() }
        ui.onSelect = { [weak self] key in self?.selectConversation(key,entry:.history) }
        ui.onHide = { [weak self] in self?.pet.composerVisible = false; self?.composerSide = nil; self?.pet.placeBubble() }
        ui.isPetInteraction = { [weak self] event in
            guard let self else {return false}
            guard let window = event.window else {return false}
            return window === self.pet.window || window === self.pet.bubble.window || window === self.pet.status.button?.window
        }
        pet.composerFrame = { [weak self] in self?.ui.composerFrame }
        pet.bubble.fileLinkDirectory = { [weak self] in
            guard let self,let key = self.pet.bubble.relatedConversation,
                  let conversation = self.store.conversations.first(where:{$0.key == key}),!conversation.cwd.isEmpty else {return nil}
            return URL(fileURLWithPath:conversation.cwd,isDirectory:true)
        }
        connection.event = { [weak self] method,p in self?.receive(method,p) }
        connection.request = { [weak self] id,method,p in self?.requestCoordinator.enqueue(id,method,p) }
        connection.disconnected = { [weak self] error in if self?.running != nil {self?.finish("interrupted",error:CodexErrorMessage.encode(["message":error.localizedDescription,"code":"localConnectionDisconnected"]))} }
        pet.cliDiagnostics = { [weak self] in
            guard let self else { return L10n.text(.conversation,"chatController.text.3") }
            return self.connection.diagnostics + L10n.text(.conversation,"chatController.text.4") + (self.running?.1.status ?? L10n.text(.conversation,"chatController.text.5"))
        }
        pet.onComposer = { [weak self] in self?.toggleComposer() }
        pet.onDismissComposer = { [weak self] in
            guard let self,!self.ui.presentingFolderPicker,self.ui.composer.attachedSheet == nil else {return}
            self.ui.hideComposer()
        }
        pet.onHistory = { [weak self] key in self?.showHistory(key) }
        workspacePanel.onShowRequested = { [weak self] in self?.showWorkspace() }
        workspacePanel.onHide = { [weak pet] in pet?.placeBubble() }
        pet.workspaceFrame = { [weak self] in self?.workspacePanel.frame }
        pet.onWorkspace = { [weak self] in
            guard let self else {return}
            let next = !self.pet.preferences.bool("gitWindowEnabled")
            if next {self.pet.reveal()}
            self.pet.preferences.set(next,for:"gitWindowEnabled")
        }
        pet.workspaceProvider = { [weak self] key in
            guard let self,let conversation = self.allConversations.first(where:{$0.key == key}) else {return nil}
            return (conversation,self.running?.0.key == key || self.desktopSession.observedTurns.contains {conversation.threadID != nil && $0.threadID == conversation.threadID && $0.active})
        }
        pet.onReply = { [weak self] key in
            guard let self,let conversation = self.store.conversations.first(where:{$0.key == key}) else {return}
            self.selectConversation(conversation.key,entry:.composer)
            self.openComposerForUser()
        }
        pet.onCodex = { [weak self] key in
            if let self, let (conversation,turn) = self.running, conversation.key == key,
               ["waitingForInput","waitingForApproval"].contains(turn.status), let request = self.requestCoordinator.alert {
                let parent = request.window.sheetParent ?? self.approvalParent()
                if parent === self.ui.history {
                    InterfaceWindows.shared.focus(parent)
                } else {
                    if parent.isMiniaturized {parent.deminiaturize(nil)}
                    NSApp.activate(ignoringOtherApps:true)
                    parent.makeKeyAndOrderFront(nil)
                }
                request.window.makeKeyAndOrderFront(nil); return
            }
            CodexConnection.openConversation(self?.store.conversations.first(where:{$0.key == key})?.threadID)
        }
        pet.onQuota = { [weak self] in self?.quota() }
        pet.bubble.taskProvider = { [weak self] in
            guard let self else {return BubbleTaskOverview(status:L10n.text(.conversation,"chatController.text.6"))}
            // 执行中取实时来源，不能从历史快照的旧状态推断当前任务。
            var tasks = self.desktopSession.observedTurns.filter {!self.store.deletedThreads.contains($0.threadID)}.map {task in
                let conversation = self.store.conversations.first {$0.external && $0.threadID == task.threadID}
                let edits = task.fileEdits.isEmpty ? conversation?.turns.first {$0.key == task.key || $0.id == task.turnID || $0.date == task.start}?.fileEdits ?? [] : task.fileEdits
                return BubbleTaskSummary(key:task.key,title:conversation?.title ?? task.title,threadID:task.threadID,status:task.status,start:task.start,end:task.end,
                    turnID:task.turnID,activity:task.activity,connectionFailed:task.connectionFailed,directory:task.directory.isEmpty ? conversation?.cwd ?? "" : task.directory,fileEdits:edits)
            }
            let observed = Set(tasks.compactMap(\.threadID))
            for conversation in self.store.conversations {
                guard !conversation.external || !observed.contains(conversation.threadID ?? ""),
                      let turn = conversation.turns.max(by:{$0.date < $1.date}) else {continue}
                let live = !conversation.external && self.running?.1 === turn
                guard live || TaskOutcome.terminalStatuses.contains(turn.status) else {continue}
                tasks.append(BubbleTaskSummary(key:turn.key,title:conversation.title,threadID:conversation.threadID,status:turn.status,start:turn.date,end:turn.completedAt,activity:live ? (turn.status == "waitingForApproval" ? TaskActivity.waiting(approval:true) : turn.status == "waitingForInput" ? TaskActivity.waiting(approval:false) : self.messagesState.currentActivity) : nil,connectionFailed:!live && turn.status != "completed" && CodexErrorMessage(turn.error)?.category == .network,directory:conversation.cwd,fileEdits:turn.fileEdits ?? []))
            }
            // 去重只作用于实时任务行，不合并任何消息或历史卡片。
            tasks = Dictionary(grouping:tasks,by:{$0.threadID ?? $0.key}).values.compactMap {$0.max(by:{$0.start < $1.start})}
            let active = tasks.filter(\.active).sorted {$0.start < $1.start}
            let recent = tasks.filter {TaskOutcome.terminalStatuses.contains($0.status)}
                .sorted {($0.end ?? $0.start) > ($1.end ?? $1.start)}
            return BubbleTaskOverview(tasks:active+recent,status:self.desktopTaskReadStatus)
        }
        pet.onGeometry = { [weak self] in self?.positionComposer(); self?.positionWorkspace() }
        pet.onVisibility = { [weak self] shown in
            if shown {
                guard let self,!self.workspacePanel.visible else {return}
                self.showWorkspace()
            }
            else {self?.ui.hideComposer(); self?.workspacePanel.hide()}
        }
        pet.onPreferencesChanged = { [weak self] in
            guard let self else {return}
            self.store.setRecording(self.pet.preferences.bool("recordHistory")); self.refresh()
        }
        refresh()
        DispatchQueue.main.async { [weak self] in self?.showWorkspace() }
    }
    var personalizedPersona: String {
        let preferences = pet.preferences
        // 名字按 JSON 字符串编码，仅作为角色称呼数据，不拼入可执行配置。
        let data: [String:String] = [L10n.text(.conversation,"chatController.data.text"):preferences.petName,L10n.text(.conversation,"chatController.data.text.2"):preferences.ownerName,L10n.text(.conversation,"chatController.data.text.3"):preferences.ownerName]
        let encoded = String(data:try! JSONEncoder().encode(data),encoding:.utf8)!
        return persona + L10n.text(.conversation,"chatController.encoded.text") + encoded
    }
    private func loadHistoryInputs(_ conversation:Conversation,turns:[Turn]) {
        let page = [conversation.key]+turns.map(\.key)
        guard page != historyInputPage else {return}
        historyInputPage = page; historyInputRequest = UUID()
        guard let thread = conversation.threadID else {return}
        let missing = turns.filter {conversation.external && $0.input.isEmpty && store.canEnrichInput($0,in:conversation)}.compactMap(\.id)
        let missingUsage = turns.filter {!activeStatuses.contains($0.status) && $0.tokenUsage == nil && store.canEnrichInput($0,in:conversation)}.compactMap(\.id)
        guard !missing.isEmpty || !missingUsage.isEmpty else {return}
        let request = historyInputRequest, key = conversation.key
        // 复用已有只读队列，只补当前一页，不新增轮询或全库回填。
        titleQueue.async { [weak self] in
            let inputs = Result {try missing.isEmpty ? [:] : DesktopHistoryReader.userInputs(thread:thread,turns:missing)}
            let usages = Result {try missingUsage.isEmpty ? [:] : DesktopHistoryReader.tokenUsages(thread:thread,turns:missingUsage)}
            DispatchQueue.main.async {
                guard let self,!self.closing,self.historyInputRequest == request,
                      self.ui.history.isVisible,!self.ui.history.isMiniaturized,
                      let current = self.store.conversations.first(where:{$0.key == key}) else {return}
                var changed = false
                switch inputs {
                case .success(let inputs):
                    for turn in current.turns where missing.contains(turn.id ?? "") && turn.input.isEmpty && self.store.canEnrichInput(turn,in:current) {
                        if let id = turn.id,let input = inputs[id] {turn.input = input; changed = true}
                    }
                case .failure(let error):
                    self.ui.historyStatus.stringValue = L10n.text(.conversation,"chatController.loadHistoryInputs.text")+error.localizedDescription
                }
                switch usages {
                case .success(let values):
                    for turn in current.turns where self.store.canEnrichInput(turn,in:current) {
                        guard let id = turn.id,let value = values[id],turn.tokenUsage == nil else {continue}
                        if turn.tokenUsage != value.usage || turn.tokenUsageError != value.error {
                            turn.tokenUsage = value.usage; turn.tokenUsageError = value.error; changed = true
                        }
                    }
                case .failure(let error):self.ui.historyStatus.stringValue = L10n.text(.conversation,"chatController.failure")+error.localizedDescription
                }
                if changed {self.persist()}
            }
        }
    }
    func refresh() {
        ui.refresh(allConversations,selected:selected,historyState:inputState(selected,kind:selected.kind),composerState:inputState(composerSelection,kind:composerKind))
        pet.refreshWorkspaceBars()
        if workspacePanel.visible {
            if let conversation = allConversations.first(where:{$0.key == workspacePanel.conversationKey}) {
                workspacePanel.update(conversation:conversation,executing:inputState(conversation,kind:conversation.kind).executing)
            } else {showWorkspace()}
        }
    }

    private func inputState(_ conversation:Conversation?,kind:ConversationKind) -> ChatInputState {
        var state = ChatInputState(conversation:conversation,kind:kind)
        state.runningTitle = running?.0.title; state.ownsRunningTask = conversation != nil && running?.0 === conversation
        state.stopping = state.ownsRunningTask && cancelled
        state.executing = state.ownsRunningTask || (conversation?.external == true && desktopSession.observedTurns.contains {$0.threadID == conversation?.threadID && $0.active})
        state.newConversation = conversation.map {candidate in candidate.turns.isEmpty && unstartedConversations.contains {$0 === candidate}} ?? false
        state.readOnly = store.isReadOnly
        if let conversation,conversation.external {
            state.sending = desktopSession.sending(conversation.key); state.unconfirmed = desktopSession.unconfirmed(conversation.key)
            state.desktopPreparing = desktopSession.preparing(conversation.key)
            if pet.preferences.projectSendChannel == .modern {
                let target = desktopSession.target(conversation)
                state.modelNote = .viewInCodex
                state.replyMode = target?.mode == .start ? .start : nil
                state.desktopReady = true
                state.requiresCodexForSteering = state.executing && conversation.threadID != nil
                state.replyNote = desktopSession.replyNote(conversation.key,turnID:target?.id)
                if state.replyNote == nil && !state.requiresCodexForSteering {
                    state.replyNote = state.replyMode == .start ? L10n.text(.conversation,"chatController.inputState.text") : L10n.text(.conversation,"chatController.inputState.text.2")
                }
                return state
            }
            state.replyMode = desktopSession.target(conversation)?.mode
            state.modelSettings = desktopSession.modelSettings(conversation.key)
            state.modelNote = desktopSession.modelNote(conversation.key); state.replyNote = desktopSession.replyNote(conversation.key)
            state.desktopReady = desktopSession.canReply(conversation.key)
        }
        return state
    }
    func approvalParent() -> NSWindow {
        if ui.history.isVisible { return ui.history }
        if !ui.composerVisible { presentComposer() }
        return ui.composer
    }
    func persist() { store.save(); refresh() }
    private func renameHistory(_ key:String,title:String) {
        guard let conversation = allConversations.first(where:{$0.key == key}) else {return}
        if unstartedConversations.contains(where:{$0 === conversation}) {
            conversation.title = title; conversation.localTitle = title; refresh(); return
        }
        titleRequests.removeValue(forKey:key)
        do {try store.setTitle(title,for:conversation,manual:true); refresh()}
        catch {showError(L10n.text(.conversation,"chatController.renameHistory.error"),error)}
    }
    private func syncHistoryTitle(_ key:String) {
        guard let conversation = store.conversations.first(where:{$0.key == key}),let id = conversation.threadID else {return}
        let request = UUID(); titleRequests[key] = request
        titleQueue.async { [weak self] in
            let result = Result {try DesktopHistoryReader.readTitles([id])[id]}
            DispatchQueue.main.async {
                guard let self,self.titleRequests[key] == request,self.store.conversations.contains(where:{$0 === conversation}) else {return}
                self.titleRequests.removeValue(forKey:key)
                do {
                    guard let title = try result.get(),!title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                        throw PetFailure(message:L10n.text(.conversation,"chatController.syncHistoryTitle.message"))
                    }
                    try self.store.setTitle(title,for:conversation,manual:false); self.refresh()
                } catch {showError(L10n.text(.conversation,"chatController.syncHistoryTitle.error"),error)}
            }
        }
    }
    private func deleteHistory(_ key:String) {
        guard let conversation = allConversations.first(where:{$0.key == key}) else {return}
        guard running?.0 !== conversation else {showError(L10n.text(.conversation,"chatController.deleteHistory.error"),PetFailure(message:L10n.text(.conversation,"chatController.deleteHistory.message"))); return}
        guard !desktopSession.sending(key) else {showError(L10n.text(.conversation,"chatController.deleteHistory.error"),PetFailure(message:L10n.text(.conversation,"chatController.deleteHistory.message.2"))); return}
        do {
            if !unstartedConversations.contains(where:{$0 === conversation}) {try store.delete(conversation)}
            titleRequests.removeValue(forKey:key); ui.discardHistory(key); onHistoryDeleted(conversation)
            desktopSession.forget(key)
            pet.bubble.discardCards(conversation:key)
            unstartedConversations.removeAll {$0.key == key}
            recentComposerTargets = recentComposerTargets.filter {$0.value != key}
            if selected === conversation {selected = store.conversations.last ?? store.create(cwd:pet.preferences.defaultWorkspace.path)}
            if composerSelection === conversation {
                composerSelection = nil
                ComposerDestination.save(composerKind,conversation:nil,in:.standard)
                if composerKind == .persona {selectComposerMode(.persona)}
            }
            refresh()
        } catch {showError(L10n.text(.conversation,"chatController.deleteHistory.error.2"),error)}
    }
    func toggleComposer() {
        if ui.composerVisible {pet.onDismissComposer(); return}
        openComposerForUser()
    }
    private func openComposerForUser() {
        pet.dismissBubblesForComposer()
        if ui.composerVisible {ui.composer.makeFirstResponder(ui.composerEditor); return}
        presentComposer()
    }
    private func presentComposer() {
        refresh()
        pet.composerVisible = true
        pet.reveal(); pet.undock(); pet.interaction()
        ui.prepareComposer()
        positionComposer(); loadModels(entry:.composer)
        ui.showComposer()
        pet.placeBubble(); refreshDesktopSettingsIfNeeded()
    }
    private var composerSide:BubblePlacement.Side?
    func positionComposer() {
        guard pet.composerVisible else{return}
        let screenFrame = pet.screen.visibleFrame
        let result = BubblePlacement.resolve(size:ui.composerFrame.size,pet:pet.visiblePetFrame,
            screen:screenFrame,preferred:[.above,.below,.right,.left],previous:composerSide)
        composerSide = result.side; ui.moveComposer(to:result.frame.origin,screenFrame:screenFrame)
    }

    private func showWorkspace(_ key:String? = nil) {
        guard !closing,!pet.hidden,pet.preferences.bool("gitWindowEnabled") else {return}
        let requested = key ?? (pet.bubble.visible ? pet.bubble.relatedConversation : nil) ?? workspacePanel.conversationKey
        let conversation = allConversations.first {$0.key == requested} ?? (ui.composerVisible ? composerSelection : ui.history.isVisible ? selected : nil) ?? running?.0 ?? allConversations.max(by:{$0.lastActivity < $1.lastActivity}) ?? selected
        workspacePanel.update(conversation:conversation,executing:inputState(conversation,kind:conversation.kind).executing)
        workspacePanel.show(near:pet.visiblePetFrame,screen:pet.screen.visibleFrame,avoiding:ui.composerVisible ? [ui.composerFrame] : [])
        pet.placeBubble()
    }
    private func positionWorkspace() {
        workspacePanel.position(near:pet.visiblePetFrame,screen:pet.screen.visibleFrame,avoiding:ui.composerVisible ? [ui.composerFrame] : [])
    }

    // 两种会话共用用户卡片入口；发送、审批及停止仍由各自连接负责。
    func showUserMessage(_ text:String,in conversation:Conversation,timing:TaskTiming,messageID:String,steering:Bool = false,select:Bool = false) {
        showWorkspace(conversation.key)
        let title = pet.preferences.statusLine(steering ? "taskSteeringTemplate" : conversation.external ? "desktopTaskReceivedTemplate" : "taskReceivedTemplate")
        pet.say(title,body:UserInputText.display(text),kind:"task",thread:conversation.key,
            purpose:.progress,personalizeTitle:false,animateHeading:timing.finished == nil,timing:timing,
            messageID:messageID,selectCard:select,isUserInput:true)
    }
    func submit(_ text:String,to key:String,entry:ChatEntry) {
        guard !clearingWorkspace else {showError(L10n.text(.conversation,"chatController.submit.error"),PetFailure(message:L10n.text(.conversation,"chatController.submit.message"))); return}
        guard !store.isReadOnly else {pet.showSettings(section:.advanced); return}
        guard let c = allConversations.first(where:{$0.key == key}),ui.targetKey(entry) == key else {return}
        let closeComposer = entry == .composer
        if c.external {desktopSession.submit(text,to:c,entry:entry); return}
        let settings = ui.modelSettings(entry)
        guard running == nil && !closing && !settings.loading && settings.error == nil else{return}
        let modelParams: [String:Any]
        do {modelParams = try settings.parameters()}
        catch {showError(L10n.text(.conversation,"chatController.submit.error.2"),error); return}
        let configuredProvider = settings.configuredProvider
        ui.clearFailure()
        if unstartedConversations.contains(where:{$0 === c}) {
            unstartedConversations.removeAll {$0 === c}; store.conversations.append(c)
        }
        let turn = Turn(); turn.input = text; c.turns.append(turn)
        if c.turns.count == 1 && c.localTitle == nil { c.title = String(text.prefix(36)) }
        tokenAccumulator = TurnTokenAccumulator()
        running = (c,turn); cancelled = false; interruptInFlight = false; messagesState = TaskMessageAccumulator()
        reminderClock = TaskReminderClock(now:Date().timeIntervalSince1970)
        ui.clearSubmittedDraft(key:c.key,fromComposer:closeComposer,text:text)
        if closeComposer {ui.hideComposer()}
        let trace = TerminalMonitor.active?.begin(.persona,context:TerminalMonitor.context(c.key,turn:turn.key),event:L10n.text(.conversation,"chatController.trace.event"))
        pet.taskStarted("own"); showUserMessage(text,in:c,timing:.init(start:turn.date,key:"own",activityKey:turn.key),messageID:"task-received",select:true); persist()
        connection.connect { [weak self, weak turn] error in
            guard let self, let turn, self.running?.1 === turn else{return}
            if let error {trace?.step(L10n.text(.conversation,"chatController.error.text")+TerminalMonitor.errorCode(error),.error); self.finish("failed",error:error.localizedDescription); return}
            if self.cancelled {self.finish("interrupted"); return}
            trace?.step(L10n.text(.conversation,"chatController.error.text.2"))
            var params: [String:Any] = ["cwd":c.cwd,"sandbox":"workspace-write","approvalPolicy":"on-request","approvalsReviewer":"user","developerInstructions":self.personalizedPersona]
            if let model = modelParams["model"] {params["model"] = model}
            if c.threadID == nil {
                params["historyMode"] = "legacy"
                params["modelProvider"] = configuredProvider
            }
            self.connection.prepareThread(c.threadID,params:params) { [weak self, weak turn] result in
                guard let self, let turn, self.running?.1 === turn else{return}
                switch result {
                case .failure(let error):
                    trace?.step(L10n.text(.conversation,"chatController.error.text.3")+TerminalMonitor.errorCode(error),.error)
                    self.finish("failed",error:error.localizedDescription)
                case .success(let prepared):
                    let thread = prepared.id
                    c.threadID = thread
                    if let provider = prepared.provider {c.modelProvider = provider}
                    if self.cancelled { self.finish("interrupted"); return }
                    if let provider = c.modelProvider,let configuredProvider,provider != configuredProvider {
                        self.finish("failed",error:L10n.format(.conversation,"chatController.submit.text",String(describing:ModelPresentation.provider(provider) ?? provider)))
                        return
                    }
                    turn.model = modelParams["model"] as? String ?? prepared.model
                    turn.effort = modelParams["effort"] as? String ?? (prepared.model == turn.model ? prepared.effort : nil)
                    var turnParams: [String:Any] = ["threadId":thread,"cwd":c.cwd,"input":[["type":"text","text":text]],"approvalPolicy":"on-request","approvalsReviewer":"user","summary":"concise","sandboxPolicy":["type":"workspaceWrite","writableRoots":[c.cwd],"networkAccess":false]]
                    turnParams.merge(modelParams) {_,selected in selected}
                    trace?.step(L10n.text(.conversation,"chatController.labels.text")+TerminalMonitor.tag(thread))
                    self.connection.call("turn/start",turnParams) { [weak self, weak turn] result in
                        guard let self, let turn, self.running?.1 === turn else{return}
                        switch result {
                        case .success(let value):
                            turn.id = (value["turn"] as? [String:Any])?["id"] as? String
                            trace?.step(L10n.text(.conversation,"chatController.value.text")+(turn.id.map {L10n.text(.conversation,"chatController.value.text.2")+TerminalMonitor.tag($0)} ?? ""),.success)
                            turn.status = "running"; if self.cancelled {self.interrupt()}; self.persist()
                        case .failure(let error):
                            let timedOut = (error as? CodexProtocol.Failure)?.isTimeout == true
                            trace?.step((timedOut ? L10n.text(.conversation,"chatController.timedOut.text") : L10n.text(.conversation,"chatController.timedOut.text.2"))+"  ·  "+TerminalMonitor.errorCode(error),timedOut ? .warning : .error)
                            if turn.id != nil || (error as? CodexProtocol.Failure)?.isTimeout == true { turn.status = "unknown"; turn.error = error.localizedDescription; self.persist() }
                            else {self.finish("failed",error:error.localizedDescription)}
                        }
                    }
                }
            }
        }
    }
    func receive(_ method: String, _ p: [String:Any]) {
        guard let (c,t) = running, p["threadId"] as? String == c.threadID else{return}
        if let id = p["turnId"] as? String, let current = t.id, id != current {return}
        switch method {
        case "turn/started": t.id = (p["turn"] as? [String:Any])?["id"] as? String; t.status = "running"; if cancelled {interrupt()}
        case "thread/tokenUsage/updated":
            guard let current = t.id,p["turnId"] as? String == current else {return}
            tokenAccumulator.receive(p["tokenUsage"]); t.tokenUsage = tokenAccumulator.usage; return
        case "turn/completed":
            guard let turn = p["turn"] as? [String:Any], t.id == nil || t.id == turn["id"] as? String else{return}
            for item in turn["items"] as? [[String:Any]] ?? [] {messagesState.record(item)}
            let status = turn["status"] as? String ?? "unknown", error = CodexErrorMessage.encode(turn["error"])
            updateText(); finish(status,error:error.isEmpty && status == "failed" ? t.error : error); return
        case "error":
            messagesState.receiveError(p)
            if p["willRetry"] as? Bool != true {t.error = CodexErrorMessage.encode(p["error"])}
        default:guard messagesState.receive(method,p) else {return}
        }
        reminderClock?.lastProgress = Date().timeIntervalSince1970
        scheduleUpdate()
    }
    func updateText() {
        guard let turn = running?.1 else {return}
        messagesState.apply(to:turn)
    }
    func scheduleUpdate() {
        if updateTimer != nil {return}
        let timer = Timer(timeInterval:1.0/30,repeats:false) { [weak self] _ in
            guard let self else {return}
            self.updateTimer = nil
            guard let (c,t) = self.running else {return}
            let previousMessageAt = t.lastMessageAt, previousEdits = t.fileEdits
            self.messagesState.apply(to:t)
            let editsChanged = previousEdits != t.fileEdits
            self.ui.refreshTurn(t,in:c,previousMessageAt:previousMessageAt,editsChanged:editsChanged)
            if editsChanged {
                self.pet.refreshWorkspaceBars()
                if self.workspacePanel.visible,self.workspacePanel.conversationKey == c.key {
                    self.workspacePanel.update(conversation:c,executing:true)
                }
            }
            self.scheduleSave()
            guard !["waitingForInput","waitingForApproval"].contains(t.status) else {return}
            if self.messagesState.currentActivity == nil {self.pet.bubble.removeActivity(taskKey:"own")}
            self.presentAgentMessages(conversation:c,turn:t)
            self.pet.showProgressToast(self.messagesState.currentActivity,key:"own",timing:.init(start:t.date,key:"own",activityKey:t.key),thread:c.key)

        }
        updateTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func presentAgentMessages(conversation:Conversation,turn:Turn) {
        for message in messagesState.takeChangedMessages() {
            pet.say(pet.preferences.statusLine(message.isImage ? "taskUpdateTemplate" : "taskReplyTemplate"),body:message.text,kind:"task",thread:conversation.key,personalizeTitle:false,animateHeading:turn.completedAt == nil,
                timing:.init(start:turn.date,key:"own",finished:turn.completedAt,status:turn.completedAt == nil ? nil : turn.status,activityKey:turn.key),messageID:message.id)
            reminderClock?.lastNotice = Date().timeIntervalSince1970
        }
    }
    func scheduleSave() {
        guard saveTimer == nil else{return}
        let timer = Timer(timeInterval:1,repeats:false) { [weak self] _ in self?.saveTimer = nil; self?.store.save() }
        saveTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func finish(_ status: String, error: String = "") {
        guard let (c,t) = running else{return}
        TerminalMonitor.active?.write(.persona,TerminalMonitor.context(c.key,turn:t.key)+L10n.text(.conversation,"chatController.finish.text")+TerminalMonitor.status(status),
                                      status == "completed" ? .success : status == "failed" ? .error : .warning)
        pet.bubble.removeActivity(taskKey:"own"); messagesState.clearActivity()
        updateTimer?.invalidate(); updateTimer = nil; saveTimer?.invalidate(); saveTimer = nil; updateText(); t.status = status; t.error = error; t.completedAt = Date()
        messagesState.finalize(t)
        presentAgentMessages(conversation:c,turn:t)
        let stoppedByUser = cancelled && TaskOutcome.stoppedStatuses.contains(status)
        reminderClock = nil; interruptInFlight = false
        running = nil; requestCoordinator.dismiss(); pet.bubble.resolveQuestions(taskKey:"own"); pet.taskEnded("own",status:status); persist()
        let title = stoppedByUser ? pet.preferences.statusLine("taskStoppedTemplate") : pet.preferences.taskResultLine(status)
        if !error.isEmpty && status != "completed" && !stoppedByUser && !closing {
            let failure = AppFailure.codex(error)
            if composerSelection === c {
                ui.showFailure(failure) { [weak self] in
                    guard let self,self.composerSelection === c else {return}
                    self.ui.restoreInput(t.input,key:c.key,entry:.composer); self.refresh()
                }
            }
            if !pet.hidden {
                pet.quotaActive = false
                pet.bubble.showFailure(failure,scale:Double(pet.bubblePercent)/100,taskStartedAt:t.date,taskFinishedAt:Date(),taskStatus:status)
                pet.placeBubble()
            }
        } else {
            pet.say(title,body:GeneratedImageLink.appending(messagesState.imageLinks,to:t.final),kind:"task",thread:c.key,
                    purpose:status == "completed" ? .result : .attention,personalizeTitle:false,
                    timing:.init(start:t.date,key:"own",finished:t.completedAt,status:status,activityKey:t.key),
                    messageID:messagesState.finalMessageID ?? "result",fileEdits:t.fileEdits ?? [],
                    completionFooter:TurnCompletion(t,completedAt:t.completedAt))
        }
        messagesState = TaskMessageAccumulator()
        if closing {finishShutdown()}
    }
    func stop() {
        guard let (_,turn) = running,!cancelled else {return}
        cancelled = true; requestCoordinator.dismiss(); refresh()
        if turn.id == nil {connection.abortUnconfirmedTask()} else {interrupt()}
    }
    func interrupt() {
        guard let (c,t) = running,let thread = c.threadID,let turn = t.id,!interruptInFlight else{return}
        interruptInFlight = true
        connection.call("turn/interrupt",["threadId":thread,"turnId":turn]) { [weak self,weak t] result in
            guard let self,let t,self.running?.1 === t else {return}
            if case .failure(let error) = result {
                self.interruptInFlight = false; self.cancelled = false; t.error = error.localizedDescription; self.persist()
                showError(L10n.text(.conversation,"chatController.interrupt.error"),error)
            }
        }
    }
    func shutdown(_ completion: @escaping () -> Void) {
        closing = true; onFinishedShutdown = completion
        desktopSession.stopQueueProcesses()
        workspacePanel.hide()
        quotaCoordinator.cancel()
        if running != nil {
            stop()
            let timer = Timer(timeInterval:2,repeats:false) { [weak self] _ in
                self?.shutdownTimer = nil
                if self?.running != nil {self?.finish("interrupted",error:L10n.text(.conversation,"chatController.shutdown.text"))}
            }
            shutdownTimer = timer
            RunLoop.main.add(timer,forMode:.common)
            RunLoop.main.add(timer,forMode:.modalPanel)
        } else {finishShutdown()}
    }
    func finishShutdown() { shutdownTimer?.invalidate(); shutdownTimer = nil; updateTimer?.invalidate(); saveTimer?.invalidate(); connection.close(); store.finish(); ui.hideComposer(); ui.history.orderOut(nil); let completion = onFinishedShutdown; onFinishedShutdown = nil; completion?() }
}
