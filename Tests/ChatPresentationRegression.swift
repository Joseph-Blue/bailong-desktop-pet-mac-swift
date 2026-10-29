import AppKit

@main
struct ChatPresentationRegression {
    static func main() throws {
        func check(_ condition: Bool, _ text: String) {if !condition {fputs("失败：\(text)\n",stderr); exit(1)}}
        func spin(_ seconds: Double) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let saved = ["petChatModel","petChatEffort"].map {($0,UserDefaults.standard.object(forKey:$0))}
        defer {for (key,value) in saved {if let value {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}}
        let ui = ChatInterface()
        let fixtures = #"[{"id":"a","model":"model-a","displayName":"模型 A","defaultReasoningEffort":"medium","supportedReasoningEfforts":[{"reasoningEffort":"medium","description":"中"},{"reasoningEffort":"xhigh","description":"极高"}],"isDefault":true,"hidden":false},{"id":"b","model":"model-b","displayName":"模型 B","defaultReasoningEffort":"low","supportedReasoningEfforts":[{"reasoningEffort":"low","description":"低"}],"isDefault":false,"hidden":false}]"#
        let models = try JSONDecoder().decode([ChatModel].self,from:Data(fixtures.utf8))
        ui.models.loaded(models,configuredModel:"model-a",configuredEffort:"xhigh")
        ui.models.chooseModel(nil); ui.models.chooseEffort(nil)
        let defaults = try ui.models.parameters()
        check(defaults["model"] as? String == "model-a" && defaults["effort"] as? String == "xhigh","默认模型没有跟随有效配置")
        ui.models.chooseModel("model-a"); ui.models.chooseEffort("xhigh")
        check(ui.composerModel.title == ui.historyModel.title && ui.historyModel.title.contains("极高"),"两个入口选择没有同步")
        ui.models.chooseModel("model-b")
        let changed = try ui.models.parameters()
        check(changed["model"] as? String == "model-b" && changed["effort"] as? String == "low","更换模型后仍使用不支持的档位")

        let c = Conversation(), t = Turn(); c.cwd = "/tmp"; c.turns = [t]
        t.input = "你好"; t.date = Date(timeIntervalSince1970:1790000017); t.status = "running"
        ui.refresh([c],selected:c,busy:true)
        check(ui.transcript.string.contains("主人 · "),"主人称呼")
        check(ui.history.title == "GPT白龙娘动态桌宠 · 历史对话" && ui.composer.title.isEmpty && !ui.composer.styleMask.contains(.titled),"历史标题与无标题输入气泡")
        ui.history.contentView!.layoutSubtreeIfNeeded()
        let input = ui.historyEditor.enclosingScrollView!
        let box = input.convert(input.bounds,to:ui.history.contentView)
        check(box.width > 800 && box.minX < 40,"历史输入框未占整行")
        check(ui.history.toolbar!.items.contains(where:{$0.itemIdentifier.rawValue == "reveal"}),"访达入口缺失")
        let reply = String(repeating:"主人，今天也一起努力。👩🏽‍💻\n",count:25)
        t.messages = reply; ui.refresh([c],selected:c,busy:true); spin(0.04)
        check(ui.transcript.isRevealing && !ui.transcript.string.contains(reply),"历史未逐步显示新回复")
        spin(0.8); check(ui.transcript.string.contains(reply),"流式历史丢字或重复")
        t.status = "completed"; t.final = reply; ui.refresh([c],selected:c,busy:false)
        check(!ui.transcript.isRevealing && ui.transcript.string.components(separatedBy:reply).count == 2,"完成后未收尾或重复正文")
        let stream = StreamingTextView()
        stream.setContent(NSAttributedString(string:"👍"),animated:false)
        stream.setContent(NSAttributedString(string:"👍🏽继续，e\u{301}👩‍💻"),animated:true); spin(0.4)
        check(stream.string == "👍🏽继续，e\u{301}👩‍💻","组合字符被拆断或重复")
        stream.setContent(NSAttributedString(string:reply),animated:true); spin(0.03)
        stream.setContent(NSAttributedString(string:reply),animated:false)
        check(stream.string == reply && !stream.isRevealing,"相同目标的完成更新未立即收尾")

        let bubble = Bubble()
        for scale in [0.5,1.0,1.5] {
            bubble.show(title:"主人，我正在回复你…",body:"测试",kind:"task",scale:scale,seconds:0,details:true)
            let content = bubble.window.contentView!
            let detail = content.subviews.compactMap {$0 as? ActionButton}.first(where:{$0.title == "详情"})!
            check(abs(detail.frame.width-(bubble.window.frame.width-32*scale)) < 1 && detail.bezelColor != nil,"详情按钮未占整行或没有强调色")
            check(content is BubbleBackgroundView,"气泡仍使用会叠加边缘的材质")
        }
        bubble.hide(); ui.history.orderOut(nil); ui.composer.orderOut(nil)
        print("通过：模型参数与双入口同步、整行输入、作者文案、流式追加/完成去重、Unicode 边界、全宽详情。")

        if CommandLine.arguments.contains("--catalog") {
            let connection = CodexConnection(); var finished = false; var failure: Error?
            connection.connect { error in
                if let error {failure = error; finished = true; return}
                connection.call("model/list",["limit":100,"includeHidden":false]) { result in
                    do {
                        let value = try result.get()
                        let rows = try JSONDecoder().decode([ChatModel].self,from:JSONSerialization.data(withJSONObject:value["data"] ?? []))
                        check(!rows.isEmpty,"本机模型列表为空")
                        print("通过：本机 model/list 返回 \(rows.count) 个模型，思考等级字段可解析。未发起推理任务。")
                    } catch {failure = error}
                    finished = true
                }
            }
            let deadline = Date().addingTimeInterval(15)
            while !finished && Date() < deadline {spin(0.05)}
            connection.close()
            check(finished,"本机模型列表读取超时")
            if let failure {throw failure}
        }
    }
}
