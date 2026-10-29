import AppKit

struct AppFailure {
    let title: String, message: String, detail: String
    var openDesktop = false
    static func animation(_ error: Error) -> AppFailure {
        AppFailure(title:"这个动作暂时无法播放",message:"桌宠会保留当前画面。可以重试，或从菜单选择其他动作。",detail:error.localizedDescription)
    }
    static func codex(_ raw: String) -> AppFailure {
        let lower = raw.lowercased()
        if lower.contains("newer version") || lower.contains("upgrade") {
            return AppFailure(title:"Codex 需要更新",message:"当前 Codex 版本无法使用这个模型。请更新桌面应用，再回来重试。",detail:raw,openDesktop:true)
        }
        if lower.contains("没有找到") || lower.contains("不可执行") {
            return AppFailure(title:"暂时无法连接 Codex",message:"请安装或打开 Codex 桌面应用并完成登录，然后重试。",detail:raw,openDesktop:true)
        }
        if lower.contains("unauthorized") || lower.contains("401") || lower.contains("sign in") || lower.contains("not logged") {
            return AppFailure(title:"需要重新登录",message:"请在 Codex 桌面应用中确认登录状态，再回来继续。",detail:raw,openDesktop:true)
        }
        if lower.contains("429") || lower.contains("usage limit") {
            return AppFailure(title:"当前额度暂不可用",message:"请查看剩余额度和重置时间，稍后再试。",detail:raw)
        }
        if lower.contains("network") || lower.contains("connect") || lower.contains("timed out") || lower.contains("超时") {
            return AppFailure(title:"连接暂时中断",message:"请检查网络和 Codex 状态。任务尚未确认完成，原始记录已保留。",detail:raw)
        }
        return AppFailure(title:"这次任务未能完成",message:"原始记录已保留。可以查看原因，并把内容放回输入框后重新发送。",detail:raw)
    }
    func showDetails() {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:480,height:180))
        let text = NSTextView(frame:scroll.bounds); text.isEditable = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize:11,weight:.regular); text.string = detail
        text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; alert.accessoryView = scroll
        alert.addButton(withTitle:"关闭"); alert.addButton(withTitle:"复制详情")
        alert.applyAccent()
        if alert.runModal() == .alertSecondButtonReturn {NSPasteboard.general.clearContents(); NSPasteboard.general.setString(detail,forType:.string)}
    }
}

// 显示数据保持可选值：额度缺失不等于零，也不等于不限额。
struct QuotaRow {
    let title: String, value: String, detail: String?
    let remaining: Double?
}
struct QuotaOverview {
    let plan: String
    var rows: [QuotaRow]
    var notice: String?
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
        QuotaOverview(plan:plan(nil,account:account),rows:[QuotaRow(title:"使用额度",value:"暂时无法获取",detail:emptyMessage(account),remaining:nil)],notice:nil)
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
