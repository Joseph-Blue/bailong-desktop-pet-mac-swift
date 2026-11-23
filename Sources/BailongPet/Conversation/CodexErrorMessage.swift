import Foundation

// 中文说明只用于显示；原始错误继续用于技术详情与历史记录。
struct CodexErrorMessage {
    enum Category {case modelConnection, model, quota, balance, budget, sessionBudget, rateLimit, authentication, busy, network, context, request, permission, writer, localConnection, unknown}
    static let reconnectStopped = L10n.text(.conversation,"codexErrorMessage.reconnectStopped")
    static let reconnectAdvice = L10n.text(.conversation,"codexErrorMessage.reconnectAdvice")
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
        message = error["message"] as? String ?? decoded as? String ?? (object.isEmpty ? raw : L10n.text(.conversation,"codexErrorMessage.category.text"))
        let text = message.lowercased()
        let info = error["codexErrorInfo"] ?? error["errorInfo"]
        let infoObject = info as? [String:Any] ?? [:]
        let codes = Set(([error["code"] as? String,error["type"] as? String,info as? String].compactMap {$0}+Array(infoObject.keys)).map {$0.lowercased()})
        func has(_ values:String...) -> Bool {!codes.isDisjoint(with:values.map {$0.lowercased()})}
        let httpStatus = infoObject.values.compactMap {($0 as? [String:Any])?["httpStatusCode"] as? Int}.first
        let connection = has("httpConnectionFailed","responseStreamConnectionFailed","responseStreamDisconnected","responseTooManyFailedAttempts")
        if text.contains("already has an active writer") {
            category = .writer; title = L10n.text(.conversation,"codexErrorMessage.has.title"); body = L10n.text(.conversation,"codexErrorMessage.has.heading")
        } else if has("localConnectionDisconnected") {
            category = .localConnection; title = L10n.text(.conversation,"codexErrorMessage.has.title.2"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.2")
        } else if has("contextWindowExceeded","context_length_exceeded") || text.contains("context window exceeded") || text.contains("maximum context length") {
            category = .context; title = L10n.text(.conversation,"codexErrorMessage.has.title.3"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.3")
        } else if has("sessionBudgetExceeded") {
            category = .sessionBudget; title = L10n.text(.conversation,"codexErrorMessage.has.title.4"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.4")
        } else if has("usageLimitExceeded") || text.contains("you've hit your usage limit") || text.contains("you have hit your usage limit") {
            category = .quota; title = L10n.text(.conversation,"codexErrorMessage.has.title.5"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.5")
        } else if has("credit_balance_exhausted") || text.contains("insufficient balance") || text.contains("insufficient credits") {
            category = .balance; title = L10n.text(.conversation,"codexErrorMessage.has.title.6"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.6")
        } else if has("project_budget_exceeded","organization_usage_limit_exceeded","billing_hard_limit_reached") {
            category = .budget; title = L10n.text(.conversation,"codexErrorMessage.has.title.7"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.7")
        } else if has("insufficient_quota") || text.contains("exceeded your current quota") {
            category = .budget; title = L10n.text(.conversation,"codexErrorMessage.has.title.8"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.8")
        } else if text.contains("model") && (text.contains("not supported when using codex with") || text.contains("not supported with a chatgpt account") || text.contains("not supported with api key")) {
            category = .modelConnection; title = L10n.text(.conversation,"codexErrorMessage.has.title.9"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.9")
        } else if has("model_not_found") || (text.contains("model") && text.contains("does not exist or you do not have access")) {
            category = .model; title = L10n.text(.conversation,"codexErrorMessage.has.title.10"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.10")
        } else if has("unauthorized","invalid_api_key","token_expired","refresh_token_expired","refresh_token_reused") || httpStatus == 401 || text.contains("incorrect api key") || text.contains("authentication token has expired") {
            category = .authentication; title = L10n.text(.conversation,"codexErrorMessage.has.title.11"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.11")
        } else if has("rateLimitExceeded","rate_limit_exceeded","slow_down") || text.contains("rate limit reached") {
            category = .rateLimit; title = L10n.text(.conversation,"codexErrorMessage.has.title.12"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.12")
        } else if has("serverOverloaded","policyCapacityUnavailable","internalServerError") || text.contains("server is overloaded") || text.contains("server is busy") {
            category = .busy; title = L10n.text(.conversation,"codexErrorMessage.has.title.13"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.13")
        } else if httpStatus == 403 {
            category = .permission; title = L10n.text(.conversation,"codexErrorMessage.has.title.14"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.14")
        } else if httpStatus == 400 || has("badRequest","invalidPrompt","invalid_request_error") {
            category = .request; title = L10n.text(.conversation,"codexErrorMessage.has.title.15"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.15")
        } else if connection || text.contains("stream disconnected before completion") || text.contains("error sending request for url") || text.contains("connection reset by peer") || text.contains("request timed out") {
            category = .network; title = L10n.text(.conversation,"codexErrorMessage.has.title.16"); body = Self.reconnectFailed
        } else if has("sandboxError") || text.contains("permission denied") || text.contains("operation not permitted") {
            category = .permission; title = L10n.text(.conversation,"codexErrorMessage.has.title.17"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.16")
        } else {
            category = .unknown; title = L10n.text(.conversation,"codexErrorMessage.has.title.18"); body = L10n.text(.conversation,"codexErrorMessage.has.heading.17")
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
        return .init(title:L10n.text(.conversation,"codexErrorMessage.retryActivity.title")+(progress.isEmpty ? "…" : " "+progress+"…"),kind:.status,statusSymbol:"wifi.exclamationmark")
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
            status = .init(title:L10n.text(.conversation,"codexErrorMessage.receiveProgress.title"),kind:.status,statusSymbol:"wifi")
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
