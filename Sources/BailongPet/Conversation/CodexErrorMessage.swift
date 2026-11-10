import Foundation

// 中文说明只用于显示；原始错误继续用于技术详情与历史记录。
struct CodexErrorMessage {
    enum Category {case modelConnection, model, quota, balance, budget, sessionBudget, rateLimit, authentication, busy, network, context, request, permission, writer, localConnection, unknown}
    static let reconnectStopped = "重新连接失败，Codex 已停止重试。"
    static let reconnectAdvice = "检查你的网络或节点环境。"
    static let reconnectFailed = reconnectStopped+reconnectAdvice
    let category:Category
    let original:String
    let message:String
    let title:String
    let body:String
    var symbol:String {category == .network || category == .localConnection ? "wifi.slash" : "exclamationmark.triangle"}
    init?(_ raw:String) {
        let raw = raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !raw.isEmpty,raw != "null" else {return nil}
        original = raw
        let decoded = try? JSONSerialization.jsonObject(with:Data(raw.utf8),options:.fragmentsAllowed)
        let object = decoded as? [String:Any] ?? [:]
        let error = object["error"] as? [String:Any] ?? object
        message = error["message"] as? String ?? decoded as? String ?? (object.isEmpty ? raw : "Codex 未提供错误说明。")
        let text = message.lowercased()
        let info = error["codexErrorInfo"] ?? error["errorInfo"]
        let infoObject = info as? [String:Any] ?? [:]
        let codes = Set(([error["code"] as? String,error["type"] as? String,info as? String].compactMap {$0}+Array(infoObject.keys)).map {$0.lowercased()})
        func has(_ values:String...) -> Bool {!codes.isDisjoint(with:values.map {$0.lowercased()})}
        let httpStatus = infoObject.values.compactMap {($0 as? [String:Any])?["httpStatusCode"] as? Int}.first
        let connection = has("httpConnectionFailed","responseStreamConnectionFailed","responseStreamDisconnected","responseTooManyFailedAttempts")
        if text.contains("already has an active writer") {
            category = .writer; title = "暂时无法在桌宠中使用这条会话"; body = "请在 Codex 中继续这条会话，或在桌宠中新建对话。"
        } else if has("localConnectionDisconnected") {
            category = .localConnection; title = "与本机 Codex 的连接已断开"; body = "桌宠无法继续接收任务状态。请打开 Codex 确认任务结果。"
        } else if has("contextWindowExceeded","context_length_exceeded") || text.contains("context window exceeded") || text.contains("maximum context length") {
            category = .context; title = "对话上下文已超限"; body = "当前对话已超过模型的上下文上限。请在 Codex 中压缩上下文或新建对话。"
        } else if has("sessionBudgetExceeded") {
            category = .sessionBudget; title = "本次任务预算已用尽"; body = "本次任务已达到预算上限，请在 Codex 中检查会话预算设置。"
        } else if has("usageLimitExceeded") || text.contains("you've hit your usage limit") || text.contains("you have hit your usage limit") {
            category = .quota; title = "Codex 使用额度已用尽"; body = "当前账号的 Codex 使用额度已用尽。请在 Codex 中查看额度恢复时间或调整套餐。"
        } else if has("credit_balance_exhausted") || text.contains("insufficient balance") || text.contains("insufficient credits") {
            category = .balance; title = "API 余额不足"; body = "当前 API 余额不足，请到对应服务商补充余额。"
        } else if has("project_budget_exceeded","organization_usage_limit_exceeded","billing_hard_limit_reached") {
            category = .budget; title = "API 已达到用量上限"; body = "当前 API 已达到用量上限，请检查服务商的用量设置。"
        } else if has("insufficient_quota") || text.contains("exceeded your current quota") {
            category = .budget; title = "API 可用额度不足"; body = "当前 API 可用额度不足，请检查对应服务商的余额和用量上限。"
        } else if text.contains("model") && (text.contains("not supported when using codex with") || text.contains("not supported with a chatgpt account") || text.contains("not supported with api key")) {
            category = .modelConnection; title = "模型与当前连接方式不匹配"; body = "当前模型不支持此连接方式。请在 Codex 中切换到匹配的模型或服务商。"
        } else if has("model_not_found") || (text.contains("model") && text.contains("does not exist or you do not have access")) {
            category = .model; title = "当前连接无法使用这个模型"; body = "模型不存在或当前账号没有访问权限，请在 Codex 中重新选择模型。"
        } else if has("unauthorized","invalid_api_key","token_expired","refresh_token_expired","refresh_token_reused") || httpStatus == 401 || text.contains("incorrect api key") || text.contains("authentication token has expired") {
            category = .authentication; title = "身份验证失败"; body = "当前连接的身份验证失败，请在 Codex 中重新登录或检查 API 配置。"
        } else if has("rateLimitExceeded","rate_limit_exceeded","slow_down") || text.contains("rate limit reached") {
            category = .rateLimit; title = "请求频率受限"; body = "请求过于频繁，请稍后重试。"
        } else if has("serverOverloaded","policyCapacityUnavailable","internalServerError") || text.contains("server is overloaded") || text.contains("server is busy") {
            category = .busy; title = "模型服务繁忙"; body = "模型服务暂时无法处理请求，请稍后重试。"
        } else if httpStatus == 403 {
            category = .permission; title = "当前连接没有访问权限"; body = "当前服务拒绝访问，请在 Codex 中检查账号权限和服务商配置。"
        } else if httpStatus == 400 || has("badRequest","invalidPrompt","invalid_request_error") {
            category = .request; title = "请求未被当前服务接受"; body = "请查看技术详情，并检查当前模型、参数和附件设置。"
        } else if connection || text.contains("stream disconnected before completion") || text.contains("error sending request for url") || text.contains("connection reset by peer") || text.contains("request timed out") {
            category = .network; title = "重新连接失败"; body = Self.reconnectFailed
        } else if has("sandboxError") || text.contains("permission denied") || text.contains("operation not permitted") {
            category = .permission; title = "操作权限不足"; body = "本次操作没有所需权限，请查看技术详情中的受限操作。"
        } else {
            category = .unknown; title = "Codex 任务未能完成"; body = "Codex 报告了错误，请查看技术详情。"
        }
    }
    static func encode(_ raw:Any?) -> String {
        guard let value = raw as? [String:Any] else {return raw as? String ?? ""}
        let fields = value.filter {["message","codexErrorInfo","errorInfo","code","type","additionalDetails"].contains($0.key)}
        // 字段来自已解码 JSON；保留结构化类别，避免只留下英文 message。
        guard JSONSerialization.isValidJSONObject(fields),let data = try? JSONSerialization.data(withJSONObject:fields,options:.sortedKeys) else {return value["message"] as? String ?? ""}
        return String(decoding:data,as:UTF8.self)
    }
    static func retryActivity(message:String) -> TaskActivity {
        let expression = #"(?i)\breconnecting\s*\.?\.?\.?\s*(\d+)\s*/\s*(\d+)"#
        let range = message.range(of:expression,options:.regularExpression)
        let progress = range.map {String(message[$0]).filter {$0.isNumber || $0 == "/"}} ?? ""
        return .init(title:"正在重新连接"+(progress.isEmpty ? "…" : " "+progress+"…"),kind:.status,statusSymbol:"wifi.exclamationmark")
    }
}

// 仅持有本轮显示状态；恢复来自真实模型进展，不用等待时长推断。
struct CodexConnectionProgress {
    private var errorIdentity:String?
    private var status:TaskActivity?
    private var recoveredAt:TimeInterval?
    var activity:TaskActivity? {
        if status?.statusSymbol == "wifi",let recoveredAt,ProcessInfo.processInfo.systemUptime-recoveredAt >= 2 {return nil}
        return status
    }
    mutating func receiveError(_ item:[String:Any]) {
        recoveredAt = nil
        let message = item["message"] as? String ?? ""
        if item["willRetry"] as? Bool == true {
            status = CodexErrorMessage.retryActivity(message:message)
        } else if item["willRetry"] as? Bool == false,
                  let error = CodexErrorMessage(CodexErrorMessage.encode(item)),error.category == .network {
            status = .init(title:CodexErrorMessage.reconnectStopped,kind:.status,statusSymbol:"wifi.slash")
        } else {status = nil}
    }
    mutating func receiveProgress() {
        guard let current = activity else {return}
        if current.statusSymbol == "wifi.exclamationmark" {
            status = .init(title:"连接已恢复，继续处理。",kind:.status,statusSymbol:"wifi")
            recoveredAt = ProcessInfo.processInfo.systemUptime
        } else if current.statusSymbol == "wifi.slash" {status = nil}
    }
    mutating func observe(items:[[String:Any]],resumed:Bool) {
        let index = items.lastIndex { $0["type"] as? String == "error" && $0["willRetry"] is Bool }
        if let index {
            let item = items[index]
            let identity = (item["id"] as? String ?? "")+CodexErrorMessage.encode(item)+String(item["willRetry"] as? Bool ?? false)
            let laterProgress = items.suffix(from:index+1).contains {Self.isModelItem($0)}
            if errorIdentity != identity {
                let initial = errorIdentity == nil
                errorIdentity = identity
                if initial && laterProgress {status = nil}
                else {
                    receiveError(item)
                    if laterProgress || resumed {receiveProgress()}
                }
                return
            }
            if laterProgress {receiveProgress()}
        }
        if resumed {receiveProgress()}
    }

    static func isModelItem(_ item:[String:Any]) -> Bool {["agentMessage","reasoning"].contains(item["type"] as? String ?? "")}
}
