import Foundation
import SQLite3

private final class ReadDatabase {
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
    var key: String { actual+":"+turn }
    var fingerprint: String { [status,messages,final,alert,step,error].joined(separator:"\u{001f}") }
}

final class DesktopSync {
    let chat: ChatController
    private let queue = DispatchQueue(label:"白龙外部任务只读观察",qos:.utility)
    private var timer: Timer?
    private var reading = false, stopped = false, initial = true
    private let born = Date().timeIntervalSince1970
    private var tracked = [String:PublicSnapshot]()
    private var fingerprints = [String:String](), changedAt = [String:Double](), noticedAt = [String:Double]()
    private var running = Set<String>()
    var status = "等待观察本机任务"
    init(chat: ChatController) {
        self.chat = chat
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.poll() }
    }
    private func poll() {
        guard !reading && !stopped else{return}; reading = true
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID})
        let watched = tracked.values.filter{running.contains($0.key)}
        queue.async { [weak self] in
            guard let self else{return}
            do {let values = try Self.read(excluded:excluded,watched:Array(watched)); DispatchQueue.main.async {self.reading = false; if !self.stopped {self.accept(values)}}}
            catch {DispatchQueue.main.async {self.reading = false; self.status = "任务同步暂不可用："+error.localizedDescription}}
        }
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
            var turns = try history.rows("SELECT turn_id,status,error_json,started_at FROM thread_turns WHERE thread_id=? ORDER BY started_at DESC LIMIT 3",[actual])
            for old in watched where old.actual == actual && !turns.contains(where:{$0["turn_id"] == old.turn}) {
                turns += try history.rows("SELECT turn_id,status,error_json,started_at FROM thread_turns WHERE thread_id=? AND turn_id=?",[actual,old.turn])
            }
            for turn in turns {
                // 仅投影公开消息、工具状态及失败摘要；不读取 reasoning、工具参数或成功输出。
                let items = try history.rows("""
                SELECT item_type,json_extract(item_json,'$.phase') phase,json_extract(item_json,'$.text') text,
                json_extract(item_json,'$.status') status,json_extract(item_json,'$.exitCode') exitCode,
                json_extract(item_json,'$.error') error,json_extract(item_json,'$.questions') questions,
                CASE WHEN json_extract(item_json,'$.status')='failed' OR json_extract(item_json,'$.exitCode') NOT IN (0)
                THEN substr(json_extract(item_json,'$.aggregatedOutput'),-2500) ELSE NULL END failedOutput
                FROM thread_items WHERE thread_id=? AND turn_id=? AND item_type IN
                ('agentMessage','commandExecution','fileChange','mcpToolCall','webSearch','imageGeneration','imageView')
                ORDER BY rollout_ordinal DESC LIMIT 200
                """,[actual,turn["turn_id"]!]).reversed()
                var messages = [String](), final = "", alert = "", step = ""
                for item in items {
                    if item["item_type"] == "agentMessage" {
                        if let text = item["text"], !text.isEmpty {
                            if ["final_answer","final"].contains(item["phase"] ?? "") {final = text}
                            else if item["phase"] == nil || item["phase"] == "commentary" {messages.append(text); alert = ""}
                        }
                        if let questions = item["questions"], questions != "[]" && questions != "null" {alert = "这一步需要回答或确认，请回到 Codex 查看。"}
                    } else if ["waitingForApproval","waitingForInput","requiresApproval"].contains(item["status"] ?? "") {
                        alert = "这一步等待权限或补充信息，请回到 Codex 处理。"
                    } else if item["status"] == "failed" || item["error"] != nil || (item["exitCode"] != nil && item["exitCode"] != "0") {
                        let raw = item["error"] ?? item["failedOutput"] ?? "暂未提供错误详情。"
                        let safe = raw.split(separator:"\n").filter { line in !["authorization","api_key","password","token","secret"].contains(where:line.lowercased().contains) }.suffix(3).joined(separator:"\n")
                        alert = "这一步执行遇到问题，任务尚未报告完成。\n"+String(safe.prefix(500))
                    } else if ["inProgress","running"].contains(item["status"] ?? "") {
                        step = ["commandExecution":"正在执行操作","fileChange":"正在修改文件","mcpToolCall":"正在调用工具","webSearch":"正在查阅资料","imageGeneration":"正在生成图片","imageView":"正在查看图片"][item["item_type"] ?? ""] ?? "正在处理"
                    }
                }
                result.append(PublicSnapshot(logical:logical,actual:actual,turn:turn["turn_id"]!,title:thread["title"] ?? "Codex 任务",cwd:thread["cwd"] ?? NSHomeDirectory(),historyMode:thread["history_mode"] ?? "legacy",status:turn["status"]!,started:Double(turn["started_at"] ?? "0") ?? 0,messages:messages.joined(separator:"\n\n"),final:final,alert:alert,step:step,error:turn["error_json"] ?? ""))
            }
        }
        return result.sorted{$0.started < $1.started}
    }
    private func accept(_ values: [PublicSnapshot]) {
        var changed = false
        let now = Date().timeIntervalSince1970
        let excluded = Set(chat.store.conversations.filter{!$0.external}.compactMap{$0.threadID})
        for value in values {
            if excluded.contains(value.logical) || excluded.contains(value.actual) {continue}
            let key = value.key, active = activeStatuses.contains(value.status)
            if tracked[key] == nil && !active && (initial || value.started < born) {continue}
            if tracked[key] == nil && active && value.started < born-86400 {continue}
            var c = chat.store.conversations.first(where:{$0.external && $0.threadID == value.logical})
            if c == nil {c = chat.store.create(cwd:value.cwd,external:true); c!.title = value.title; c!.threadID = value.logical}
            let conversation = c!; conversation.historyMode = value.historyMode
            var t = conversation.turns.first(where:{$0.id == value.turn})
            if t == nil {t = Turn(); t!.id = value.turn; t!.owned = false; t!.date = Date(timeIntervalSince1970:value.started); conversation.turns.append(t!); changed = true}
            let turn = t!, different = fingerprints[key] != value.fingerprint
            tracked[key] = value
            if different {
                fingerprints[key] = value.fingerprint; changedAt[key] = now
                turn.status = value.status; turn.messages = value.messages; turn.final = value.final; turn.steps = value.alert.isEmpty ? value.step : value.alert; turn.error = value.error; changed = true
            }
            if active {
                if !running.contains(key) {running.insert(key); chat.pet.taskStarted(key)}
                let repeatDue = now-(noticedAt[key] ?? 0) >= 300
                if different || repeatDue {
                    let quiet = now-(changedAt[key] ?? now) >= 90
                    let text = !value.alert.isEmpty ? value.alert : ["waitingForInput","waitingForApproval"].contains(value.status) ? "任务正在等待你的处理，请回到原 Codex 窗口。" : quiet ? "已经有一会儿没有新进度，任务尚未报告完成。" : value.messages.isEmpty ? value.step : value.messages.components(separatedBy:"\n\n").last!
                    let signature = text
                    if !text.isEmpty && (turn.notices[signature] == nil || (repeatDue && (!value.alert.isEmpty || quiet || value.status.hasPrefix("waiting")))) {
                        chat.pet.say("主人，我还在留意进展…",body:text,kind:"task",seconds:12,thread:conversation.key,followsText:false)
                        turn.notices[signature] = now; noticedAt[key] = now; changed = true
                    }
                }
            } else if ["completed","failed","interrupted"].contains(value.status) {
                running.remove(key)
                if !turn.finished {
                    turn.finished = true; changed = true; chat.pet.taskEnded(key,status:value.status)
                    chat.pet.say(value.status == "completed" ? "主人，完成啦！" : "主人，任务还没有完成。",body:!value.error.isEmpty ? value.error : !value.final.isEmpty ? value.final : value.title,kind:"task",seconds:20,thread:conversation.key,followsText:false,resetText:true)
                }
            }
        }
        initial = false
        let present = Set(values.map{$0.key}), missing = running.subtracting(present)
        status = missing.isEmpty ? "已观察 \(values.count) 轮，\(running.count) 轮活动中" : "\(missing.count) 个活动轮次暂未返回，等待后续记录；不会视为完成。"
        if changed {chat.persist()}
    }
    func close() {stopped = true; timer?.invalidate()}
}
