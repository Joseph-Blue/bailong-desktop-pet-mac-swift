import Foundation

struct PublicUserMessage:Equatable {
    let id:String
    let text:String
}

struct PublicAgentMessage:Equatable {
    let id:String
    let text:String
    let isFinal:Bool
    var isImage = false
}

struct DesktopQuestionNotice {
    static let openInCodex = L10n.text(.conversation,"desktopSync.openInCodex")
    let body:String
    let form:QuestionPresentation?

    init?(_ attention:TaskAttention?,channel:ProjectSendChannel,
          submit:@escaping ([String:String], @escaping (Error?) -> Void) -> Void,
          skip:@escaping (Set<String>) -> Void) {
        guard let attention,attention.kind == .answer else {return nil}
        if channel == .modern {
            body = Self.openInCodex
            form = nil
        } else {
            body = attention.body
            let questions = attention.questions
            let editable = !attention.isSensitive && !questions.isEmpty && questions.allSatisfy {!$0.id.isEmpty}
            form = .init(questions:questions,submit:editable ? submit : nil,skip:skip)
        }
    }
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
    var modelProvider:String?
    var createdWithChatGPT = false
    var agentMessages = [PublicAgentMessage]()
    var fileEdits = [FileEditSummary]()
    var tokenUsage:TokenUsage?
    var tokenUsageError:String?
    var isLatest = true
    var receivedText:String?
    var steeringMessages = [PublicUserMessage]()
    var resultText:String {GeneratedImageLink.appending(agentMessages.filter(\.isImage).map(\.text),to:final)}
    var key: String { actual+":"+turn }
    var observedTurn: ObservedDesktopTurn {
        ObservedDesktopTurn(key:key,threadID:logical,turnID:turn,status:status,start:Date(timeIntervalSince1970:started),
            end:completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil},title:title,
            activity:attention.map {TaskActivity.waiting(approval:$0.kind == .approval)} ?? activity,
            connectionFailed:!activeStatuses.contains(status) && status != "completed" && CodexErrorMessage(error)?.category == .network,
            directory:cwd,fileEdits:fileEdits)
    }
    var fingerprint:[String] {
        var result = steeringMessages.flatMap {[$0.id,$0.text]}
        result += fileEdits.flatMap(\.signature)
        result += [tokenUsage?.signature ?? "",tokenUsageError ?? ""]
        result += agentMessages.flatMap {[$0.id,$0.text]}
        result += [status,messages,final,alert,step,error,receivedText ?? "",approvalID,approval?.details ?? "",attention?.kind.rawValue ?? "",hasSensitiveInput ? "sensitive-input" : "",hasSensitiveQuestion ? "sensitive-question" : ""]
        for question in attention?.questions ?? [] {
            result += [question.id,question.prompt]
            result += question.options.flatMap {[$0.title,$0.detail ?? "",String($0.recommended)]}
        }
        return result
    }
}

final class DesktopSync {
    let chat: ChatController
    private let queue = DispatchQueue(label:L10n.text(.tasks,"desktopSync.queue.label"),qos:.utility,autoreleaseFrequency:.workItem)
    private let permissionHook = DesktopPermissionListener()
    private var hookChannel:ProjectSendChannel?
    private var hookStartError:String?
    private let approvalReader = DesktopApprovalReader()
    private var timer: Timer?
    private var reading = false, stopped = false, initial = true
    private var monitorReadIssue:String?
    private func recordReadIssue(_ issue:String?) {
        guard issue != monitorReadIssue else {return}
        monitorReadIssue = issue
        guard let monitor = TerminalMonitor.active else {return}
        if let issue {monitor.write(.desktop,issue,.warning)}
        else {monitor.write(.desktop,L10n.text(.tasks,"desktopSync.issue.text"),.success)}
    }
    private var lastTitleSync = Date.distantPast
    private var lastHistoryRead = Date.distantPast
    private var historyValues = [PublicSnapshot]()
    private let born = Date().timeIntervalSince1970
    private var tracked = [String:PublicSnapshot]()
    private var fingerprints = [String:[String]](), changedAt = [String:Double](), noticedAt = [String:Double]()
    private var running = Set<String>()
    private var skippedQuestionIDs = Set<String>()
    private var lastQuestionChannel:ProjectSendChannel?
    private var clearedBefore = UserDefaults.standard.double(forKey:"desktopHistoryClearedBefore")
    func clearLocalProjection() {
        permissionHook.discard()
        skippedQuestionIDs.removeAll()
        clearedBefore = Date().timeIntervalSince1970
        UserDefaults.standard.set(clearedBefore,forKey:"desktopHistoryClearedBefore")
        for key in running {chat.pet.taskEnded(key,status:"interrupted")}
        running.removeAll(); tracked.removeAll(); fingerprints.removeAll(); noticedAt.removeAll(); changedAt.removeAll()
        chat.desktopSession.observedTurns = []; chat.desktopTaskReadStatus = L10n.text(.conversation,"chatController.quota.text")
    }
    private(set) var diagnostics = L10n.text(.conversation,"desktopSync.diagnostics")
    func reportMonitorState(to monitor:TerminalMonitor) {
        let turns = chat.desktopSession.observedTurns.filter(\.active)
        let phase = initial ? L10n.text(.conversation,"desktopSync.phase") : L10n.format(.conversation,"desktopSync.phase.2",String(describing:turns.count))
        monitor.write(.desktop,L10n.text(.tasks,"desktopSync.phase.text")+phase+(monitorReadIssue.map {"  ·  "+$0} ?? ""))
        for turn in turns {
            monitor.write(.desktop,L10n.text(.tasks,"desktopSync.phase.text.2")+TerminalMonitor.tag(turn.turnID)+"  "+TerminalMonitor.status(turn.status)
                + (turn.activity.map {"  ·  "+$0.monitorLabel} ?? ""))
        }
    }
    var status = L10n.text(.conversation,"desktopSync.reportMonitorState.text")
    init(chat: ChatController) {
        self.chat = chat
        permissionHook.canPresent = { [weak chat] in
            guard let pet = chat?.pet else {return false}
            return pet.preferences.projectSendChannel == .modern && !pet.hidden && pet.preferences.allows(.attention)
        }
        chat.onHistoryDeleted = { [weak self] conversation in self?.forget(conversation) }
        timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in self?.poll() }
    }
    private func configurePermissionHook(_ channel:ProjectSendChannel) {
        guard channel != hookChannel else {return}
        hookChannel = channel; hookStartError = nil
        guard channel == .modern else {permissionHook.stop(); return}
        queue.async {self.approvalReader.close()}
        do {try permissionHook.start()}
        catch {
            let message = L10n.text(.conversation,"desktopSync.configurePermissionHook.message")+error.localizedDescription
            hookStartError = message; TerminalMonitor.active?.write(.approval,message,.warning)
        }
    }
    private func forget(_ conversation:Conversation) {
        chat.desktopSession.observedTurns.removeAll {$0.threadID == conversation.threadID}
        let keys = tracked.filter {$0.value.logical == conversation.threadID || $0.value.actual == conversation.threadID}.map(\.key)
        for key in keys {
            tracked.removeValue(forKey:key); fingerprints.removeValue(forKey:key)
            noticedAt.removeValue(forKey:key); changedAt.removeValue(forKey:key)
            if running.remove(key) != nil {chat.pet.stopObservingTask(key)}
        }
    }
    private func poll() {
        guard !stopped else {return}
        configurePermissionHook(chat.pet.preferences.projectSendChannel)
        chat.checkTaskReminder(now:Date().timeIntervalSince1970)
        chat.refreshDesktopSettingsIfNeeded()
        guard !reading && !stopped else{return}; reading = true
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID}).union(chat.store.deletedThreads)
        let watched = tracked.values.filter{running.contains($0.key)}
        let unresolvedThreads = Set(chat.store.conversations.filter {$0.external && $0.turns.contains(where:{activeStatuses.contains($0.status)})}.compactMap(\.threadID))
        let titleIDs = chat.store.recordsAutomatically && Date().timeIntervalSince(lastTitleSync) >= 5 ? chat.store.conversations.filter {$0.external && $0.localTitle == nil}.compactMap(\.threadID) : []
        let legacy = chat.pet.preferences.projectSendChannel == .legacy
        queue.async { [weak self] in
            guard let self else{return}
            do {
                if Date().timeIntervalSince(self.lastHistoryRead) >= 1 {
                    self.historyValues = try DesktopHistoryReader.read(excluded:excluded,watched:Array(watched),additionalThreads:unresolvedThreads)
                    self.lastHistoryRead = Date()
                }
                var values = self.historyValues.filter {!excluded.contains($0.logical) && !excluded.contains($0.actual)}
                var approvalError:String?
                var monitorIssue:String?
                if legacy {
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
                        if self.approvalReader.unavailableCount > 0 {
                            approvalError = L10n.format(.conversation,"desktopSync.poll.text",String(describing:self.approvalReader.unavailableCount))
                            monitorIssue = approvalError
                        }
                    } catch {
                        approvalError = error.localizedDescription
                        monitorIssue = L10n.text(.conversation,"desktopSync.poll.text.2")+TerminalMonitor.errorCode(error)
                    }
                }
                let titles = try DesktopHistoryReader.readTitles(titleIDs)
                DispatchQueue.main.async {
                    self.reading = false; guard !self.stopped else {return}
                    guard legacy == (self.chat.pet.preferences.projectSendChannel == .legacy) else {return}
                    if !legacy {self.permissionHook.project(into:&values)}
                    self.recordReadIssue(monitorIssue)
                    self.chat.desktopTaskReadStatus = nil
                    self.chat.desktopSession.observedTurns = values.filter {$0.isLatest && $0.started > self.clearedBefore && !self.chat.store.deletedThreads.contains($0.logical)}.map(\.observedTurn)
                    if !titleIDs.isEmpty {self.lastTitleSync = Date()}
                    var changed = false
                    for conversation in self.chat.store.conversations where conversation.external && conversation.localTitle == nil && self.chat.store.recordsAutomatically {
                        if let id = conversation.threadID, let title = titles[id], !title.isEmpty, title != conversation.title {
                            conversation.title = title; changed = true
                        }
                    }
                    let displayChanged = values.contains {self.fingerprints[$0.key] != $0.fingerprint || self.tracked[$0.key]?.activity != $0.activity}
                    let recordsChanged = self.accept(values)
                    if let approvalError = approvalError ?? (legacy ? nil : self.hookStartError) {
                        self.diagnostics += L10n.text(.conversation,"desktopSync.poll.text.3")+approvalError
                        self.status += L10n.text(.conversation,"desktopSync.poll.text.4")+approvalError
                    }
                    if recordsChanged || changed {self.chat.persist()}
                    else if displayChanged {self.chat.refresh()}
                }
            }
            catch {DispatchQueue.main.async {
                self.reading = false
                self.permissionHook.discard()
                self.recordReadIssue(L10n.text(.conversation,"desktopSync.poll.text.5")+TerminalMonitor.errorCode(error))
                self.chat.desktopSession.observedTurns = []; self.chat.desktopTaskReadStatus = L10n.text(.conversation,"desktopSync.poll.text.6"); self.diagnostics = L10n.text(.conversation,"desktopSync.poll.text.7") + error.localizedDescription; self.status = L10n.text(.conversation,"desktopSync.poll.text.8")+error.localizedDescription}}
        }
    }
    private func accept(_ values: [PublicSnapshot]) -> Bool {
        var changed = false
        let channel = chat.pet.preferences.projectSendChannel
        let channelChanged = lastQuestionChannel != nil && lastQuestionChannel != channel
        lastQuestionChannel = channel
        let now = Date().timeIntervalSince1970
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID}).union(chat.store.deletedThreads)
        let currentActive = Set(values.filter {$0.isLatest && activeStatuses.contains($0.status)}.map(\.key))
        for key in running.subtracting(currentActive) {
            if tracked[key]?.attention != nil {chat.pet.bubble.resolveQuestions(taskKey:key)}
            chat.pet.stopObservingTask(key); running.remove(key)
        }
        for var value in values {
            var skippedAll = false
            let questionModeChanged = channelChanged && value.attention?.kind == .answer
            if channel == .legacy,let attention = value.attention,attention.kind == .answer,!attention.isSensitive,!attention.questions.isEmpty {
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
            let existing = chat.store.conversations.first(where:{$0.external && $0.threadID == value.logical})
            let previouslyFinished = existing?.turns.first(where:{$0.id == value.turn})?.finished == true
            if let existing,value.createdWithChatGPT,existing.createdWithChatGPT != true {
                existing.createdWithChatGPT = true; changed = true
            }
            if tracked[key] == nil && !active && (initial || value.started < born || previouslyFinished) {
                // 补齐扫描范围内已有历史的图片入口与文件摘要，不把旧任务重新弹出或新增为历史。
                if chat.store.recordsAutomatically,!chat.store.isReadOnly,
                   let conversation = existing,
                   let turn = conversation.turns.first(where:{$0.id == value.turn}) {
                    if let provider = value.modelProvider,conversation.modelProvider != provider {
                        conversation.modelProvider = provider; changed = true
                    }
                    if chat.store.canEnrichInput(turn,in:conversation),let input = value.receivedText,turn.input.isEmpty,!input.isEmpty {turn.input = input; changed = true}
                    let enriched = GeneratedImageLink.appending(value.agentMessages.filter(\.isImage).map(\.text),to:turn.messages)
                    if enriched != turn.messages {turn.messages = enriched; changed = true}
                    if turn.fileEdits != value.fileEdits {turn.fileEdits = value.fileEdits; changed = true}
                    if chat.store.canEnrichInput(turn,in:conversation),turn.tokenUsage != value.tokenUsage || turn.tokenUsageError != value.tokenUsageError {
                        turn.tokenUsage = value.tokenUsage; turn.tokenUsageError = value.tokenUsageError; changed = true
                    }
                }
                continue
            }
            if tracked[key] == nil && active && value.started < born-86400 {continue}
            var c = existing
            if c == nil {
                c = chat.store.create(cwd:value.cwd,external:true); c!.title = value.title; c!.threadID = value.logical
                if value.createdWithChatGPT {c!.createdWithChatGPT = true}
            }
            let conversation = c!; conversation.historyMode = value.historyMode
            if let provider = value.modelProvider,conversation.modelProvider != provider {
                conversation.modelProvider = provider; changed = true
            }
            if chat.store.recordsAutomatically && conversation.localTitle == nil && !value.title.isEmpty && conversation.title != value.title {conversation.title = value.title; changed = true}
            var t = conversation.turns.first(where:{$0.id == value.turn})
            if t == nil {t = Turn(); t!.id = value.turn; t!.owned = false; t!.date = Date(timeIntervalSince1970:value.started); conversation.turns.append(t!); changed = true}
            let previous = tracked[key]
            let turn = t!, previousAttention = previous?.attention?.kind, different = fingerprints[key] != value.fingerprint
            if value.started > 0,turn.date != Date(timeIntervalSince1970:value.started) {
                turn.date = Date(timeIntervalSince1970:value.started); changed = true
            }
            if TaskOutcome.terminalStatuses.contains(value.status) {
                let end = value.completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil} ?? turn.completedAt ?? Date()
                if turn.completedAt != end {turn.completedAt = end; changed = true}
            }
            if let monitor = TerminalMonitor.active {
                let context = {TerminalMonitor.context(conversation.key,turn:value.turn)}
                if previous?.status != value.status {
                    let level:TerminalMonitor.Level = value.status == "failed" ? .error : value.status == "completed" ? .success : .info
                    monitor.write(.desktop,context()+L10n.text(.tasks,"desktopSync.level.text")+TerminalMonitor.status(value.status),level)
                }
                if active,let activity = value.activity,previous?.activity?.monitorLabel != activity.monitorLabel {
                    monitor.write(.desktop,context()+L10n.text(.tasks,"desktopSync.activity.text")+activity.monitorLabel,activity.outcome == .failed ? .error : .info)
                }
                if previous?.approvalID != value.approvalID || previousAttention != value.attention?.kind {
                    if value.approval != nil {monitor.write(.approval,context()+L10n.text(.tasks,"desktopSync.labels.text"))}
                    else if let attention = value.attention {monitor.write(.approval,context()+L10n.text(.tasks,"desktopSync.attention.text")+(attention.kind == .approval ? L10n.text(.tasks,"desktopSync.attention.text.2") : L10n.text(.tasks,"desktopSync.attention.text.3")))}
                    else if previousAttention != nil {monitor.write(.approval,context()+L10n.text(.tasks,"desktopSync.attention.text.4"))}
                }
            }
            tracked[key] = value
            if previous == nil {noticedAt[key] = now}
            if previous?.activity != value.activity {changedAt[key] = now}
            if active && value.attention == nil && !value.status.hasPrefix("waiting"),
               previous == nil || previous?.receivedText != value.receivedText {
                chat.showUserMessage(value.receivedText ?? "",in:conversation,timing:.init(start:turn.date,key:key),messageID:"task-received")
            }
            if different {
                if value.activity == nil || !active {chat.pet.bubble.removeActivity(taskKey:key)}
                if active && previousAttention != nil && value.attention == nil {chat.pet.bubble.resolveQuestions(taskKey:key)}
                if value.alert.isEmpty && !value.status.hasPrefix("waiting") && chat.pet.bubble.purpose == .attention && chat.pet.bubble.relatedConversation == conversation.key {
                    chat.pet.bubble.hide()
                }
                fingerprints[key] = value.fingerprint; changedAt[key] = now
                if let input = value.receivedText,turn.input.isEmpty,!input.isEmpty {turn.input = input}
                if value.hasSensitiveQuestion {turn.sensitiveQuestionNotice = chat.pet.preferences.sensitiveQuestionNotice}
                if value.hasSensitiveInput {turn.sensitiveInputNotice = chat.pet.preferences.sensitiveInputNotice}
                if turn.messages != value.messages || turn.final != value.final {
                    let time = previous == nil ? (value.completed ?? value.started) : now
                    turn.lastMessageAt = Date(timeIntervalSince1970:time)
                }
                turn.fileEdits = value.fileEdits
                turn.tokenUsage = value.tokenUsage; turn.tokenUsageError = value.tokenUsageError
                turn.status = value.status; turn.messages = value.messages; turn.final = value.final; turn.steps = value.attention?.isSensitive == true ? "" : value.alert.isEmpty ? value.step : value.alert; turn.error = value.error; changed = true
            }
            if different {
                // 保留消息边界；一次轮询读到多条也逐条入卡，同一 item 的流式变化原地更新。
                let messages = value.agentMessages.filter {!$0.isFinal}
                let incoming = previous == nil && value.started < born ? Array(messages.suffix(1)) : messages
                for message in incoming where previous?.agentMessages.first(where:{$0.id == message.id})?.text != message.text {
                    chat.pet.say(chat.pet.preferences.statusLine("taskUpdateTemplate"),body:message.text,kind:"task",thread:conversation.key,
                        purpose:.progress,personalizeTitle:false,animateHeading:active,
                        timing:.init(start:Date(timeIntervalSince1970:value.started),key:key,finished:active ? nil : turn.completedAt,status:active ? nil : value.status),messageID:message.id)
                    noticedAt[key] = now
                }
                // 同一观察入口覆盖桌宠 IPC 与 Codex 端插话；回执不另造卡片。
                // 首次接入已在运行的旧任务不重放先前插话；后续只显示真实 ID 的新增或更新。
                if previous != nil || value.started >= born {
                    for message in value.steeringMessages where previous?.steeringMessages.first(where:{$0.id == message.id})?.text != message.text {
                        chat.showUserMessage(message.text,in:conversation,
                            timing:.init(start:turn.date,key:key,finished:active ? nil : turn.completedAt,status:active ? nil : value.status),
                            messageID:"user-"+message.id,steering:true)
                    }
                }
            }
            if active {
                // 重连提示不按相同文案过滤，沿用现有状态入口与观察节奏。
                if value.attention == nil,(previous?.activity != value.activity || value.activity?.isReconnecting == true) {
                    chat.pet.showProgressToast(value.activity,key:key,timing:.init(start:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,key:key),thread:conversation.key)
                }
                if !running.contains(key) {running.insert(key); chat.pet.taskStarted(key)}
                if value.attention == nil && ["running","inProgress"].contains(value.status),
                   TaskReminderClock.isDue(now:now,lastProgress:changedAt[key] ?? now,lastNotice:noticedAt[key] ?? now,interval:chat.pet.preferences.number("taskReminderMinutes")*60),
                   chat.showTaskReminder(conversation:conversation,start:turn.date,key:key) {noticedAt[key] = now}
                let repeatDue = now-(noticedAt[key] ?? now) >= 300
                if !skippedAll && (different || repeatDue || questionModeChanged) {
                    let quiet = now-(changedAt[key] ?? now) >= 90
                    let question = DesktopQuestionNotice(value.attention,channel:channel,submit:{ [weak self] answers,completion in
                        self?.submitAnswers(value,answers:answers,completion:completion)
                    },skip:{ [weak self] ids in self?.skippedQuestionIDs.formUnion(ids) })
                    let statusText = !value.alert.isEmpty ? value.alert : ["waitingForInput","waitingForApproval"].contains(value.status) ? L10n.text(.conversation,"desktopSync.statusText") : quiet ? L10n.text(.tasks,"taskReminder.showTaskReminder.text") : value.messages.isEmpty ? value.step : value.agentMessages.last(where:{!$0.isFinal})?.text ?? value.messages
                    let text = question?.body ?? statusText
                    let questionIDs = value.attention?.questions.map(\.id).joined(separator:"\u{001f}") ?? ""
                    let signature = (value.attention?.kind.rawValue ?? "progress")+":"+value.approvalID+":"+questionIDs+":"+text
                    if (value.attention != nil || value.status.hasPrefix("waiting")) && !text.isEmpty && (questionModeChanged || turn.notices[signature] == nil || previous?.approval?.details != value.approval?.details || previousAttention != value.attention?.kind || (repeatDue && (!value.alert.isEmpty || quiet || value.status.hasPrefix("waiting")))) {
                        chat.pet.say(chat.pet.preferences.statusLine(value.attention?.kind.templateKey ?? "taskProgressTemplate"), body:text, kind:"task", thread:conversation.key, purpose:!value.alert.isEmpty || value.status.hasPrefix("waiting") ? .attention : .progress, personalizeTitle:false, animateHeading:value.attention == nil, attentionAction:value.attention != nil, timing:.init(start:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,key:key,status:value.attention?.kind.status), question:question?.form,approval:value.approval.map(ApprovalPresentation.init))
                        turn.notices[signature] = now; noticedAt[key] = now; changed = true
                    }
                }
            } else if TaskOutcome.terminalStatuses.contains(value.status) {
                running.remove(key)
                if !turn.finished || (previous != nil && (previous?.fileEdits != value.fileEdits || previous?.tokenUsage != value.tokenUsage || previous?.tokenUsageError != value.tokenUsageError)) {
                    if !turn.finished {turn.finished = true; changed = true; chat.pet.taskEnded(key,status:value.status)}
                    let failure = value.status != "completed" && CodexErrorMessage(value.error) != nil ? AppFailure.codex(value.error) : nil
                    let completedAt = value.completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil}
                    let body = failure?.message ?? TaskOutcome.body(status:value.status,error:value.error,final:value.resultText)
                    chat.pet.say(chat.pet.preferences.taskResultLine(value.status),body:body,kind:"task",thread:conversation.key,
                        resetText:true,purpose:value.status == "completed" ? .result : .attention,personalizeTitle:false,
                        timing:.init(start:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,
                                     key:key,finished:completedAt ?? Date(),status:value.status),
                        messageID:value.agentMessages.last(where:{$0.isFinal})?.id ?? "result",fileEdits:value.fileEdits,
                        completionFooter:TurnCompletion(turn,completedAt:completedAt),failure:failure)
                }
            }
        }
        if initial {
            TerminalMonitor.active?.write(.desktop,L10n.format(.tasks,"desktopSync.labels.text.2",String(describing:values.count),String(describing:currentActive.count)),.success)
            initial = false
        }
        let present = Set(values.map{$0.key}), missing = running.subtracting(present)
        // 离开扫描范围的已结束轮次仅留在持久历史，不在观察器再留一份正文与指纹。
        let retained = present.union(running)
        tracked = tracked.filter {retained.contains($0.key)}
        fingerprints = fingerprints.filter {retained.contains($0.key)}
        changedAt = changedAt.filter {retained.contains($0.key)}
        noticedAt = noticedAt.filter {retained.contains($0.key)}
        diagnostics = L10n.format(.conversation,"desktopSync.accept.text",String(describing:values.count),String(describing:running.count),String(describing:missing.count)) + Date().formatted(.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))
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
                    throw PetFailure(message:L10n.text(.conversation,"desktopSync.submitAnswers.message"))
                }
                DispatchQueue.main.async {
                    guard self.chat.pet.preferences.projectSendChannel == .legacy else {
                        completion(PetFailure(message:DesktopQuestionNotice.openInCodex)); return
                    }
                    DesktopQuestionReply.submit(thread:snapshot.logical,cwd:snapshot.cwd,questions:questions,answers:answers,completion:completion)
                }
            } catch {DispatchQueue.main.async {completion(error)}}
        }
    }
    private static func describeStatus(_ records: [PublicSnapshot], missing: Int) -> String {
        let counts = Dictionary(grouping:records,by:{$0.status}).mapValues(\.count)
        let working = ["pending","running","inProgress"].reduce(0) {$0+(counts[$1] ?? 0)}
        let known: Set<String> = activeStatuses.union(TaskOutcome.terminalStatuses)
        let stopped = TaskOutcome.stoppedStatuses.reduce(0) {$0 + (counts[$1] ?? 0)}
        let unknown = records.filter {!known.contains($0.status)}.count
        let conversations = Set(records.map(\.logical)).count
        var lines = [
            L10n.format(.conversation,"desktopSync.describeStatus.text",String(describing:records.count),String(describing:conversations)),
            "",
            L10n.format(.conversation,"desktopSync.describeStatus.text.2",String(describing:working)),
            L10n.format(.conversation,"desktopSync.describeStatus.text.3",String(describing:counts["waitingForApproval"] ?? 0)),
            L10n.format(.conversation,"desktopSync.describeStatus.text.4",String(describing:counts["waitingForInput"] ?? 0)),
            L10n.format(.conversation,"desktopSync.describeStatus.text.5",String(describing:counts["completed"] ?? 0)),
            L10n.format(.conversation,"desktopSync.describeStatus.text.6",String(describing:counts["failed"] ?? 0)),
            L10n.format(.conversation,"desktopSync.describeStatus.text.7",String(describing:stopped))
        ]
        if unknown > 0 {lines.append(L10n.format(.conversation,"desktopSync.describeStatus.text.8",String(describing:unknown)))}
        if missing > 0 {lines.append(L10n.format(.conversation,"desktopSync.describeStatus.text.9",String(describing:missing)))}
        lines += [
            "", L10n.text(.conversation,"desktopSync.describeStatus.text.10")+Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)),
        ]
        return lines.joined(separator:"\n")
    }
    func close() {permissionHook.stop(); diagnostics = L10n.text(.conversation,"desktopSync.close.text"); stopped = true; timer?.invalidate(); queue.async {self.approvalReader.close()}; status = L10n.text(.conversation,"desktopSync.close.text.2")}
}
