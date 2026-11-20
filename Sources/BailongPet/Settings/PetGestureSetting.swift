struct PetGestureSetting {
    let key: String
    let title: String
    let defaultAction: String
    let keywords: String
    var help: String? = nil

    static let group = "鼠标与触控板互动"
    static let actions = [("none","无动作"),("chat","临时聊天面板"),("quota","查看额度"),("history","查看历史消息"),
                              ("workspace","显示或隐藏工作区状态条"),("random","显示任务进度、播放随机动画"),("randomAnimation","播放随机动画")]

    static let all = PetGesture.allCases.map(\.setting)
}

extension PetGesture {
    private static let clickKeywords = "点击 点按 单句台词 Control ⌃ ^ 右键"

    var setting: PetGestureSetting {
        switch self {
        case .singleClick:
            return .init(key:"singleClickAction", title:"单击桌宠", defaultAction:"random", keywords:Self.clickKeywords)
        case .doubleClick:
            return .init(key:"doubleClickAction", title:"双击桌宠", defaultAction:"quota", keywords:Self.clickKeywords)
        case .rightDoubleClick:
            return .init(key:"rightDoubleClickAction", title:"右键双击桌宠", defaultAction:"chat", keywords:Self.clickKeywords, help:"""
                如使用触控板：

                1. 按住 ^（control 键）点按或双击点按（一段下压）桌宠，等同于鼠标右键点击或双击。
                2. 无论 macOS 系统设置中，触控板的辅助点按触发方式如何设置，只有点按（一段下压）才可正确触发双击鼠标右键效果
                """)
        case .forceClick:
            return .init(key:"forceClickAction", title:"触控板用力点按（两段下压）", defaultAction:"chat",
                         keywords:"触控板重按 第二段下压 压感 Force Touch Force Click")
        }
    }
}
