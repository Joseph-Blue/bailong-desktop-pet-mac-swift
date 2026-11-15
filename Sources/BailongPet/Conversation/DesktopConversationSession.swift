import AppKit

// 外部 Codex 会话的发送、待确认和只读设置状态；不持有内置 CodexConnection。
final class DesktopConversationSession {
    private let store:HistoryStore
    private let tasks:() -> [BubbleTaskSummary]
    private let canSend:() -> Bool, isClosing:() -> Bool
    var onChange:() -> Void = {}, onPersist:() -> Void = {}
    var onSubmitted:(String,String,ChatEntry) -> Void = {_,_,_ in}
    private var desktopSettings = [String:DesktopReply.Settings]()
    private var desktopModelNotes = [String:String]()
    private var desktopModelChecked = [String:Date]()
    private var desktopModelRequests = [String:UUID]()
    private var settingsReady = Set<String>()
    private var desktopSending = [String:UUID]()
    private var desktopUnconfirmed = Set<String>()
    private var desktopReplyNotes = [String:String]()

    init(store:HistoryStore,tasks:@escaping () -> [BubbleTaskSummary],canSend:@escaping () -> Bool,isClosing:@escaping () -> Bool) {
        self.store = store; self.tasks = tasks
        self.canSend = canSend; self.isClosing = isClosing
    }
    var hasPendingSend:Bool {!desktopSending.isEmpty}
    func sending(_ key:String) -> Bool {desktopSending[key] != nil}
    func unconfirmed(_ key:String) -> Bool {desktopUnconfirmed.contains(key)}
    func replyNote(_ key:String) -> String? {desktopReplyNotes[key]}
    func modelSettings(_ key:String) -> DesktopReply.Settings? {desktopSettings[key]}
    func modelNote(_ key:String) -> String? {desktopModelNotes[key]}
    func canReply(_ key:String) -> Bool {settingsReady.contains(key)}
    func forget(_ key:String) {
        desktopSettings.removeValue(forKey:key)
        settingsReady.remove(key)
        desktopUnconfirmed.remove(key); desktopReplyNotes.removeValue(forKey:key)
        desktopModelNotes.removeValue(forKey:key); desktopModelChecked.removeValue(forKey:key); desktopModelRequests.removeValue(forKey:key)
    }
    func clear() {
        desktopSettings.removeAll()
        settingsReady.removeAll()
        desktopUnconfirmed.removeAll(); desktopReplyNotes.removeAll()
        desktopModelNotes.removeAll(); desktopModelChecked.removeAll(); desktopModelRequests.removeAll()
    }
    func target(_ conversation:Conversation) -> (id:String,mode:DesktopReply.Mode,start:Date)? {
        if let live = tasks().first(where:{$0.threadID == conversation.threadID}) {
            guard let id = live.turnID,let mode = DesktopReply.mode(for:live.status) else {return nil}
            return (id,mode,live.start)
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
        guard !isClosing(),let thread = conversation.threadID else {return}
        let key = conversation.key
        guard !sending(key),desktopModelRequests[key] == nil,force || Date().timeIntervalSince(desktopModelChecked[key] ?? .distantPast) >= 5 else {return}
        if force {desktopSettings.removeValue(forKey:key); settingsReady.remove(key); desktopModelNotes.removeValue(forKey:key)}
        let request = UUID(); desktopModelRequests[key] = request; desktopModelChecked[key] = Date()
        DesktopReply.readSettings(thread:thread) { [weak self] result in
            guard let self,!self.isClosing(),self.desktopModelRequests[key] == request else {return}
            self.desktopModelRequests.removeValue(forKey:key)
            guard self.store.conversations.contains(where:{$0.key == key}) else {return}
            switch result {
            case .success(let settings):
                self.desktopSettings[key] = settings; self.desktopModelNotes.removeValue(forKey:key); self.settingsReady.insert(key)
            case .failure(let error):
                self.desktopSettings.removeValue(forKey:key)
                self.settingsReady.remove(key)
                self.desktopModelNotes[key] = error is DesktopReply.OwnerUnavailable ? error.localizedDescription : "读取会话设置失败："+error.localizedDescription
            }
            self.onChange()
        }
    }
    func submit(_ text:String,to conversation:Conversation,entry:ChatEntry) {
        let key = conversation.key
        guard !isClosing(),canSend(),desktopSending[key] == nil,!desktopUnconfirmed.contains(key),
              let thread = conversation.threadID,let target = target(conversation) else {return}
        let request = UUID()
        desktopSending[key] = request
        desktopModelRequests.removeValue(forKey:key)
        desktopReplyNotes[key] = "正在连接 Codex 原会话…"; onChange()
        let needsOpen = !settingsReady.contains(key)
        let send:() -> Void = { [weak self,weak conversation] in
            guard let self,let conversation else {return}
            self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,openOnMissingOwner:!needsOpen,deadline:Date().addingTimeInterval(20))
        }
        if needsOpen {openForReply(conversation,thread:thread,request:request,completion:send)}
        else {send()}
    }
    private func isCurrent(_ conversation:Conversation,thread:String,request:UUID) -> Bool {
        !isClosing() && desktopSending[conversation.key] == request && conversation.threadID == thread &&
            store.conversations.contains(where:{$0 === conversation})
    }
    private func failBeforeSend(_ conversation:Conversation,error:Error) {
        let key = conversation.key
        desktopSending.removeValue(forKey:key)
        settingsReady.remove(key); desktopSettings.removeValue(forKey:key)
        desktopModelNotes[key] = error.localizedDescription
        desktopReplyNotes[key] = "消息未发送，草稿已保留。"; onChange()
    }
    private func openForReply(_ conversation:Conversation,thread:String,request:UUID,completion:@escaping () -> Void) {
        guard isCurrent(conversation,thread:thread,request:request) else {return}
        let key = conversation.key
        desktopReplyNotes[key] = "正在打开 Codex 原会话…"; onChange()
        CodexConnection.openConversationForReply(thread) { [weak self,weak conversation] error in
            guard let self,let conversation,self.isCurrent(conversation,thread:thread,request:request) else {return}
            if let error {self.failBeforeSend(conversation,error:error); return}
            completion()
        }
    }
    private func sendReply(_ text:String,to conversation:Conversation,entry:ChatEntry,thread:String,
                           target:(id:String,mode:DesktopReply.Mode,start:Date),request:UUID,openOnMissingOwner:Bool,deadline:Date) {
        guard isCurrent(conversation,thread:thread,request:request) else {return}
        guard canSend(),let latest = self.target(conversation),latest.id == target.id,latest.mode == target.mode else {
            failBeforeSend(conversation,error:PetFailure(message:"任务状态已变化，消息未发送。请确认后再次发送。")); return
        }
        let key = conversation.key, started = Date()
        desktopReplyNotes[key] = "正在连接，连上后自动发送…"; onChange()
        DesktopReply.submit(thread:thread,previousTurn:target.id,cwd:conversation.cwd,text:text,mode:target.mode,connectionDeadline:deadline,onConnected:{ [weak self,weak conversation] in
            guard let self,let conversation,self.isCurrent(conversation,thread:thread,request:request) else {return}
            self.desktopReplyNotes[key] = "正在发送…"; self.onChange()
        }) { [weak self,weak conversation] result in
            guard let self,let conversation,self.isCurrent(conversation,thread:thread,request:request) else {return}
            // 只重试未提交消息的连接阶段；真正发送后的任何错误均不进入此分支。
            if case .failure(let error) = result,error is DesktopReply.ConnectionPending {
                if openOnMissingOwner {
                    self.openForReply(conversation,thread:thread,request:request) { [weak self,weak conversation] in
                        guard let self,let conversation else {return}
                        self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,openOnMissingOwner:false,deadline:Date().addingTimeInterval(20))
                    }
                } else if deadline.timeIntervalSinceNow > 0.25 {
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [weak self,weak conversation] in
                        guard let self,let conversation else {return}
                        self.sendReply(text,to:conversation,entry:entry,thread:thread,target:target,request:request,openOnMissingOwner:false,deadline:deadline)
                    }
                } else {
                    self.failBeforeSend(conversation,error:PetFailure(message:"连接 Codex 原会话超时。"+error.localizedDescription))
                }
                return
            }
            self.desktopSending.removeValue(forKey:key)
            switch result {
            case .success(let receipt):
                // 观察器与发送回执均以真实 turn ID 合并，避免生成两条记录。
                if let turn = conversation.turns.first(where:{$0.id == receipt.turnID}) {
                    turn.lastMessageAt = started
                    if target.mode == .steer {turn.input += (turn.input.isEmpty ? "" : "\n\n")+"插话："+text}
                    else {turn.input = text}
                }
                else {
                    let turn = Turn(); turn.id = receipt.turnID; turn.input = text; turn.owned = false
                    turn.date = target.mode == .steer ? target.start : started; turn.status = receipt.status; turn.lastMessageAt = started; conversation.turns.append(turn)
                }
                self.onSubmitted(key,text,entry)
                self.desktopReplyNotes.removeValue(forKey:key)
                self.onPersist()
            case .failure(let error):
                if error is DesktopReply.Unconfirmed {self.desktopUnconfirmed.insert(key)}
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
        let alert = NSAlert(); alert.messageText = "确认消息是否已发送"
        alert.informativeText = "请在 Codex 的“\(conversation.title)”中查看这条消息。确认未发送后，才能再次发送。草稿已保留。"
        alert.addButton(withTitle:"稍后确认"); alert.addButton(withTitle:"确认未发送，重新编辑"); alert.applyAccent()
        alert.beginSheetModal(for:parent) { [weak self] response in
            guard response == .alertSecondButtonReturn,let self,self.store.conversations.contains(where:{$0 === conversation}) else {return}
            self.desktopUnconfirmed.remove(key); self.desktopReplyNotes.removeValue(forKey:key); self.onChange()
        }
    }
}
