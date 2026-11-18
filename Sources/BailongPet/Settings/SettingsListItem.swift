import AppKit

enum SettingsDetail:Hashable {
    case lines, actions, messages(MessageSettingsPage.Topic)
    var title:String {
        switch self {
        case .lines:return "管理台词"
        case .actions:return "管理动作"
        case .messages(let topic):return topic.rawValue
        }
    }
}

// 搜索与管理列表共用项目身份和分组，只有实际显示行时才读取偏好和创建控件。
struct SettingsListItem {
    enum Kind {
        case template(String,preview:Clip?)
        case interaction(Clip)
        case animation(Clip,weighted:Bool)
    }
    let group:String, title:String, kind:Kind
    var keywords:String = ""
    var id:String {
        switch kind {
        case .template(let key,_):return key
        case .interaction(let clip),.animation(let clip,_):return clip.id
        }
    }
    var preview:Clip? {
        switch kind {
        case .template(_,let clip):return clip
        case .interaction(let clip),.animation(let clip,_):return clip
        }
    }
    func summary(_ preferences:PetPreferences) -> String {
        switch kind {
        case .template(let key,_):return preferences.string(key)
        case .interaction(let clip):
            let custom = (preferences.value("customLines") as? [String:String])?[clip.id] ?? ""
            return custom.isEmpty ? preferences.templateSource(clip.line ?? "") : custom
        case .animation(let clip,let weighted):
            let speed = preferences.clipSpeed(clip.id).formatted()+"×"
            return weighted ? speed+"   权重 "+String(preferences.baseWeight(clip.id)) : speed
        }
    }
    func searchEntry(_ detail:SettingsDetail) -> SettingsSearchEntry {
        .init(section:detail == .actions ? .activity : .identity,group:group,title:title,
              keywords:keywords,detail:detail,itemID:id)
    }
}
