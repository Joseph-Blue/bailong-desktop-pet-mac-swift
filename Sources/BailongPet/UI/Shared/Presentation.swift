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

extension NSAlert {
    func setScrollableDetail(_ value:String,size:NSSize) {
        let scroll = GutterScrollView(frame:NSRect(origin:.zero,size:size))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let text = AppTextView(frame:scroll.contentView.bounds)
        text.isEditable = false; text.isSelectable = true
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.font = .monospacedSystemFont(ofSize:11,weight:.regular); text.string = value
        scroll.documentView = text; accessoryView = scroll
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
        alert.setScrollableDetail(detail,size:NSSize(width:480,height:180))
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
    var resetsAt: Date? = nil
    var retry = false
    var wrapsValue = false
    var loading = false
    var usage:TokenUsage?
    var subtitle:String?
    var footnote:String?
}
struct QuotaOverview {
    let plan: String
    var rows: [QuotaRow]
    var notice: String?
    var management:SubscriptionManagement = .personal
    var subscriptionHeading: String {
        if plan == "Free" {return "ChatGPT 免费用户"}
        if management == .api || management == .bedrock || management == .gcp {return "计费方式 · "+plan}
        return "ChatGPT 订阅 · "+plan
    }
}
enum QuotaPresentation {
    static let plans = [
        "free":"Free", "free_workspace":"Free", "go":"Go", "plus":"Plus",
        "prolite":"Pro 100", "pro":"Pro 200", "promax":"Pro 500",
        "team":"Business Standard", "business":"Business Standard", "business_standard":"Business Standard", "self_serve_business":"Business Standard",
        "self_serve_business_prolite":"Business Premium", "business_premium":"Business Premium",
        "self_serve_business_usage_based":"Business 按量计费", "business_usage_based":"Business 按量计费",
        "ent26":"Enterprise", "enterprise":"Enterprise", "hc":"Enterprise",
        "enterprise_cbp_automation":"Enterprise（自动化）", "enterprise_cbp_usage_based":"Enterprise 按量计费",
        "edu":"Edu", "education":"Edu", "edu_plus":"Edu Plus", "edu_pro":"Edu Pro",
        "sci":"Science", "sci_plus":"Science Plus"
    ]
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
    static func rawPlan(_ value: Any?, account: [String:Any]?) -> String? {
        let supplied = string(value), accountPlan = string(account?["planType"])
        if let accountPlan, accountPlan != "unknown", plans[accountPlan] != nil {
            if supplied == nil || supplied == "unknown" || ["team","business","pro","edu","sci"].contains(supplied!) {
                return accountPlan
            }
        }
        return supplied == nil || supplied == "unknown" ? accountPlan ?? supplied : supplied
    }
    static func plan(_ value: Any?, account: [String:Any]?) -> String {
        if let raw = rawPlan(value,account:account) {
            return plans[raw] ?? (raw == "unknown" ? "套餐未识别" : "套餐："+raw)
        }
        switch account?["type"] as? String {
        case "apiKey": return "API 按量计费"
        case "amazonBedrock": return "Amazon Bedrock"
        case "gcp": return "Google Cloud Vertex AI"
        default: return "套餐信息暂不可用"
        }
    }
    static func resetDateText(_ date: Date) -> String {
        "重置："+date.formatted(date:.abbreviated,time:.shortened).replacingOccurrences(of:"日 ",with:"日")
    }
    static func countdown(until date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining < 60 {return "<1分钟"}
        let totalMinutes = Int(remaining/60)
        let days = totalMinutes/1440, hours = (totalMinutes%1440)/60, minutes = totalMinutes%60
        return [days > 0 ? "\(days)天" : nil,hours > 0 ? "\(hours)小时" : nil,minutes > 0 ? "\(minutes)分钟" : nil]
            .compactMap {$0}.joined()
    }
    static func reset(_ value: Any?, now: Date = Date()) -> String? {
        guard let seconds = number(value) else {return nil}
        let date = Date(timeIntervalSince1970:seconds)
        return resetDateText(date)+"\t"+countdown(until:date,now:now)
    }
    private static func periodTitle(minutes: Double?, role: String, monthlyOnly: Bool) -> String {
        if monthlyOnly {return "30 天额度"}
        guard let minutes, minutes > 0 else {return role == "primary" ? "主要额度" : "次要额度"}
        if abs(minutes-43200) <= 2160 {
            return minutes.truncatingRemainder(dividingBy:1440) == 0 ? String(format:"%.0f 天额度",minutes/1440) : "30 天额度"
        }
        if abs(minutes-10080) <= 1 {return "周额度"}
        if minutes >= 1440 && minutes.truncatingRemainder(dividingBy:1440) == 0 {
            return String(format:"%.0f 天额度",minutes/1440)
        }
        if minutes.truncatingRemainder(dividingBy:60) == 0 {
            return String(format:"%.0f 小时额度",minutes/60)
        }
        return String(format:"%.0f 分钟额度",minutes)
    }
    static func overview(_ value: [String:Any], account: [String:Any]?, now: Date = Date()) -> QuotaOverview {
        let map = value["rateLimitsByLimitId"] as? [String:[String:Any]] ?? [:]
        var buckets = map.keys.sorted {a,b in a == "codex" && b != "codex" || a != "codex" && b != "codex" && a < b}.compactMap {map[$0]}
        if buckets.isEmpty, let legacy = value["rateLimits"] as? [String:Any] {buckets = [legacy]}
        let bucketPlan = buckets.compactMap {string($0["planType"])}.first(where:{$0 != "unknown"})
        let resolvedPlan = rawPlan(bucketPlan,account:account)
        let isFreeOrGo = ["free","free_workspace","go"].contains(resolvedPlan ?? "")
        var result = QuotaOverview(plan:plan(bucketPlan,account:account),rows:[])
        var creditNotes = [String]()
        result.management = .forAccount(account,plan:result.plan)
        for (index,bucket) in buckets.enumerated() {
            let name = string(bucket["limitName"]) ?? string(bucket["limitId"]) ?? "额度组 \(index+1)"
            let prefix = buckets.count > 1 ? name+" · " : ""
            let before = result.rows.count
            let bucketRawPlan = rawPlan(bucket["planType"],account:account) ?? resolvedPlan
            let monthlyOnly = ["free","free_workspace","go"].contains(bucketRawPlan ?? "")
            let allWindows = ["primary","secondary"].compactMap {key in (bucket[key] as? [String:Any]).map {(key,$0)}}
            let selectedWindows: [(String,[String:Any])]
            if monthlyOnly {
                selectedWindows = allWindows.max {(number($0.1["windowDurationMins"]) ?? 0) < (number($1.1["windowDurationMins"]) ?? 0)}.map {[$0]} ?? []
            } else {
                selectedWindows = allWindows
            }
            for (key,window) in selectedWindows {
                let period = periodTitle(minutes:number(window["windowDurationMins"]),role:key,monthlyOnly:monthlyOnly)
                let remaining = number(window["usedPercent"]).map {max(0,min(100,100-$0))}
                let resetDate = number(window["resetsAt"]).map {Date(timeIntervalSince1970:$0)}
                result.rows.append(QuotaRow(title:prefix+period,value:remaining.map {String(format:"剩余 %.0f%%",$0)} ?? "暂未提供",detail:resetDate == nil ? "重置时间暂未提供" : nil,remaining:remaining,resetsAt:resetDate))
            }
            if let limit = bucket["individualLimit"] as? [String:Any] {
                let remaining = number(limit["remainingPercent"]).map {max(0,min(100,$0))}
                let amounts = [string(limit["used"]).map {"已用 "+$0},string(limit["limit"]).map {"上限 "+$0}].compactMap {$0}.joined(separator:" / ")
                let resetDate = number(limit["resetsAt"]).map {Date(timeIntervalSince1970:$0)}
                result.rows.append(QuotaRow(title:prefix+"个人使用限额",value:remaining.map {String(format:"剩余 %.0f%%",$0)} ?? "暂未提供",detail:amounts.isEmpty ? nil : amounts,remaining:remaining,resetsAt:resetDate))
            }
            if let credits = bucket["credits"] as? [String:Any] {
                let unlimited = credits["unlimited"] as? Bool == true
                let balance = string(credits["balance"])
                let amount = unlimited ? "不限额" : balance.map {"剩余 "+$0} ?? (credits["hasCredits"] as? Bool == false ? "无可用点数" : "余额暂未提供")
                creditNotes.append(prefix+"可用点数 · "+amount)
            }
            if result.rows.count == before,bucket["credits"] as? [String:Any] == nil {
                result.rows.append(QuotaRow(title:prefix+"使用额度",value:"暂未提供",detail:"服务未返回额度窗口或点数信息。",remaining:nil))
            }
            if bucket["spendControlReached"] as? Bool == true {result.notice = "已达到工作区设置的使用限额。"}
            else if string(bucket["rateLimitReachedType"]) != nil {result.notice = "服务报告当前已达到使用限制。"}
        }
        if result.rows.isEmpty && creditNotes.isEmpty {result.rows = [QuotaRow(title:"使用额度",value:"暂未提供",detail:emptyMessage(account),remaining:nil)]}
        let cards = QuotaResetCards(value)
        let hidesEmptyResetCards = isFreeOrGo || [.api,.bedrock,.gcp].contains(result.management)
        if !hidesEmptyResetCards || (cards.availableCount ?? 0) > 0 || !creditNotes.isEmpty {
            result.rows.append(QuotaRow(title:"额度重置卡",value:cards.amount,detail:cards.detail,remaining:nil,footnote:creditNotes.isEmpty ? nil : creditNotes.joined(separator:"\n")))
        }
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
