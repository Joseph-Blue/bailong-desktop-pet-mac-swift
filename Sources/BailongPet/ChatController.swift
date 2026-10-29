import AppKit

// 参照作者 chat_backend.PERSONA，仅作用于桌宠创建的任务会话。
let persona = "你是GPT白龙娘桌宠中的白龙娘，是一位温柔、聪明、认真负责的白龙少女。用自然、轻柔、可爱的中文和用户交流，适度称呼用户为‘主人’，偶尔有一点小得意或小傲娇。不要每句话都重复称呼，不滥用撒娇、拟声词、表情或夸张承诺。执行任务时保持严谨，先解决问题，保留代码、文件名、数据和技术解释的准确性。进度、困难和待确认的问题也用白龙娘的口吻说清楚，不编造过程，不把失败或中断说成完成。最终结果直接给出正文，客户端会单独显示完成提示。角色口吻不改变用户的任务范围、访问权限或审批要求。"

final class ChatController {
    let pet: PetController
    let store: HistoryStore
    let ui = ChatInterface()
    let connection = CodexConnection()
    var selected: Conversation
    var running: (Conversation,Turn)?
    var cancelled = false, closing = false
    var messages = [String:String](), messageOrder = [String](), summaries = [String:String](), steps = [String:String]()
    var lastPreview = "", lastKind = "output"
    var saveError: String?
    var updateTimer: Timer?
    var alert: NSAlert?
    var requests = [(Any,String,[String:Any])]()
    var quotaSerial = 0
    var onFinishedShutdown: (() -> Void)?
    init(pet: PetController) throws {
        self.pet = pet; store = try HistoryStore()
        let workspace = Paths.data.appendingPathComponent("Workspace")
        try FileManager.default.createDirectory(at:workspace,withIntermediateDirectories:true)
        selected = store.conversations.last(where:{!$0.external}) ?? store.create(cwd:workspace.path)
        store.onError = { [weak self] error in
            guard let self else{return}
            if self.saveError == nil { showError("历史保存失败，原文件未清空",error) }
            self.saveError = error.localizedDescription; self.ui.status.stringValue = "历史保存失败，请检查磁盘空间。"
        }
        ui.onSubmit = { [weak self] text in self?.submit(text) }; ui.onStop = { [weak self] in self?.stop() }
        ui.onNew = { [weak self] in self?.newConversation() }; ui.onFolder = { [weak self] in self?.chooseFolder() }
        ui.onSelect = { [weak self] key in guard let self else{return}; self.selected = self.store.conversations.first(where:{$0.key == key})!; self.refresh() }
        ui.onContinue = { [weak self] in self?.continueExternal() }; ui.onHide = { [weak self] in self?.pet.composerVisible = false }
        connection.event = { [weak self] method,p in self?.receive(method,p) }
        connection.request = { [weak self] id,method,p in self?.requests.append((id,method,p)); self?.nextRequest() }
        connection.disconnected = { [weak self] error in if self?.running != nil {self?.finish("interrupted",error:error.localizedDescription)} }
        pet.onComposer = { [weak self] in self?.toggleComposer() }; pet.onHistory = { [weak self] key in self?.showHistory(key) }
        pet.onQuota = { [weak self] in self?.quota() }
        pet.onGeometry = { [weak self] in self?.positionComposer() }
        pet.onVisibility = { [weak self] shown in if !shown {self?.ui.composer.orderOut(nil); self?.pet.composerVisible = false} }
        refresh()
    }
    func refresh() {
        ui.refresh(store.conversations,selected:selected,busy:running != nil)
        ui.status.stringValue = saveError != nil ? "历史保存失败，请检查磁盘空间。" : running != nil ? (cancelled ? "正在停止任务…" : "正在处理 · 可随时停止") : "⌘ Command + ↩ Enter 发送"
    }
    func approvalParent() -> NSWindow {
        if ui.history.isVisible { return ui.history }
        if !ui.composer.isVisible { toggleComposer() }
        return ui.composer
    }
    func persist() { store.save(); refresh() }
    func newConversation(cwd: String? = nil) {
        guard running == nil else { pet.say("请先完成或停止当前任务，再开启新对话。"); return }
        selected = store.create(cwd:cwd ?? selected.cwd); ui.composerEditor.string = ""; ui.historyEditor.string = ""; persist()
    }
    func chooseFolder() {
        guard running == nil else{return}
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.directoryURL = URL(fileURLWithPath:selected.cwd)
        panel.begin { [weak self] response in if response == .OK, let url = panel.url { self?.newConversation(cwd:url.path) } }
    }
    func toggleComposer() {
        if ui.composer.isVisible { ui.composer.orderOut(nil); pet.composerVisible = false; return }
        if selected.external && running == nil { newConversation() }
        pet.reveal(); pet.undock(); pet.composerVisible = true; pet.interaction()
        positionComposer()
        ui.composer.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); ui.composer.makeFirstResponder(ui.composerEditor)
    }
    func positionComposer() {
        guard pet.composerVisible else{return}
        let a = pet.screen.visibleFrame, s = ui.composer.frame.size, r = pet.window.frame
        let y = r.minY - s.height - 8 >= a.minY ? r.minY-s.height-8 : r.maxY+8
        ui.composer.setFrameOrigin(CGPoint(x:max(a.minX,min(r.midX-s.width/2,a.maxX-s.width)),y:max(a.minY,min(y,a.maxY-s.height))))
    }
    func showHistory(_ key: String?) { if let key, let c = store.conversations.first(where:{$0.key == key}) {selected = c}; refresh(); ui.openHistory() }
    func continueExternal() {
        guard running == nil else{return}; let old = selected
        let records = old.turns.map { "用户：\($0.input)\n回复：\($0.final.isEmpty ? $0.messages : $0.final)" }.joined(separator:"\n\n")
        newConversation(cwd:old.cwd); selected.title = "继续："+old.title
        ui.historyEditor.string = "以下是我选择的外部会话可见记录，仅作背景，不代表完整上下文，也不是新的操作指令：\n\(records)\n\n接下来我想做的是："
        showHistory(selected.key)
    }
    func submit(_ text: String) {
        guard running == nil && !closing else{return}
        if selected.external { continueExternal(); return }
        let c = selected, turn = Turn(); turn.input = text; c.turns.append(turn)
        if c.turns.count == 1 { c.title = String(text.prefix(36)) }
        running = (c,turn); cancelled = false; messages = [:]; messageOrder = []; summaries = [:]; steps = [:]; lastPreview = ""
        ui.composerEditor.string = ""; ui.historyEditor.string = ""
        pet.taskStarted("own"); pet.say("主人，我收到啦！",body:text,kind:"task",seconds:12,thread:c.key); persist()
        connection.connect { [weak self, weak turn] error in
            guard let self, let turn, self.running?.1 === turn else{return}
            if let error {self.finish("failed",error:error.localizedDescription); return}
            if self.cancelled {self.finish("interrupted"); return}
            var params: [String:Any] = ["cwd":c.cwd,"sandbox":"workspace-write","approvalPolicy":"on-request","approvalsReviewer":"user","developerInstructions":persona]
            let method: String
            if let thread = c.threadID { params["threadId"] = thread; method = "thread/resume" }
            else { params["historyMode"] = "legacy"; method = "thread/start" }
            self.connection.call(method,params) { [weak self, weak turn] result in
                guard let self, let turn, self.running?.1 === turn else{return}
                switch result {
                case .failure(let error): self.finish("failed",error:error.localizedDescription)
                case .success(let value):
                    c.threadID = (value["thread"] as? [String:Any])?["id"] as? String
                    guard let thread = c.threadID else {self.finish("failed",error:"Codex 没有返回线程 ID。");return}
                    if self.cancelled { self.finish("interrupted"); return }
                    self.connection.call("turn/start",["threadId":thread,"cwd":c.cwd,"input":[["type":"text","text":text]],"approvalPolicy":"on-request","approvalsReviewer":"user","summary":"concise","sandboxPolicy":["type":"workspaceWrite","writableRoots":[c.cwd],"networkAccess":false]]) { [weak self, weak turn] result in
                        guard let self, let turn, self.running?.1 === turn else{return}
                        switch result {
                        case .success(let value): turn.id = (value["turn"] as? [String:Any])?["id"] as? String; turn.status = "running"; if self.cancelled {self.interrupt()}; self.persist()
                        case .failure(let error):
                            if turn.id != nil || error.localizedDescription.contains("超时") { turn.status = "unknown"; turn.error = error.localizedDescription; self.persist() }
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
        case "item/agentMessage/delta":
            let id = p["itemId"] as! String; if messages[id] == nil {messageOrder.append(id)}
            messages[id,default:""] += p["delta"] as? String ?? ""; lastKind = "output"
        case "item/reasoning/summaryTextDelta":
            let key = "\(p["itemId"] ?? ""):\(p["summaryIndex"] ?? 0)"; summaries[key,default:""] += p["delta"] as? String ?? ""; lastKind = "summary"
        case "item/started", "item/completed": if let item = p["item"] as? [String:Any] { record(item) }
        case "turn/plan/updated": steps["plan"] = (p["plan"] as? [[String:Any]] ?? []).map { "\($0["status"] ?? "") · \($0["step"] ?? "")" }.joined(separator:"\n"); lastKind = "progress"
        case "turn/completed":
            guard let turn = p["turn"] as? [String:Any], t.id == nil || t.id == turn["id"] as? String else{return}
            for item in turn["items"] as? [[String:Any]] ?? [] {record(item)}
            updateText(); finish(turn["status"] as? String ?? "unknown",error:(turn["error"] as? [String:Any])?["message"] as? String ?? ""); return
        case "error": t.error = (p["error"] as? [String:Any])?["message"] as? String ?? "Codex 报告错误"
        default:return
        }
        scheduleUpdate()
    }
    func record(_ item: [String:Any]) {
        let id = item["id"] as? String ?? UUID().uuidString
        switch item["type"] as? String {
        case "agentMessage":
            if messages[id] == nil {messageOrder.append(id)}; messages[id] = item["text"] as? String ?? ""; lastKind = "output"
            if item["phase"] as? String == "final_answer" {running?.1.final = item["text"] as? String ?? ""}
        case "reasoning":
            // 只读取协议公开 summary，不读取 content 或加密推理字段。
            for (index,part) in (item["summary"] as? [Any] ?? []).enumerated() {summaries["\(id):\(index)"] = part as? String ?? (part as? [String:Any])?["text"] as? String ?? ""}; lastKind = "summary"
        case "commandExecution": steps[id] = "\(item["status"] ?? "") · \(item["command"] ?? "")\n\(item["aggregatedOutput"] ?? "")"; lastKind = "progress"
        case "fileChange": steps[id] = (item["changes"] as? [[String:Any]] ?? []).compactMap{$0["path"] as? String}.joined(separator:"\n"); lastKind = "progress"
        case "mcpToolCall", "dynamicToolCall": steps[id] = "\(item["status"] ?? "") · \(item["tool"] ?? "工具")"; lastKind = "progress"
        case "webSearch": steps[id] = "搜索：\(item["query"] ?? "")"; lastKind = "progress"
        default:break
        }
    }
    func updateText() { running?.1.messages = messageOrder.compactMap{messages[$0]}.joined(separator:"\n\n"); running?.1.summary = summaries.sorted{$0.key<$1.key}.map{$0.value}.joined(separator:"\n"); running?.1.steps = steps.sorted{$0.key<$1.key}.map{$0.value}.joined(separator:"\n\n") }
    func scheduleUpdate() {
        if updateTimer != nil {return}
        updateTimer = Timer.scheduledTimer(withTimeInterval:0.35,repeats:false) { [weak self] _ in
            guard let self else{return}; self.updateTimer = nil; self.updateText(); self.persist()
            guard let (c,t) = self.running else{return}
            let text = self.lastKind == "summary" ? t.summary : self.lastKind == "progress" ? t.steps : t.messages
            if !text.isEmpty && text != self.lastPreview {self.lastPreview = text; self.pet.say(self.lastKind == "summary" ? "主人，我正在理清思路…（公开摘要）" : "主人，我忙到这一步啦…",body:text,kind:"task",seconds:12,thread:c.key)}
        }
    }
    func finish(_ status: String, error: String = "") {
        guard let (c,t) = running else{return}
        updateTimer?.invalidate(); updateTimer = nil; updateText(); t.status = status; t.error = error
        if t.final.isEmpty {t.final = messageOrder.last.flatMap{messages[$0]} ?? ""}
        running = nil; dismissRequests(); pet.taskEnded("own",status:status); persist()
        let title = status == "completed" ? "主人，完成啦！" : status == "interrupted" ? "主人，我先停下来啦。" : "主人，这次任务尚未完成。"
        pet.say(title,body:error.isEmpty ? t.final : error,kind:"task",seconds:20,thread:c.key)
        if closing {finishShutdown()}
    }
    func stop() { guard running != nil else{return}; cancelled = true; dismissRequests(); ui.status.stringValue = "正在停止任务…"; interrupt() }
    func interrupt() {
        guard let (c,t) = running, let thread = c.threadID, let turn = t.id else{return}
        connection.call("turn/interrupt",["threadId":thread,"turnId":turn]) { [weak self] result in if case .failure(let error) = result {self?.running?.1.error = error.localizedDescription; self?.persist()} }
    }
    func nextRequest() {
        guard alert == nil && !requests.isEmpty else{return}
        let (id,method,p) = requests.removeFirst()
        guard running != nil && !cancelled else {connection.unsupported(id,method); nextRequest();return}
        if method == "item/permissions/requestApproval" {connection.reply(id,["permissions":[:],"scope":"turn"]); nextRequest();return}
        if method == "item/tool/requestUserInput" { questions(id,p["questions"] as? [[String:Any]] ?? [],answers:[:]); return }
        guard method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval" else {connection.unsupported(id,method); nextRequest();return}
        running?.1.status = "waitingForApproval"; persist()
        let a = NSAlert(); alert = a; a.messageText = "主人，这一步需要你批准"
        a.informativeText = p["reason"] as? String ?? "请查看具体操作后决定。"
        let details = NSTextView(frame:NSRect(x:0,y:0,width:520,height:180)); details.isEditable = false
        details.string = String(data:(try? JSONSerialization.data(withJSONObject:p,options:.prettyPrinted)) ?? Data(),encoding:.utf8) ?? ""
        let scroll = NSScrollView(frame:details.frame); scroll.documentView = details; scroll.hasVerticalScroller = true; a.accessoryView = scroll
        a.addButton(withTitle:"拒绝"); a.addButton(withTitle:"允许这一次"); a.buttons[0].keyEquivalent = "\r"; a.buttons[1].keyEquivalent = ""
        NSApp.activate(ignoringOtherApps:true)
        a.beginSheetModal(for:approvalParent()) { [weak self] response in
            guard let self else{return}; self.alert = nil
            self.connection.reply(id,["decision":response == .alertSecondButtonReturn && !self.cancelled && self.running != nil ? "accept" : "decline"])
            self.running?.1.status = "running"; self.persist(); self.nextRequest()
        }
    }
    func questions(_ id: Any, _ questions: [[String:Any]], answers: [String:Any]) {
        guard running != nil && !cancelled else {connection.reply(id,["answers":answers]); return}
        guard let q = questions.first else {connection.reply(id,["answers":answers]); running?.1.status = "running"; persist(); nextRequest();return}
        let a = NSAlert(); alert = a; a.messageText = q["header"] as? String ?? "请补充信息"; a.informativeText = q["question"] as? String ?? ""
        let input: NSView
        if q["isSecret"] as? Bool == true {input = NSSecureTextField(frame:NSRect(x:0,y:0,width:420,height:28))}
        else if let options = q["options"] as? [[String:Any]], !options.isEmpty {
            let combo = NSComboBox(frame:NSRect(x:0,y:0,width:420,height:28)); combo.addItems(withObjectValues:options.compactMap{$0["label"] as? String}); combo.isEditable = true; input = combo
        } else {input = NSTextField(frame:NSRect(x:0,y:0,width:420,height:28))}
        a.accessoryView = input; a.addButton(withTitle:"提交"); a.addButton(withTitle:"取消并停止")
        running?.1.status = "waitingForInput"; persist(); NSApp.activate(ignoringOtherApps:true)
        a.beginSheetModal(for:approvalParent()) { [weak self] response in
            guard let self else{return}; self.alert = nil
            guard response == .alertFirstButtonReturn && !self.cancelled else {self.connection.reply(id,["answers":answers]); self.stop();return}
            var next = answers; next[q["id"] as! String] = ["answers":[(input as! NSTextField).stringValue]]
            self.questions(id,Array(questions.dropFirst()),answers:next)
        }
    }
    func dismissRequests() {
        requests.removeAll()
        if let alert, let parent = alert.window.sheetParent {parent.endSheet(alert.window,returnCode:.cancel)}
        alert = nil
    }
    func quota() {
        guard !pet.quotaActive else{return}; pet.quotaActive = true; quotaSerial += 1; let serial = quotaSerial
        if pet.dock == nil {pet.play(pet.catalog.quotaAnimation,"quota")}
        pet.say("让我看看额度还有多少……",kind:"quota",seconds:0)
        connection.connect { [weak self] error in
            guard let self else{return}
            if let error {self.quotaResult(serial,.failure(error));return}
            self.connection.call("account/rateLimits/read",[:]) { [weak self] result in self?.quotaResult(serial,result) }
        }
    }
    func quotaResult(_ serial: Int, _ result: Result<[String:Any],Error>) {
        guard serial == quotaSerial && pet.quotaActive && !closing else{return}
        switch result {
        case .failure(let error): pet.say("主人，暂时没能查到额度。",body:error.localizedDescription,kind:"quota",seconds:8)
        case .success(let value):
            var buckets = Array((value["rateLimitsByLimitId"] as? [String:[String:Any]] ?? [:]).values)
            if buckets.isEmpty, let legacy = value["rateLimits"] as? [String:Any] {buckets = [legacy]}
            var lines = [String]()
            var rows = [(String,Double?,String)]()
            for bucket in buckets { for key in ["primary","secondary"] {
                guard let w = bucket[key] as? [String:Any] else {continue}
                let duration = w["windowDurationMins"] as? Double
                let period = duration.map { $0 == 10080 ? "一周" : "\($0/60) 小时" } ?? "额度窗口"
                let remaining = (w["usedPercent"] as? Double).map {String(format:"剩余 %.0f%%",max(0,min(100,100-$0)))} ?? "暂未提供"
                let reset = (w["resetsAt"] as? Double).map{Date(timeIntervalSince1970:$0).formatted()} ?? "暂未提供"
                lines.append("\(bucket["limitName"] ?? bucket["limitId"] ?? "Codex") · \(period)\n\(remaining)\n重置：\(reset)")
                rows.append(("\(bucket["limitName"] ?? bucket["limitId"] ?? "Codex") · \(period)", (w["usedPercent"] as? Double).map{max(0,min(100,100-$0))},reset))
            }}
            pet.say("Codex 剩余额度",body:lines.isEmpty ? "服务器暂未提供额度窗口。" : lines.joined(separator:"\n\n"),kind:"quota",seconds:12)
            if !rows.isEmpty {pet.bubble.quotaRows(rows,scale:Double(pet.bubblePercent)/100)}
        }
    }
    func shutdown(_ completion: @escaping () -> Void) {
        closing = true; onFinishedShutdown = completion
        if running != nil {
            stop()
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in if self?.running != nil {self?.finish("interrupted",error:"桌宠退出，任务未确认完成。")} }
        } else {finishShutdown()}
    }
    func finishShutdown() { connection.close(); store.finish(); ui.composer.orderOut(nil); ui.history.orderOut(nil); let completion = onFinishedShutdown; onFinishedShutdown = nil; completion?() }
}
