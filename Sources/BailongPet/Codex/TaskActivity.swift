import Foundation

struct TaskActivity:Equatable {
    enum Kind {case reasoning, tool, reply, status, attention}
    enum ToolOperation {
        case tool, command, read, search, listFiles, edit, webSearch, webOpen, webFind
        case imageGeneration, imageView, compaction, plan, collaboration, waiting, review
        case document, spreadsheet, presentation, mail, calendar, code
    }
    enum Outcome:String {
        case failed, declined, cancelled, interrupted
        var label:String {
            switch self {case .failed:return "失败"; case .declined:return "被拒绝"; case .cancelled:return "已取消"; case .interrupted:return "已中断"}
        }
        var symbol:String {
            switch self {case .failed:return "exclamationmark.circle.fill"; case .declined:return "hand.raised.slash.fill"; case .cancelled,.interrupted:return "xmark.circle.fill"}
        }
    }
    let title:String
    var detail:String = ""
    var kind:Kind = .tool
    var finished = false
    var templateKey:String? = nil
    var toolOperation:ToolOperation = .tool
    var statusSymbol:String? = nil
    var outcome:Outcome? = nil
    static func waiting(approval:Bool) -> TaskActivity {
        .init(title:approval ? "等待批准" : "等待回答",kind:.attention,statusSymbol:approval ? "hand.raised" : "questionmark.bubble")
    }
    // 保留命令入口、子命令和参数；长命令及文件清单使用有界摘要。
    var displayDetail:String {
        guard kind == .tool else {return detail}
        let lines = detail.split(whereSeparator:{$0.isNewline}).map(String.init)
        var result = lines.prefix(3).map {Self.short($0)}
        if lines.count > 3 {result.append("另有 \(lines.count-3) 项")}
        return result.joined(separator:"\n")
    }
    var text:String {displayDetail.isEmpty ? title : title+"\n\n"+displayDetail}
    private static func short(_ text:String) -> String {
        let line = text.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        return line.count > 120 ? String(line.prefix(120))+"…" : line
    }
    private static func commandSummary(_ command:String?) -> String {
        guard let command = command?.trimmingCharacters(in:.whitespacesAndNewlines),!command.isEmpty else {return ""}
        // 多行脚本只取入口行；不把脚本正文压成一整条跑马灯或 hover。
        let end = command.firstIndex(where:{$0.isNewline}) ?? command.endIndex
        let firstLine = short(String(command[..<end]))
        return firstLine+(end == command.endIndex ? "" : " …（多行命令）")
    }
    var symbolName:String {
        switch kind {
        case .reasoning:return "atom"
        case .reply:return "text.bubble"
        case .status,.attention:return statusSymbol ?? "exclamationmark.triangle"
        case .tool:
            switch toolOperation {
            case .command:return "terminal"
            case .read:return "doc.text"
            case .search:return "magnifyingglass"
            case .listFiles:return "folder"
            case .edit:return "square.and.pencil"
            case .webSearch:return "globe"
            case .webOpen:return "network"
            case .webFind:return "doc.text.magnifyingglass"
            case .imageGeneration:return "photo.badge.plus"
            case .imageView:return "photo"
            case .compaction:return "arrow.down.right.and.arrow.up.left"
            case .plan:return "list.bullet.clipboard"
            case .collaboration:return "figure.and.child.holdinghands"
            case .waiting:return "figure.child.and.lock"
            case .review:return "doc.text.magnifyingglass"
            case .document:return "doc.richtext"
            case .spreadsheet:return "tablecells"
            case .presentation:return "rectangle.on.rectangle"
            case .mail:return "envelope"
            case .calendar:return "calendar"
            case .code:return "curlybraces"
            case .tool:return "wrench.and.screwdriver"
            }
        }
    }
    var displayTitle:String {
        if let templateKey {return PetPreferences.shared.statusLine(templateKey)}
        return finished || kind == .reply || kind == .status || kind == .attention ? title : PetPreferences.shared.statusLine(kind == .reasoning ? "taskThinkingTemplate" : "taskToolTemplate")
    }
    var actionTitle:String {kind == .tool && (outcome != nil || (!finished && templateKey == nil)) ? title : ""}
    var line:String {
        // 跑马灯使用公开摘要和操作状态，不使用气泡标题的个性台词。
        let detail = displayDetail
        let detailOnly = outcome == nil && !detail.isEmpty && (kind == .reasoning || (kind == .tool && [.read,.search,.listFiles].contains(toolOperation)))
        let parts = (detailOnly ? [detail] : [title,detail]).filter {!$0.isEmpty}
        return parts.joined(separator:" · ").replacingOccurrences(of:"**",with:"").split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
    }
    var visible:Bool {kind == .reasoning ? PetPreferences.shared.bool("showThinkingProgress") : kind == .tool ? PetPreferences.shared.bool("showToolProgress") : true}
    static func summary(_ parts:[Any]) -> String {
        parts.compactMap {$0 as? String ?? ($0 as? [String:Any])?["text"] as? String}.filter {!$0.isEmpty}.joined(separator:"\n")
    }
    // 只按公开工具身份分类；不读取 arguments，不从脚本内容推断操作。
    private static let knownTools:[String:ToolOperation] = {
        var result = [String:ToolOperation]()
        func add(_ namespaces:[String],_ names:[String],_ operation:ToolOperation) {
            for namespace in namespaces {for name in names {
                result[namespace+"."+name] = operation
                if namespace.hasPrefix("mcp__") {
                    let separator = namespace == "mcp__node_repl" ? "__" : "_"
                    result[namespace+separator+name] = operation
                }
            }}
        }
        add(["functions"],["exec_command","write_stdin"],.command)
        add(["functions"],["apply_patch"],.edit)
        add(["functions"],["view_image"],.imageView)
        add(["functions"],["update_plan"],.plan)
        add(["web"],["run"],.webSearch)
        result["web__run"] = .webSearch
        add(["image_gen"],["imagegen"],.imageGeneration)
        result["image_gen__imagegen"] = .imageGeneration
        add(["mcp__node_repl","node_repl"],["js","js_reset","js_add_node_module_dir"],.code)
        add(["mcp__codex_apps__search_service"],["web_run"],.webSearch)
        let drive = ["mcp__codex_apps__google_drive","google_drive"]
        add(drive,["batch_update_document","get_document","get_document_text","get_document_tables","get_document_paragraph_range","find_document_text_range","get_document_comments","import_document"],.document)
        add(drive,["batch_update_spreadsheet","get_spreadsheet_cells","get_spreadsheet_metadata","get_spreadsheet_range","get_spreadsheet_comments","search_spreadsheet_rows","import_spreadsheet","duplicate_sheet_in_new_spreadsheet"],.spreadsheet)
        add(drive,["batch_update_presentation","get_presentation","get_presentation_text","get_presentation_outline","get_presentation_tables","get_presentation_comments","get_slide","get_slide_thumbnail","import_presentation","create_presentation_from_template"],.presentation)
        add(["mcp__codex_apps__gmail","gmail"],["read_email","read_email_thread","batch_read_email","batch_read_email_threads","read_attachment","search_emails","search_email_ids","create_draft","update_draft","list_drafts","send_draft","send_email","forward_emails","archive_emails","delete_emails","apply_labels_to_emails","batch_modify_email","bulk_label_matching_emails","create_label","list_labels"],.mail)
        add(["mcp__codex_apps__google_calendar","google_calendar"],["read_event","batch_read_event","search","search_events","fetch","create_event","update_event","delete_event","respond_event","get_availability","list_calendars","get_colors","list_event_labels","set_event_label_silently"],.calendar)
        return result
    }()
    static func from(type:String,status:String?,summary:String = "",tool:String? = nil,command:String? = nil,
                     actions:[[String:Any]] = [],paths:[String] = [],text:String = "",webAction:[String:Any] = [:]) -> TaskActivity? {
        // reasoning 项结束只表示这一段摘要结束，不能将仍在执行的轮次改成“思考摘要”。
        if type == "reasoning" {return .init(title:"正在思考",detail:summary,kind:.reasoning)}
        var operation:ToolOperation
        var action:String
        switch type {
        case "commandExecution":operation = .command; action = "运行命令"
        case "fileChange":operation = .edit; action = "修改文件"
        case "mcpToolCall","dynamicToolCall":operation = knownTools[tool ?? ""] ?? .tool; action = "调用工具"
        case "webSearch":
            switch webAction["type"] as? String {
            case "openPage":operation = .webOpen; action = "打开网页"
            case "findInPage":operation = .webFind; action = "在网页内查找"
            case "other":operation = .webSearch; action = "浏览网页"
            default:operation = .webSearch; action = "搜索网页"
            }
        case "imageGeneration":operation = .imageGeneration; action = "生成图片"
        case "imageView":operation = .imageView; action = "查看图片"
        case "contextCompaction":operation = .compaction; action = "压缩上下文"
        case "plan":operation = .plan; action = "制定计划"
        case "enteredReviewMode","exitedReviewMode":operation = .review; action = "审查代码"
        case "collabAgentToolCall","collabToolCall":
            switch tool {
            case "spawnAgent":operation = .collaboration; action = "派发子任务"
            case "wait":operation = .waiting; action = "等待子代理"
            case "sendInput":operation = .collaboration; action = "向子代理发送消息"
            case "resumeAgent":operation = .collaboration; action = "恢复子代理"
            case "closeAgent":operation = .collaboration; action = "关闭子代理"
            default:operation = .collaboration; action = "协调子代理"
            }
        default:return nil
        }
        let outcome = Outcome(rawValue:status == "canceled" ? "cancelled" : status ?? "")
        let ended = status == "completed" || outcome != nil
        let succeeded = status == "completed"
        if type == "commandExecution",!actions.isEmpty {
            let types = Set(actions.compactMap {$0["type"] as? String})
            if types.count == 1,let actionType = types.first {
                operation = ["read":.read,"search":.search,"listFiles":.listFiles][actionType] ?? .command
                action = ["read":"读取文件","search":"搜索内容","listFiles":"列出文件"][actionType] ?? action
            }
        }
        var detail = type == "commandExecution" ? commandSummary(command) : tool ?? ""
        if type == "commandExecution",!actions.isEmpty {
            detail = actions.map { entry in
                let path = entry["path"] as? String ?? ""
                // 被拒绝、失败及取消不能写成“已读取／已搜索”。
                func label(_ verb:String) -> String {outcome != nil ? verb : (succeeded ? "已" : "正在")+verb}
                switch entry["type"] as? String {
                case "read":return label("读取")+" "+(entry["name"] as? String ?? path)
                case "listFiles":return label("列出文件")+(path.isEmpty ? "" : " · "+path)
                case "search":
                    let query = entry["query"] as? String ?? ""
                    return label("搜索")+(query.isEmpty ? "" : "「"+query+"」")+(path.isEmpty ? "" : " · "+path)
                default:return commandSummary(entry["command"] as? String ?? command)
                }
            }.filter {!$0.isEmpty}.joined(separator:"\n")
        }
        if type == "fileChange" {detail = paths.joined(separator:"\n")}
        if type == "plan" {detail = text}
        if type == "enteredReviewMode" || type == "exitedReviewMode" {detail = ""}
        if type == "webSearch" {
            switch operation {
            case .webOpen:detail = webAction["url"] as? String ?? ""
            case .webFind:detail = [webAction["pattern"] as? String,webAction["url"] as? String].compactMap {$0}.joined(separator:" · ")
            default:
                let queries = webAction["queries"] as? [String] ?? []
                detail = queries.isEmpty ? webAction["query"] as? String ?? tool ?? "" : queries.joined(separator:"\n")
            }
        }
        let title:String
        if let outcome {title = action+" · "+outcome.label}
        else if type == "enteredReviewMode" {title = "已进入代码审查"}
        else if type == "exitedReviewMode" {title = "代码审查已结束"}
        else {title = (succeeded ? "已" : "正在")+action}
        let template:String? = outcome == .failed ? "taskWarningTemplate" : outcome != nil ? nil :
            type == "commandExecution" ? (ended ? "taskCommandCompletedTemplate" : "taskCommandTemplate") : nil
        return .init(title:title,detail:detail,finished:ended || type == "enteredReviewMode" || type == "exitedReviewMode",templateKey:template,toolOperation:operation,outcome:outcome)
    }
    static func from(item:[String:Any]) -> TaskActivity? {
        var status = item["status"] as? String
        if status == nil,(item["completed"] as? Bool == true || item["completedAtMs"] as? NSNumber != nil) {status = "completed"}
        if item["type"] as? String == "dynamicToolCall",status == "completed",item["success"] as? Bool == false {status = "failed"}
        let tool = [item["namespace"] as? String ?? item["server"] as? String,item["tool"] as? String].compactMap {$0}.filter {!$0.isEmpty}.joined(separator:".")
        return from(type:item["type"] as? String ?? "",status:status,summary:summary(item["summary"] as? [Any] ?? []),
                    tool:tool.isEmpty ? item["query"] as? String : tool,command:item["command"] as? String,
                    actions:item["commandActions"] as? [[String:Any]] ?? [],paths:(item["changes"] as? [[String:Any]] ?? []).compactMap {$0["path"] as? String},
                    text:item["text"] as? String ?? "",webAction:item["action"] as? [String:Any] ?? [:])
    }
    static func current(items:[[String:Any]],replyTemplateKey:String = "taskReplyTemplate") -> TaskActivity? {
        var result:TaskActivity?, runningTool:TaskActivity?
        for item in items {
            let type = item["type"] as? String ?? ""
            if type == "agentMessage" {result = .init(title:"正在回复",kind:.reply,templateKey:replyTemplateKey); continue}
            guard let next = from(item:item) else {continue}
            if next.kind == .tool,!next.finished,["inProgress","running"].contains(item["status"] as? String ?? "") {runningTool = next}
            // 连续的空 reasoning 项不擦掉此前同阶段已公开的摘要；工具/回复切换仍改变状态。
            if next.kind == .reasoning,next.detail.isEmpty,result?.kind == .reasoning,!((result?.detail.isEmpty) ?? true) {continue}
            result = next
        }
        return runningTool ?? result
    }
}
