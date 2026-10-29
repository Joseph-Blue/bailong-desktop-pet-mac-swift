import AppKit

@main
struct QuotaInterfaceRegression {
    static func main() throws {
        func check(_ valid: Bool, _ message: String) {if !valid {fputs("失败：\(message)\n",stderr); exit(1)}}
        func json(_ value: String) throws -> [String:Any] {try JSONSerialization.jsonObject(with:Data(value.utf8)) as! [String:Any]}
        let plus = QuotaPresentation.overview(try json(#"{"rateLimits":{"planType":"plus","limitName":null,"primary":{"usedPercent":16,"windowDurationMins":300,"resetsAt":null},"secondary":{"usedPercent":40,"windowDurationMins":10080}}}"#),account:nil)
        check(plus.plan == "Plus" && plus.rows.count == 2 && plus.rows[0].remaining == 84 && plus.rows[1].remaining == 60,"Plus 两个窗口")
        let pro = QuotaPresentation.overview(["rateLimits":["planType":"prolite","primary":["usedPercent":40,"windowDurationMins":10080]]],account:nil)
        check(pro.plan == "Pro 100" && pro.rows[0].title == "每周额度" && pro.rows[0].remaining == 60,"修复前失败的 Swift 整数字段")
        let missing = QuotaPresentation.overview(try json(#"{"rateLimits":{"planType":"free","primary":{"usedPercent":null,"resetsAt":null}}}"#),account:nil)
        check(missing.plan == "Free" && missing.rows[0].remaining == nil && missing.rows[0].value == "暂未提供","免费账号缺失额度不能显示为零")
        let enterprise = QuotaPresentation.overview(try json(#"{"rateLimits":{"planType":"enterprise_cbp_usage_based","individualLimit":{"limit":"1000","used":"250","remainingPercent":75,"resetsAt":1790000000},"credits":{"unlimited":false,"hasCredits":true,"balance":"123.50"}}}"#),account:nil)
        check(enterprise.rows.count == 2 && enterprise.rows[0].remaining == 75 && enterprise.rows[1].value == "剩余 123.50" && enterprise.rows[1].remaining == nil,"企业个人限额与点数")
        let unlimited = QuotaPresentation.overview(try json(#"{"rateLimits":{"planType":"edu","credits":{"unlimited":true,"hasCredits":true,"balance":null}}}"#),account:nil)
        check(unlimited.rows[0].value == "不限额" && unlimited.rows[0].remaining == nil,"不限额必须由服务明确返回")
        let exhausted = QuotaPresentation.overview(try json(#"{"rateLimits":{"planType":"free","primary":{"usedPercent":100,"windowDurationMins":300},"credits":{"unlimited":false,"hasCredits":false,"balance":null}}}"#),account:nil)
        check(exhausted.rows[0].remaining == 0 && exhausted.rows[1].value == "无可用点数","真实零额度")
        let multi = QuotaPresentation.overview(try json(#"{"ordinaryUsageAllowed":false,"rateLimitsByLimitId":{"codex":{"planType":"promax","primary":{"usedPercent":20,"windowDurationMins":300}},"other":{"planType":"promax","limitName":"另一项服务的较长额度名称","secondary":{"usedPercent":25,"windowDurationMins":10080}}}}"#),account:nil)
        check(multi.plan == "Pro 500" && multi.rows.count == 2 && multi.notice != nil,"多额度组与服务限制状态")
        let unknown = QuotaPresentation.overview([:],account:nil)
        check(unknown.rows[0].remaining == nil && unknown.plan == "套餐信息暂不可用","无账号数据")
        check(QuotaPresentation.plan("unknown",account:["planType":"plus"]) == "Plus","套餐回退到账户信息")
        check(QuotaPresentation.unavailable(account:["type":"apiKey"]).plan == "API 按量计费","API 账户不可用状态")
        for key in QuotaPresentation.plans.keys {check(!QuotaPresentation.plan(key,account:nil).contains("null"),"完整套餐映射")}
        print("通过：Plus、Free、Pro 100/200/500、企业限额与点数、Edu 不限额、API、未知值及旧失败用例。")

        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let ui = ChatInterface()
        let oldStyle = UserDefaults.standard.object(forKey:"accentStyle"), oldRGB = UserDefaults.standard.object(forKey:"accentRGB")
        defer {
            if let oldStyle {UserDefaults.standard.set(oldStyle,forKey:"accentStyle")} else {UserDefaults.standard.removeObject(forKey:"accentStyle")}
            if let oldRGB {UserDefaults.standard.set(oldRGB,forKey:"accentRGB")} else {UserDefaults.standard.removeObject(forKey:"accentRGB")}
            ui.history.orderOut(nil); ui.composer.orderOut(nil); app.setActivationPolicy(.accessory)
        }
        AppAccent.select("purple"); check(ui.composerButton.bezelColor != nil,"发送按钮缺少强调色")
        AppAccent.setCustom(NSColor(srgbRed:0.2,green:0.4,blue:0.6,alpha:1))
        check(abs(ui.composerButton.bezelColor!.usingColorSpace(.sRGB)!.redComponent-0.2) < 0.001,"自定义色未更新按钮")
        AppAccent.select("system"); check(AppAccent.selection == "system","系统强调色选项")
        func descendants(_ root: NSView) -> [NSView] {root.subviews.flatMap {[$0]+descendants($0)}}
        let bubble = Bubble()
        for sample in [plus,missing,enterprise,multi,unknown] {
            bubble.show(title:"Codex 额度",body:" ",kind:"quota",scale:1.5,seconds:0)
            bubble.quotaRows(sample,scale:1.5)
            let views = descendants(bubble.window.contentView!)
            let close = views.compactMap {$0 as? BubbleCloseButton}.first!
            check(close.frame.midX < bubble.window.frame.width/2,"关闭按钮未在左侧")
            let bars = views.compactMap {$0 as? AccentProgressIndicator}
            check(bars.count == sample.rows.filter {$0.remaining != nil}.count,"未知或不限额出现百分比条")
            let scroll = views.compactMap {$0 as? NSScrollView}.first!
            for label in scroll.documentView!.subviews.compactMap({$0 as? NSTextField}) {
                check(label.frame.maxX <= scroll.documentView!.frame.width+1 && label.frame.maxY <= scroll.documentView!.frame.height+1,"长名称排版越界")
            }
        }
        bubble.hide()
        let settings = SettingsPanel(); settings.select(.appearance)
        let sliders = descendants(settings.window.contentView!).compactMap {$0 as? NSSlider}
        check(sliders.map {$0.numberOfTickMarks}.filter {$0 > 0}.sorted() == [5,7],"大小设置缺少 25% 刻度")
        let screen = NSRect(x:-1440,y:80,width:1440,height:820), pet = NSRect(x:-180,y:160,width:120,height:180), cursor = NSPoint(x:-175,y:200)
        let frame = MenuPlacement.frame(size:NSSize(width:240,height:600),cursor:cursor,screen:screen,pet:pet)
        check(screen.contains(frame) && !frame.intersects(pet),"菜单遮挡或越界")
        check(abs(frame.maxX-cursor.x) < 20,"左侧菜单仍离鼠标太远")
        ui.openHistory(); RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        check(app.activationPolicy() == .regular && ui.history.miniwindowImage != nil,"Dock 策略或应用图标")
        ui.history.miniaturize(nil); RunLoop.main.run(until:Date().addingTimeInterval(0.4))
        ui.openHistory(); RunLoop.main.run(until:Date().addingTimeInterval(0.4))
        check(!ui.history.isMiniaturized && ui.history.isVisible,"最小化的历史无法恢复")
        ui.history.orderOut(nil); ui.openHistory(); check(ui.history.isVisible,"隐藏历史无法恢复")
        print("通过：额度布局、左侧关闭、可替换强调色、大小刻度、贴近鼠标的菜单、历史最小化/隐藏恢复。")
    }
}
