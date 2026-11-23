import AppKit

enum MessageSettingsPage {
    static let workspaceStatusGroupTitle = L10n.text(.settings,"messages.workspaceStatusGroupTitle")

    enum Topic:String,CaseIterable {
        case content, reading, input
        var title:String {
            switch self {
            case .content:return L10n.text(.settings,"messages.content")
            case .reading:return L10n.text(.settings,"messages.content.2")
            case .input:return L10n.text(.settings,"messages.content.3")
            }
        }
    }

    private enum Value {
        case number(String,unit:String), hours
        var keys:[String] {
            switch self {case .number(let key,_):return [key]; case .hours:return ["quietStart","quietEnd"]}
        }
        func title(for row:String) -> String {
            switch self {
            case .number(let key,_):return key == "taskReminderMinutes" ? L10n.text(.settings,"messages.number.2") : L10n.format(.settings,"messageSettingsPage.key.text",String(describing:row))
            case .hours:return L10n.text(.settings,"messages.hours")
            }
        }
        func summary(_ prefs:PetPreferences) -> String {
            switch self {
            case let .number(key,unit):
                let value = prefs.number(key)
                return value == 0 ? L10n.text(.settings,"messages.summary.text") : value.formatted()+" "+unit
            case .hours:
                func time(_ key:String) -> String {
                    let minute = Int(prefs.number(key))
                    return String(format:"%02d:%02d",minute/60,minute%60)
                }
                let start = time("quietStart"), end = time("quietEnd")
                return start+"–"+end+(start == end ? L10n.text(.settings,"messages.time.text") : "")
            }
        }
        func button(for row:String,requires:[String],form:SettingsForm) -> SettingsValueButton {
            let title = title(for:row)
            let button = SettingsValueButton(label:title,preferences:form.preferences) { editor in
                switch self {
                case let .number(key,unit):
                    let range = PetPreferences.ranges[key]!
                    let slider = editor.slider(title,key,range:range,suffix:unit,minimumLabel:range.lowerBound == 0 ? L10n.text(.settings,"messages.summary.text") : nil)
                    editor.fill(slider,in:editor.content)
                case .hours:
                    editor.fill(editor.time(L10n.text(.settings,"messages.button.text"),"quietStart"),in:editor.content)
                    editor.fill(editor.time(L10n.text(.settings,"messages.button.text.2"),"quietEnd"),in:editor.content)
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
        Group(title:L10n.text(.settings,"messages.group.title"),symbol:"book",keywords:L10n.text(.settings,"messages.group.keywords"),rows:[
            Row(L10n.text(.settings,"messages.recordHistory.title"),.toggle("recordHistory"),detail:L10n.text(.settings,"messages.recordHistory.detail")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.2"),topic:.input,symbol:"checkmark.shield",keywords:L10n.text(.settings,"messages.group.keywords.2"),rows:[
            Row(L10n.text(.settings,"messages.approvalButtonOrder.title"),.choice("approvalButtonOrder",[("rejectLeft",L10n.text(.settings,"messages.approvalButtonOrder.option.rejectLeft")),("allowLeft",L10n.text(.settings,"messages.approvalButtonOrder.option.allowLeft"))]),detail:L10n.text(.settings,"messages.approvalButtonOrder.detail")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.3"),topic:.input,symbol:"keyboard",keywords:L10n.text(.settings,"messages.group.keywords.3"),rows:[
            Row(L10n.text(.settings,"messages.sendShortcut.title"),.choice("sendShortcut",SendShortcut.options,width:260),keywords:L10n.text(.settings,"messages.sendShortcut.keywords"),help:L10n.text(.settings,"messages.sendShortcut.help")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.4"),topic:.content,symbol:"bubble.left.and.bubble.right",keywords:L10n.text(.settings,"messages.group.keywords.4"),rows:[
            Row(L10n.text(.settings,"messages.taskBubbles.title"),.toggle("taskBubbles"),detail:L10n.text(.settings,"messages.taskBubbles.detail")),
            Row(L10n.text(.settings,"messages.progressBubbles.title"),.toggle("progressBubbles",.number("progressSeconds",unit:L10n.text(.settings,"activity.leisureInterval.suffix"))),requires:["taskBubbles"]),
            Row(L10n.text(.settings,"messages.resultBubbles.title"),.toggle("resultBubbles",.number("resultSeconds",unit:L10n.text(.settings,"activity.leisureInterval.suffix"))),requires:["taskBubbles"]),
            Row(L10n.text(.settings,"messages.progressToastEnabled.title"),.toggle("progressToastEnabled",.number("progressToastSeconds",unit:L10n.text(.settings,"activity.leisureInterval.suffix"))),keywords:L10n.text(.settings,"messages.progressToastEnabled.keywords"),requires:["taskBubbles","progressBubbles"]),
        ]),
        Group(title:workspaceStatusGroupTitle,image:{GitIcons.git},keywords:L10n.text(.settings,"messages.group.keywords.5"),rows:[
            Row(L10n.text(.settings,"messages.group.text"),.gitStatusStyle,keywords:GitStatusStyle.options.map(\.1).joined(separator:" ")+L10n.text(.settings,"messageSettingsPage.labels.text")),
            Row(L10n.text(.settings,"messages.gitTerminologyInEnglish.title"),.toggle(GitTerminology.key),keywords:L10n.text(.settings,"messages.gitTerminologyInEnglish.keywords")),
            Row(L10n.text(.settings,"messages.taskInfoBarEnabled.title"),.toggle("taskInfoBarEnabled"),keywords:L10n.text(.settings,"messages.taskInfoBarEnabled.keywords"),detail:L10n.text(.settings,"messages.taskInfoBarEnabled.detail")),
            Row(L10n.text(.settings,"messages.gitWindowEnabled.title"),.toggle("gitWindowEnabled"),detail:L10n.text(.settings,"messages.gitWindowEnabled.detail")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.5"),topic:.content,symbol:"line.3.horizontal.decrease.circle",keywords:L10n.text(.settings,"messages.group.keywords.6"),rows:[
            Row(L10n.text(.settings,"identity.restore.text.5"),.toggle("interactionBubbles",.number("interactionSeconds",unit:L10n.text(.settings,"activity.leisureInterval.suffix"))),keywords:L10n.text(.settings,"messages.interactionBubbles.keywords")),
            Row(L10n.text(.settings,"messages.showThinkingProgress.title"),.toggle("showThinkingProgress"),keywords:L10n.text(.settings,"messages.showThinkingProgress.keywords")),
            Row(L10n.text(.settings,"messages.showToolProgress.title"),.toggle("showToolProgress")),
            Row(L10n.text(.settings,"messages.hideToolFailures.title"),.toggle("hideToolFailures"),keywords:L10n.text(.settings,"messages.hideToolFailures.keywords"),requires:["showToolProgress"],detail:L10n.text(.settings,"messages.hideToolFailures.detail")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.6"),topic:.content,symbol:"rectangle.stack",keywords:L10n.text(.settings,"messages.group.keywords.7"),rows:[
            Row(L10n.text(.settings,"messages.bubbleCardLimit.title"),.slider("bubbleCardLimit",suffix:L10n.text(.settings,"messages.bubbleCardLimit.suffix"))),
            Row(L10n.text(.settings,"messages.showTaskOverview.title"),.toggle("showTaskOverview"),detail:L10n.text(.settings,"messages.showTaskOverview.detail")),
            Row(L10n.text(.settings,"messages.recentTaskCount.title"),.slider("recentTaskCount",suffix:L10n.text(.settings,"messages.bubbleCardLimit.suffix")),requires:["showTaskOverview"],detail:L10n.text(.settings,"messages.recentTaskCount.detail")),
        ]),
        Group(title:L10n.text(.settings,"messages.title.text"),topic:.reading,symbol:"timer",keywords:L10n.text(.settings,"messages.group.keywords.8"),detail:L10n.text(.settings,"messages.group.text.3"),rows:[
            Row(L10n.text(.settings,"identity.restore.text.5"),.slider("interactionSeconds",suffix:L10n.text(.settings,"activity.leisureInterval.suffix"),minimumLabel:L10n.text(.settings,"messages.summary.text")),requires:["interactionBubbles"]),
            Row(L10n.text(.settings,"messages.progressBubbles.title"),.slider("progressSeconds",suffix:L10n.text(.settings,"activity.leisureInterval.suffix"),minimumLabel:L10n.text(.settings,"messages.summary.text")),requires:["taskBubbles","progressBubbles"]),
            Row(L10n.text(.settings,"messages.resultBubbles.title"),.slider("resultSeconds",suffix:L10n.text(.settings,"activity.leisureInterval.suffix"),minimumLabel:L10n.text(.settings,"messages.summary.text")),requires:["taskBubbles","resultBubbles"]),
            Row(L10n.text(.settings,"messages.quotaSeconds.title"),.slider("quotaSeconds",suffix:L10n.text(.settings,"activity.leisureInterval.suffix"),minimumLabel:L10n.text(.settings,"messages.summary.text"))),
            Row(L10n.text(.settings,"messages.autoReadTime.title"),.toggle("autoReadTime"),requires:["taskBubbles","resultBubbles"],detail:L10n.text(.settings,"messages.autoReadTime.detail")),
            Row(L10n.text(.settings,"messages.pauseOnHover.title"),.toggle("pauseOnHover")),
            Row(L10n.text(.settings,"messages.progressToastEnabled.title"),.slider("progressToastSeconds",suffix:L10n.text(.settings,"activity.leisureInterval.suffix")),keywords:L10n.text(.settings,"messages.progressToastSeconds.keywords"),requires:["taskBubbles","progressBubbles","progressToastEnabled"],detail:L10n.text(.settings,"messages.progressToastSeconds.detail")),
            Row(L10n.text(.settings,"messages.group.text.4"),.preview),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.7"),symbol:"speaker.wave.2",keywords:L10n.text(.settings,"messages.group.title.7"),rows:[
            Row(L10n.text(.settings,"messages.soundEnabled.title"),.toggle("soundEnabled")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.8"),topic:.reading,symbol:"chart.bar",rows:[
            Row(L10n.text(.settings,"messages.group.text.5"),.choice(TokenCountFormat.key,TokenCountFormat.options),keywords:L10n.text(.settings,"messages.group.keywords.9"),detail:L10n.text(.settings,"messages.group.text.6")),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.9"),topic:.reading,symbol:"moon",keywords:L10n.text(.settings,"messages.group.keywords.10"),detail:L10n.text(.settings,"messages.group.text.7"),rows:[
            Row(L10n.text(.settings,"messages.quietCompanion.title"),.toggle("quietCompanion"),detail:L10n.text(.settings,"messages.quietCompanion.detail")),
            Row(L10n.text(.settings,"messages.quietSchedule.title"),.toggle("quietSchedule",.hours),detail:L10n.text(.settings,"messages.quietSchedule.detail")),
            Row(L10n.text(.settings,"messages.button.text"),.time("quietStart"),requires:["quietSchedule"]),
            Row(L10n.text(.settings,"messages.button.text.2"),.time("quietEnd"),requires:["quietSchedule"]),
        ]),
        Group(title:L10n.text(.settings,"messages.group.title.10"),topic:.reading,symbol:"bell.badge",keywords:L10n.text(.settings,"messages.group.keywords.11"),rows:[
            Row(L10n.text(.settings,"messages.taskReminderEnabled.title"),.toggle("taskReminderEnabled",.number("taskReminderMinutes",unit:L10n.text(.settings,"messages.taskReminderEnabled.title.2"))),requires:["taskBubbles","progressBubbles"],detail:L10n.text(.settings,"messages.taskReminderEnabled.detail")),
            Row(L10n.text(.settings,"messages.number.2"),.slider("taskReminderMinutes",suffix:L10n.text(.settings,"messages.taskReminderEnabled.title.2")),requires:["taskBubbles","progressBubbles","taskReminderEnabled"]),
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
            requires.isEmpty ? "" : L10n.text(.settings,"messages.condition.text")+requires.map {titlesByKey[$0]!}.joined(separator:"、")+L10n.text(.settings,"messages.condition.text.2")
        }
        return groups.flatMap { group in
            group.rows.flatMap { row -> [SettingsSearchEntry] in
                let keywords = group.keywords+" "+row.keywords
                let entry = SettingsSearchEntry(section:.messages,group:group.title,title:row.title,keywords:keywords,condition:condition(row.requires))
                guard let value = row.quickValue,let topic = group.topic else {return [entry]}
                let title = value.title(for:row.title)
                return [entry,SettingsSearchEntry(section:.messages,group:group.title,title:title,keywords:keywords+L10n.text(.settings,"messages.condition.text.3"),
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
                    return form.row(row.title,control:ActionButton(L10n.text(.settings,"messages.render.button")) {onPreview(.result)})
                }
            }
            form.group(group.title,rows,symbol:group.symbol,image:group.image?(),detail:group.detail)
        }
    }

    private static func gitStatusLegend(form:SettingsForm) -> NSView {
        let font = GitStatusText.settingsLegendFont
        let heading = NSTextField(labelWithString:L10n.text(.settings,"messageSettingsPage.heading.labelWithString"))
        heading.font = .systemFont(ofSize:font.pointSize,weight:.semibold)
        let repositories = NSTextField(labelWithString:"")
        let symbol = NSImage(systemSymbolName:"info.circle",accessibilityDescription:nil)!
        let info = NSTextField(labelWithString:"")
        info.setAccessibilityElement(true)
        let clean = NSTextField(labelWithString:"")
        let repositoryRow = NSStackView(views:[repositories,info,clean])
        repositoryRow.orientation = .horizontal
        repositoryRow.alignment = .firstBaseline
        repositoryRow.spacing = 4
        repositoryRow.setCustomSpacing(20,after:info)

        let indicators = NSTextField(wrappingLabelWithString:"")
        indicators.isSelectable = false
        indicators.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let legend = NSStackView(views:[heading,repositoryRow,indicators])
        legend.orientation = .vertical
        legend.alignment = .leading
        legend.spacing = 2
        indicators.widthAnchor.constraint(equalTo:legend.widthAnchor).isActive = true
        var previousTerms:GitTerminology?
        form.observeValues { [weak clean,weak indicators,weak repositories,weak info] preferences in
            let terms = preferences.gitTerminology
            if previousTerms != terms {
                previousTerms = terms
                repositories?.attributedStringValue = GitStatusText.settingsRepositories(terms)
                let infoTitle = terms.text("gitStatusText.rows.text")
                let infoText = NSMutableAttributedString(attributedString:InlineStatusLayout.imageAttachment(symbol,description:infoTitle,font:font,side:font.pointSize,color:.secondaryLabelColor))
                infoText.addAttribute(.font,value:font,range:NSRange(location:0,length:infoText.length))
                info?.attributedStringValue = infoText
                info?.setAccessibilityLabel(infoTitle)
                info?.setHoverHelp(GitStatusText.additionalRepositoryLegend(terms))
            }
            let content = GitStatusText.settingsLegend(preferences.gitStatusStyle,terms:terms)
            if let clean,!clean.attributedStringValue.isEqual(to:content.clean) {clean.attributedStringValue = content.clean}
            if let indicators,!indicators.attributedStringValue.isEqual(to:content.indicators) {indicators.attributedStringValue = content.indicators}
        }
        return legend
    }
}
