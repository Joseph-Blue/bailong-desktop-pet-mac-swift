import Foundation
import SQLite3

final class ReadDatabase {
    var db: OpaquePointer?
    init(_ path: String) throws {
        let result = sqlite3_open_v2(path,&db,SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,nil)
        guard result == SQLITE_OK else {let message = db.map{String(cString:sqlite3_errmsg($0))} ?? path; if let db {sqlite3_close(db)}; db = nil; throw PetFailure(message:message)}
        sqlite3_busy_timeout(db,150)
    }
    deinit {sqlite3_close(db)}
    func rows(_ sql: String, _ values: [String] = []) throws -> [[String:String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else {throw PetFailure(message:String(cString:sqlite3_errmsg(db)))}
        defer {sqlite3_finalize(statement)}
        for (i,value) in values.enumerated() { _ = value.withCString{sqlite3_bind_text(statement,Int32(i+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))} }
        var result = [[String:String]]()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {break}
            guard step == SQLITE_ROW else {throw PetFailure(message:String(cString:sqlite3_errmsg(db)))}
            var row = [String:String]()
            for index in 0..<sqlite3_column_count(statement) {
                if let value = sqlite3_column_text(statement,index) { row[String(cString:sqlite3_column_name(statement,index))] = String(cString:value) }
            }
            result.append(row)
        }
        return result
    }
}
struct PublicSnapshot {
    var logical: String, actual: String, turn: String, title: String, cwd: String, historyMode: String
    var status: String, started: Double, messages: String, final: String, alert: String, step: String, error: String
    var completed: Double?
    var attention: TaskAttention?
    var hasSensitiveInput = false
    var hasSensitiveQuestion = false
    var key: String { actual+":"+turn }
    var fingerprint: String { [status,messages,final,alert,step,error,attention?.kind.rawValue ?? "",hasSensitiveInput ? "sensitive-input" : "",hasSensitiveQuestion ? "sensitive-question" : ""].joined(separator:"\u{001f}") }
}

final class DesktopSync {
    let chat: ChatController
    private let queue = DispatchQueue(label:"白龙娘外部任务只读观察",qos:.utility)
    private var timer: Timer?
    private var reading = false, stopped = false, initial = true
    private var lastTitleSync = Date.distantPast
    private let born = Date().timeIntervalSince1970
    private var tracked = [String:PublicSnapshot]()
    private var fingerprints = [String:String](), changedAt = [String:Double](), noticedAt = [String:Double]()
    private var running = Set<String>()
    private var skippedQuestionIDs = Set<String>()
    private var clearedBefore = UserDefaults.standard.double(forKey:"desktopHistoryClearedBefore")
    func clearLocalProjection() {
        skippedQuestionIDs.removeAll()
        clearedBefore = Date().timeIntervalSince1970
        UserDefaults.standard.set(clearedBefore,forKey:"desktopHistoryClearedBefore")
        for key in running {chat.pet.taskEnded(key,status:"interrupted")}
        running.removeAll(); tracked.removeAll(); fingerprints.removeAll(); noticedAt.removeAll(); changedAt.removeAll()
    }
    private(set) var diagnostics = "等待同步"
    var status = "正在准备读取本机 Codex 的任务记录。\n读取成功后，这里会显示任务数量、当前状态和最近刷新时间。"
    init(chat: ChatController) {
        self.chat = chat
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.poll() }
    }
    private func poll() {
        guard !reading && !stopped else{return}; reading = true
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID})
        let watched = tracked.values.filter{running.contains($0.key)}
        let titleIDs = Date().timeIntervalSince(lastTitleSync) >= 15 ? chat.store.conversations.filter(\.external).compactMap(\.threadID) : []
        queue.async { [weak self] in
            guard let self else{return}
            do {
                let values = try Self.read(excluded:excluded,watched:Array(watched))
                let titles = try Self.readTitles(titleIDs)
                DispatchQueue.main.async {
                    self.reading = false; guard !self.stopped else {return}
                    if !titleIDs.isEmpty {self.lastTitleSync = Date()}
                    var changed = false
                    for conversation in self.chat.store.conversations where conversation.external {
                        if let id = conversation.threadID, let title = titles[id], !title.isEmpty, title != conversation.title {
                            conversation.title = title; changed = true
                        }
                    }
                    self.accept(values)
                    if changed {self.chat.persist()}
                }
            }
            catch {DispatchQueue.main.async {self.reading = false; self.diagnostics = "读取失败：" + error.localizedDescription; self.status = "暂时无法读取 Codex 的任务记录。\n桌宠会自动重试；你也可以打开 Codex，确认会话能够正常使用。\n\n具体原因（供排查）：\n"+error.localizedDescription}}
        }
    }
    static func readTitles(_ ids:[String]) throws -> [String:String] {
        guard !ids.isEmpty else {return [:]}
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let state = try ReadDatabase(root+"/state_5.sqlite")
        var titles = [String:String]()
        for start in stride(from:0,to:ids.count,by:400) {
            let batch = Array(ids[start..<min(ids.count,start+400)])
            let placeholders = Array(repeating:"?",count:batch.count).joined(separator:",")
            for row in try state.rows("SELECT id,title FROM threads WHERE id IN ("+placeholders+")",batch) {
                if let id = row["id"],let title = row["title"] {titles[id] = title}
            }
        }
        return titles
    }
    private static func read(excluded: Set<String>, watched: [PublicSnapshot]) throws -> [PublicSnapshot] {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let state = try ReadDatabase(root+"/state_5.sqlite"), history = try ReadDatabase(root+"/thread_history_1.sqlite")
        var threads = try state.rows("SELECT id,rollout_path,title,cwd,history_mode FROM threads WHERE archived=0 AND updated_at>=? AND (thread_source='user' OR thread_source IS NULL) AND (source IS NULL OR source NOT LIKE '%subagent%') ORDER BY updated_at DESC LIMIT 40",[String(Int(Date().timeIntervalSince1970)-86400)])
        for logical in Set(watched.map{$0.logical}) where !threads.contains(where:{$0["id"] == logical}) {
            threads += try state.rows("SELECT id,rollout_path,title,cwd,history_mode FROM threads WHERE id=?",[logical])
        }
        let pattern = try NSRegularExpression(pattern:"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
        var result = [PublicSnapshot]()
        for thread in threads {
            let logical = thread["id"]!, path = thread["rollout_path"] ?? ""
            let match = pattern.matches(in:path,range:NSRange(path.startIndex...,in:path)).last
            let actual = match.flatMap{Range($0.range,in:path)}.map{String(path[$0])} ?? logical
            if excluded.contains(logical) || excluded.contains(actual) {continue}
            var turns = try history.rows("SELECT turn_id,status,error_json,started_at,completed_at FROM thread_turns WHERE thread_id=? ORDER BY started_at DESC LIMIT 3",[actual])
            for old in watched where old.actual == actual && !turns.contains(where:{$0["turn_id"] == old.turn}) {
                turns += try history.rows("SELECT turn_id,status,error_json,started_at,completed_at FROM thread_turns WHERE thread_id=? AND turn_id=?",[actual,old.turn])
            }
            // 回答会写入后续 userMessage；跨轮次只取问题 ID，不读取答案正文。
            let answeredRows = try history.rows("""
                SELECT DISTINCT json_extract(reply.value,'$.questionItemId') question_id
                FROM thread_items item, json_each(item.item_json,'$.content') part,
                json_each(CASE WHEN json_extract(part.value,'$.text') LIKE '<send_user_message_question_reply>%'
                    AND json_valid(replace(replace(json_extract(part.value,'$.text'),'<send_user_message_question_reply>',''),'</send_user_message_question_reply>',''))
                    THEN replace(replace(json_extract(part.value,'$.text'),'<send_user_message_question_reply>',''),'</send_user_message_question_reply>','') ELSE '[]' END) reply
                WHERE item.thread_id=? AND item.item_type='userMessage' AND json_type(reply.value,'$.questionItemId')='text'
                """,[actual])
            let answeredIDs = Set(answeredRows.compactMap {$0["question_id"]})
            for turn in turns {
                // 工具中间失败由原 Codex 对话处理；这里只观察公开消息、进展和待处理状态。
                // 不读取 reasoning、工具参数、退出码或工具输出，也不据此生成失败提醒。
                let items = try history.rows("""
                SELECT item_type,json_extract(item_json,'$.id') item_id,json_extract(item_json,'$.phase') phase,
                CASE WHEN NOT EXISTS (SELECT 1 FROM json_each(item_json,'$.questions') q WHERE json_extract(q.value,'$.isSecret')=1)
                    THEN json_extract(item_json,'$.text') END text,
                json_extract(item_json,'$.status') status,json_extract(item_json,'$.questions') questions,
                json_extract(item_json,'$.reason') reason
                FROM thread_items WHERE thread_id=? AND turn_id=? AND item_type IN
                ('agentMessage','userMessage','commandExecution','fileChange','mcpToolCall','webSearch','imageGeneration','imageView')
                ORDER BY rollout_ordinal DESC LIMIT 200
                """,[actual,turn["turn_id"]!]).reversed()
                var messages = [String](), final = "", alert = "", step = ""
                var questions = [[String:Any]](), approval:TaskAttention?, hasSensitiveInput = false, hasSensitiveQuestion = false
                for item in items {
                    if item["item_type"] == "userMessage" {continue}
                    if let raw = item["questions"], raw != "null", let incoming = try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [[String:Any]] {
                        for (index,var question) in incoming.enumerated() {
                            if let itemID = item["item_id"] {
                                let id = try JSONSerialization.data(withJSONObject:["request_user_input_async",itemID,index])
                                question["id"] = String(decoding:id,as:UTF8.self)
                            }
                            let secret = question["isSecret"] as? Bool == true
                            hasSensitiveQuestion = hasSensitiveQuestion || secret
                            if answeredIDs.contains(question["id"] as? String ?? "") {hasSensitiveInput = hasSensitiveInput || secret}
                            else {questions.append(question)}
                        }
                    }
                    if item["item_type"] == "agentMessage" {
                        if let text = item["text"], !text.isEmpty {
                            if ["final_answer","final"].contains(item["phase"] ?? "") {final = text; step = ""}
                            else if item["phase"] == nil || item["phase"] == "commentary" {messages.append(text)}
                        }
                    } else if ["waitingForApproval","requiresApproval"].contains(item["status"] ?? "") {
                        approval = .approval(fileChange:item["item_type"] == "fileChange",reason:item["reason"])
                    } else if item["status"] == "waitingForInput", questions.isEmpty {
                        questions.append(["title":"需要补充信息，请回到 Codex 处理。"])
                    } else if ["inProgress","running"].contains(item["status"] ?? "") {
                        step = ["commandExecution":"正在执行操作","fileChange":"正在修改文件","mcpToolCall":"正在调用工具","webSearch":"正在查阅资料","imageGeneration":"正在生成图片","imageView":"正在查看图片"][item["item_type"] ?? ""] ?? "正在处理"
                    }
                }
                var attention:TaskAttention?
                if let approval {attention = approval}
                else if let secret = questions.first(where:{$0["isSecret"] as? Bool == true}) {attention = .question(secret)}
                else if !questions.isEmpty {attention = TaskAttention(kind:.answer,body:questions.map {TaskAttention.question($0).body}.joined(separator:"\n\n"),questions:questions.flatMap {TaskAttention.question($0).questions})}
                else if turn["status"] == "waitingForApproval" {attention = .approval(fileChange:false,reason:nil)}
                else if turn["status"] == "waitingForInput" {attention = TaskAttention(kind:.answer,body:"需要补充信息，请回到 Codex 处理。")}
                if ["completed","failed","interrupted"].contains(turn["status"] ?? "") {attention = nil; step = ""}
                alert = attention?.body ?? ""
                result.append(PublicSnapshot(logical:logical,actual:actual,turn:turn["turn_id"]!,title:thread["title"] ?? "Codex 任务",cwd:thread["cwd"] ?? NSHomeDirectory(),historyMode:thread["history_mode"] ?? "legacy",status:attention?.kind.status ?? turn["status"]!,started:Double(turn["started_at"] ?? "0") ?? 0,messages:messages.joined(separator:"\n\n"),final:final,alert:alert,step:step,error:turn["error_json"] ?? "",completed:Double(turn["completed_at"] ?? ""),attention:attention,hasSensitiveInput:hasSensitiveInput,hasSensitiveQuestion:hasSensitiveQuestion))
            }
        }
        return result.sorted{$0.started < $1.started}
    }
    private func accept(_ values: [PublicSnapshot]) {
        var changed = false
        let now = Date().timeIntervalSince1970
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID})
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
            let key = value.key, active = activeStatuses.contains(value.status)
            if tracked[key] == nil && !active && (initial || value.started < born) {continue}
            if tracked[key] == nil && active && value.started < born-86400 {continue}
            var c = chat.store.conversations.first(where:{$0.external && $0.threadID == value.logical})
            if c == nil {c = chat.store.create(cwd:value.cwd,external:true); c!.title = value.title; c!.threadID = value.logical}
            let conversation = c!; conversation.historyMode = value.historyMode
            if !value.title.isEmpty && conversation.title != value.title {conversation.title = value.title; changed = true}
            var t = conversation.turns.first(where:{$0.id == value.turn})
            if t == nil {t = Turn(); t!.id = value.turn; t!.owned = false; t!.date = Date(timeIntervalSince1970:value.started); conversation.turns.append(t!); changed = true}
            let turn = t!, previousAttention = tracked[key]?.attention?.kind, different = fingerprints[key] != value.fingerprint
            tracked[key] = value
            if different {
                if previousAttention == .answer && value.attention == nil {chat.pet.bubble.resolveQuestions(taskKey:key)}
                if value.alert.isEmpty && !value.status.hasPrefix("waiting") && chat.pet.bubble.purpose == .attention && chat.pet.bubble.relatedConversation == conversation.key {
                    chat.pet.bubble.hide()
                }
                fingerprints[key] = value.fingerprint; changedAt[key] = now
                if value.hasSensitiveQuestion {turn.sensitiveQuestionNotice = chat.pet.preferences.sensitiveQuestionNotice}
                if value.hasSensitiveInput {turn.sensitiveInputNotice = chat.pet.preferences.sensitiveInputNotice}
                turn.status = value.status; turn.messages = value.messages; turn.final = value.final; turn.steps = value.attention?.isSensitive == true ? "" : value.alert.isEmpty ? value.step : value.alert; turn.error = value.error; changed = true
            }
            if active {
                if !running.contains(key) {running.insert(key); chat.pet.taskStarted(key)}
                let repeatDue = now-(noticedAt[key] ?? 0) >= 300
                if !skippedAll && (different || repeatDue) {
                    let quiet = now-(changedAt[key] ?? now) >= 90
                    let text = !value.alert.isEmpty ? value.alert : ["waitingForInput","waitingForApproval"].contains(value.status) ? "任务正在等待你的处理，请回到原 Codex 窗口。" : quiet ? "已经有一会儿没有新进度，任务尚未报告完成。" : value.messages.isEmpty ? value.step : value.messages.components(separatedBy:"\n\n").last!
                    let signature = (value.attention?.kind.rawValue ?? "progress")+":"+text
                    if !text.isEmpty && (turn.notices[signature] == nil || previousAttention != value.attention?.kind || (repeatDue && (!value.alert.isEmpty || quiet || value.status.hasPrefix("waiting")))) {
                        chat.pet.say(chat.pet.preferences.statusLine(value.attention?.kind.templateKey ?? "taskProgressTemplate"),body:text,kind:"task",thread:conversation.key,followsText:false,purpose:!value.alert.isEmpty || value.status.hasPrefix("waiting") ? .attention : .progress,personalizeTitle:false,animateHeading:value.attention == nil,taskStartedAt:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,taskKey:key,attentionAction:value.attention != nil,questions:value.attention?.questions ?? [],questionSubmit:value.attention?.kind == .answer && value.attention?.isSensitive == false && value.attention?.questions.allSatisfy({!$0.id.isEmpty}) == true ? { [weak self] answers,completion in
                            self?.submitAnswers(value,answers:answers,completion:completion)
                        } : nil,questionSkip:{ [weak self] ids in self?.skippedQuestionIDs.formUnion(ids) })
                        turn.notices[signature] = now; noticedAt[key] = now; changed = true
                    }
                }
            } else if ["completed","failed","interrupted"].contains(value.status) {
                running.remove(key)
                if !turn.finished {
                    turn.finished = true; changed = true; chat.pet.taskEnded(key,status:value.status)
                    chat.pet.say(chat.pet.preferences.taskResultLine(value.status),body:TaskOutcome.body(status:value.status,error:value.error,final:value.final),kind:"task",thread:conversation.key,followsText:false,resetText:true,purpose:value.status == "completed" ? .result : .attention,personalizeTitle:false,taskStartedAt:value.started > 0 ? Date(timeIntervalSince1970:value.started) : nil,taskKey:key,taskFinishedAt:value.completed.flatMap {$0 > 0 ? Date(timeIntervalSince1970:$0) : nil} ?? Date(),taskStatus:value.status)
                }
            }
        }
        initial = false
        let present = Set(values.map{$0.key}), missing = running.subtracting(present)
        diagnostics = "\(values.count) 条 · 活跃 \(running.count) · 待更新 \(missing.count) · " + Date().formatted(.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))
        status = Self.describeStatus(values,missing:missing.count)
        if changed {chat.persist()}
    }
    private func submitAnswers(_ snapshot:PublicSnapshot,answers:[String:String],completion:@escaping (Error?) -> Void) {
        let questions = snapshot.attention?.questions ?? []
        queue.async {
            do {
                let current = try Self.read(excluded:[],watched:[snapshot]).first {$0.key == snapshot.key}
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
    func close() {diagnostics = "已停止"; stopped = true; timer?.invalidate(); status = "任务同步已停止，当前不会读取新的任务状态。"}
}
