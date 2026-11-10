import Foundation

// 默认值、编辑控件、恢复范围和搜索共用同一份台词定义。
enum ConversationLines {
    struct Entry {let key:String; let title:String; let text:String}
    static let task:[Entry] = [
        .init(key:"taskReceivedTemplate",title:"桌宠对话收到任务",text:"{用户名}，我收到啦！这就认真帮你处理。"),
        .init(key:"taskReplyTemplate",title:"桌宠对话正在回复",text:"{用户名}，我正在回复你…"),
        .init(key:"desktopTaskReceivedTemplate",title:"Codex 对话收到任务",text:"{用户名}，我收到啦！这就认真帮你处理 Codex 里的任务。"),
        .init(key:"taskSteeringTemplate",title:"收到插话",text:"{用户名}，补充的话我收到啦，我会记着一起处理。"),
        .init(key:"taskStoppingTemplate",title:"正在停止任务",text:"{用户名}，我正在收好手头的工作…"),
        .init(key:"taskStoppedTemplate",title:"主动停止完成",text:"{用户名}，我先停下来啦。"),
        .init(key:"taskWarningTemplate",title:"步骤执行异常",text:"{用户名}，有个情况要告诉你。")]
    static let interface:[Entry] = [
        .init(key:"conversationNewTemplate",title:"新对话已准备",text:"{用户名}，新对话准备好啦。"),
        .init(key:"conversationBusyTemplate",title:"临时聊天执行中",text:"{用户名}，我正在认真忙着呢…"),
        .init(key:"historyBusyTemplate",title:"历史窗口执行中",text:"{用户名}，我正忙着呢，进展会记在这里哦"),
        .init(key:"historyIdleTemplate",title:"历史窗口空闲",text:"{用户名}的叮嘱，我都记在这台电脑里啦"),
        .init(key:"conversationEmptyTemplate",title:"空对话引导",text:"{用户名}，我在这里等你呀。把想做的事写在下方，我们就可以开始啦。")]
    static let working:[Entry] = [
        .init(key:"workingPawsTemplate",title:"小爪爪",text:"{用户名}，小爪爪还在忙呢，来看看任务进展吧。"),
        .init(key:"workingBusyTemplate",title:"认真忙碌",text:"{用户名}，我还在认真忙着哦。手头的事情都在这里啦。"),
        .init(key:"workingVisitTemplate",title:"查岗",text:"{用户名}来查岗啦？{桌宠名}有在认真干活哦！"),
        .init(key:"workingHornsTemplate",title:"龙角",text:"龙角收到{用户名}的关注啦！一起看看忙到哪里了吧。"),
        .init(key:"workingTsundereTemplate",title:"傲娇",text:"才没有偷懒呢……{用户名}，进展在这里，给你看。"),
        .init(key:"workingCompanyTemplate",title:"陪伴",text:"{用户名}，陪我看一眼进展吧，{桌宠名}还在努力呢。"),
        .init(key:"workingReminderTemplate",title:"叮嘱",text:"{用户名}的叮嘱，我都有放在心上。来看看这些事情吧。"),
        .init(key:"workingEncouragementTemplate",title:"鼓励",text:"{用户名}，给忙碌的{桌宠名}一点鼓励吧，摸摸龙角也可以哦。")]
    static var keys:[String] {(task+interface+working).map(\.key)}
    static var defaults:[String:Any] {Dictionary(uniqueKeysWithValues:(task+interface+working).map {($0.key,$0.text as Any)})}
    static func limit(_ key:String) -> Int {key == "desktopTaskReceivedTemplate" ? 240 : 120}
    static func migrateReceivedLine(_ values:[String:Any]) -> [String:Any] {
        var values = values
        let titleKey = "desktopTaskReceivedTemplate", bodyKey = "desktopTaskReceivedBodyTemplate"
        guard values[bodyKey] == nil || values[bodyKey] is String else {return values}
        let oldTitle = "{用户名}，我收到啦！", oldBody = "这就认真帮你处理 Codex 里的任务。"
        let title = values[titleKey] as? String, body = values[bodyKey] as? String
        if body != nil || title == oldTitle {
            let heading = title?.isEmpty == false ? title! : oldTitle
            let detail = body?.isEmpty == false ? body! : oldBody
            values[titleKey] = heading == oldTitle && detail == oldBody
                ? defaults[titleKey] : heading + detail
        }
        values.removeValue(forKey:bodyKey)
        return values
    }
}
