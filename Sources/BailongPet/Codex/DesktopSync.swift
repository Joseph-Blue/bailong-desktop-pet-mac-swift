import Foundation

struct PublicAgentMessage:Equatable {
    let id:String
    let text:String
    let isFinal:Bool
    var isImage = false
}

struct PublicSnapshot {
    var logical: String, actual: String, turn: String, title: String, cwd: String, historyMode: String
    var status: String, started: Double, messages: String, final: String, alert: String, step: String, error: String
    var completed: Double?
    var attention: TaskAttention?
    var approvalID = ""
    var approval:DesktopApproval?
    var activity:TaskActivity?
    var hasSensitiveInput = false
    var hasSensitiveQuestion = false
    var agentMessages = [PublicAgentMessage]()
    var fileEdits = [FileEditSummary]()
    var isLatest = true
    var resultText:String {GeneratedImageLink.appending(agentMessages.filter(\.isImage).map(\.text),to:final)}
    var key: String { actual+":"+turn }
    var fingerprint: [String] { fileEdits.flatMap(\.signature) + agentMessages.flatMap {[$0.id,$0.text]} + [status,messages,final,alert,step,error,approvalID,approval?.details ?? "",attention?.kind.rawValue ?? "",hasSensitiveInput ? "sensitive-input" : "",hasSensitiveQuestion ? "sensitive-question" : ""] + (attention?.questions.flatMap {[$0.id,$0.prompt] + $0.options.flatMap {[$0.title,$0.detail ?? "",String($0.recommended)]}} ?? []) }
}

final class DesktopSync {
    let chat: ChatController
    private let queue = DispatchQueue(label:"白龙娘外部任务只读观察",qos:.utility)
    private let approvalReader = DesktopApprovalReader()
    private var timer: Timer?
    private var reading = false, stopped = false, initial = true
    private var lastTitleSync = Date.distantPast
    private var lastHistoryRead = Date.distantPast
    private var historyValues = [PublicSnapshot]()
    private let born = Date().timeIntervalSince1970
    private var tracked = [String:PublicSnapshot]()
    private var fingerprints = [String:[String]](), changedAt = [String:Double](), noticedAt = [String:Double]()
    private var running = Set<String>()
    private var skippedQuestionIDs = Set<String>()
    private var clearedBefore = UserDefaults.standard.double(forKey:"desktopHistoryClearedBefore")
    func clearLocalProjection() {
        skippedQuestionIDs.removeAll()
        clearedBefore = Date().timeIntervalSince1970
        UserDefaults.standard.set(clearedBefore,forKey:"desktopHistoryClearedBefore")
        for key in running {chat.pet.taskEnded(key,status:"interrupted")}
        running.removeAll(); tracked.removeAll(); fingerprints.removeAll(); noticedAt.removeAll(); changedAt.removeAll()
        chat.desktopTasks = []; chat.desktopTaskReadStatus = "正在同步 Codex 任务状态…"
    }
    private(set) var diagnostics = "等待同步"
    var status = "正在准备读取本机 Codex 的任务记录。\n读取成功后，这里会显示任务数量、当前状态和最近刷新时间。"
    init(chat: ChatController) {
        self.chat = chat
        chat.onHistoryDeleted = { [weak self] conversation in self?.forget(conversation) }
        timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in self?.poll() }
    }
    private func forget(_ conversation:Conversation) {
        chat.desktopTasks.removeAll {$0.threadID == conversation.threadID}
        let keys = tracked.filter {$0.value.logical == conversation.threadID || $0.value.actual == conversation.threadID}.map(\.key)
        for key in keys {
            tracked.removeValue(forKey:key); fingerprints.removeValue(forKey:key)
            noticedAt.removeValue(forKey:key); changedAt.removeValue(forKey:key)
            if running.remove(key) != nil {chat.pet.stopObservingTask(key)}
        }
    }
    private func poll() {
        chat.refreshDesktopSettingsIfNeeded()
        guard !reading && !stopped else{return}; reading = true
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID}).union(chat.store.deletedThreads)
        let watched = tracked.values.filter{running.contains($0.key)}
        let unresolvedThreads = Set(chat.store.conversations.filter {$0.external && $0.turns.contains(where:{activeStatuses.contains($0.status)})}.compactMap(\.threadID))
        let titleIDs = chat.store.recordsAutomatically && Date().timeIntervalSince(lastTitleSync) >= 5 ? chat.store.conversations.filter {$0.external && $0.localTitle == nil}.compactMap(\.threadID) : []
        queue.async { [weak self] in
            guard let self else{return}
            do {
                if Date().timeIntervalSince(self.lastHistoryRead) >= 1 {
                    self.historyValues = try DesktopHistoryReader.read(excluded:excluded,watched:Array(watched),additionalThreads:unresolvedThreads)
                    self.lastHistoryRead = Date()
                }
                var values = self.historyValues.filter {!excluded.contains($0.logical) && !excluded.contains($0.actual)}
                var approvalError:String?
                do {
                    let approvals = try self.approvalReader.read(values)
                    for index in values.indices {
                        if values[index].isLatest,self.approvalReader.knownThreads.contains(values[index].logical) {
                            values[index].activity = self.approvalReader.activities[values[index].key]
                        }
                        if let approval = approvals[values[index].key] {
                            values[index].attention = approval.attention; values[index].approvalID = approval.id; values[index].approval = approval.request
                            values[index].status = "waitingForApproval"; values[index].alert = approval.attention.body
                        } else if self.approvalReader.knownThreads.contains(values[index].logical),values[index].attention?.kind == .approval {
                            values[index].attention = nil; values[index].alert = ""; values[index].status = "inProgress"
                        }
                    }
                    if self.approvalReader.unavailableCount > 0 {approvalError = "\(self.approvalReader.unavailableCount) 个会话尚未收到 Codex 实时状态。"}
                } catch {approvalError = error.localizedDescription}
                let titles = try DesktopHistoryReader.readTitles(titleIDs)
                DispatchQueue.main.async {
                    self.reading = false; guard !self.stopped else {return}
                    self.chat.desktopTaskReadStatus = nil
                    self.chat.desktopTasks = values.filter {$0.isLatest && $0.started > self.clearedBefore && !self.chat.store.deletedThreads.contains($0.logical)}.map {
                        BubbleTaskSummary(key:$0.key,title:$0.title,threadID:$0.logical,status:$0.status,start:Date(timeIntervalSince1970:$0.started),end:$0.completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil},turnID:$0.turn,activity:$0.attention.map {TaskActivity(title:$0.kind == .approval ? "等待批准" : "等待回答",kind:.reply)} ?? $0.activity)
                    }
                    if !titleIDs.isEmpty {self.lastTitleSync = Date()}
                    var changed = false
                    for conversation in self.chat.store.conversations where conversation.external && conversation.localTitle == nil && self.chat.store.recordsAutomatically {
                        if let id = conversation.threadID, let title = titles[id], !title.isEmpty, title != conversation.title {
                            conversation.title = title; changed = true
                        }
                    }
                    let displayChanged = values.contains {self.fingerprints[$0.key] != $0.fingerprint}
                    let recordsChanged = self.accept(values)
                    if let approvalError {
                        self.diagnostics += " · 审批同步失败："+approvalError
                        self.status += "\n\n实时审批状态未同步："+approvalError
                    }
                    if recordsChanged || changed {self.chat.persist()}
                    else if displayChanged {self.chat.refresh()}
                }
            }
            catch {DispatchQueue.main.async {self.reading = false; self.chat.desktopTasks = []; self.chat.desktopTaskReadStatus = "Codex 当前任务状态读取失败"; self.diagnostics = "读取失败：" + error.localizedDescription; self.status = "暂时无法读取 Codex 的任务记录。\n桌宠会自动重试；你也可以打开 Codex，确认会话能够正常使用。\n\n具体原因（供排查）：\n"+error.localizedDescription}}
        }
    }
    private func accept(_ values: [PublicSnapshot]) -> Bool {
        var changed = false
        let now = Date().timeIntervalSince1970
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID}).union(chat.store.deletedThreads)
        let currentActive = Set(values.filter {$0.isLatest && activeStatuses.contains($0.status)}.map(\.key))
        for key in running.subtracting(currentActive) {
            chat.pet.stopObservingTask(key); running.remove(key)
        }
        for var value in values {
            var skippedAll = false
            if let attention = value.attention,attention.kind == .answer,!attention.isSensitive,!attention.questions.isEmpty {
                let remaining = attention.questions.filter {!skippedQuestionIDs.contains($0.id)}
                skippedAll = remaining.isEmpty
                if remaining.count != attention.questions.count {
                    let body = remaining.map(\.prompt).joined(separator:"\n\n")
                    value.attention = skippedAll ? nil : TaskAttention(kind:.answer,body:body,questions:remaining)
                    value.alert = body
                }
            }
            guard value.started > clearedBefore else {continue}
            if excluded.contains(value.logical) || excluded.contains(value.actual) {continue}
            let key = value.key, active = value.isLatest && activeStatuses.contains(value.status)
            if tracked[key] == nil && !active && (initial || value.started < born) {
                // 补齐扫描范围内已有历史的图片入口与文件摘要，不把旧任务重新弹出或新增为历史。
                if chat.store.recordsAutomatically,!chat.store.isReadOnly,
                   let conversation = chat.store.conversations.first(where:{$0.external && $0.threadID == value.logical}),
                   let turn = conversation.turns.first(where:{$0.id == value.turn}) {
                    let enriched = GeneratedImageLink.appending(value.agentMessages.filter(\.isImage).map(\.text),to:turn.messages)
                    if enriched != turn.messages {turn.messages = enriched; changed = true}
                    if turn.fileEdits != value.fileEdits {turn.fileEdits = value.fileEdits; changed = true}
                }
                continue
            }
            if tracked[key] == nil && active && value.started < born-86400 {continue}
            var c = chat.store.conversations.first(where:{$0.external && $0.threadID == value.logical})
            if c == nil {c = chat.store.create(cwd:value.cwd,external:true); c!.title = value.title; c!.threadID = value.logical}
            let conversation = c!; conversation.historyMode = value.historyMode
            if chat.store.recordsAutomatically && conversation.localTitle == nil && !value.title.isEmpty && conversation.title != value.title {conversation.title = value.title; changed = true}
            var t = conversation.turns.first(where:{$0.id == value.turn})
            if t == nil {t = Turn(); t!.id = value.turn; t!.owned = false; t!.date = Date(timeIntervalSince1970:value.started); conversation.turns.append(t!); changed = true}
            let previous = tracked[key]
            let turn = t!, previousAttention = previous?.attention?.kind, different = fingerprints[key] != value.fingerprint
            if value.started > 0,turn.date != Date(timeIntervalSince1970:value.started) {
                turn.date = Date(timeIntervalSince1970:value.started); changed = true
            }
            if ["completed","failed","interrupted"].contains(value.status) {
                let end = value.completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil} ?? turn.completedAt ?? Date()
                if turn.completedAt != end {turn.completedAt = end; changed = true}
            }
            tracked[key] = value
            if different {
                if value.activity == nil || !active {chat.pet.bubble.removeActivity(taskKey:key)}
                if previousAttention != nil && value.attention == nil {chat.pet.bubble.resolveQuestions(taskKey:key)}
                if value.alert.isEmpty && !value.status.hasPrefix("waiting") && chat.pet.bubble.purpose == .attention && chat.pet.bubble.relatedConversation == conversation.key {
                    chat.pet.bubble.hide()
                }
                fingerprints[key] = value.fingerprint; changedAt[key] = now
                if value.hasSensitiveQuestion {turn.sensitiveQuestionNotice = chat.pet.preferences.sensitiveQuestionNotice}
                if value.hasSensitiveInput {turn.sensitiveInputNotice = chat.pet.preferences.sensitiveInputNotice}
                if turn.messages != value.messages || turn.final != value.final {
                    let time = previous == nil ? (value.completed ?? value.started) : now
                    turn.lastMessageAt = Date(timeIntervalSince1970:time)
                }
                turn.fileEdits = value.fileEdits
                turn.status = value.status; turn.messages = value.messages; turn.final = value.final; turn.steps = value.attention?.isSensitive == true ? "" : value.alert.isEmpty ? value.step : value.alert; turn.error = value.error; changed = true
            }
            if different {
                // 保留消息边界；一次轮询读到多条也逐条入卡，同一 item 的流式变化原地更新。
                let messages = value.agentMessages.filter {!$0.isFinal}
                let incoming = previous == nil && value.started < born ? Array(messages.suffix(1)) : messages
                for message in incoming where previous?.agentMessages.first(where:{$0.id == message.id})?.text != message.text {
                    chat.pet.say(chat.pet.preferences.statusLine("taskProgressTemplate"),body:message.text,kind:"task",thread:conversation.key,
                        purpose:.progress,personalizeTitle:false,animateHeading:active,
                        timing:.init(start:Date(timeIntervalSince1970:value.started),key:key,finished:active ? nil : turn.completedAt,status:active ? nil : value.status),messageID:message.id)
                }
            }
            if active {
                if value.attention == nil,previous?.activity != value.activity {
                    chat.pet.showProgressToast(value.activity,key:key,timing:.init(start:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,key:key))
                }
                if !running.contains(key) {running.insert(key); chat.pet.taskStarted(key)}
                let repeatDue = now-(noticedAt[key] ?? 0) >= 300
                if !skippedAll && (different || repeatDue) {
                    let quiet = now-(changedAt[key] ?? now) >= 90
                    let text = !value.alert.isEmpty ? value.alert : ["waitingForInput","waitingForApproval"].contains(value.status) ? "任务正在等待你的处理，请回到原 Codex 窗口。" : quiet ? "已经有一会儿没有新进度，任务尚未报告完成。" : value.messages.isEmpty ? value.step : value.agentMessages.last(where:{!$0.isFinal})?.text ?? value.messages
                    let questionIDs = value.attention?.questions.map(\.id).joined(separator:"\u{001f}") ?? ""
                    let signature = (value.attention?.kind.rawValue ?? "progress")+":"+value.approvalID+":"+questionIDs+":"+text
                    if (value.attention != nil || value.status.hasPrefix("waiting")) && !text.isEmpty && (turn.notices[signature] == nil || previous?.approval?.details != value.approval?.details || previousAttention != value.attention?.kind || (repeatDue && (!value.alert.isEmpty || quiet || value.status.hasPrefix("waiting")))) {
                        chat.pet.say(chat.pet.preferences.statusLine(value.attention?.kind.templateKey ?? "taskProgressTemplate"), body:text, kind:"task", thread:conversation.key,  purpose:!value.alert.isEmpty || value.status.hasPrefix("waiting") ? .attention : .progress, personalizeTitle:false, animateHeading:value.attention == nil, attentionAction:value.attention != nil, timing:.init(start:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,key:key), question:.init(questions:value.attention?.questions ?? [],submit:value.attention?.kind == .answer && value.attention?.isSensitive == false && value.attention?.questions.allSatisfy({!$0.id.isEmpty}) == true ? { [weak self] answers,completion in
                            self?.submitAnswers(value,answers:answers,completion:completion)
                        } : nil,skip:{ [weak self] ids in self?.skippedQuestionIDs.formUnion(ids) }),approval:value.approval.map(ApprovalPresentation.init))
                        turn.notices[signature] = now; noticedAt[key] = now; changed = true
                    }
                }
            } else if ["completed","failed","interrupted"].contains(value.status) {
                running.remove(key)
                if !turn.finished || (previous != nil && previous?.fileEdits != value.fileEdits) {
                    if !turn.finished {turn.finished = true; changed = true; chat.pet.taskEnded(key,status:value.status)}
                    chat.pet.say(chat.pet.preferences.taskResultLine(value.status), body:TaskOutcome.body(status:value.status,error:value.error,final:value.resultText), kind:"task", thread:conversation.key,  resetText:true, purpose:value.status == "completed" ? .result : .attention, personalizeTitle:false, timing:.init(start:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,key:key,finished:value.completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil} ?? Date(),status:value.status),messageID:value.agentMessages.last(where:{$0.isFinal})?.id ?? "result",fileEdits:value.fileEdits)
                }
            }
        }
        initial = false
        let present = Set(values.map{$0.key}), missing = running.subtracting(present)
        diagnostics = "\(values.count) 条 · 活跃 \(running.count) · 待更新 \(missing.count) · " + Date().formatted(.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))
        status = Self.describeStatus(values,missing:missing.count)
        return changed
    }
    private func submitAnswers(_ snapshot:PublicSnapshot,answers:[String:String],completion:@escaping (Error?) -> Void) {
        let questions = snapshot.attention?.questions ?? []
        queue.async {
            do {
                let current = try DesktopHistoryReader.read(excluded:[],watched:[snapshot]).first {$0.key == snapshot.key}
                guard let current,current.attention?.isSensitive == false,
                      Set(questions.map(\.id)).isSubset(of:Set(current.attention?.questions.map(\.id) ?? [])),!questions.isEmpty else {
                    throw PetFailure(message:"这道问题已回答或已结束，请查看 Codex 当前状态。")
                }
                DesktopQuestionReply.submit(thread:snapshot.logical,cwd:snapshot.cwd,questions:questions,answers:answers,completion:completion)
            } catch {DispatchQueue.main.async {completion(error)}}
        }
    }
    private static func describeStatus(_ records: [PublicSnapshot], missing: Int) -> String {
        let counts = Dictionary(grouping:records,by:{$0.status}).mapValues(\.count)
        let working = ["pending","running","inProgress"].reduce(0) {$0+(counts[$1] ?? 0)}
        let known: Set<String> = activeStatuses.union(["completed","failed","interrupted"])
        let unknown = records.filter {!known.contains($0.status)}.count
        let conversations = Set(records.map(\.logical)).count
        var lines = [
            "当前读取到 \(records.count) 条任务记录，来自 \(conversations) 个 Codex 会话。",
            "",
            "正在进行：\(working) 条",
            "等待你批准：\(counts["waitingForApproval"] ?? 0) 条",
            "等待你补充信息：\(counts["waitingForInput"] ?? 0) 条",
            "已完成：\(counts["completed"] ?? 0) 条",
            "已失败：\(counts["failed"] ?? 0) 条",
            "已停止：\(counts["interrupted"] ?? 0) 条"
        ]
        if unknown > 0 {lines.append("状态尚不明确：\(unknown) 条")}
        if missing > 0 {lines.append("另有 \(missing) 条此前仍在进行的任务暂时读不到，正在等待状态更新。")}
        lines += [
            "", "最近刷新："+Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)),
            "", "这些数量怎么理解？",
            "每次发送消息并等待回复算一条任务记录；同一个会话里多次发送会分别计数。",
            "统计范围是最近使用的 Codex 会话，以及桌宠已经在跟踪的任务。",
            "需要批准或补充信息时，请回到原 Codex 会话处理。"
        ]
        return lines.joined(separator:"\n")
    }
    func close() {diagnostics = "已停止"; stopped = true; timer?.invalidate(); queue.async {self.approvalReader.close()}; status = "任务同步已停止，当前不会读取新的任务状态。"}
}
