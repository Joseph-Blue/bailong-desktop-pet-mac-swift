import AppKit

final class RequestCoordinator {
    private unowned let chat:ChatController
    private(set) var alert:NSAlert?
    private var rejectCurrent:(() -> Void)?
    private var requests = [(Any,String,[String:Any],String?)]()
    init(chat:ChatController) {self.chat = chat}
    func enqueue(_ id:Any,_ method:String,_ params:[String:Any]) {
        if let thread = params["threadId"] as? String,thread != chat.running?.0.threadID {
            chat.connection.reject(id,"请求不属于当前任务。"); return
        }
        if let turn = params["turnId"] as? String,let current = chat.running?.1.id,turn != current {
            chat.connection.reject(id,"请求不属于当前轮次。"); return
        }
        do {try CodexProtocol.validate(method,params)}
        catch {chat.connection.reject(id,error.localizedDescription); return}
        requests.append((id,method,params,chat.running?.1.key)); nextRequest()
    }
    private func showAttention(_ attention:TaskAttention, submit: (([String:String], @escaping (Error?) -> Void) -> Void)? = nil) {
        guard let (conversation,turn) = self.chat.running else {return}
        self.chat.pet.say(self.chat.pet.preferences.statusLine(attention.kind.templateKey), body:attention.body, kind:"task", thread:conversation.key, followsText:false, resetText:true, purpose:.attention, personalizeTitle:false, animateHeading:false, attentionAction:true, timing:.init(start:turn.date,key:"own"), question:.init(questions:attention.questions,submit:submit))
    }
    private func clearAttention() {
        if let (conversation,_) = self.chat.running, self.chat.pet.bubble.relatedConversation == conversation.key, self.chat.pet.bubble.purpose == .attention {self.chat.pet.bubble.hide()}
    }
    func nextRequest() {
        guard alert == nil && !requests.isEmpty else{return}
        let (id,method,p,turnKey) = requests.removeFirst()
        guard self.chat.running?.1.key == turnKey && self.chat.running != nil && !self.chat.cancelled else {self.chat.connection.unsupported(id,method); nextRequest();return}
        if method == "item/permissions/requestApproval" {self.chat.connection.reply(id,["permissions":[:],"scope":"turn"]); nextRequest();return}
        if method == "item/tool/requestUserInput" { questions(id,p["questions"] as? [[String:Any]] ?? [],answers:[:]); return }
        guard method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval" else {self.chat.connection.unsupported(id,method); nextRequest();return}
        rejectCurrent = { [weak self] in self?.chat.connection.reply(id,["decision":"decline"]) }
        self.chat.running?.1.status = "waitingForApproval"; self.chat.persist()
        let owner = self.chat.running?.1
        let a = NSAlert(); alert = a; a.messageText = self.chat.pet.preferences.statusLine("taskApprovalTemplate")
        a.informativeText = p["reason"] as? String ?? "请查看具体操作后决定。"
        let details = AppTextView(frame:NSRect(x:0,y:0,width:520,height:180)); details.isEditable = false; details.isSelectable = true
        details.string = String(data:(try? JSONSerialization.data(withJSONObject:p,options:.prettyPrinted)) ?? Data(),encoding:.utf8) ?? ""
        let scroll = NSScrollView(frame:details.frame); scroll.documentView = details; scroll.hasVerticalScroller = true; a.accessoryView = scroll
        a.addButton(withTitle:"拒绝"); a.addButton(withTitle:"允许这一次"); a.buttons[0].keyEquivalent = "\r"; a.buttons[1].keyEquivalent = ""
        NSApp.activate(ignoringOtherApps:true)
        a.applyAccent()
        showAttention(.approval(fileChange:method == "item/fileChange/requestApproval",reason:p["reason"] as? String))
        a.beginSheetModal(for:self.chat.approvalParent()) { [weak self] response in
            guard let self,self.alert === a,self.chat.running?.1 === owner else {return}; self.alert = nil; self.rejectCurrent = nil; self.clearAttention()
            self.chat.connection.reply(id,["decision":response == .alertSecondButtonReturn && !self.chat.cancelled && self.chat.running != nil ? "accept" : "decline"])
            self.chat.running?.1.status = "running"; self.chat.persist(); self.nextRequest()
        }
    }
    func questions(_ id: Any, _ questions: [[String:Any]], answers: [String:Any]) {
        guard self.chat.running != nil && !self.chat.cancelled else {self.chat.connection.reply(id,["answers":answers]); return}
        guard let q = questions.first else {self.chat.connection.reply(id,["answers":answers]); self.chat.running?.1.status = "running"; self.chat.persist(); nextRequest();return}
        guard let questionID = q["id"] as? String else {self.chat.connection.reject(id,"问题缺少标识。"); nextRequest(); return}
        rejectCurrent = { [weak self] in self?.chat.connection.reply(id,["answers":answers]) }
        let owner = self.chat.running?.1
        let a = NSAlert(); alert = a; a.messageText = q["header"] as? String ?? "请补充信息"; a.informativeText = q["question"] as? String ?? ""
        let input: NSView
        if q["isSecret"] as? Bool == true {input = NSSecureTextField(frame:NSRect(x:0,y:0,width:420,height:28))}
        else if let options = q["options"] as? [[String:Any]], !options.isEmpty {
            let combo = NSComboBox(frame:NSRect(x:0,y:0,width:420,height:28)); combo.addItems(withObjectValues:options.compactMap{$0["label"] as? String}); combo.isEditable = true; input = combo
        } else {input = NSTextField(frame:NSRect(x:0,y:0,width:420,height:28))}
        a.accessoryView = input; a.addButton(withTitle:"提交"); a.addButton(withTitle:"取消并停止")
        self.chat.running?.1.status = "waitingForInput"
        if q["isSecret"] as? Bool == true {self.chat.running?.1.sensitiveQuestionNotice = self.chat.pet.preferences.sensitiveQuestionNotice}
        self.chat.persist()
        let submit: (([String:String], @escaping (Error?) -> Void) -> Void)? = q["isSecret"] as? Bool == true ? nil : { [weak self,weak a] values,completion in
            guard let self,let a,self.alert === a,let parent = a.window.sheetParent,let key = q["id"] as? String else {completion(PetFailure(message:"这道问题已结束。")); return}
            (input as! NSTextField).stringValue = values[key] ?? ""
            parent.endSheet(a.window,returnCode:.alertFirstButtonReturn); completion(nil)
        }
        showAttention(.question(q),submit:submit); NSApp.activate(ignoringOtherApps:true)
        a.applyAccent()
        a.beginSheetModal(for:self.chat.approvalParent()) { [weak self] response in
            guard let self,self.alert === a,self.chat.running?.1 === owner else {return}; self.alert = nil; self.rejectCurrent = nil
            self.clearAttention()
            guard response == .alertFirstButtonReturn && !self.chat.cancelled else {self.chat.connection.reply(id,["answers":answers]); self.chat.stop();return}
            if q["isSecret"] as? Bool == true {self.chat.running?.1.sensitiveInputNotice = self.chat.pet.preferences.sensitiveInputNotice}
            var next = answers; next[questionID] = ["answers":[(input as! NSTextField).stringValue]]
            self.questions(id,Array(questions.dropFirst()),answers:next)
        }
    }
    func dismiss() {
        let queued = requests; requests.removeAll()
        let reject = rejectCurrent; rejectCurrent = nil
        if chat.connection.isConnected {
            reject?()
            for (id,method,_,_) in queued {chat.connection.unsupported(id,method)}
        }
        let previous = alert; alert = nil
        if let previous,let parent = previous.window.sheetParent {parent.endSheet(previous.window,returnCode:.cancel)}
    }
}
