import AppKit

enum MessageSettingsPage {
    enum Topic:String,CaseIterable {
        case content = "气泡内容与任务概览", reading = "阅读与预览", input = "输入与审批"
    }

    private enum Value {
        case number(String,unit:String), hours
        var keys:[String] {
            switch self {case .number(let key,_):return [key]; case .hours:return ["quietStart","quietEnd"]}
        }
        func title(for row:String) -> String {
            switch self {
            case .number(_,let unit):return unit == "秒" ? row+"停留时间" : "提醒间隔"
            case .hours:return "安静时段"
            }
        }
        func summary(_ prefs:PetPreferences) -> String {
            switch self {
            case let .number(key,unit):
                let value = prefs.number(key)
                return value == 0 ? "手动关闭" : value.formatted()+" "+unit
            case .hours:
                func time(_ key:String) -> String {
                    let minute = Int(prefs.number(key))
                    return String(format:"%02d:%02d",minute/60,minute%60)
                }
                let start = time("quietStart"), end = time("quietEnd")
                return start+"–"+end+(start == end ? "（全天）" : "")
            }
        }
        func button(for row:String,requires:[String],form:SettingsForm) -> SettingsValueButton {
            let title = title(for:row)
            let button = SettingsValueButton(label:title,preferences:form.preferences) { editor in
                switch self {
                case let .number(key,unit):
                    let range = PetPreferences.ranges[key]!
                    let slider = editor.slider(title,key,range:range,suffix:unit,minimumLabel:range.lowerBound == 0 ? "手动关闭" : nil)
                    editor.fill(slider,in:editor.content)
                case .hours:
                    editor.fill(editor.time("开始时间","quietStart"),in:editor.content)
                    editor.fill(editor.time("结束时间","quietEnd"),in:editor.content)
                }
            }
            form.observeValues { [weak button] prefs in
                guard let button else {return}
                let value = summary(prefs)
                if value != button.title {button.title = value; button.setAccessibilityValue(value)}
                button.isEnabled = requires.allSatisfy {prefs.bool($0)}
                if !button.isEnabled {button.closeEditor()}
            }
            return button
        }
    }

    private enum Control {
        case toggle(String,Value? = nil)
        case choice(String,[(String,String)])
        case slider(String,suffix:String)
        case value(Value), preview
        var key:String? {
            switch self {
            case let .toggle(key,_),let .choice(key,_),let .slider(key,_):return key
            case .value,.preview:return nil
            }
        }
    }

    private struct Row {
        let title: String
        let control: Control
        var value:Value? {
            switch control {
            case let .toggle(_,value):return value
            case .value(let value):return value
            default:return nil
            }
        }
        var valueRequires:[String] {requires+[control.key].compactMap {$0}}
        let keywords: String
        let requires: [String]
        let detail: String?

        init(_ title:String,_ control:Control,keywords:String = "",requires:[String] = [],detail:String? = nil) {
            self.title = title
            self.control = control
            self.keywords = keywords
            self.requires = requires
            self.detail = detail
        }
    }

    private struct Group {
        let title: String
        var topic:Topic? = nil
        var destination:Topic? = nil
        var symbol: String? = nil
        var image: (() -> NSImage?)? = nil
        var keywords = ""
        var detail: String? = nil
        let rows: [Row]
    }

    private static let groups: [Group] = [
        Group(title:"历史记录",symbol:"book",keywords:"聊天 保存 同步",rows:[
            Row("记录历史",.toggle("recordHistory"),detail:"关闭后保留已有记录，停止保存新内容；重新开启不会补录。Codex 自身的记录不受影响。"),
        ]),
        Group(title:"气泡窗审批",topic:.input,symbol:"checkmark.shield",keywords:"批准 允许这一次 允许本轮 拒绝 左拒绝 右允许 左允许 右拒绝 左右 位置 红叉 绿对钩",rows:[
            Row("气泡窗审批按钮顺序",.choice("approvalButtonOrder",[("rejectLeft","左拒绝 · 右允许"),("allowLeft","左允许 · 右拒绝")]),detail:"只调整气泡中的按钮位置。红叉拒绝、绿对钩允许；审批需点击按钮，不能用键盘提交。"),
        ]),
        Group(title:"输入快捷键",topic:.input,symbol:"keyboard",keywords:"回车 Return Enter ⌃ Control Ctrl ⌘ Command ⇧ Shift ⌥ Option 发送 换行 快捷回复 插话 问卷",rows:[
            Row("发送与换行",.choice("sendShortcut",SendShortcut.options)),
        ]),
        Group(title:"任务气泡",destination:.content,symbol:"bubble.left.and.bubble.right",keywords:"任务气泡提醒 任务进展 通知 显示 开关",rows:[
            Row("显示任务气泡",.toggle("taskBubbles"),detail:"关闭后仍会显示审批、待回答的问题和错误提示。"),
            Row("任务过程消息",.toggle("progressBubbles",.number("progressSeconds",unit:"秒")),requires:["taskBubbles"]),
            Row("最终回复",.toggle("resultBubbles",.number("resultSeconds",unit:"秒")),requires:["taskBubbles"]),
            Row("在气泡中显示任务信息栏",.toggle("taskInfoBarEnabled"),keywords:"Git 状态 GitHub 分支 仓库状态 任务概览 本轮文件改动 文件增删 状态栏 进度 工具调用",detail:"在任务气泡和任务概览中同行显示 Git 状态和本轮文件改动。"),
            Row("思考与工具进展小气泡",.toggle("progressToastEnabled",.number("progressToastSeconds",unit:"秒")),keywords:"自动显示进展小气泡 默认开启 2s 2秒 思考摘要 工具调用 短气泡 小窗口 顶部 进展 自动 弹出 开关",requires:["taskBubbles","progressBubbles"]),
        ]),
        Group(title:"工作区状态条",image:{GitIcons.git},keywords:"Git GitHub 分支 仓库 工作区 目录 文件修改 增删 状态 状态条 独立 小窗 常驻 隐藏工作区状态条",rows:[
            Row("显示工作区状态条",.toggle("gitWindowEnabled"),detail:"在桌宠旁常驻显示当前会话的目录、Git 状态和本轮文件改动。"),
        ]),
        Group(title:"显示哪些消息",topic:.content,symbol:"line.3.horizontal.decrease.circle",keywords:"显示思考过程 思考摘要 工具名称 操作 执行状态 短气泡 小窗口 顶部 进展 自动 弹出 开关",rows:[
            Row("显示思考摘要",.toggle("showThinkingProgress"),keywords:"正在思考 思考图标 灯泡 lightbulb.max 公开摘要"),
            Row("显示工具调用",.toggle("showToolProgress")),
            Row("隐藏工具执行失败提示",.toggle("hideToolFailures"),keywords:"工具失败 执行失败 命令失败 报错 错误提示 失败角标 过滤 隐藏 概览 组标题 小气泡",requires:["showToolProgress"],detail:"隐藏进展小气泡和概览标题中的单次工具失败。历史记录与整轮任务失败照常显示。"),
        ]),
        Group(title:"气泡卡片与任务概览",topic:.content,symbol:"rectangle.stack",keywords:"消息 历史 上一条 下一条 正在执行 最近 完成",rows:[
            Row("气泡卡片保留数量",.slider("bubbleCardLimit",suffix:"条")),
            Row("互动气泡显示任务概览",.toggle("showTaskOverview"),detail:"鼠标操作设为“显示任务进度、播放随机动画”时，台词下方显示任务列表。点击任务可在 Codex 中打开。"),
            Row("近期结束任务数量",.slider("recentTaskCount",suffix:"条"),requires:["showTaskOverview"],detail:"每个会话只显示最近一次任务。"),
        ]),
        Group(title:"互动与额度",destination:.reading,symbol:"timer",keywords:"气泡 消息 通知 停留时间 秒 时长 手动关闭",rows:[
            Row("互动台词",.toggle("interactionBubbles",.number("interactionSeconds",unit:"秒"))),
            Row("额度信息",.value(.number("quotaSeconds",unit:"秒"))),
        ]),
        Group(title:"阅读与预览",topic:.reading,symbol:"text.bubble",keywords:"停留时间 气泡 自动关闭 预览 悬停 手动关闭 秒",rows:[
            Row("长回复自动延长阅读时间",.toggle("autoReadTime"),requires:["taskBubbles","resultBubbles"],detail:"最长 120 秒。"),
            Row("鼠标移入时暂停倒计时",.toggle("pauseOnHover")),
            Row("预览最终回复气泡",.preview),
        ]),
        Group(title:"声音",symbol:"speaker.wave.2",keywords:"声音",rows:[
            Row("播放音效",.toggle("soundEnabled")),
        ]),
        Group(title:"安静陪伴与提醒",symbol:"moon",keywords:"安静陪伴模式 启用专注时段 免打扰 时间 夜间 静音",detail:"按本机时间执行。时段可跨天，起止时间相同表示全天。",rows:[
            Row("立即开启安静陪伴",.toggle("quietCompanion"),detail:"减少活动并停止自动移动，隐藏互动台词和进展气泡，关闭音效。最终回复和待处理通知照常显示。"),
            Row("定时开启安静陪伴",.toggle("quietSchedule",.hours),detail:"手动开启后会一直保持安静，关闭后恢复定时安排。"),
            Row("久无进展时提醒",.toggle("taskReminderEnabled",.number("taskReminderMinutes",unit:"分钟")),keywords:"进展提醒 任务 执行 无新进度 90秒 5分钟 定时 等待 台词",requires:["taskBubbles","progressBubbles"],detail:"任务连续 90 秒没有新进展后，按下方间隔提醒。等待回答、批准或正在停止时不提醒。"),
        ]),
    ]

    private static let titlesByKey = Dictionary(uniqueKeysWithValues:groups.flatMap { group in
        group.rows.compactMap { row in row.control.key.map {($0,row.title)} }
    })

    // 旧版两个开关仍属于本页恢复范围。
    static var preferenceKeys:[String] {
        groups.flatMap {group in group.rows.flatMap {[$0.control.key].compactMap {$0} + ($0.value?.keys ?? [])}} + ["countAfterReveal","typingEffect"]
    }

    static var searchEntries:[SettingsSearchEntry] {
        groups.flatMap { group in
            group.rows.flatMap { row -> [SettingsSearchEntry] in
                func entry(_ title:String,requires:[String],valueTitle:String? = nil) -> SettingsSearchEntry {
                    let condition = requires.isEmpty ? "" : "开启"+requires.map {titlesByKey[$0]!}.joined(separator:"、")+"后可调整"
                    let keywords = [group.keywords,row.keywords,row.title,valueTitle ?? "",valueTitle == nil ? "" : "时间 时长 调整"].joined(separator:" ")
                    return .init(section:.messages,group:group.title,title:title,keywords:keywords,condition:condition,
                                 detail:group.topic.map(SettingsDetail.messages),anchorTitle:valueTitle)
                }
                guard let value = row.value else {return [entry(row.title,requires:row.requires)]}
                let title = value.title(for:row.title)
                let names:[String]
                switch value {case .hours:names = [title,"开始时间","结束时间"]; case .number:names = [title]}
                let valueEntries = names.map {entry($0,requires:row.valueRequires,valueTitle:title)}
                if case .value = row.control {return valueEntries}
                return [entry(row.title,requires:row.requires)]+valueEntries
            }
        }
    }

    static func render(form:SettingsForm,topic:Topic?,open:@escaping (Topic) -> Void,onPreview:@escaping (MessagePurpose) -> Void) {
        for group in groups where group.topic == topic {
            let rows = group.rows.map { row -> NSView in
                switch row.control {
                case let .toggle(key,adjustment):
                    let value = adjustment?.button(for:row.title,requires:row.valueRequires,form:form)
                    return form.toggle(row.title,key,detail:row.detail,requires:row.requires,accessory:value)
                case let .choice(key,options):
                    return form.choice(row.title,key,options,detail:row.detail,requires:row.requires)
                case let .slider(key,suffix):
                    return form.slider(row.title,key,range:PetPreferences.ranges[key]!,suffix:suffix,detail:row.detail,requires:row.requires)
                case .value(let value):
                    return form.row(value.title(for:row.title),control:value.button(for:row.title,requires:row.requires,form:form))
                case .preview:
                    return form.row(row.title,control:ActionButton("预览…") {onPreview(.result)})
                }
            }
            let link = group.destination.map { target in form.navigationButton(target.rawValue) {open(target)} }
            form.group(group.title,rows,symbol:group.symbol,image:group.image?(),action:link,detail:group.detail)
        }
        if topic == nil {form.content.addArrangedSubview(form.navigationButton(Topic.input.rawValue) {open(.input)})}
    }
}
