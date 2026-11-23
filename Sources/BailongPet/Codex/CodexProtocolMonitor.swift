import Foundation

// 格式化 app-server 的协议元数据。自由文本与 RPC 参数对象都不进入终端。
extension TerminalMonitor {
    private static let rpcMethods:Set<String> = [
        "initialize","initialized","model/list","config/read","account/read","account/rateLimits/read",
        "thread/start","thread/resume","turn/start","turn/interrupt","item/commandExecution/requestApproval",
        "item/fileChange/requestApproval","item/permissions/requestApproval","item/tool/requestUserInput"
    ]
    static func rpcName(_ method:String) -> String {rpcMethods.contains(method) ? method : L10n.text(.tasks,"codexProtocolMonitor.rpcName.text")}
    static func serverRequestID(_ value:Any) -> String {
        if let id = value as? Int {return String(id)}
        if let id = value as? String {return tag(id)}
        return "?"
    }
    static func rpcFields(_ value:[String:Any]) -> String {
        let thread = value["thread"] as? [String:Any], turn = value["turn"] as? [String:Any]
        var fields = ""
        if let id = (value["threadId"] ?? thread?["id"]) as? String {fields += L10n.text(.tasks,"desktopQuestionReply.record.text")+tag(id)}
        if let id = (value["turnId"] ?? turn?["id"]) as? String {fields += L10n.text(.tasks,"codexProtocolMonitor.id.text")+tag(id)}
        return fields
    }
    static func rpcResult(_ method:String,_ result:[String:Any]) -> String {
        if method == "model/list",let models = result["data"] as? [Any] {
            return L10n.format(.tasks,"codexProtocolMonitor.models.text",String(describing:models.count))+(result["nextCursor"] is String ? L10n.text(.tasks,"codexProtocolMonitor.models.text.2") : "")
        }
        if method == "account/rateLimits/read",let limits = result["rateLimitsByLimitId"] as? [String:Any] {
            return L10n.format(.tasks,"codexProtocolMonitor.limits.text",String(describing:limits.count))
        }
        return rpcFields(result)
    }
    static func rpcError(_ value:[String:Any]) -> String {
        let code = (value["code"] as? Int).map {"  ·  RPC \($0)"} ?? ""
        let failure = CodexErrorMessage(CodexErrorMessage.encode(value))
        return "  ·  "+(failure?.title ?? L10n.text(.tasks,"codexProtocolMonitor.failure.text"))+code
    }
    func serverEvent(_ method:String,_ params:[String:Any],connection:Int) {
        let detail:String
        var level = Level.info
        switch method {
        case "turn/started","thread/closed":detail = ""
        case "turn/completed":
            let turn = params["turn"] as? [String:Any] ?? [:]
            let status = turn["status"] as? String ?? ""
            level = status == "completed" ? .success : status == "failed" ? .error : .warning
            detail = "  ·  "+Self.status(status)+((turn["items"] as? [Any]).map {L10n.format(.tasks,"codexProtocolMonitor.status.text",String(describing:$0.count))} ?? "")
        case "item/started","item/completed":
            guard let item = params["item"] as? [String:Any] else {return}
            let type = item["type"] as? String ?? ""
            let known = ["agentMessage","userMessage","reasoning","commandExecution","fileChange","mcpToolCall","dynamicToolCall",
                         "webSearch","imageGeneration","imageView","contextCompaction","plan","enteredReviewMode","exitedReviewMode",
                         "collabAgentToolCall","collabToolCall","sleep"]
            let status = item["status"] as? String
            let outcome = status.flatMap {TaskActivity.Outcome(rawValue:$0 == "canceled" ? "cancelled" : $0)}
            let failed = outcome == .failed || item["success"] as? Bool == false
            if failed {level = .error} else if outcome != nil {level = .warning}
            var operation = ""
            if ["commandExecution","mcpToolCall","dynamicToolCall","webSearch"].contains(type),
               let activity = TaskActivity.from(item:item) {operation = "  ·  "+activity.toolOperation.monitorName}
            if type == "fileChange",let changes = item["changes"] as? [Any] {operation = L10n.format(.tasks,"codexProtocolMonitor.changes.text",String(describing:changes.count))}
            detail = "  ·  "+(known.contains(type) ? type : L10n.text(.tasks,"codexProtocolMonitor.changes.text.2"))
                + ((item["id"] as? String).map {" #"+Self.tag($0)} ?? "") + operation
                + (failed ? L10n.text(.tasks,"codexProtocolMonitor.changes.text.3") : outcome.map {"  ·  "+$0.label} ?? "")
        case "turn/plan/updated":
            detail = (params["plan"] as? [Any]).map {L10n.format(.tasks,"codexProtocolMonitor.labels.text",String(describing:$0.count))} ?? ""
        case "error":
            let retry = params["willRetry"] as? Bool == true
            level = retry ? .warning : .error
            detail = (retry ? L10n.text(.tasks,"codexProtocolMonitor.retry.text") : "")+Self.rpcError(params["error"] as? [String:Any] ?? [:])
        default:return // 流式 delta 和用量快照保持原有消费节奏。
        }
        write(.server,L10n.text(.tasks,"codexProtocolMonitor.retry.text.2")+method+L10n.format(.tasks,"codexProtocolMonitor.retry.text.3",String(describing:connection))+Self.rpcFields(params)+detail,level)
    }
}
