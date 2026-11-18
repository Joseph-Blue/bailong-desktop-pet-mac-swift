import AppKit

enum MessageSettingsPage {
    private enum Control {
        case toggle(String)
        case choice(String,[(String,String)])
        case slider(String,suffix:String,minimumLabel:String? = nil)
        case time(String)
        case preview

        var key:String? {
            switch self {
            case let .toggle(key),let .choice(key,_),let .slider(key,_,_),let .time(key): return key
            case .preview: return nil
            }
        }
    }

    private struct Row {
        let title: String
        let control: Control
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
        Group(title:"气泡窗审批",symbol:"checkmark.shield",keywords:"批准 允许这一次 允许本轮 拒绝 左拒绝 右允许 左允许 右拒绝 左右 位置 红叉 绿对钩",rows:[
            Row("气泡窗审批按钮顺序",.choice("approvalButtonOrder",[("rejectLeft","左拒绝 · 右允许"),("allowLeft","左允许 · 右拒绝")]),detail:"只调整气泡中的按钮位置。红叉拒绝、绿对钩允许；审批需点击按钮，不能用键盘提交。"),
        ]),
        Group(title:"输入快捷键",symbol:"keyboard",keywords:"回车 Return Enter ⌃ Control Ctrl ⌘ Command ⇧ Shift ⌥ Option 发送 换行 快捷回复 插话 问卷",rows:[
            Row("发送与换行",.choice("sendShortcut",SendShortcut.options)),
        ]),
        Group(title:"任务气泡",symbol:"bubble.left.and.bubble.right",keywords:"任务气泡提醒 任务进展 通知 显示 开关",rows:[
            Row("显示任务气泡",.toggle("taskBubbles"),detail:"关闭后仍会显示审批、待回答的问题和错误提示。"),
            Row("任务过程消息",.toggle("progressBubbles"),requires:["taskBubbles"]),
            Row("最终回复",.toggle("resultBubbles"),requires:["taskBubbles"]),
            Row("在气泡中显示任务信息栏",.toggle("taskInfoBarEnabled"),keywords:"Git 仓库状态 本轮文件改动 状态栏 进度 工具调用",detail:"显示 Git 仓库状态和本轮文件改动。"),
            Row("思考与工具进展小气泡",.toggle("progressToastEnabled"),keywords:"自动显示进展小气泡 默认开启 2s 2秒 思考摘要 工具调用 短气泡 小窗口 顶部 进展 自动 弹出 开关",requires:["taskBubbles","progressBubbles"]),
        ]),
        Group(title:"工作区状态条",image:{GitIcons.git},keywords:"Git GitHub 分支 仓库 工作区 目录 文件修改 增删 状态 状态条 独立 小窗 常驻 隐藏工作区状态条",rows:[
            Row("显示工作区状态条",.toggle("gitWindowEnabled"),detail:"在桌宠旁常驻显示当前会话的目录、Git 状态和本轮文件改动。"),
        ]),
        Group(title:"显示哪些消息",symbol:"line.3.horizontal.decrease.circle",keywords:"显示思考过程 思考摘要 工具名称 操作 执行状态 短气泡 小窗口 顶部 进展 自动 弹出 开关",rows:[
            Row("互动台词",.toggle("interactionBubbles"),keywords:"通知 显示 开关"),
            Row("显示思考摘要",.toggle("showThinkingProgress")),
            Row("显示工具调用",.toggle("showToolProgress")),
            Row("隐藏工具执行失败提示",.toggle("hideToolFailures"),keywords:"工具失败 执行失败 命令失败 报错 错误提示 失败角标 过滤 隐藏 概览 组标题 小气泡",requires:["showToolProgress"],detail:"隐藏进展小气泡和概览标题中的单次工具失败。历史记录与整轮任务失败照常显示。"),
        ]),
        Group(title:"气泡卡片与任务概览",symbol:"rectangle.stack",keywords:"消息 历史 上一条 下一条 正在执行 最近 完成",rows:[
            Row("气泡卡片保留数量",.slider("bubbleCardLimit",suffix:"条")),
            Row("互动气泡显示任务概览",.toggle("showTaskOverview"),detail:"鼠标操作设为“显示任务进度、播放随机动画”时，台词下方显示任务列表。点击任务可在 Codex 中打开。"),
            Row("近期结束任务数量",.slider("recentTaskCount",suffix:"条"),requires:["showTaskOverview"],detail:"每个会话只显示最近一次任务。"),
        ]),
        Group(title:"停留时间",symbol:"timer",keywords:"气泡 自动关闭 手动关闭 秒 时长 悬停 预览 任务进展 ChatGPT 订阅 额度 重置 倒计时",detail:"审批、问题和错误提示需手动关闭。",rows:[
            Row("互动台词",.slider("interactionSeconds",suffix:"秒",minimumLabel:"手动关闭"),requires:["interactionBubbles"]),
            Row("任务过程消息",.slider("progressSeconds",suffix:"秒",minimumLabel:"手动关闭"),requires:["taskBubbles","progressBubbles"]),
            Row("最终回复",.slider("resultSeconds",suffix:"秒",minimumLabel:"手动关闭"),requires:["taskBubbles","resultBubbles"]),
            Row("额度信息",.slider("quotaSeconds",suffix:"秒",minimumLabel:"手动关闭")),
            Row("长回复自动延长阅读时间",.toggle("autoReadTime"),requires:["taskBubbles","resultBubbles"],detail:"最长 120 秒。"),
            Row("鼠标移入时暂停倒计时",.toggle("pauseOnHover")),
            Row("思考与工具进展小气泡",.slider("progressToastSeconds",suffix:"秒"),keywords:"进展小气泡停留时间 思考 工具调用 短气泡 小窗口 自动关闭 持续 时间 秒 时长 2s 2秒",requires:["taskBubbles","progressBubbles","progressToastEnabled"],detail:"内容更新后重新计时。"),
            Row("预览最终回复气泡",.preview),
        ]),
        Group(title:"声音",symbol:"speaker.wave.2",keywords:"声音",rows:[
            Row("播放音效",.toggle("soundEnabled")),
        ]),
        Group(title:"安静陪伴",symbol:"moon",keywords:"安静陪伴模式 启用专注时段 免打扰 时间 夜间 静音",detail:"按本机时间执行，可跨天；开始和结束时间相同表示全天。",rows:[
            Row("立即开启安静陪伴",.toggle("quietCompanion"),detail:"减少活动并停止自动移动，隐藏互动台词和进展气泡，关闭音效。最终回复和待处理通知照常显示。"),
            Row("定时开启安静陪伴",.toggle("quietSchedule"),detail:"手动开启后会一直保持安静，关闭后恢复定时安排。"),
            Row("开始时间",.time("quietStart"),requires:["quietSchedule"]),
            Row("结束时间",.time("quietEnd"),requires:["quietSchedule"]),
        ]),
        Group(title:"进展提醒",symbol:"bell.badge",keywords:"任务 执行 无新进度 90秒 5分钟 定时 等待 台词",rows:[
            Row("久无进展时提醒",.toggle("taskReminderEnabled"),requires:["taskBubbles","progressBubbles"],detail:"任务连续 90 秒没有新进展后，按下方间隔提醒。等待回答、批准或正在停止时不提醒。"),
            Row("提醒间隔",.slider("taskReminderMinutes",suffix:"分钟"),requires:["taskBubbles","progressBubbles","taskReminderEnabled"]),
        ]),
    ]

    private static let titlesByKey = Dictionary(uniqueKeysWithValues:groups.flatMap { group in
        group.rows.compactMap { row in row.control.key.map {($0,row.title)} }
    })

    // 旧版两个开关仍属于本页恢复范围。
    static var preferenceKeys:[String] {
        groups.flatMap {$0.rows.compactMap { $0.control.key }} + ["countAfterReveal","typingEffect"]
    }

    static var searchEntries:[SettingsSearchEntry] {
        groups.flatMap { group in
            group.rows.map { row in
                let titles = row.requires.map {titlesByKey[$0]!}
                let condition = titles.isEmpty ? "" : "开启"+titles.joined(separator:"、")+"后可调整"
                return SettingsSearchEntry(section:.messages,group:group.title,title:row.title,
                    keywords:row.keywords.isEmpty ? group.keywords : row.keywords,condition:condition)
            }
        }
    }

    static func render(form:SettingsForm,onPreview:@escaping (MessagePurpose) -> Void) {
        for group in groups {
            let rows = group.rows.map { row -> NSView in
                switch row.control {
                case .toggle(let key):
                    return form.toggle(row.title,key,detail:row.detail,requires:row.requires)
                case let .choice(key,options):
                    return form.choice(row.title,key,options,detail:row.detail,requires:row.requires)
                case let .slider(key,suffix,minimumLabel):
                    return form.slider(row.title,key,range:PetPreferences.ranges[key]!,suffix:suffix,
                                       detail:row.detail,requires:row.requires,minimumLabel:minimumLabel)
                case .time(let key):
                    let time = form.time(row.title,key,requires:row.requires)
                    return form.conditional(time,when:{prefs in row.requires.allSatisfy {prefs.bool($0)}})
                case .preview:
                    return form.row(row.title,control:ActionButton("预览…") {onPreview(.result)})
                }
            }
            form.group(group.title,rows,symbol:group.symbol,image:group.image?(),detail:group.detail)
        }
    }
}
