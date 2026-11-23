import AppKit

// 桌面观察器提供的本轮状态，只保留发送和任务概览需要的公开字段。
struct ObservedDesktopTurn {
    let key: String
    let threadID: String
    let turnID: String
    let status: String
    let start: Date
    let end: Date?
    let title: String
    let activity: TaskActivity?
    let connectionFailed: Bool
    let directory:String
    let fileEdits:[FileEditSummary]
    var active: Bool {activeStatuses.contains(status)}
}

// 外部 Codex 会话的发送、待确认和只读设置状态；不持有内置 CodexConnection。
final class DesktopConversationSession {
    enum ModelNotice {
        case awaitingFirstSend, connecting, viewInCodex, failure(String)

        var message:String {
            switch self {
            case .awaitingFirstSend: return L10n.text(.conversation,"desktopConversationSession.awaitingFirstSend")
            case .connecting: return L10n.text(.conversation,"desktopConversationSession.connecting")
            case .viewInCodex: return L10n.text(.conversation,"desktopConversationSession.viewInCodex")
            case .failure(let message): return message
            }
        }
        var canRetry:Bool {
            if case .failure = self {return true}
            return false
        }
    }

    private enum NavigationRecovery {case existingConnection, none}
    private struct ColdPreparation {
        let request:UUID
        let thread:String
        let deadline:Date
        let send:(DesktopReply.PreparedConnection) -> Void
    }
    private let store:HistoryStore
    private let preferences:PetPreferences
    var observedTurns = [ObservedDesktopTurn]()
    private var queueProcesses = [String:Process]()
    private struct UnconfirmedQueueSubmission {
        let request:UUID
        let text:String
        let entry:ChatEntry
    }
    private var unconfirmedQueueSubmissions = [String:UnconfirmedQueueSubmission]()
    private var queuedAfterTurn = [String:String]()
    private let canSend:() -> Bool, isClosing:() -> Bool
    var onChange:() -> Void = {}, onPersist:() -> Void = {}
    var onSubmitted:(String,String,ChatEntry) -> Void = {_,_,_ in}
    var openThreadForReply:(String,@escaping () -> Bool,@escaping (Result<Bool,Error>) -> Void) -> Void = CodexConnection.openConversationForReply
    var queueDestination:() throws -> DesktopQueue.Destination = DesktopQueue.Destination.running
    var reopenThreadForReply:(String,@escaping () -> Bool) -> Void = CodexConnection.reopenConversationForReply
    var coldReopenOffsets:[TimeInterval] = [2.5,7.5,14.0]
    var coldDiscoveryTimeout:TimeInterval = 1.5
    var coldRetryInterval:TimeInterval = 0.25
    var coldTotalTimeout:TimeInterval = 60
    private var desktopSettings = [String:DesktopReply.Settings]()
    private var desktopModelNotes = [String:ModelNotice]()
    private var desktopModelChecked = [String:Date]()
    private var desktopModelRequests = [String:UUID]()
    private var settingsReady = Set<String>()
    private struct PendingSend {
        let id:UUID
        let trace:TerminalMonitor.Send?
        var waitingForQueue = false
    }
    private var desktopSending = [String:PendingSend]()
    private var coldPreparing = [String:ColdPreparation]()
    private var desktopUnconfirmed = Set<String>()
    private var desktopReplyNotes = [String:String]()

    init(store:HistoryStore,preferences:PetPreferences,canSend:@escaping () -> Bool,isClosing:@escaping () -> Bool) {
        self.store = store
        self.preferences = preferences
        self.canSend = canSend; self.isClosing = isClosing
    }
    var hasPendingSend:Bool {!desktopSending.isEmpty}
    func sending(_ key:String) -> Bool {desktopSending[key] != nil}
    func preparing(_ key:String) -> Bool {coldPreparing[key] != nil || desktopSending[key]?.waitingForQueue == true}
    func cancelPreparation(_ key:String) {
        guard preparing(key) else {return}
        coldPreparing.removeValue(forKey:key)
        desktopSending.removeValue(forKey:key)?.trace?.step(L10n.text(.conversation,"desktopConversationSession.cancelPreparation.text.2"),.warning); desktopModelRequests.removeValue(forKey:key)
        desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.cancelPreparation.text"); onChange()
    }
    func unconfirmed(_ key:String) -> Bool {desktopUnconfirmed.contains(key)}
    func replyNote(_ key:String,turnID:String? = nil) -> String? {
        if let note = desktopReplyNotes[key] {return note}
        guard let turnID,queuedAfterTurn[key] == turnID else {return nil}
        return L10n.text(.conversation,"desktopConversationSession.replyNote.text")
    }
    func modelSettings(_ key:String) -> DesktopReply.Settings? {desktopSettings[key]}
    func modelNote(_ key:String) -> ModelNotice? {desktopModelNotes[key]}
    func canReply(_ key:String) -> Bool {settingsReady.contains(key)}
    func forget(_ key:String) {
        cancelPreparation(key)
        desktopSettings.removeValue(forKey:key)
        settingsReady.remove(key)
        queuedAfterTurn.removeValue(forKey:key); unconfirmedQueueSubmissions.removeValue(forKey:key)
        desktopUnconfirmed.remove(key); desktopReplyNotes.removeValue(forKey:key)
        desktopModelNotes.removeValue(forKey:key); desktopModelChecked.removeValue(forKey:key); desktopModelRequests.removeValue(forKey:key)
    }
    func clear() {
        for key in desktopSending.keys.filter(preparing) {cancelPreparation(key)}
        desktopSettings.removeAll()
        settingsReady.removeAll()
        queuedAfterTurn.removeAll(); unconfirmedQueueSubmissions.removeAll()
        desktopUnconfirmed.removeAll(); desktopReplyNotes.removeAll()
        desktopModelNotes.removeAll(); desktopModelChecked.removeAll(); desktopModelRequests.removeAll()
    }
    func target(_ conversation:Conversation) -> (id:String,mode:DesktopReply.Mode,start:Date)? {
        if let live = observedTurns.first(where:{$0.threadID == conversation.threadID}) {
            guard let mode = DesktopReply.mode(for:live.status) else {return nil}
            return (live.turnID,mode,live.start)
        }
        // 读取未完成或失败时，不用旧历史中的执行状态开放插话。
        guard let last = conversation.turns.max(by:{$0.date < $1.date}),let id = last.id,
              DesktopReply.mode(for:last.status) == .start else {return nil}
        return (id,.start,last.date)
    }
    func refreshSettings(_ conversations:[Conversation]) {
        for conversation in conversations where conversation.external {refreshSettings(conversation)}
    }
    func refreshSettings(_ conversation:Conversation,force:Bool = false) {
        guard preferences.projectSendChannel == .legacy,!isClosing(),let thread = conversation.threadID else {return}
        let key = conversation.key
        guard !sending(key),desktopModelRequests[key] == nil,force || Date().timeIntervalSince(desktopModelChecked[key] ?? .distantPast) >= 5 else {return}
        if force {desktopSettings.removeValue(forKey:key); settingsReady.remove(key); desktopModelNotes.removeValue(forKey:key)}
        let request = UUID(); desktopModelRequests[key] = request; desktopModelChecked[key] = Date()
        DesktopReply.prepareConnection(thread:thread,timeout:12) { [weak self,weak conversation] result in
            guard let self,let conversation,!self.isClosing(),self.desktopModelRequests[key] == request else {return}
            self.desktopModelRequests.removeValue(forKey:key)
            guard self.store.conversations.contains(where:{$0 === conversation}) else {return}
            switch result {
            case .success(let connection):
                self.desktopSettings[key] = connection.settings; self.desktopModelNotes.removeValue(forKey:key); self.settingsReady.insert(key)
            case .failure(let error):
                self.desktopSettings.removeValue(forKey:key)
                self.settingsReady.remove(key)
                if error is DesktopSocket.Unavailable || error is DesktopReply.OwnerUnavailable {
                    self.desktopModelNotes[key] = .awaitingFirstSend
                } else {
                    self.desktopModelNotes[key] = .failure(L10n.text(.conversation,"desktopConversationSession.refreshSettings.text")+error.localizedDescription)
                }
            }
            self.onChange()
        }
    }
    func submit(_ text:String,to conversation:Conversation,entry:ChatEntry) {
        let key = conversation.key
        guard !isClosing(),canSend(),desktopSending[key] == nil,!desktopUnconfirmed.contains(key),
              let thread = conversation.threadID,let target = target(conversation) else {return}
        queuedAfterTurn.removeValue(forKey:key)
        if preferences.projectSendChannel == .modern {
            if target.mode == .start {submitQueued(text,to:conversation,entry:entry,thread:thread,previousTurn:target.id)}
            return
        }
        let request = UUID()
        let trace = TerminalMonitor.active?.begin(.ipc,
            context:TerminalMonitor.context(key)+L10n.text(.conversation,"desktopConversationSession.trace.text")+TerminalMonitor.tag(request.uuidString),
            event:target.mode == .steer ? L10n.text(.conversation,"desktopConversationSession.submit.text") : L10n.text(.conversation,"desktopConversationSession.submit.text.2"))
        desktopSending[key] = PendingSend(id:request,trace:trace)
        desktopModelRequests.removeValue(forKey:key)
        desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.connecting"); onChange()
        let needsOpen = !settingsReady.contains(key)
        let send:(NavigationRecovery) -> Void = { [weak self,weak conversation] recovery in
            guard let self,let conversation else {return}
            self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,recovery:recovery,deadline:Date().addingTimeInterval(20))
        }
        if needsOpen {
            openForReply(conversation,thread:thread,request:request) { [weak self,weak conversation] launched in
                guard let self,let conversation else {return}
                if launched {self.prepareColdReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request)}
                else {send(.none)}
            }
        }
        else {send(.existingConnection)}
    }
    private func submitQueued(_ text:String,to conversation:Conversation,entry:ChatEntry,thread:String,previousTurn:String) {
        let key = conversation.key, request = UUID()
        guard let threadID = UUID(uuidString:thread) else {
            desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.submitQueued.text"); onChange(); return
        }
        let trace = TerminalMonitor.active?.begin(.desktopQueue,context:TerminalMonitor.context(key),event:L10n.text(.conversation,"desktopConversationSession.trace.event"))
        desktopSending[key] = PendingSend(id:request,trace:trace,waitingForQueue:true)
        let isCurrent = { [weak self,weak conversation] in
            guard let self,let conversation else {return false}
            return self.isCurrent(conversation,thread:thread,request:request)
        }
        let submitWhenReady:(Result<DesktopQueue.Destination,Error>) -> Void = { [weak self,weak conversation] result in
            guard let self,let conversation,isCurrent() else {return}
            do {
                let destination = try result.get()
                guard !destination.app.isTerminated,self.canSend(),let current = self.target(conversation),
                      current.id == previousTurn,current.mode == .start else {
                    throw PetFailure(message:L10n.text(.conversation,"desktopConversationSession.submitQueued.message"))
                }
                self.desktopSending[key]?.waitingForQueue = false
                trace?.step(L10n.text(.conversation,"desktopConversationSession.current.text"))
                self.desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.submitQueued.text.2"); self.onChange()
                self.queueProcesses[key] = try DesktopQueue.submit(cli:destination.cli,store:destination.store,thread:threadID,text:text) { [weak self] result in
                    guard let self,isCurrent() else {return}
                    self.queueProcesses.removeValue(forKey:key)
                    self.desktopSending.removeValue(forKey:key)
                    self.applyQueueReceipt(result,to:key,after:previousTurn,request:request,text:text,entry:entry,trace:trace)
                }
            } catch {
                self.desktopSending.removeValue(forKey:key)
                trace?.step(L10n.text(.conversation,"desktopConversationSession.labels.text")+TerminalMonitor.errorCode(error),.warning)
                self.desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.submitQueued.text.3")+error.localizedDescription
                self.onChange()
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+coldTotalTimeout) { [weak self,weak conversation] in
            guard let self,let conversation,isCurrent(),self.preparing(key) else {return}
            self.failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.submitQueued.text.4"),error:PetFailure(message:L10n.text(.conversation,"desktopConversationSession.submitQueued.message.2")))
        }
        // 队列由桌面端共享；即使进程已运行，也要打开本次发送的会话才能在该页处理消息。
        openForReply(conversation,thread:thread,request:request) { [weak self] _ in
            guard let self else {return}
            trace?.step(L10n.text(.conversation,"desktopConversationSession.self.text"))
            self.desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.submitQueued.text.5"); self.onChange()
            DesktopQueue.prepare(thread:thread,previousTurn:previousTurn,id:threadID,destination:self.queueDestination,
                                 isCurrent:isCurrent,completion:submitWhenReady)
        }
    }
    func applyQueueReceipt(_ result:Result<UUID,Error>,to key:String,after previousTurn:String,request:UUID,
                           text:String,entry:ChatEntry,trace:TerminalMonitor.Send?) {
        switch result {
        case .success(let id):
            trace?.step(L10n.text(.conversation,"desktopConversationSession.id.text")+TerminalMonitor.tag(id.uuidString),.success)
            desktopReplyNotes.removeValue(forKey:key)
            queuedAfterTurn[key] = previousTurn
            onSubmitted(key,text,entry)
        case .failure(let error):
            trace?.step(L10n.text(.conversation,"desktopConversationSession.error.text"),.warning)
            desktopReplyNotes[key] = error.localizedDescription
            unconfirmedQueueSubmissions[key] = UnconfirmedQueueSubmission(request:request,text:text,entry:entry)
            desktopUnconfirmed.insert(key)
        }
        onChange()
    }
    func stopQueueProcesses() {
        for task in queueProcesses.values where task.isRunning {kill(task.processIdentifier,SIGKILL)}
        queueProcesses.removeAll()
    }
    private func isCurrent(_ conversation:Conversation,thread:String,request:UUID) -> Bool {
        !isClosing() && desktopSending[conversation.key]?.id == request && conversation.threadID == thread &&
            store.conversations.contains(where:{$0 === conversation})
    }
    private func failBeforeSend(_ conversation:Conversation,stage:String,error:Error) {
        let key = conversation.key
        coldPreparing.removeValue(forKey:key)
        desktopSending.removeValue(forKey:key)?.trace?.step(stage+"  ·  "+TerminalMonitor.errorCode(error),.error)
        settingsReady.remove(key); desktopSettings.removeValue(forKey:key)
        desktopModelNotes[key] = .failure(error.localizedDescription)
        desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.failBeforeSend.text")+error.localizedDescription; onChange()
    }
    private func prepareColdReply(_ text:String,to conversation:Conversation,entry:ChatEntry,thread:String,
                                  target:(id:String,mode:DesktopReply.Mode,start:Date),request:UUID) {
        guard isCurrent(conversation,thread:thread,request:request) else {return}
        let key = conversation.key
        desktopModelRequests.removeValue(forKey:key)
        desktopSettings.removeValue(forKey:key); settingsReady.remove(key)
        coldPreparing[key] = ColdPreparation(request:request,thread:thread,deadline:Date().addingTimeInterval(coldTotalTimeout)) { [weak self,weak conversation] connection in
            guard let self,let conversation else {return}
            self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,recovery:.none,deadline:Date().addingTimeInterval(20),prepared:connection)
        }
        desktopSending[key]?.trace?.step(L10n.text(.conversation,"desktopConversationSession.conversation.text"))
        desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.prepareColdReply.text"); onChange()
        for offset in coldReopenOffsets {
            DispatchQueue.main.asyncAfter(deadline:.now()+offset) { [weak self,weak conversation] in
                guard let self,let conversation,let pending = self.coldPreparing[key],
                      pending.request == request,pending.deadline > Date(),
                      !self.settingsReady.contains(key),
                      self.isCurrent(conversation,thread:thread,request:request) else {return}
                self.reopenThreadForReply(thread) { [weak self,weak conversation] in
                    guard let self,let conversation,self.coldPreparing[key]?.request == request else {return false}
                    return self.isCurrent(conversation,thread:thread,request:request)
                }
            }
        }
        probeColdReply(conversation,request:request)
    }
    private func probeColdReply(_ conversation:Conversation,request:UUID) {
        let key = conversation.key
        guard let pending = coldPreparing[key],pending.request == request,
              isCurrent(conversation,thread:pending.thread,request:request) else {return}
        let remaining = pending.deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.submitQueued.text.4"),error:PetFailure(message:L10n.text(.conversation,"desktopConversationSession.probeColdReply.message"))); return
        }
        let timeout = max(2,min(8,Int(ceil(remaining))))
        let discovery = min(coldDiscoveryTimeout,remaining)
        DesktopReply.prepareConnection(thread:pending.thread,timeout:timeout,discoveryTimeout:discovery,wakeOnOwnerBroadcast:true,qos:.userInitiated) { [weak self,weak conversation] result in
            guard let self,let conversation,let current = self.coldPreparing[key],
                  current.request == request,self.isCurrent(conversation,thread:current.thread,request:request) else {return}
            switch result {
            case .success(let connection):
                self.coldPreparing.removeValue(forKey:key)
                self.desktopSettings[key] = connection.settings
                self.desktopModelNotes.removeValue(forKey:key)
                self.settingsReady.insert(key)
                self.desktopModelChecked[key] = Date()
                guard current.deadline > Date() else {
                    self.failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.submitQueued.text.4"),error:PetFailure(message:L10n.text(.conversation,"desktopConversationSession.probeColdReply.message"))); return
                }
                self.onChange()
                current.send(connection)
            case .failure(let error):
                self.desktopSettings.removeValue(forKey:key)
                self.settingsReady.remove(key)
                if DesktopReply.connectionPending(error),current.deadline.timeIntervalSinceNow > self.coldRetryInterval {
                    self.desktopModelNotes[key] = .connecting
                    self.onChange()
                    DispatchQueue.main.asyncAfter(deadline:.now()+self.coldRetryInterval) { [weak self,weak conversation] in
                        guard let self,let conversation else {return}
                        self.probeColdReply(conversation,request:request)
                    }
                } else if DesktopReply.connectionPending(error) {
                    self.failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.submitQueued.text.4"),error:PetFailure(message:L10n.text(.conversation,"desktopConversationSession.probeColdReply.message")+error.localizedDescription))
                } else {
                    self.failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.probeColdReply.text"),error:error)
                }
            }
        }
    }
    private func openForReply(_ conversation:Conversation,thread:String,request:UUID,completion:@escaping (Bool) -> Void) {
        guard isCurrent(conversation,thread:thread,request:request) else {return}
        let key = conversation.key
        desktopSending[key]?.trace?.step(L10n.text(.conversation,"desktopConversationSession.key.text"))
        desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.openForReply.text"); onChange()
        openThreadForReply(thread,{ [weak self,weak conversation] in
            guard let self,let conversation else {return false}
            return self.isCurrent(conversation,thread:thread,request:request)
        }) { [weak self,weak conversation] result in
            guard let self,let conversation,self.isCurrent(conversation,thread:thread,request:request) else {return}
            switch result {
            case .success(let launched):completion(launched)
            case .failure(let error):self.failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.failure"),error:error)
            }
        }
    }
    private func sendReply(_ text:String,to conversation:Conversation,entry:ChatEntry,thread:String,
                           target:(id:String,mode:DesktopReply.Mode,start:Date),request:UUID,recovery:NavigationRecovery,deadline:Date,prepared:DesktopReply.PreparedConnection? = nil) {
        guard isCurrent(conversation,thread:thread,request:request) else {return}
        guard canSend(),let latest = self.target(conversation),latest.id == target.id,latest.mode == target.mode else {
            failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.sendReply.text"),error:PetFailure(message:L10n.text(.conversation,"desktopConversationSession.sendReply.message"))); return
        }
        let key = conversation.key, started = Date()
        desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.sendReply.text.2"); onChange()
        DesktopReply.submit(thread:thread,previousTurn:target.id,cwd:conversation.cwd,text:text,mode:target.mode,connectionDeadline:deadline,prepared:prepared,onConnected:{ [weak self,weak conversation] in
            guard let self,let conversation,self.isCurrent(conversation,thread:thread,request:request) else {return}
            self.desktopSending[key]?.trace?.step(target.mode == .steer ? L10n.text(.conversation,"desktopConversationSession.conversation.text.2") : L10n.text(.conversation,"desktopConversationSession.conversation.text.3"))
            self.desktopReplyNotes[key] = L10n.text(.conversation,"desktopConversationSession.sendReply.text.3"); self.onChange()
        }) { [weak self,weak conversation] result in
            guard let self,let conversation,self.isCurrent(conversation,thread:thread,request:request) else {return}
            // 只重试未提交消息的连接阶段；真正发送后的任何错误均不进入此分支。
            if case .failure(let error) = result,error is DesktopReply.ConnectionPending {
                if recovery != .none {
                    self.openForReply(conversation,thread:thread,request:request) { [weak self,weak conversation] launched in
                        guard let self,let conversation else {return}
                        if launched {self.prepareColdReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request)}
                        else {self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,recovery:.none,deadline:Date().addingTimeInterval(20))}
                    }
                } else if deadline.timeIntervalSinceNow > 0.25 {
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [weak self,weak conversation] in
                        guard let self,let conversation else {return}
                        self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,recovery:.none,deadline:deadline)
                    }
                } else {
                    self.failBeforeSend(conversation,stage:L10n.text(.conversation,"desktopConversationSession.sendReply.text.4"),error:PetFailure(message:L10n.text(.conversation,"desktopConversationSession.sendReply.message.2")+error.localizedDescription))
                }
                return
            }
            let trace = self.desktopSending.removeValue(forKey:key)?.trace
            switch result {
            case .success(let receipt):
                trace?.step(L10n.text(.conversation,"desktopConversationSession.receipt.text")+TerminalMonitor.tag(receipt.turnID),.success)
                // 观察器与发送回执均以真实 turn ID 合并，避免生成两条记录。
                if let turn = conversation.turns.first(where:{$0.id == receipt.turnID}) {
                    turn.lastMessageAt = started
                    if target.mode == .steer {turn.input += (turn.input.isEmpty ? "" : "\n\n")+L10n.text(.conversation,"desktopConversationSession.sendReply.text.5")+text}
                    else {turn.input = text}
                }
                else {
                    let turn = Turn(); turn.id = receipt.turnID; turn.input = text; turn.owned = false
                    turn.date = target.mode == .steer ? target.start : started; turn.status = receipt.status; turn.lastMessageAt = started; conversation.turns.append(turn)
                }
                self.onSubmitted(key,text,entry)
                self.desktopReplyNotes.removeValue(forKey:key)
                if case .awaitingFirstSend? = self.desktopModelNotes[key] {self.refreshSettings(conversation,force:true)}
                self.onPersist()
            case .failure(let error):
                if let unconfirmed = error as? DesktopReply.Unconfirmed {
                    trace?.step(L10n.text(.conversation,"desktopConversationSession.unconfirmed.text")+TerminalMonitor.errorCode(unconfirmed.underlying),.warning)
                    self.desktopUnconfirmed.insert(key)
                } else {
                    trace?.step(L10n.text(.conversation,"desktopConversationSession.unconfirmed.text.2")+TerminalMonitor.errorCode(error),.error)
                }
                self.desktopReplyNotes[key] = error.localizedDescription
                // 回执只更新原会话状态。用户已切换或关闭窗口时不弹模态框、激活应用。
                self.onChange()
            }
        }
    }
    func checkDelivery(_ conversation:Conversation,parent:NSWindow) {
        let key = conversation.key
        guard desktopUnconfirmed.contains(key) else {return}
        CodexConnection.openConversation(conversation.threadID)
        let alert = NSAlert(); alert.messageText = L10n.text(.conversation,"desktopConversationSession.checkDelivery.messageText")
        if let submission = unconfirmedQueueSubmissions[key] {
            alert.messageText = L10n.text(.conversation,"desktopConversationSession.checkDelivery.messageText.2")
            alert.informativeText = L10n.text(.conversation,"desktopConversationSession.checkDelivery.informativeText")
            alert.addButton(withTitle:L10n.text(.conversation,"desktopConversationSession.checkDelivery.button"))
            alert.addButton(withTitle:L10n.text(.conversation,"desktopConversationSession.checkDelivery.button.2"))
            alert.addButton(withTitle:L10n.text(.conversation,"desktopConversationSession.checkDelivery.button.3"))
            alert.applyAccent()
            alert.beginSheetModal(for:parent) { [weak self] response in
                guard let self,self.unconfirmedQueueSubmissions[key]?.request == submission.request,
                      self.store.conversations.contains(where:{$0 === conversation}),
                      response == .alertSecondButtonReturn || response == .alertThirdButtonReturn else {return}
                self.unconfirmedQueueSubmissions.removeValue(forKey:key)
                self.desktopUnconfirmed.remove(key); self.desktopReplyNotes.removeValue(forKey:key)
                if response == .alertSecondButtonReturn {self.onSubmitted(key,submission.text,submission.entry)}
                self.onChange()
            }
            return
        }
        alert.informativeText = L10n.format(.conversation,"desktopConversationSession.checkDelivery.informativeText.2",String(describing:conversation.title))
        alert.addButton(withTitle:L10n.text(.conversation,"desktopConversationSession.checkDelivery.button")); alert.addButton(withTitle:L10n.text(.conversation,"desktopConversationSession.checkDelivery.button.4")); alert.applyAccent()
        alert.beginSheetModal(for:parent) { [weak self] response in
            guard response == .alertSecondButtonReturn,let self,self.store.conversations.contains(where:{$0 === conversation}) else {return}
            self.desktopUnconfirmed.remove(key); self.desktopReplyNotes.removeValue(forKey:key); self.onChange()
        }
    }
}
