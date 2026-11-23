import AppKit

enum SettingsDetail:Hashable {
    case lines, actions, messages(MessageSettingsPage.Topic)
    var title:String {
        switch self {
        case .lines:return L10n.text(.settings,"settingsListItem.lines")
        case .actions:return L10n.text(.settings,"settingsListItem.actions")
        case .messages(let topic):return topic.title
        }
    }
}

enum SettingsLineResetGroup {
    case working, interaction

    var title:String {
        switch self {case .working:return L10n.text(.settings,"identity.workingLineEditTarget.text"); case .interaction:return L10n.text(.settings,"identity.restore.text.5")}
    }

    func restore(in preferences:PetPreferences) {
        switch self {
        case .working:preferences.reset(["randomWorkingLines"]+ConversationLines.working.map(\.key))
        case .interaction:preferences.set([String:String](),for:"customLines")
        }
    }
}

// 首页、管理列表和静态搜索共用项目身份；创建索引时只读取元数据。
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
    var lineResetGroup:SettingsLineResetGroup? {
        switch kind {
        case .interaction:return .interaction
        case .template(let key,_):return ConversationLines.working.contains {$0.key == key} ? .working : nil
        case .animation:return nil
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
            return custom.isEmpty ? preferences.templateSource(clip.localizedLine ?? "") : custom
        case .animation(let clip,let weighted):
            let speed = preferences.clipSpeed(clip.id).formatted()+"×"
            return weighted ? speed+L10n.text(.settings,"settingsListItem.summary.text")+String(preferences.baseWeight(clip.id)) : speed
        }
    }
    func searchEntry(in section:SettingsSection) -> SettingsSearchEntry {
        .init(section:section,group:group,title:title,keywords:keywords,itemID:id,anchorTitle:id)
    }

    func lineEditor(in form:SettingsForm,onPreview:@escaping () -> Void) -> NSView? {
        let button = preview.map { _ in form.animationPreviewButton(title,compact:true,action:onPreview) }
        switch kind {
        case .template(let key,_):
            return form.text(title,key,limit:ConversationLines.limit(key),action:button)
        case .interaction(let clip):
            let prefs = form.preferences
            return form.entry(title,value:summary(prefs),emptyFallback:prefs.templateSource(clip.localizedLine ?? ""),limit:120,action:button) {
                prefs.setLine($0,for:clip.id)
            }
        case .animation:return nil
        }
    }
}
