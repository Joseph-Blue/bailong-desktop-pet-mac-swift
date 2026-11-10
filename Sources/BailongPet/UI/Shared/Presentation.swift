import AppKit

enum TaskAttentionKind: String {
    case answer, approval
    var templateKey: String {self == .answer ? "taskAnswerTemplate" : "taskApprovalTemplate"}
    var status: String {self == .answer ? "waitingForInput" : "waitingForApproval"}
}
struct TaskQuestionOption: Equatable {
    let title: String
    let detail: String?
    let recommended: Bool
}
struct TaskQuestion: Equatable {
    let prompt: String
    let options: [TaskQuestionOption]
    var id: String = ""
}
struct TaskAttention {
    let kind: TaskAttentionKind
    let body: String
    var isSensitive = false
    var questions: [TaskQuestion] = []
    static func question(_ question: [String:Any]) -> TaskAttention {
        if question["isSecret"] as? Bool == true {
            return TaskAttention(kind:.answer,body:"需要输入敏感信息，请前往处理。",isSensitive:true)
        }
        let prompt = question["question"] as? String ?? question["title"] as? String ?? "请补充信息。"
        let options = (question["options"] as? [Any] ?? []).compactMap {value -> TaskQuestionOption? in
            let object = value as? [String:Any]
            guard let title = value as? String ?? object?["label"] as? String else {return nil}
            // 推荐标签只来自原数据标记或原始名称，不根据位置推断。
            let suffixes = [" (Recommended)","（推荐）"," (推荐)"]
            let suffix = suffixes.first {title.hasSuffix($0)}
            return TaskQuestionOption(title:suffix.map {String(title.dropLast($0.count))} ?? title,
                detail:object?["description"] as? String,
                recommended:object?["recommended"] as? Bool == true || suffix != nil)
        }
        return TaskAttention(kind:.answer,body:([prompt]+options.map {"• "+$0.title+($0.recommended ? "（推荐）" : "")+($0.detail.map {"："+$0} ?? "")}).joined(separator:"\n"),
            questions:[TaskQuestion(prompt:prompt,options:options,id:question["id"] as? String ?? "")])
    }

    static func approval(fileChange: Bool, reason: String?) -> TaskAttention {
        let action = fileChange ? "等待批准文件修改。" : "等待批准执行操作。"
        return TaskAttention(kind:.approval,body:[action,reason ?? ""].filter {!$0.isEmpty}.joined(separator:"\n"))
    }
}

struct AppFailure {
    let title: String, message: String, detail: String
    var openDesktop = false
    var statusSymbol:String? = nil
    static func animation(_ error: Error) -> AppFailure {
        AppFailure(title:"这个动作暂时无法播放",message:"桌宠会保留当前画面。可以重试，或从菜单选择其他动作。",detail:error.localizedDescription)
    }
    static func codex(_ raw: String) -> AppFailure {
        guard let error = CodexErrorMessage(raw) else {
            return AppFailure(title:"Codex 任务未能完成",message:"Codex 未提供错误说明。",detail:raw)
        }
        return AppFailure(title:error.category == .network ? CodexErrorMessage.reconnectStopped : error.title,message:error.category == .network ? CodexErrorMessage.reconnectAdvice : error.body,detail:error.original,openDesktop:error.category == .writer || error.category == .localConnection,statusSymbol:error.symbol)
    }

    func showDetails() {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let scroll = GutterScrollView(frame:NSRect(x:0,y:0,width:480,height:180))
        let text = AppTextView(frame:scroll.bounds); text.isEditable = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize:11,weight:.regular); text.string = detail
        text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; alert.accessoryView = scroll
        alert.addButton(withTitle:"关闭"); alert.addButton(withTitle:"拷贝详情")
        alert.applyAccent(primary:1,keyboardDefault:1)
        CopyFeedback.attach(to:alert.buttons[1]) {self.detail}
        alert.runModal()
    }
}

// 显示数据保持可选值：额度缺失不等于零，也不等于不限额。
struct QuotaRow {
    let title: String, value: String, detail: String?
    let remaining: Double?
    var retry = false
    var wrapsValue = false
    var loading = false
}
struct QuotaOverview {
    let plan: String
    var rows: [QuotaRow]
    var notice: String?
    var management:SubscriptionManagement = .personal
}
enum QuotaPresentation {
    static let plans = ["free":"Free", "go":"Go", "plus":"Plus", "prolite":"Pro 100", "pro":"Pro 200", "promax":"Pro 500",
        "team":"Team", "business":"Business", "self_serve_business_prolite":"Business Premium", "self_serve_business_usage_based":"Business（按量计费）",
        "ent26":"Enterprise", "enterprise":"Enterprise", "enterprise_cbp_automation":"Enterprise（自动化）", "enterprise_cbp_usage_based":"Enterprise（按量计费）",
        "edu":"Edu", "edu_plus":"Edu Plus", "edu_pro":"Edu Pro", "sci":"Science", "sci_plus":"Science Plus"]
    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else {return nil}
        let result = text.trimmingCharacters(in:.whitespacesAndNewlines)
        return result.isEmpty || ["null","<null>"].contains(result.lowercased()) ? nil : result
    }
    static func number(_ value: Any?) -> Double? {
        // JSON 的整数和浮点值统一经 NSNumber 读取；Swift 字典中的 Int 也适用。
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {return nil}
        return value.doubleValue
    }
    static func plan(_ value: Any?, account: [String:Any]?) -> String {
        let supplied = string(value), accountPlan = string(account?["planType"])
        let raw = supplied == nil || supplied == "unknown" ? accountPlan ?? supplied : supplied
        if let raw {return plans[raw] ?? (raw == "unknown" ? "套餐未识别" : "套餐："+raw)}
        switch account?["type"] as? String {
        case "apiKey": return "API 按量计费"
        case "amazonBedrock": return "Amazon Bedrock"
        case "gcp": return "Google Cloud Vertex AI"
        default: return "套餐信息暂不可用"
        }
    }
    static func reset(_ value: Any?) -> String? {
        number(value).map {"重置："+Date(timeIntervalSince1970:$0).formatted(date:.abbreviated,time:.shortened)}
    }
    static func overview(_ value: [String:Any], account: [String:Any]?) -> QuotaOverview {
        let map = value["rateLimitsByLimitId"] as? [String:[String:Any]] ?? [:]
        var buckets = map.keys.sorted {a,b in a == "codex" && b != "codex" || a != "codex" && b != "codex" && a < b}.compactMap {map[$0]}
        if buckets.isEmpty, let legacy = value["rateLimits"] as? [String:Any] {buckets = [legacy]}
        let bucketPlan = buckets.compactMap {string($0["planType"])}.first(where:{$0 != "unknown"})
        var result = QuotaOverview(plan:plan(bucketPlan,account:account),rows:[])
        result.management = .forAccount(account,plan:result.plan)
        for (index,bucket) in buckets.enumerated() {
            let name = string(bucket["limitName"]) ?? string(bucket["limitId"]) ?? "额度组 \(index+1)"
            let prefix = buckets.count > 1 ? name+" · " : ""
            let before = result.rows.count
            for key in ["primary","secondary"] {
                guard let window = bucket[key] as? [String:Any] else {continue}
                let period: String
                if let minutes = number(window["windowDurationMins"]) {
                    period = minutes == 10080 ? "每周额度" : minutes.truncatingRemainder(dividingBy:60) == 0 ? String(format:"%.0f 小时额度",minutes/60) : String(format:"%.0f 分钟额度",minutes)
                } else {period = key == "primary" ? "主要额度" : "次要额度"}
                let remaining = number(window["usedPercent"]).map {max(0,min(100,100-$0))}
                result.rows.append(QuotaRow(title:prefix+period,value:remaining.map {String(format:"剩余 %.0f%%",$0)} ?? "暂未提供",detail:reset(window["resetsAt"]) ?? "重置时间暂未提供",remaining:remaining))
            }
            if let limit = bucket["individualLimit"] as? [String:Any] {
                let remaining = number(limit["remainingPercent"]).map {max(0,min(100,$0))}
                let amounts = [string(limit["used"]).map {"已用 "+$0},string(limit["limit"]).map {"上限 "+$0}].compactMap {$0}.joined(separator:" / ")
                let detail = [amounts.isEmpty ? nil : amounts,reset(limit["resetsAt"])].compactMap {$0}.joined(separator:"\n")
                result.rows.append(QuotaRow(title:prefix+"个人使用限额",value:remaining.map {String(format:"剩余 %.0f%%",$0)} ?? "暂未提供",detail:detail.isEmpty ? nil : detail,remaining:remaining))
            }
            if let credits = bucket["credits"] as? [String:Any] {
                let unlimited = credits["unlimited"] as? Bool == true
                let balance = string(credits["balance"])
                let amount = unlimited ? "不限额" : balance.map {"剩余 "+$0} ?? (credits["hasCredits"] as? Bool == false ? "无可用点数" : "余额暂未提供")
                result.rows.append(QuotaRow(title:prefix+"可用点数",value:amount,detail:unlimited ? "点数不限额；其他使用限制仍可能适用。" : nil,remaining:nil))
            }
            if result.rows.count == before {
                result.rows.append(QuotaRow(title:prefix+"使用额度",value:"暂未提供",detail:"服务未返回额度窗口或点数信息。",remaining:nil))
            }
            if bucket["spendControlReached"] as? Bool == true {result.notice = "已达到工作区设置的使用限额。"}
            else if string(bucket["rateLimitReachedType"]) != nil {result.notice = "服务报告当前已达到使用限制。"}
        }
        if result.rows.isEmpty {result.rows = [QuotaRow(title:"使用额度",value:"暂未提供",detail:emptyMessage(account),remaining:nil)]}
        let cards = QuotaResetCards(value)
        result.rows.append(QuotaRow(title:"额度重置卡",value:cards.amount,detail:cards.detail,remaining:nil))
        if value["ordinaryUsageAllowed"] as? Bool == false {result.notice = "服务当前未允许使用包含额度。"}
        return result
    }
    static func emptyMessage(_ account: [String:Any]?) -> String {
        switch account?["type"] as? String {
        case "apiKey": return "API 按量计费，不使用 ChatGPT 订阅额度。"
        case "amazonBedrock","gcp": return "请在对应云服务中查看计费和使用限额。"
        default: return "服务未返回额度信息；这不表示剩余额度为零或不限额。"
        }
    }
    static func unavailable(account: [String:Any]?) -> QuotaOverview {
        QuotaOverview(plan:plan(nil,account:account),rows:[QuotaRow(title:"使用额度",value:"暂时无法获取",detail:emptyMessage(account),remaining:nil)],notice:nil,management:.forAccount(account,plan:plan(nil,account:account)))
    }
}

// 参照旧 Mac 工程的鼠标四象限定位，只避让可见桌宠，不避让整块透明画布。
enum MenuPlacement {
    static func frame(size: NSSize, cursor: NSPoint, screen: NSRect, pet: NSRect) -> NSRect {
        let area = screen.insetBy(dx:8,dy:8)
        let width = min(size.width,area.width), height = min(size.height,area.height), gap = 8.0
        func clamped(_ x: CGFloat, _ top: CGFloat) -> NSRect {
            NSRect(x:max(area.minX,min(x,area.maxX-width)),y:max(area.minY,min(top-height,area.maxY-height)),width:width,height:height)
        }
        let avoid = pet.insetBy(dx:-4,dy:-4)
        let candidates = [clamped(cursor.x+gap,cursor.y-gap),clamped(cursor.x-gap-width,cursor.y-gap),
            clamped(cursor.x+gap,cursor.y+gap+height),clamped(cursor.x-gap-width,cursor.y+gap+height),
            clamped(avoid.maxX,cursor.y),clamped(avoid.minX-width,cursor.y),
            clamped(cursor.x,avoid.minY),clamped(cursor.x,avoid.maxY+height)]
        func overlap(_ r: NSRect) -> CGFloat {let i = r.intersection(avoid); return i.isNull ? 0 : i.width*i.height}
        func distance(_ r: NSRect) -> CGFloat {
            // 到菜单最近边缘的距离；左侧菜单不再因自身宽度受到惩罚。
            hypot(max(r.minX-cursor.x,0,cursor.x-r.maxX),max(r.minY-cursor.y,0,cursor.y-r.maxY))
        }
        return candidates.enumerated().min {a,b in
            let ac = overlap(a.element), bc = overlap(b.element)
            if ac != bc {return ac < bc}
            let ad = distance(a.element), bd = distance(b.element)
            return ad == bd ? a.offset < b.offset : ad < bd
        }!.element
    }
}
