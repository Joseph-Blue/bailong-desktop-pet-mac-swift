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
        guard desktopModelRequests[key] == nil,force || Date().timeIntervalSince(desktopModelChecked[key] ?? .distantPast) >= 5 else {return}
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
        guard !isClosing(),canSend(),canReply(key),desktopSending[key] == nil,!desktopUnconfirmed.contains(key),
              let thread = conversation.threadID,let target = target(conversation) else {return}
        let request = UUID(), started = Date()
        desktopSending[key] = request; desktopReplyNotes.removeValue(forKey:key); onChange()
        DesktopReply.submit(thread:thread,previousTurn:target.id,cwd:conversation.cwd,text:text,mode:target.mode) { [weak self,weak conversation] result in
            guard let self,let conversation,!self.isClosing(),self.desktopSending[key] == request,
                  self.store.conversations.contains(where:{$0 === conversation}) else {return}
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
                if error is DesktopReply.OwnerUnavailable {
                    self.settingsReady.remove(key); self.desktopModelNotes[key] = error.localizedDescription
                    self.desktopReplyNotes.removeValue(forKey:key)
                } else {
                    if error is DesktopReply.Unconfirmed {self.desktopUnconfirmed.insert(key)}
                    self.desktopReplyNotes[key] = error.localizedDescription
                }
                // 回执只更新原会话状态。用户已切换或关闭窗口时不弹模态框、激活应用。
                self.onChange()
            }
        }
    }
    func checkDelivery(_ conversation:Conversation,parent:NSWindow) {
        let key = conversation.key
        guard desktopUnconfirmed.contains(key) else {return}
        CodexConnection.openConversation(conversation.threadID)
        let alert = NSAlert(); alert.messageText = "检查 Codex 中的发送结果"
        alert.informativeText = "请查看“\(conversation.title)”是否已收到这条消息。草稿仍保留；确认未发送后才重新启用发送。"
        alert.addButton(withTitle:"保留待确认状态"); alert.addButton(withTitle:"已确认未发送"); alert.applyAccent()
        alert.beginSheetModal(for:parent) { [weak self] response in
            guard response == .alertSecondButtonReturn,let self,self.store.conversations.contains(where:{$0 === conversation}) else {return}
            self.desktopUnconfirmed.remove(key); self.desktopReplyNotes.removeValue(forKey:key); self.onChange()
        }
    }
}
