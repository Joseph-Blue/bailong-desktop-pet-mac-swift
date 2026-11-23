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
        case .bashGitPrompt:return L10n.text(.workspace,"gitStatusText.bashGitPrompt")
        case .powerlevel10k:return L10n.text(.workspace,"gitStatusText.powerlevel10k")
        case .gitCLI:return L10n.text(.workspace,"gitStatusText.gitCLI")
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
        (.conflicted,Indicator("~","✖","C",GitWorkspaceStatus.Group.conflicted.title,StatusTextColor.red)),
        (.staged,Indicator("+","●","S",GitWorkspaceStatus.Group.staged.title,StatusTextColor.green)),
        (.unstaged,Indicator("!","✚","M",GitWorkspaceStatus.Group.unstaged.title,StatusTextColor.orange)),
        (.untracked,Indicator("?","…","?",GitWorkspaceStatus.Group.untracked.title,.labelColor))
    ]
    private static let clean = Indicator("✓","✔","✓",L10n.text(.workspace,"gitStatusText.clean"),StatusTextColor.green)
    private static let stash = Indicator("*","⚑","SH",GitWorkspaceStatus.stashLabel,StatusTextColor.purple)
    private static let upstreamIndicators:[(indicator:Indicator,count:KeyPath<GitWorkspaceStatus,Int?>)] = [
        (Indicator("⇣","↓","↓",L10n.text(.workspace,"gitStatusText.upstreamIndicators.text"),StatusTextColor.blue),\.behind),
        (Indicator("⇡","↑","↑",L10n.text(.workspace,"gitStatusText.upstreamIndicators.text.2"),StatusTextColor.blue),\.ahead)
    ]
    private static let pushIndicators:[(indicator:Indicator,count:KeyPath<GitWorkspaceStatus.PushTarget,Int?>)] = [
        (Indicator("⇠","⇠","⇠",L10n.text(.workspace,"gitStatusText.pushIndicators.text"),StatusTextColor.blue),\.behind),
        (Indicator("⇢","⇢","⇢",L10n.text(.workspace,"gitStatusText.pushIndicators.text.2"),StatusTextColor.blue),\.ahead)
    ]
    static let pushTitle = L10n.text(.workspace,"gitStatusText.pushTitle.text")

    static let settingsLegendFont = NSFont.systemFont(ofSize:11)
    private static func repositoryIcon(_ kind:GitWorkspaceStatus.RepositoryKind) -> NSAttributedString {
        InlineStatusLayout.imageAttachment(GitIcons.repository(kind),description:kind.title,font:settingsLegendFont,side:settingsLegendFont.pointSize,color:.labelColor)
    }
    private static func repositoryLabel(_ title:String) -> NSAttributedString {
        NSAttributedString(string:title,attributes:[.font:settingsLegendFont,.foregroundColor:NSColor.labelColor])
    }
    static let settingsRepositories: NSAttributedString = {
        let kinds:[GitWorkspaceStatus.RepositoryKind] = [.generic,.github,.remote]
        let repositories = kinds.map {kind in
            let label = kind == .github ? kind.title+L10n.text(.workspace,"gitStatusText.label.text") : kind.title
            let text = NSMutableAttributedString(attributedString:repositoryIcon(kind))
            text.append(repositoryLabel(" "+label))
            return text
        }
        return InlineStatusLayout.tabbedRows([repositories],font:settingsLegendFont,columnGap:20)
    }()
    static let additionalRepositoryLegend: NSAttributedString = {
        let rows = GitWorkspaceStatus.RepositoryKind.additionalRemotes.map {kind in
            [repositoryIcon(kind),repositoryLabel(kind.title)]
        }
        return InlineStatusLayout.tabbedRows([[repositoryLabel(L10n.text(.workspace,"gitStatusText.rows.text"))]]+rows,
                                             font:settingsLegendFont,columnGap:6,paragraphSpacing:2)
    }()

    private static let settingsLegends = Dictionary(uniqueKeysWithValues:GitStatusStyle.allCases.map {style in
        let font = settingsLegendFont
        let fileIndicators = (groups.map(\.indicator) + [stash]).map {marked($0,label:$0.label,font:font,style:style)}
        let upstream = upstreamIndicators.map {marked($0.indicator,label:$0.indicator.label,font:font,style:style)}
        let push = pushIndicators.map {marked($0.indicator,label:$0.indicator.label,font:font,style:style)}
        let indicators = NSMutableAttributedString(attributedString:InlineStatusLayout.tabbedRows([fileIndicators+upstream,[]],font:font,columnGap:16,paragraphSpacing:2))
        indicators.append(InlineStatusLayout.tabbedRows([push],font:font,columnGap:16))
        return (style,(clean:marked(clean,label:clean.label,font:font,style:style),
                       indicators:NSAttributedString(attributedString:indicators)))
    })
    static func settingsLegend(_ style:GitStatusStyle) -> (clean:NSAttributedString,indicators:NSAttributedString) {
        settingsLegends[style]!
    }

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
        if let push = status.pushTarget {
            for (item,countPath) in pushIndicators {
                if let count = push[keyPath:countPath],count > 0 {append(item,count:count)}
            }
        }
        return text
    }
    static func tracking(_ status:GitWorkspaceStatus,font:NSFont,style:GitStatusStyle? = nil) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        guard let upstream = status.upstream else {return NSAttributedString(string:L10n.text(.workspace,"gitStatusText.tracking.text"),attributes:attributes)}
        let text = NSMutableAttributedString(string:upstream,attributes:attributes)
        let counts = upstreamIndicators.compactMap {direction in
            status[keyPath:direction.count].map {(direction.indicator,$0)}
        }
        guard counts.count == upstreamIndicators.count else {
            let state = status.initial ? L10n.text(.workspace,"gitStatusText.state") : L10n.text(.workspace,"gitStatusText.state.2")
            text.append(NSAttributedString(string:" · "+state,attributes:attributes))
            return text
        }
        appendComparison(counts,to:text,font:font,style:style)
        return text
    }
    static func push(_ target:GitWorkspaceStatus.PushTarget,font:NSFont,style:GitStatusStyle? = nil) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        let destination = target.address.map {[$0.host,$0.repository].compactMap {$0}.joined(separator:"/")} ?? L10n.text(.workspace,"gitStatusText.destination.text")
        let text = NSMutableAttributedString()
        if style != nil,let address = target.address {
            let icon = GitIcons.repository(target.kind)
            text.append(InlineStatusLayout.imageAttachment(icon,description:address.host ?? target.remote,font:font,side:font.pointSize,color:.labelColor))
            text.append(NSAttributedString(string:" ",attributes:attributes))
        }
        text.append(NSAttributedString(string:target.remote+"/"+target.branch+" · "+destination,attributes:attributes))
        let counts = pushIndicators.compactMap {direction in target[keyPath:direction.count].map {(direction.indicator,$0)}}
        appendComparison(counts,to:text,font:font,style:style)
        return text
    }
    private static func appendComparison(_ counts:[(Indicator,Int)],to text:NSMutableAttributedString,font:NSFont,style:GitStatusStyle?) {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
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
    }
    static func stateDetails(_ status:GitWorkspaceStatus,font:NSFont,style:GitStatusStyle) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        let labels = [status.detachedSummary,status.initial ? L10n.text(.workspace,"gitStatusText.labels") : nil,status.operation?.detailTitle]
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
    private static func marked(_ item:Indicator,label:String,font:NSFont,style:GitStatusStyle) -> NSAttributedString {
        let markerFont = style == .gitCLI ? NSFont.monospacedSystemFont(ofSize:font.pointSize,weight:.semibold) : font
        let text = NSMutableAttributedString(attributedString:markerText(item.marker(style),font:markerFont,color:item.color))
        text.append(NSAttributedString(string:" "+label,attributes:[.font:font,.foregroundColor:item.color]))
        return text
    }
    private static func markerText(_ marker:String,font:NSFont,color:NSColor) -> NSAttributedString {
        if marker.first?.isLetter == true {
            return NSAttributedString(string:marker,attributes:[.font:font,.foregroundColor:color])
        }
        return InlineStatusLayout.centeredSymbol(marker,font:font,color:color)
    }
}
