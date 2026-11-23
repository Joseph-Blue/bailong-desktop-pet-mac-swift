struct PetGestureSetting {
    let key: String
    let title: String
    let defaultAction: String
    let keywords: String
    var help: String? = nil

    static let group = L10n.text(.settings,"petGestureSetting.group")
    static let actions = [("none",L10n.text(.settings,"petGestureSetting.actions")),("chat",L10n.text(.settings,"petGestureSetting.actions.2")),("quota",L10n.text(.settings,"petGestureSetting.actions.3")),("history",L10n.text(.settings,"petGestureSetting.actions.4")),
                              ("workspace",L10n.text(.settings,"petGestureSetting.text")),("random",L10n.text(.settings,"petGestureSetting.text.2")),("randomAnimation",L10n.text(.settings,"petGestureSetting.text.3"))]

    static let all = PetGesture.allCases.map(\.setting)
}

extension PetGesture {
    private static let clickKeywords = L10n.text(.settings,"petGestureSetting.clickKeywords")

    var setting: PetGestureSetting {
        switch self {
        case .singleClick:
            return .init(key:"singleClickAction", title:L10n.text(.settings,"petGestureSetting.singleClickAction.title"), defaultAction:"random", keywords:Self.clickKeywords)
        case .doubleClick:
            return .init(key:"doubleClickAction", title:L10n.text(.settings,"petGestureSetting.doubleClickAction.title"), defaultAction:"quota", keywords:Self.clickKeywords)
        case .rightDoubleClick:
            return .init(key:"rightDoubleClickAction", title:L10n.text(.settings,"petGestureSetting.rightDoubleClickAction.title"), defaultAction:"chat", keywords:Self.clickKeywords, help:L10n.text(.settings,"petGestureSetting.rightDoubleClickAction.help"))
        case .forceClick:
            return .init(key:"forceClickAction", title:L10n.text(.settings,"petGestureSetting.forceClickAction.title"), defaultAction:"chat",
                         keywords:L10n.text(.settings,"petGestureSetting.petGesture.keywords"))
        }
    }
}
