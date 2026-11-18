import AppKit

enum IdentitySettingsPage {
    static func render(form:SettingsForm,catalog:Catalog?,window:NSWindow,onLinePreview:@escaping (Clip,String) -> Void,manage:@escaping () -> Void) {
        let preferences = form.preferences
        func templatePreview(_ title:String,key:String,clip:Clip?) -> ActionButton {
            let button = form.animationPreviewButton(title,compact:true) { [weak window] in
                guard let clip,window?.makeFirstResponder(nil) == true else {return}
                onLinePreview(clip,preferences.statusLine(key))
            }
            button.isEnabled = clip != nil
            return button
        }
        form.content.addArrangedSubview(form.navigationButton(SettingsDetail.lines.title,action:manage))
        form.fill(form.note("{用户名} 是你的名字，{桌宠名} 是桌宠的名字；{特定称呼} 使用下面填写的内容，留空沿用你的名字。右键点击台词或特定称呼输入框，可插入这些变量。"),in:form.content)
        let names = [form.text("你的名字","ownerName",placeholder:"默认为“主人”"),form.text("桌宠的名字","petName",placeholder:"白龙娘"),form.text("特定称呼","customAddress",placeholder:"留空沿用你的名字，可以插入变量")]
        form.group("我们怎么称呼彼此",names,symbol:"person.2")
        let greetingPreview = templatePreview("问候语",key:"greetingTemplate",clip:catalog?.variants.first(where:{$0.id == "01"}))
        form.group("见面时说",[form.text("问候语","greetingTemplate",limit:120,action:greetingPreview)],symbol:"hand.wave")
        form.group("工作中台词",[form.toggle("随机工作中台词抽取","randomWorkingLines",detail:"有执行中任务时，每次打开任务概览随机抽取一句。关闭后使用“执行任务中”台词。")],symbol:"text.bubble")
    }

    static func items(catalog:Catalog?) -> [SettingsListItem] {
        func templates(_ group:String,_ entries:[ConversationLines.Entry]) -> [SettingsListItem] {
            entries.map {.init(group:group,title:$0.title,kind:.template($0.key,preview:nil),keywords:"台词 模板 "+$0.text)}
        }
        var result = templates("工作中台词",ConversationLines.working) + templates("任务状态台词",ConversationLines.task)
        for (title,key,keywords) in [
            ("执行任务中","taskProgressTemplate","我还在留意进展"),("有新进展","taskUpdateTemplate","进度 任务计划 阶段性进展 Codex 项目任务 我忙到这一步啦"),
            ("等待回答","taskAnswerTemplate","审批"),("等待批准","taskApprovalTemplate","审批"),
            ("任务成功","taskSuccessTemplate",""),("任务失败","taskFailureTemplate",""),("任务中断或取消","taskInterruptedTemplate","")
        ] {
            result.append(.init(group:"任务状态台词",title:title,kind:.template(key,preview:nil),keywords:"台词 模板 "+keywords))
        }
        result += templates("聊天窗口台词",ConversationLines.interface)
        result.append(.init(group:"额度查询台词",title:"正在查询",kind:.template("quotaLoadingTemplate",preview:catalog?.quotaAnimation),keywords:"额度 ChatGPT 订阅 台词 动作 播放 预览"))
        if let catalog {
            result += (catalog.variants+catalog.work).filter {$0.line != nil}.map {
                .init(group:"互动台词",title:$0.title,kind:.interaction($0),keywords:"台词 模板 动作 播放 预览")
            }
        }
        return result
    }
}
