import AppKit

enum MessageSettingsPage {
    static let workspaceStatusGroupTitle = "工作区状态"

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
            let available:(PetPreferences) -> Bool = {prefs in requires.allSatisfy {prefs.bool($0)}}
            if !requires.isEmpty {_ = form.conditional(button,when:available)}
            form.observeValues { [weak button] prefs in
                guard let button else {return}
                let value = summary(prefs)
                if value != button.title {button.title = value; button.setAccessibilityValue(value)}
                if !available(prefs) {button.closeEditor()}
            }
            return button
        }
    }

    private enum Control {
        case toggle(String,Value? = nil)
        case choice(String,[(String,String)],width:CGFloat = 190)
        case slider(String,suffix:String,minimumLabel:String? = nil)
        case time(String)
        case gitStatusStyle
        case preview

        var key:String? {
            switch self {
            case let .toggle(key,_),let .choice(key,_,_),let .slider(key,_,_),let .time(key): return key
            case .gitStatusStyle:return GitStatusStyle.key
            case .preview: return nil
            }
        }
    }

    private struct Row {
        let title: String
        let control: Control
        var quickValue:Value? {
            switch control {
            case .toggle(_,let value):return value
            case .slider("quotaSeconds",let unit,_):return .number("quotaSeconds",unit:unit)
            default:return nil
            }
        }
        var quickRequires:[String] {
            if case .toggle(let key,_) = control {return requires+[key]}
            return requires
        }
        let keywords: String
        let requires: [String]
        let detail: String?
        let help: String?

        init(_ title:String,_ control:Control,keywords:String = "",requires:[String] = [],detail:String? = nil,help:String? = nil) {
            self.title = title
            self.control = control
            self.keywords = keywords
            self.requires = requires
            self.detail = detail
            self.help = help
        }
    }

    private struct Group {
        let title: String
        var topic:Topic? = nil
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
            Row("气泡窗审批按钮顺序",.choice("approvalButtonOrder",[("rejectLeft","左拒绝 · 右允许"),("allowLeft","左允许 · 右拒绝")]),detail:"只调整气泡中的按钮位置。红叉拒绝、绿对钩允许。"),
        ]),
        Group(title:"输入快捷键",topic:.input,symbol:"keyboard",keywords:"回车 Return Enter ⌃ Control Ctrl ⌘ Command ⇧ Shift ⌥ Option 发送 换行 快捷回复 插话 问卷",rows:[
            Row("发送与换行",.choice("sendShortcut",SendShortcut.options,width:260),keywords:"小键盘 ⌤ Alt",help:"""
                按键说明

                ⌘\tCommand
                ⌥\tOption / Alt
                ⇧\tShift
                ⌃\tControl
                ↩\tReturn\t（主键区回车）
                ⌤\tEnter\t（全键键盘的小键盘区回车）

                发送和换行时，⌤ Enter 与 ↩ Return 作用相同

                如外接 PC 键盘：⊞ Win 徽标键 = ⌘，Alt = ⌥，Ctrl = ⌃
                """),
        ]),
        Group(title:"任务气泡",topic:.content,symbol:"bubble.left.and.bubble.right",keywords:"任务气泡提醒 任务进展 通知 显示 开关",rows:[
            Row("显示任务气泡",.toggle("taskBubbles"),detail:"关闭后仍会显示审批、待回答的问题和错误提示。"),
            Row("任务过程消息",.toggle("progressBubbles",.number("progressSeconds",unit:"秒")),requires:["taskBubbles"]),
            Row("最终回复",.toggle("resultBubbles",.number("resultSeconds",unit:"秒")),requires:["taskBubbles"]),
            Row("思考与工具进展小气泡",.toggle("progressToastEnabled",.number("progressToastSeconds",unit:"秒")),keywords:"自动显示进展小气泡 默认开启 2s 2秒 思考摘要 工具调用 短气泡 小窗口 顶部 进展 自动 弹出 开关",requires:["taskBubbles","progressBubbles"]),
        ]),
        Group(title:workspaceStatusGroupTitle,image:{GitIcons.git},keywords:"Git GitHub 分支 仓库 工作区 目录 文件修改 增删 状态 状态条 独立 小窗 常驻 隐藏工作区状态条",rows:[
            Row("Git 状态显示风格",.gitStatusStyle,keywords:GitStatusStyle.options.map(\.1).joined(separator:" ")+" P10k PL10K VS Code VSCode Git CLI Git 状态图例 远端仓库图标 GitLab Gitee Gitea Forgejo Codeberg Hugging Face 冲突 已暂存 未暂存 未跟踪 贮藏 Stash 领先 落后 上游 推送目标 Push Remote"),
            Row("显示任务信息栏",.toggle("taskInfoBarEnabled"),keywords:"在气泡中显示任务信息栏 Git 状态 GitHub 分支 仓库状态 任务概览 本轮文件改动 文件增删 状态栏 进度 工具调用",detail:"在任务气泡和任务概览中显示 Git 状态与本轮文件改动。"),
            Row("显示工作区状态条",.toggle("gitWindowEnabled"),detail:"在桌宠旁常驻显示当前会话的目录、Git 状态与本轮文件改动。"),
        ]),
        Group(title:"显示哪些消息",topic:.content,symbol:"line.3.horizontal.decrease.circle",keywords:"显示思考过程 思考摘要 工具名称 操作 执行状态 短气泡 小窗口 顶部 进展 自动 弹出 开关",rows:[
            Row("互动台词",.toggle("interactionBubbles",.number("interactionSeconds",unit:"秒")),keywords:"通知 显示 开关"),
            Row("显示思考摘要",.toggle("showThinkingProgress"),keywords:"正在思考 思考图标 灯泡 lightbulb.max 公开摘要"),
            Row("显示工具调用",.toggle("showToolProgress")),
            Row("隐藏工具执行失败提示",.toggle("hideToolFailures"),keywords:"工具失败 执行失败 命令失败 报错 错误提示 失败角标 过滤 隐藏 概览 组标题 小气泡",requires:["showToolProgress"],detail:"隐藏进展小气泡和概览标题中的单次工具失败。历史记录与整轮任务失败照常显示。"),
        ]),
        Group(title:"气泡卡片与任务概览",topic:.content,symbol:"rectangle.stack",keywords:"消息 历史 上一条 下一条 正在执行 最近 完成",rows:[
            Row("气泡卡片保留数量",.slider("bubbleCardLimit",suffix:"条")),
            Row("互动气泡显示任务概览",.toggle("showTaskOverview"),detail:"鼠标操作设为“显示任务进度、播放随机动画”时，台词下方显示任务列表。点击任务可在 Codex 中打开。"),
            Row("近期结束任务数量",.slider("recentTaskCount",suffix:"条"),requires:["showTaskOverview"],detail:"每个会话只显示最近一次任务。"),
        ]),
        Group(title:"停留时间",topic:.reading,symbol:"timer",keywords:"气泡 自动关闭 手动关闭 秒 时长 悬停 预览 任务进展 ChatGPT 订阅 额度 重置 倒计时",detail:"审批、问题和错误提示需手动关闭。",rows:[
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
        Group(title:"Token 用量",topic:.reading,symbol:"chart.bar",rows:[
            Row("Token 计数格式",.choice(TokenCountFormat.key,TokenCountFormat.options),keywords:"千 百万 十亿 K M B 万 亿 缩写 小数 千分位",detail:"额度、任务气泡和历史共用此格式。缩写保留两位小数。"),
        ]),
        Group(title:"安静陪伴",topic:.reading,symbol:"moon",keywords:"安静陪伴模式 启用专注时段 免打扰 时间 夜间 静音",detail:"按本机时间执行，可跨天；开始和结束时间相同表示全天。",rows:[
            Row("立即开启安静陪伴",.toggle("quietCompanion"),detail:"减少活动并停止自动移动，隐藏互动台词和进展气泡，关闭音效。最终回复和待处理通知照常显示。"),
            Row("定时开启安静陪伴",.toggle("quietSchedule",.hours),detail:"手动开启后会一直保持安静，关闭后恢复定时安排。"),
            Row("开始时间",.time("quietStart"),requires:["quietSchedule"]),
            Row("结束时间",.time("quietEnd"),requires:["quietSchedule"]),
        ]),
        Group(title:"进展提醒",topic:.reading,symbol:"bell.badge",keywords:"任务 执行 无新进度 90秒 5分钟 定时 等待 台词",rows:[
            Row("久无进展时提醒",.toggle("taskReminderEnabled",.number("taskReminderMinutes",unit:"分钟")),requires:["taskBubbles","progressBubbles"],detail:"任务连续 90 秒没有新进展后，按下方间隔提醒。等待回答、批准或正在停止时不提醒。"),
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

    // 搜索到已收起的项目时，定位到第一个尚未开启的前置开关。
    static func prerequisite(for entry:SettingsSearchEntry,preferences:PetPreferences) -> SettingsSearchEntry? {
        guard let group = groups.first(where:{$0.title == entry.group}) else {return nil}
        for row in group.rows {
            let keys:[String]
            if row.title == entry.title {keys = row.requires}
            else if row.quickValue?.title(for:row.title) == entry.title {keys = row.quickRequires}
            else {continue}
            guard let key = keys.first(where:{!preferences.bool($0)}) else {return nil}
            for parent in groups {
                if let toggle = parent.rows.first(where:{$0.control.key == key}) {
                    return SettingsSearchEntry(section:.messages,group:parent.title,title:toggle.title)
                }
            }
        }
        return nil
    }

    static var searchEntries:[SettingsSearchEntry] {
        func condition(_ requires:[String]) -> String {
            requires.isEmpty ? "" : "开启"+requires.map {titlesByKey[$0]!}.joined(separator:"、")+"后可调整"
        }
        return groups.flatMap { group in
            group.rows.flatMap { row -> [SettingsSearchEntry] in
                let keywords = group.keywords+" "+row.keywords
                let entry = SettingsSearchEntry(section:.messages,group:group.title,title:row.title,keywords:keywords,condition:condition(row.requires))
                guard let value = row.quickValue,let topic = group.topic else {return [entry]}
                let title = value.title(for:row.title)
                return [entry,SettingsSearchEntry(section:.messages,group:group.title,title:title,keywords:keywords+" 时间 时长 调整",
                    condition:condition(row.quickRequires),detail:.messages(topic),anchorTitle:title)]
            }
        }
    }

    static func render(form:SettingsForm,topic:Topic?,onPreview:@escaping (MessagePurpose) -> Void) {
        for group in groups where topic == nil || group.topic == topic {
            // 主页按原顺序展示所有控件；子页已在开关旁提供的值只显示一次。
            let inlineKeys = Set(group.rows.flatMap { row -> [String] in
                guard topic != nil,case .toggle(_,let value) = row.control else {return []}
                return value?.keys ?? []
            })
            let rows = group.rows.compactMap { row -> NSView? in
                if let key = row.control.key,inlineKeys.contains(key) {return nil}
                switch row.control {
                case let .toggle(key,adjustment):
                    let button = topic == nil ? nil : adjustment?.button(for:row.title,requires:row.quickRequires,form:form)
                    return form.toggle(row.title,key,detail:row.detail,requires:row.requires,accessory:button)
                case let .choice(key,options,width):
                    return form.choice(row.title,key,options,width:width,detail:row.detail,help:row.help,requires:row.requires)
                case let .slider(key,suffix,minimumLabel):
                    if topic != nil,let value = row.quickValue {
                        return form.row(value.title(for:row.title),control:value.button(for:row.title,requires:row.requires,form:form))
                    }
                    return form.slider(row.title,key,range:PetPreferences.ranges[key]!,suffix:suffix,
                                       detail:row.detail,requires:row.requires,minimumLabel:minimumLabel)
                case .time(let key):
                    return form.time(row.title,key,requires:row.requires)
                case .gitStatusStyle:
                    return form.segmented(row.title,GitStatusStyle.key,GitStatusStyle.options,footer:gitStatusLegend(form:form))
                case .preview:
                    return form.row(row.title,control:ActionButton("预览…") {onPreview(.result)})
                }
            }
            form.group(group.title,rows,symbol:group.symbol,image:group.image?(),detail:group.detail)
        }
    }

    private static func gitStatusLegend(form:SettingsForm) -> NSView {
        let font = GitStatusText.settingsLegendFont
        let heading = NSTextField(labelWithString:"图例：")
        heading.font = .systemFont(ofSize:font.pointSize,weight:.semibold)
        let repositories = NSTextField(labelWithAttributedString:GitStatusText.settingsRepositories)
        let infoTitle = "更多远端仓库图标"
        let symbol = NSImage(systemSymbolName:"info.circle",accessibilityDescription:infoTitle)!
        let infoText = NSMutableAttributedString(attributedString:InlineStatusLayout.imageAttachment(symbol,description:infoTitle,font:font,side:font.pointSize,color:.secondaryLabelColor))
        infoText.addAttribute(.font,value:font,range:NSRange(location:0,length:infoText.length))
        let info = NSTextField(labelWithAttributedString:infoText)
        info.setAccessibilityElement(true)
        info.setAccessibilityLabel(infoTitle)
        info.setHoverHelp(GitStatusText.additionalRepositoryLegend)
        let clean = NSTextField(labelWithString:"")
        let repositoryRow = NSStackView(views:[repositories,info,clean])
        repositoryRow.orientation = .horizontal
        repositoryRow.alignment = .firstBaseline
        repositoryRow.spacing = 4
        repositoryRow.setCustomSpacing(20,after:info)

        let indicators = NSTextField(wrappingLabelWithString:"")
        indicators.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let legend = NSStackView(views:[heading,repositoryRow,indicators])
        legend.orientation = .vertical
        legend.alignment = .leading
        legend.spacing = 2
        indicators.widthAnchor.constraint(equalTo:legend.widthAnchor).isActive = true
        form.observeValues { [weak clean,weak indicators] preferences in
            let content = GitStatusText.settingsLegend(preferences.gitStatusStyle)
            if let clean,!clean.attributedStringValue.isEqual(to:content.clean) {clean.attributedStringValue = content.clean}
            if let indicators,!indicators.attributedStringValue.isEqual(to:content.indicators) {indicators.attributedStringValue = content.indicators}
        }
        return legend
    }
}
