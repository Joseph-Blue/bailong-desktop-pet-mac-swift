import AppKit

enum GitStatusStyle:String,CaseIterable {
    case bashGitPrompt, powerlevel10k, gitCLI

    static let key = "gitStatusStyle"
    static let defaultStyle = GitStatusStyle.bashGitPrompt
    static var options:[(String,String)] {
        allCases.map {($0.rawValue,$0.title)}
    }
    private var title:String {
        switch self {
        case .bashGitPrompt:return "bash-git-prompt 符号风格"
        case .powerlevel10k:return "Powerlevel10k 符号风格"
        case .gitCLI:return "缩写字母风格"
        }
    }
}

enum GitStatusText {
    private struct Indicator {
        let symbol:String, promptSymbol:String, mnemonic:String, label:String
        let color:NSColor

        init(_ symbol:String,_ promptSymbol:String,_ mnemonic:String,_ label:String,_ color:NSColor) {
            self.symbol = symbol; self.promptSymbol = promptSymbol
            self.mnemonic = mnemonic; self.label = label; self.color = color
        }
        func marker(_ style:GitStatusStyle) -> String {
            switch style {
            case .powerlevel10k:return symbol
            case .bashGitPrompt:return promptSymbol
            case .gitCLI:return mnemonic
            }
        }
    }
    private static let groups:[(group:GitWorkspaceStatus.Group,indicator:Indicator)] = [
        (.conflicted,Indicator("~","✖","C",GitWorkspaceStatus.Group.conflicted.rawValue,StatusTextColor.red)),
        (.staged,Indicator("+","●","S",GitWorkspaceStatus.Group.staged.rawValue,StatusTextColor.green)),
        (.unstaged,Indicator("!","✚","M",GitWorkspaceStatus.Group.unstaged.rawValue,StatusTextColor.orange)),
        (.untracked,Indicator("?","…","?",GitWorkspaceStatus.Group.untracked.rawValue,.labelColor))
    ]
    private static let clean = Indicator("✓","✔","✓","工作区干净",StatusTextColor.green)
    private static let stash = Indicator("*","⚑","SH",GitWorkspaceStatus.stashLabel,StatusTextColor.purple)
    private static let upstreamIndicators:[(indicator:Indicator,count:KeyPath<GitWorkspaceStatus,Int?>)] = [
        (Indicator("⇣","↓","↓","落后",StatusTextColor.blue),\.behind),
        (Indicator("⇡","↑","↑","领先",StatusTextColor.blue),\.ahead)
    ]

    private static let compactLegends = Dictionary(uniqueKeysWithValues:GitStatusStyle.allCases.map {style in
        let font = NSFont.systemFont(ofSize:11)
        let text = NSMutableAttributedString()
        for item in groups.map(\.indicator) + [stash] + upstreamIndicators.map(\.indicator) {
            if text.length > 0 {text.append(NSAttributedString(string:" ",attributes:[.font:font]))}
            text.append(marked(item,label:item.label,font:font,style:style,separator:""))
        }
        return (style,NSAttributedString(attributedString:text))
    })
    static func legend(_ style:GitStatusStyle) -> NSAttributedString {compactLegends[style]!}

    private static let settingsLegends = Dictionary(uniqueKeysWithValues:GitStatusStyle.allCases.map {style in
        let font = NSFont.systemFont(ofSize:11)
        let base:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        func repository(_ kind:GitWorkspaceStatus.RepositoryKind) -> NSAttributedString {
            let title:String
            switch kind {
            case .generic:title = "通用 Git 仓库"
            case .github:title = "GitHub 远端仓库"
            case .remote:title = "其他远端仓库"
            }
            let icon = GitIcons.repository(kind)
            let text = NSMutableAttributedString(attributedString:InlineStatusLayout.imageAttachment(icon,description:title,font:font,side:12,color:.labelColor))
            text.append(NSAttributedString(string:" "+title,attributes:base))
            return text
        }
        let repositories = GitWorkspaceStatus.RepositoryKind.allCases.map(repository) + [marked(clean,label:clean.label,font:font,style:style)]
        let fileIndicators = (groups.map(\.indicator) + [stash]).map {marked($0,label:$0.label,font:font,style:style)}
        let upstream = upstreamIndicators.map {marked($0.indicator,label:$0.indicator.label+"上游",font:font,style:style)}
        let heading = NSFont.systemFont(ofSize:font.pointSize,weight:.semibold)
        let text = NSMutableAttributedString(string:"图例：\n",attributes:[.font:heading,.foregroundColor:NSColor.labelColor])
        text.append(InlineStatusLayout.tabbedRows([repositories,[]],font:font,columnGap:20,paragraphSpacing:2))
        text.append(InlineStatusLayout.tabbedRows([fileIndicators+upstream],font:font,columnGap:16))
        return (style,NSAttributedString(attributedString:text))
    })
    static func settingsLegend(_ style:GitStatusStyle) -> NSAttributedString {settingsLegends[style]!}

    static func compact(_ status:GitWorkspaceStatus,font:NSFont,style:GitStatusStyle) -> NSAttributedString {
        let text = NSMutableAttributedString(), counts = status.counts
        func append(_ item:Indicator,count:Int? = nil) {
            if text.length > 0 {text.append(NSAttributedString(string:" ",attributes:[.font:font]))}
            text.append(markerText(item.marker(style),font:font,color:item.color))
            if let count {text.append(NSAttributedString(string:String(count),attributes:[.font:font,.foregroundColor:item.color]))}
        }
        for (group,item) in groups {
            if let count = counts[group],count > 0 {append(item,count:count)}
        }
        if status.clean {append(clean)}
        if status.stashes > 0 {append(stash,count:status.stashes)}
        for (item,countPath) in upstreamIndicators {
            if let count = status[keyPath:countPath],count > 0 {append(item,count:count)}
        }
        return text
    }
    static func tracking(_ status:GitWorkspaceStatus,font:NSFont,style:GitStatusStyle? = nil) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        guard let upstream = status.upstream else {return NSAttributedString(string:"未设置",attributes:attributes)}
        let text = NSMutableAttributedString(string:upstream,attributes:attributes)
        let counts = upstreamIndicators.compactMap {direction in
            status[keyPath:direction.count].map {(direction.indicator,$0)}
        }
        guard counts.count == upstreamIndicators.count else {
            let state = status.initial ? "尚无本地提交" : "上游引用缺失"
            text.append(NSAttributedString(string:" · "+state,attributes:attributes))
            return text
        }
        for (item,count) in counts {
            text.append(NSAttributedString(string:" · ",attributes:attributes))
            let label = item.label+" \(count)"
            if let style {
                let countFont = count > 0 ? NSFont.systemFont(ofSize:font.pointSize,weight:.semibold) : font
                text.append(marked(item,label:label,font:countFont,style:style))
            } else {
                text.append(NSAttributedString(string:label,attributes:attributes))
            }
        }
        text.append(NSAttributedString(string:"（本机记录）",attributes:attributes))
        return text
    }
    static func stateDetails(_ status:GitWorkspaceStatus,font:NSFont,style:GitStatusStyle) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        let labels = [status.detachedSummary,status.initial ? "尚无提交记录" : nil,status.operation?.detailTitle]
        let text = NSMutableAttributedString(string:labels.compactMap {$0}.joined(separator:" · "),attributes:attributes)
        if let stashSummary = status.stashSummary {
            if text.length > 0 {text.append(NSAttributedString(string:" · ",attributes:attributes))}
            text.append(marked(stash,label:stashSummary,font:font,style:style))
        }
        return text
    }
    static func groupDetail(_ group:GitWorkspaceStatus.Group,count:Int,font:NSFont,style:GitStatusStyle) -> NSAttributedString {
        let item = groups.first {$0.group == group}!.indicator
        return marked(item,label:item.label+" · \(count)",font:font,style:style)
    }
    private static func marked(_ item:Indicator,label:String,font:NSFont,style:GitStatusStyle,separator:String = " ") -> NSAttributedString {
        let markerFont = style == .gitCLI ? NSFont.monospacedSystemFont(ofSize:font.pointSize,weight:.semibold) : font
        let text = NSMutableAttributedString(attributedString:markerText(item.marker(style),font:markerFont,color:item.color))
        text.append(NSAttributedString(string:separator+label,attributes:[.font:font,.foregroundColor:item.color]))
        return text
    }
    private static func markerText(_ marker:String,font:NSFont,color:NSColor) -> NSAttributedString {
        if marker.first?.isLetter == true {
            return NSAttributedString(string:marker,attributes:[.font:font,.foregroundColor:color])
        }
        return InlineStatusLayout.centeredSymbol(marker,font:font,color:color)
    }
}
