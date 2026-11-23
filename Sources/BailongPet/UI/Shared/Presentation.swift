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
            return TaskAttention(kind:.answer,body:L10n.text(.tasks,"presentation.question.text"),isSensitive:true)
        }
        let prompt = question["question"] as? String ?? question["title"] as? String ?? L10n.text(.tasks,"presentation.prompt")
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
        return TaskAttention(kind:.answer,body:([prompt]+options.map {"• "+$0.title+($0.recommended ? L10n.text(.tasks,"presentation.suffixes") : "")+($0.detail.map {"："+$0} ?? "")}).joined(separator:"\n"),
            questions:[TaskQuestion(prompt:prompt,options:options,id:question["id"] as? String ?? "")])
    }

    static func approval(fileChange: Bool, reason: String?) -> TaskAttention {
        let action = fileChange ? L10n.text(.tasks,"presentation.action") : L10n.text(.tasks,"presentation.action.2")
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
        scroll.documentView = text; accessoryView = MessageTextBoxSurface(scroll:scroll)
    }
}

struct AppFailure {
    let title: String, message: String, detail: String
    var openDesktop = false
    var statusSymbol:String? = nil
    static func animation(_ error: Error) -> AppFailure {
        AppFailure(title:L10n.text(.tasks,"presentation.animation.title"),message:L10n.text(.tasks,"presentation.animation.message"),detail:error.localizedDescription)
    }
    static func codex(_ raw: String) -> AppFailure {
        guard let error = CodexErrorMessage(raw) else {
            return AppFailure(title:L10n.text(.tasks,"presentation.codex.title"),message:L10n.text(.tasks,"presentation.codex.message"),detail:raw)
        }
        return AppFailure(title:error.category == .network ? CodexErrorMessage.reconnectStopped : error.title,message:error.category == .network ? CodexErrorMessage.reconnectAdvice : error.body,detail:error.original,openDesktop:error.category == .writer || error.category == .localConnection,statusSymbol:error.symbol)
    }

    func showDetails() {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.setScrollableDetail(detail,size:NSSize(width:480,height:180))
        alert.addButton(withTitle:L10n.text(.tasks,"presentation.showDetails.button")); alert.addButton(withTitle:L10n.text(.tasks,"presentation.showDetails.button.2"))
        alert.applyAccent(primary:1,keyboardDefault:1)
        CopyFeedback.attach(to:alert.buttons[1]) {self.detail}
        alert.runModal()
    }
}

// 显示数据保持可选值：额度缺失不等于零，也不等于不限额。
struct QuotaRow {
    enum Tone {case normal,positive,negative}
    let title: String, value: String, detail: String?
    let remaining: Double?
    var resetsAt: Date? = nil
    var retry = false
    var tone:Tone = .normal
    var startsSection = true
    var wrapsValue = false
    var loading = false
    var usage:TokenUsage?
    var subtitle:String?
    var footnote:String?
    var countdownTarget:Date?
}
struct QuotaOverview {
    let plan: String
    var rows: [QuotaRow]
    var notice: String?
    var management:SubscriptionManagement = .personal
    var apiProvider:APIProviderIdentity? = nil
    var usageHeading:String = L10n.text(.tasks,"presentation.usageHeading")
    var showsDeepSeekPricing: Bool {apiProvider?.catalogID == "deepseek"}
    func displayRows(at date:Date) -> [QuotaRow] {
        showsDeepSeekPricing ? rows + QuotaPresentation.deepSeekPricingRows(at:date) : rows
    }
    var subscriptionHeading: String {
        if let apiProvider {return apiProvider.heading}
        if plan == "Free" {return L10n.text(.tasks,"presentation.displayRows.text")}
        if management == .api || management == .bedrock || management == .gcp {return L10n.text(.tasks,"presentation.displayRows.text.2")+plan}
        return L10n.text(.tasks,"presentation.displayRows.text.3")+plan
    }
}
enum QuotaPresentation {
    static let plans = [
        "free":"Free", "free_workspace":"Free", "go":"Go", "plus":"Plus",
        "prolite":"Pro 100", "pro":"Pro 200", "promax":"Pro 500",
        "team":"Business Standard", "business":"Business Standard", "business_standard":"Business Standard", "self_serve_business":"Business Standard",
        "self_serve_business_prolite":"Business Premium", "business_premium":"Business Premium",
        "self_serve_business_usage_based":L10n.text(.usage,"presentation.quotaPresentation.text"), "business_usage_based":L10n.text(.usage,"presentation.quotaPresentation.text"),
        "ent26":"Enterprise", "enterprise":"Enterprise", "hc":"Enterprise",
        "enterprise_cbp_automation":L10n.text(.usage,"presentation.quotaPresentation.text.2"), "enterprise_cbp_usage_based":L10n.text(.usage,"presentation.quotaPresentation.text.3"),
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
            return plans[raw] ?? (raw == "unknown" ? L10n.text(.usage,"presentation.plan.text") : L10n.text(.usage,"presentation.plan.text.2")+raw)
        }
        switch account?["type"] as? String {
        case "apiKey": return L10n.text(.usage,"presentation.plan.text.3")
        case "amazonBedrock": return "Amazon Bedrock"
        case "gcp": return "Google Cloud Vertex AI"
        default: return L10n.text(.usage,"presentation.plan.text.6")
        }
    }
    static func resetDateText(_ date: Date) -> String {
        L10n.text(.usage,"presentation.resetDateText.text")+date.formatted(date:.abbreviated,time:.shortened).replacingOccurrences(of:"日 ",with:"日")
    }
    static func countdown(until date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining < 60 {return L10n.text(.usage,"presentation.countdown.text")}
        let totalMinutes = Int(remaining/60)
        let days = totalMinutes/1440, hours = (totalMinutes%1440)/60, minutes = totalMinutes%60
        return [days > 0 ? L10n.format(.usage,"presentation.countdown.text.2",String(describing:days)) : nil,hours > 0 ? L10n.format(.usage,"presentation.countdown.text.3",String(describing:hours)) : nil,minutes > 0 ? L10n.format(.usage,"presentation.countdown.text.4",String(describing:minutes)) : nil]
            .compactMap {$0}.joined()
    }
    static func reset(_ value: Any?, now: Date = Date()) -> String? {
        guard let seconds = number(value) else {return nil}
        let date = Date(timeIntervalSince1970:seconds)
        return resetDateText(date)+"\t"+countdown(until:date,now:now)
    }
    private static func periodTitle(minutes: Double?, role: String, monthlyOnly: Bool) -> String {
        if monthlyOnly {return L10n.text(.usage,"presentation.periodTitle.text")}
        guard let minutes, minutes > 0 else {return role == "primary" ? L10n.text(.usage,"presentation.periodTitle.text.2") : L10n.text(.usage,"presentation.periodTitle.text.3")}
        if abs(minutes-43200) <= 2160 {
            return minutes.truncatingRemainder(dividingBy:1440) == 0 ? String(format:L10n.text(.usage,"presentation.periodTitle.text.4"),minutes/1440) : L10n.text(.usage,"presentation.periodTitle.text")
        }
        if abs(minutes-10080) <= 1 {return L10n.text(.usage,"presentation.periodTitle.text.5")}
        if minutes >= 1440 && minutes.truncatingRemainder(dividingBy:1440) == 0 {
            return String(format:L10n.text(.usage,"presentation.periodTitle.text.4"),minutes/1440)
        }
        if minutes.truncatingRemainder(dividingBy:60) == 0 {
            return String(format:L10n.text(.usage,"presentation.periodTitle.text.6"),minutes/60)
        }
        return String(format:L10n.text(.usage,"presentation.periodTitle.text.7"),minutes)
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
            let name = string(bucket["limitName"]) ?? string(bucket["limitId"]) ?? L10n.format(.usage,"presentation.overview.text",String(describing:index+1))
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
                result.rows.append(QuotaRow(title:prefix+period,value:remaining.map {String(format:L10n.text(.usage,"presentation.overview.text.2"),$0)} ?? L10n.text(.usage,"presentation.overview.text.3"),detail:resetDate == nil ? L10n.text(.usage,"presentation.overview.text.4") : nil,remaining:remaining,resetsAt:resetDate))
            }
            if let limit = bucket["individualLimit"] as? [String:Any] {
                let remaining = number(limit["remainingPercent"]).map {max(0,min(100,$0))}
                let amounts = [string(limit["used"]).map {L10n.text(.usage,"presentation.overview.text.5")+$0},string(limit["limit"]).map {L10n.text(.usage,"presentation.overview.text.6")+$0}].compactMap {$0}.joined(separator:" / ")
                let resetDate = number(limit["resetsAt"]).map {Date(timeIntervalSince1970:$0)}
                result.rows.append(QuotaRow(title:prefix+L10n.text(.usage,"presentation.overview.text.7"),value:remaining.map {String(format:L10n.text(.usage,"presentation.overview.text.2"),$0)} ?? L10n.text(.usage,"presentation.overview.text.3"),detail:amounts.isEmpty ? nil : amounts,remaining:remaining,resetsAt:resetDate))
            }
            if let credits = bucket["credits"] as? [String:Any] {
                let unlimited = credits["unlimited"] as? Bool == true
                let balance = string(credits["balance"])
                let amount = unlimited ? L10n.text(.usage,"presentation.amount") : balance.map {L10n.text(.usage,"presentation.overview.text.8")+$0} ?? (credits["hasCredits"] as? Bool == false ? L10n.text(.usage,"presentation.overview.text.9") : L10n.text(.usage,"presentation.overview.text.10"))
                creditNotes.append(prefix+L10n.text(.usage,"presentation.overview.text.11")+amount)
            }
            if result.rows.count == before,bucket["credits"] as? [String:Any] == nil {
                result.rows.append(QuotaRow(title:prefix+L10n.text(.usage,"presentation.overview.text.12"),value:L10n.text(.usage,"presentation.overview.text.3"),detail:L10n.text(.usage,"presentation.overview.text.13"),remaining:nil))
            }
            if bucket["spendControlReached"] as? Bool == true {result.notice = L10n.text(.usage,"presentation.overview.text.14")}
            else if string(bucket["rateLimitReachedType"]) != nil {result.notice = L10n.text(.usage,"presentation.overview.text.15")}
        }
        if result.rows.isEmpty && creditNotes.isEmpty {result.rows = [QuotaRow(title:L10n.text(.usage,"presentation.overview.text.12"),value:L10n.text(.usage,"presentation.overview.text.3"),detail:emptyMessage(account),remaining:nil)]}
        let cards = QuotaResetCards(value)
        let hidesEmptyResetCards = isFreeOrGo || [.api,.bedrock,.gcp].contains(result.management)
        if !hidesEmptyResetCards || (cards.availableCount ?? 0) > 0 || !creditNotes.isEmpty {
            result.rows.append(QuotaRow(title:L10n.text(.usage,"presentation.overview.title"),value:cards.amount,detail:cards.detail,remaining:nil,footnote:creditNotes.isEmpty ? nil : creditNotes.joined(separator:"\n")))
        }
        if value["ordinaryUsageAllowed"] as? Bool == false {result.notice = L10n.text(.usage,"presentation.overview.text.16")}
        return result
    }
    static func emptyMessage(_ account: [String:Any]?) -> String {
        switch account?["type"] as? String {
        case "apiKey": return L10n.text(.usage,"presentation.emptyMessage.text")
        case "amazonBedrock","gcp": return L10n.text(.usage,"presentation.emptyMessage.text.2")
        default: return L10n.text(.usage,"presentation.emptyMessage.text.3")
        }
    }
    static func unavailable(account: [String:Any]?) -> QuotaOverview {
        QuotaOverview(plan:plan(nil,account:account),rows:[QuotaRow(title:L10n.text(.usage,"presentation.overview.text.12"),value:L10n.text(.usage,"presentation.unavailable.text"),detail:emptyMessage(account),remaining:nil)],notice:nil,management:.forAccount(account,plan:plan(nil,account:account)))
    }
    static func api(_ provider:APIProviderIdentity,usage:DailyTokenUsage) -> QuotaOverview {
        let rows = [
            QuotaRow(title:L10n.text(.usage,"presentation.api.title"),value:usage.value,detail:usage.detail,remaining:nil,
                retry:usage.failed,wrapsValue:true,loading:usage.isLoading,usage:usage.usage,subtitle:L10n.text(.usage,"presentation.api.subtitle"))
        ]
        return QuotaOverview(plan:provider.name,rows:rows,apiProvider:provider,usageHeading:L10n.text(.usage,"presentation.api.title"))
    }
    static func deepSeekPricingRows(at date:Date = Date()) -> [QuotaRow] {
        guard let pricing = DeepSeekPricing.snapshot(at:date) else {
            return [QuotaRow(title:L10n.text(.usage,"presentation.deepSeekPricingRows.title"),value:L10n.text(.usage,"presentation.deepSeekPricingRows.text"),detail:nil,remaining:nil)]
        }
        var rows = [QuotaRow(title:L10n.text(.usage,"presentation.deepSeekPricingRows.title"),value:pricing.title,detail:nil,remaining:nil,
            tone:pricing.period == .peak ? .negative : .positive)]
        if let next = pricing.next {
            let nextPeriod:DeepSeekPricing.Period = pricing.period == .peak ? .offPeak : .peak
            rows.append(QuotaRow(title:L10n.text(.usage,"presentation.deepSeekPricingRows.title.2")+nextPeriod.title,value:DeepSeekPricing.timestamp(next),
                detail:nil,remaining:nil,startsSection:false))
            rows.append(QuotaRow(title:L10n.text(.usage,"presentation.deepSeekPricingRows.title.3"),value:DeepSeekPricing.countdown(until:next,now:date),
                detail:nil,remaining:nil,startsSection:false,countdownTarget:next))
        }
        return rows
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
