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
    // 会话存在性与显示名称无关；内置对话的 name 可以尚未生成。
    static func containsThread(_ id:String) throws -> Bool {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let state = try ReadDatabase(root+"/state_5.sqlite")
        return try !state.rows("SELECT id FROM threads WHERE id=? LIMIT 1",[id]).isEmpty
    }
    static func recordedReasoningEffort(thread:String,model:String) throws -> String? {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let state = try ReadDatabase(root+"/state_5.sqlite")
        // 只用原会话、相同模型的记录补充缺失值，不借用全局默认值或其他会话。
        return try state.rows("SELECT reasoning_effort FROM threads WHERE id=? AND model=?",[thread,model]).first?["reasoning_effort"]
    }
    static func requireReplyConversation(_ thread:String,previousTurn:String,steering:Bool) throws {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let state = try ReadDatabase(root+"/state_5.sqlite")
        guard let row = try state.rows("SELECT id,rollout_path FROM threads WHERE id=? AND archived=0",[thread]).first else {
            throw PetFailure(message:"原会话已归档或不存在，请在 Codex 中处理。")
        }
        let path = row["rollout_path"] ?? ""
        let pattern = try NSRegularExpression(pattern:"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
        let actual = pattern.matches(in:path,range:NSRange(path.startIndex...,in:path)).last
            .flatMap {Range($0.range,in:path)}.map {String(path[$0])} ?? thread
        let history = try ReadDatabase(root+"/thread_history_1.sqlite")
        let turns = try history.rows("SELECT turn_id,status FROM thread_turns WHERE thread_id=? ORDER BY started_at DESC LIMIT 1",[actual])
        guard let latest = turns.first,latest["turn_id"] == previousTurn,
              (steering ? ["inProgress","running"] : ["completed","failed","interrupted","cancelled","canceled"]).contains(latest["status"] ?? "") else {
            throw PetFailure(message:"原会话状态已变化。请查看 Codex 当前对话后再发送。")
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
            for row in try state.rows("SELECT id,name AS title FROM threads WHERE id IN ("+placeholders+")",batch) {
                if let id = row["id"],let title = row["title"] {titles[id] = title}
            }
        }
        return titles
    }
    static func read(excluded: Set<String>, watched: [PublicSnapshot], additionalThreads:Set<String> = []) throws -> [PublicSnapshot] {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let state = try ReadDatabase(root+"/state_5.sqlite"), history = try ReadDatabase(root+"/thread_history_1.sqlite")
        var threads = try state.rows("SELECT id,rollout_path,COALESCE(NULLIF(TRIM(name),''),title) AS title,cwd,history_mode FROM threads WHERE archived=0 AND updated_at>=? AND (thread_source='user' OR thread_source IS NULL) AND (source IS NULL OR source NOT LIKE '%subagent%') ORDER BY updated_at DESC LIMIT 40",[String(Int(Date().timeIntervalSince1970)-86400)])
        for logical in Set(watched.map{$0.logical}).union(additionalThreads) where !threads.contains(where:{$0["id"] == logical}) {
            threads += try state.rows("SELECT id,rollout_path,COALESCE(NULLIF(TRIM(name),''),title) AS title,cwd,history_mode FROM threads WHERE id=?",[logical])
        }
        let pattern = try NSRegularExpression(pattern:"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
        var result = [PublicSnapshot]()
        for thread in threads {
            let logical = thread["id"]!, path = thread["rollout_path"] ?? ""
            let match = pattern.matches(in:path,range:NSRange(path.startIndex...,in:path)).last
            let actual = match.flatMap{Range($0.range,in:path)}.map{String(path[$0])} ?? logical
            if excluded.contains(logical) || excluded.contains(actual) {continue}
            var turns = try history.rows("SELECT turn_id,status,error_json,started_at,completed_at FROM thread_turns WHERE thread_id=? ORDER BY started_at DESC LIMIT 3",[actual])
            let latestTurn = turns.first?["turn_id"]
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
                // 只取公开摘要与操作元数据，不读取 reasoning.content、工具 arguments 或输出。
                let items = try history.rows("""
                SELECT item_type,json_extract(item_json,'$.id') item_id,json_extract(item_json,'$.phase') phase,
                CASE WHEN NOT EXISTS (SELECT 1 FROM json_each(item_json,'$.questions') q WHERE json_extract(q.value,'$.isSecret')=1)
                    THEN json_extract(item_json,'$.text') END text,
                json_extract(item_json,'$.status') status,json_extract(item_json,'$.questions') questions,
                json_extract(item_json,'$.reason') reason,
                CASE WHEN item_type='commandExecution' THEN json_extract(item_json,'$.command') END command,
                CASE WHEN item_type='commandExecution' THEN json_extract(item_json,'$.commandActions') END command_actions,
                CASE WHEN item_type='fileChange' THEN json_extract(item_json,'$.changes') END changes,
                CASE WHEN item_type='webSearch' THEN json_extract(item_json,'$.query') END query,
                CASE WHEN item_type='reasoning' THEN json_extract(item_json,'$.summary') END summary,
                CASE WHEN item_type IN ('mcpToolCall','dynamicToolCall') THEN json_extract(item_json,'$.tool') END tool,
                CASE WHEN item_type='mcpToolCall' THEN json_extract(item_json,'$.server') END server,
                CASE WHEN item_type='dynamicToolCall' THEN json_extract(item_json,'$.namespace') END namespace,
                CASE WHEN item_type='imageGeneration' THEN json_extract(item_json,'$.savedPath') END saved_path
                FROM thread_items WHERE thread_id=? AND turn_id=? AND item_type IN
                ('agentMessage','userMessage','reasoning','commandExecution','fileChange','mcpToolCall','dynamicToolCall','webSearch','imageGeneration','imageView','contextCompaction')
                ORDER BY rollout_ordinal DESC LIMIT 200
                """,[actual,turn["turn_id"]!]).reversed()
                var messages = [String](), final = "", alert = ""
                var agentMessages = [PublicAgentMessage]()
                var activity:TaskActivity?
                var activityItems = [[String:Any]]()
                var questions = [[String:Any]](), approval:TaskAttention?, hasSensitiveInput = false, hasSensitiveQuestion = false
                for item in items {
                    if item["item_type"] == "userMessage" {continue}
                    var progress:[String:Any] = ["type":item["item_type"] ?? ""]
                    for key in ["status","tool","server","namespace","command","query"] {if let value = item[key],value != "null" {progress[key] = value}}
                    for (column,field) in [("summary","summary"),("command_actions","commandActions"),("changes","changes")] {
                        if let raw = item[column],raw != "null" {progress[field] = try JSONSerialization.jsonObject(with:Data(raw.utf8))}
                    }
                    activityItems.append(progress)
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
                            if let id = item["item_id"],item["phase"] == nil || ["commentary","final_answer","final"].contains(item["phase"]!) {
                                agentMessages.append(.init(id:id,text:text,isFinal:["final_answer","final"].contains(item["phase"] ?? "")))
                            }
                            if ["final_answer","final"].contains(item["phase"] ?? "") {final = text}
                            else if item["phase"] == nil || item["phase"] == "commentary" {messages.append(text)}
                        }
                    } else if item["item_type"] == "imageGeneration",
                              let link = GeneratedImageLink.markdown(status:item["status"],savedPath:item["saved_path"]) {
                        messages.append(link)
                        if let id = item["item_id"] {agentMessages.append(.init(id:id,text:link,isFinal:false,isImage:true))}
                    } else if ["waitingForApproval","requiresApproval"].contains(item["status"] ?? "") {
                        approval = .approval(fileChange:item["item_type"] == "fileChange",reason:item["reason"])
                    } else if item["status"] == "waitingForInput", questions.isEmpty {
                        questions.append(["title":"需要补充信息，请回到 Codex 处理。"])
                    }
                }
                var attention:TaskAttention?
                if let approval {attention = approval}
                else if let secret = questions.first(where:{$0["isSecret"] as? Bool == true}) {attention = .question(secret)}
                else if !questions.isEmpty {attention = TaskAttention(kind:.answer,body:questions.map {TaskAttention.question($0).body}.joined(separator:"\n\n"),questions:questions.flatMap {TaskAttention.question($0).questions})}
                else if turn["status"] == "waitingForApproval" {attention = .approval(fileChange:false,reason:nil)}
                else if turn["status"] == "waitingForInput" {attention = TaskAttention(kind:.answer,body:"需要补充信息，请回到 Codex 处理。")}
                activity = TaskActivity.current(items:activityItems,replyTemplateKey:"taskUpdateTemplate")
                if !activeStatuses.contains(turn["status"] ?? "") {attention = nil; activity = nil}
                let step = activity?.text ?? ""
                alert = attention?.body ?? ""
                result.append(PublicSnapshot(logical:logical,actual:actual,turn:turn["turn_id"]!,title:thread["title"] ?? "Codex 任务",cwd:thread["cwd"] ?? NSHomeDirectory(),historyMode:thread["history_mode"] ?? "legacy",status:attention?.kind.status ?? turn["status"]!,started:Double(turn["started_at"] ?? "0") ?? 0,messages:messages.joined(separator:"\n\n"),final:final,alert:alert,step:step,error:turn["error_json"] ?? "",completed:Double(turn["completed_at"] ?? ""),attention:attention,hasSensitiveInput:hasSensitiveInput,hasSensitiveQuestion:hasSensitiveQuestion))
                result[result.count-1].agentMessages = agentMessages
                // 修改摘要读取完整轮次，不受上方近期 200 条进展／消息窗口限制。
                let edits = try history.rows("SELECT json_extract(item_json,'$.changes') changes FROM thread_items WHERE thread_id=? AND turn_id=? AND item_type='fileChange' AND json_extract(item_json,'$.status')='completed' ORDER BY rollout_ordinal",[actual,turn["turn_id"]!])
                var fileEdits = [FileEditSummary]()
                for edit in edits {
                    if let raw = edit["changes"],raw != "null" {
                        let changes = try JSONSerialization.jsonObject(with:Data(raw.utf8))
                        fileEdits += FileEditSummary.read(["type":"fileChange","status":"completed","changes":changes])
                    }
                }
                result[result.count-1].fileEdits = FileEditSummary.merged(fileEdits)
                result[result.count-1].activity = activity
                result[result.count-1].isLatest = turn["turn_id"] == latestTurn
            }
        }
        return result.sorted{$0.started < $1.started}
    }
}
