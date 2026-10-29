import AppKit

@main
struct ModelSelectionRegression {
    static func main() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let suite = "BailongModelSelectionRegression."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let shared = ChatModelSettings(defaults:defaults), ui: ChatInterface
        ui = ChatInterface(models:shared)
        // 两入口使用同一设置实例，全部选择仅写入临时测试偏好。
        func check(_ condition: Bool, _ message: String) throws {
            if !condition {throw PetFailure(message:message)}
        }
        func model(_ id: String, _ levels: [String], _ normal: String) -> ChatModel {
            ChatModel(id:id,model:id,displayName:id,defaultReasoningEffort:normal,
                supportedReasoningEfforts:levels.map {ChatModel.Effort(reasoningEffort:$0,description:$0)},isDefault:false,hidden:false)
        }
        func exercise(_ rows: [ChatModel], ids: [String]) throws {
            shared.loaded(rows,configuredModel:ids.first,configuredEffort:"unsupported-setting")
            let controls = ModelSelectorContent(shared), content = controls.view
            let picker = content.subviews.compactMap {$0 as? NSPopUpButton}.first!
            let slider = content.subviews.compactMap {$0 as? NSSlider}.first!
            for id in ids {
                let row = rows.first(where:{$0.model == id})!
                let index = picker.itemArray.firstIndex(where:{$0.representedObject as? String == id})!
                picker.selectItem(at:index); _ = picker.sendAction(picker.action,to:picker.target)
                let expected = row.supportedReasoningEfforts.map(\.reasoningEffort)
                try check(shared.currentModelID == id,"下拉选择未应用："+id)
                try check(slider.numberOfTickMarks == expected.count,"刻度数未随模型更新："+id)
                try check(slider.isHidden == (expected.count < 2),"无档位/单档位显示错误："+id)
                try check(slider.maxValue == Double(max(1,expected.count-1)),"滑条范围未更新："+id)
                for position in Set([0,max(0,expected.count-1)]).sorted() where expected.count > 1 {
                    slider.integerValue = position; _ = slider.sendAction(slider.action,to:slider.target)
                    let params = try shared.parameters()
                    try check(params["model"] as? String == id && params["effort"] as? String == expected[position],"滑条与请求参数不一致："+id)
                    try check(ui.composerModel.title == ui.historyModel.title,"两个聊天入口未同步")
                    try check(ui.composerModel.title.hasSuffix(" · "+ChatModelSettings.effortName(expected[position])),"档位名称不是官方文案")
                }
                let params = try shared.parameters()
                try check(expected.isEmpty ? params["effort"] == nil : expected.contains(params["effort"] as? String ?? ""),"发送了此模型不支持的档位："+id)
                print("通过：\(id) · \(expected.map(ChatModelSettings.effortName).joined(separator:" / "))")
            }
        }
        let fixtures = [model("fixture-flex",["low","medium","high","xhigh","max","ultra"],"medium"),model("fixture-single",["low"],"low"),model("fixture-none",[],"none")]
        try exercise(fixtures,ids:fixtures.map(\.model))
        shared.chooseModel("fixture-flex"); shared.chooseEffort("ultra"); shared.chooseModel("fixture-single")
        try check(shared.selectedEffort == nil && shared.currentEffort == "low","切换模型后残留不支持的偏好")
        shared.chooseEffort("ultra"); try check(shared.currentEffort == "low","可选档位校验失效")
        let astra = model("gpt-6-astra",["high","xhigh","max","ultra"],"high")
        shared.chooseModel(nil); shared.chooseEffort(nil); shared.loaded([astra],configuredModel:astra.model,configuredEffort:"ultra")
        try check(shared.effortTitle == "Ultra" && shared.showsAstraRedWarning,"默认 Ultra 名称或彩蛋失效")
        shared.chooseEffort("max"); try check(shared.effortTitle == "Max" && shared.showsAstraRedWarning,"Max 名称或彩蛋失效")
        shared.chooseEffort("high"); try check(shared.caution != nil && !shared.showsAstraRedWarning,"普通 Astra 提醒失效")
        let connection = CodexConnection(); defer {connection.close()}
        var finished = false, failure: Error?, catalog = [ChatModel]()
        func page(_ cursor: String? = nil) {
            var params: [String:Any] = ["limit":100,"includeHidden":false]
            if let cursor {params["cursor"] = cursor}
            connection.call("model/list",params) {result in
                do {
                    let result = try result.get()
                    catalog += try JSONDecoder().decode([ChatModel].self,from:JSONSerialization.data(withJSONObject:result["data"] ?? []))
                    if let cursor = result["nextCursor"] as? String {page(cursor)} else {finished = true}
                } catch {failure = error; finished = true}
            }
        }
        connection.connect {error in if let error {failure = error; finished = true} else {page()} }
        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
        try check(finished,"模型目录读取超时")
        if let failure {throw failure}
        let preferred = ["gpt-6.1-sol","gpt-6-astra","gpt-5.6-luna"]
        let candidates = preferred.compactMap {id in catalog.first(where:{$0.model == id})}
        let chosen = Array((candidates+catalog.filter {row in !candidates.contains(where:{$0.model == row.model})}).prefix(3))
        try check(!chosen.isEmpty,"真实模型目录为空")
        shared.chooseEffort(nil)
        try exercise(catalog,ids:chosen.map(\.model))
        ui.history.contentView?.layoutSubtreeIfNeeded()
        func allViews(_ root: NSView) -> [NSView] {[root]+root.subviews.flatMap(allViews)}
        let split = allViews(ui.history.contentView!).compactMap {$0 as? HistorySplitView}.first!
        split.adjustSubviews()
        try check(split.subviews[1].frame.minX-split.subviews[0].frame.maxX >= 15.5,"两个圆角框仍紧贴")
        try check(split.subviews[0] is HistorySidebarView,"侧栏未使用原生材质")
        print("通过：\(chosen.count) 个真实模型的选择/两端档位/双入口同步，以及空档位、单档位、失效档位和 16pt 双栏间距。")
        print("只请求 initialize 与 model/list，未创建 thread、未发送 turn，无推理额度消耗。")
    }
}
