import Foundation

// 默认值、编辑控件、恢复范围和搜索共用同一份台词定义。
enum ConversationLines {
    struct Entry {
        let key:String
        var title:String {L10n.text(.settings,"dialogueLabels."+key)}
        var text:String {L10n.text(.dialogue,"dialogue."+key)}
    }
    static let task:[Entry] = [
        .init(key:"taskReceivedTemplate"),
        .init(key:"taskReplyTemplate"),
        .init(key:"desktopTaskReceivedTemplate"),
        .init(key:"taskSteeringTemplate"),
        .init(key:"taskStoppingTemplate"),
        .init(key:"taskStoppedTemplate")]
    static let interface:[Entry] = [
        .init(key:"conversationNewTemplate"),
        .init(key:"conversationBusyTemplate"),
        .init(key:"historyBusyTemplate"),
        .init(key:"historyIdleTemplate"),
        .init(key:"conversationEmptyTemplate")]
    static let working:[Entry] = [
        .init(key:"workingPawsTemplate"),
        .init(key:"workingBusyTemplate"),
        .init(key:"workingVisitTemplate"),
        .init(key:"workingHornsTemplate"),
        .init(key:"workingTsundereTemplate"),
        .init(key:"workingCompanyTemplate"),
        .init(key:"workingReminderTemplate"),
        .init(key:"workingEncouragementTemplate")]
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
