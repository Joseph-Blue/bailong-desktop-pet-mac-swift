import AppKit

enum IdentitySettingsPage {
    static func render(form:SettingsForm,catalog:Catalog?,window:NSWindow,onPreview:@escaping (MessagePurpose) -> Void,reload:@escaping () -> Void) {
        let preferences = form.preferences
        form.fill(form.note("{用户名} 是你的名字，{桌宠名} 是桌宠的名字；{特定称呼} 使用下面填写的内容，留空沿用你的名字。右键点击台词或特定称呼输入框，可插入这些变量。"),in:form.content)
        let names = [form.text("你的名字","ownerName",placeholder:"默认为“主人”"),form.text("桌宠的名字","petName",placeholder:"白龙娘"),form.text("特定称呼","customAddress",placeholder:"留空沿用你的名字，可以插入变量")]
        form.group("我们怎么称呼彼此",names)
        let preview = label(preferences.statusLine("greetingTemplate")); preview.font = .systemFont(ofSize:15,weight:.medium); form.identityPreview = preview
        form.group("见面时说",[form.text("问候语","greetingTemplate",limit:120),form.alignedRow(leading:preview,control:ActionButton("预览消息") {onPreview(.preview)})])
        form.group("任务状态台词",[form.text("执行任务中","taskProgressTemplate",limit:120),form.text("正在思考","taskThinkingTemplate",limit:120),form.text("正在调用工具","taskToolTemplate",limit:120),form.text("正在运行命令","taskCommandTemplate",limit:120),form.text("已运行命令","taskCommandCompletedTemplate",limit:120),form.text("等待回答","taskAnswerTemplate",limit:120),form.text("等待批准","taskApprovalTemplate",limit:120),form.text("任务成功","taskSuccessTemplate",limit:120),form.text("任务失败","taskFailureTemplate",limit:120),form.text("任务中断或取消","taskInterruptedTemplate",limit:120)])
        form.group("额度查询台词",[form.text("正在查询","quotaLoadingTemplate",limit:120)])
        if let catalog {
            let lines = (catalog.variants+catalog.work).filter {$0.line != nil}
            let restore = ActionButton("恢复默认") { [weak window] in
                window?.makeFirstResponder(nil)
                preferences.set([String:String](),for:"customLines"); reload()
            }
            restore.controlSize = .small; restore.font = .systemFont(ofSize:11)
            restore.setAccessibilityLabel("恢复全部互动台词为默认值")
            form.group("互动台词",lines.map {clip in form.entry(clip.title,value:(preferences.value("customLines") as? [String:String])?[clip.id] ?? "",emptyFallback:preferences.templateSource(clip.line ?? ""),limit:120) {preferences.setLine($0,for:clip.id)}},action:restore)
        }
    }
}
