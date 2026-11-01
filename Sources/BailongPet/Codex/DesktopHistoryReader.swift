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
enum DesktopHistoryReader {
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
    static func read(excluded: Set<String>, watched: [PublicSnapshot]) throws -> [PublicSnapshot] {
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
}
