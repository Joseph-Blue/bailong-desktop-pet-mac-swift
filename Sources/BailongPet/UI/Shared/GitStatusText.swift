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
    private struct LegendKey:Hashable {
        let style:GitStatusStyle, terms:GitTerminology
        static let all = GitStatusStyle.allCases.flatMap {style in GitTerminology.allCases.map {Self(style:style,terms:$0)}}
    }
    private struct Indicator {
        let symbol:String, promptSymbol:String, mnemonic:String, labelKey:String
        let color:NSColor
        let detailLabelKey:String?

        init(_ symbol:String,_ promptSymbol:String,_ mnemonic:String,_ labelKey:String,_ color:NSColor,detailLabelKey:String? = nil) {
            self.symbol = symbol; self.promptSymbol = promptSymbol
            self.mnemonic = mnemonic; self.labelKey = labelKey; self.color = color
            self.detailLabelKey = detailLabelKey
        }
        func label(_ terms:GitTerminology,detail:Bool = false) -> String {
            terms.text(detail ? detailLabelKey ?? labelKey : labelKey)
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
        (.conflicted,Indicator("~","✖","C",GitWorkspaceStatus.Group.conflicted.titleKey,StatusTextColor.red)),
        (.staged,Indicator("+","●","S",GitWorkspaceStatus.Group.staged.titleKey,StatusTextColor.green)),
        (.unstaged,Indicator("!","✚","M",GitWorkspaceStatus.Group.unstaged.titleKey,StatusTextColor.orange)),
        (.untracked,Indicator("?","…","?",GitWorkspaceStatus.Group.untracked.titleKey,.labelColor))
    ]
    private static let clean = Indicator("✓","✔","✓","gitStatusText.clean",StatusTextColor.green)
    private static let stash = Indicator("*","⚑","SH","gitWorkspace.stashLabel",StatusTextColor.purple)
    private static let upstreamIndicators:[(indicator:Indicator,count:KeyPath<GitWorkspaceStatus,Int?>)] = [
        (Indicator("⇣","↓","↓","gitStatusText.upstreamIndicators.text",StatusTextColor.blue,detailLabelKey:"gitStatusText.comparison.behind"),\.behind),
        (Indicator("⇡","↑","↑","gitStatusText.upstreamIndicators.text.2",StatusTextColor.blue,detailLabelKey:"gitStatusText.comparison.ahead"),\.ahead)
    ]
    private static let pushIndicators:[(indicator:Indicator,count:KeyPath<GitWorkspaceStatus.PushTarget,Int?>)] = [
        (Indicator("⇠","←","←","gitStatusText.pushIndicators.text",StatusTextColor.blue,detailLabelKey:"gitStatusText.comparison.behind"),\.behind),
        (Indicator("⇢","→","→","gitStatusText.pushIndicators.text.2",StatusTextColor.blue,detailLabelKey:"gitStatusText.comparison.ahead"),\.ahead)
    ]
    static func pushTitle(_ terms:GitTerminology) -> String {terms.text("gitStatusText.pushTitle.text")}

    static let settingsLegendFont = NSFont.systemFont(ofSize:11)
    private static func repositoryIcon(_ kind:GitWorkspaceStatus.RepositoryKind,terms:GitTerminology) -> NSAttributedString {
        InlineStatusLayout.imageAttachment(GitIcons.repository(kind),description:kind.title(using:terms),font:settingsLegendFont,side:settingsLegendFont.pointSize,color:.labelColor)
    }
    private static func repositoryLabel(_ title:String) -> NSAttributedString {
        NSAttributedString(string:title,attributes:[.font:settingsLegendFont,.foregroundColor:NSColor.labelColor])
    }
    static func settingsRepositories(_ terms:GitTerminology) -> NSAttributedString {
        let kinds:[GitWorkspaceStatus.RepositoryKind] = [.generic,.github,.remote]
        let repositories = kinds.map {kind in
            let label = kind == .github ? "GitHub"+terms.text("gitStatusText.label.text") : kind.title(using:terms)
            let text = NSMutableAttributedString(attributedString:repositoryIcon(kind,terms:terms))
            text.append(repositoryLabel(" "+label))
            return text
        }
        return InlineStatusLayout.tabbedRows([repositories],font:settingsLegendFont,columnGap:20)
    }
    static func additionalRepositoryLegend(_ terms:GitTerminology) -> NSAttributedString {
        let rows = GitWorkspaceStatus.RepositoryKind.additionalRemotes.map {kind in
            [repositoryIcon(kind,terms:terms),repositoryLabel(kind.title(using:terms))]
        }
        return InlineStatusLayout.tabbedRows([[repositoryLabel(terms.text("gitStatusText.rows.text"))]]+rows,
                                             font:settingsLegendFont,columnGap:6,paragraphSpacing:2)
    }

    private static let settingsLegends = Dictionary(uniqueKeysWithValues:LegendKey.all.map {appearance in
        let font = settingsLegendFont
        let fileIndicators = (groups.map(\.indicator) + [stash]).map {marked($0,label:$0.label(appearance.terms),font:font,style:appearance.style)}
        let upstream = upstreamIndicators.map {marked($0.indicator,label:$0.indicator.label(appearance.terms),font:font,style:appearance.style)}
        let push = pushIndicators.map {marked($0.indicator,label:$0.indicator.label(appearance.terms),font:font,style:appearance.style)}
        let indicators = NSMutableAttributedString(attributedString:InlineStatusLayout.tabbedRows([fileIndicators+upstream,[]],font:font,columnGap:16,paragraphSpacing:2))
        indicators.append(InlineStatusLayout.tabbedRows([push],font:font,columnGap:16))
        return (appearance,(clean:cleanLabel(font:font,style:appearance.style,terms:appearance.terms),
                       indicators:NSAttributedString(attributedString:indicators)))
    })
    static func settingsLegend(_ style:GitStatusStyle,terms:GitTerminology) -> (clean:NSAttributedString,indicators:NSAttributedString) {
        settingsLegends[LegendKey(style:style,terms:terms)]!
    }
    static func cleanLabel(font:NSFont,style:GitStatusStyle,terms:GitTerminology) -> NSAttributedString {
        marked(clean,label:clean.label(terms),font:font,style:style)
    }
    static func spaceBadge(_ status:HuggingFaceSpace.Result?,font:NSFont) -> NSAttributedString? {
        guard case .runtime(let runtime) = status,let badge = runtime.badge else {return nil}
        let color:NSColor
        switch badge {
        case .running:color = StatusTextColor.green
        case .building,.starting:color = StatusTextColor.yellow
        case .paused,.stopped:color = .labelColor
        case .error:color = StatusTextColor.red
        }
        return NSAttributedString(string:badge.rawValue,attributes:[.font:font,.foregroundColor:color])
    }
    static func spaceStatusTitle(_ status:HuggingFaceSpace.Result?) -> String {
        switch status {
        case .runtime(let runtime):return runtime.title
        case .unavailable:return L10n.text(.workspace,"spaceStatus.unavailable")
        case nil:return L10n.text(.workspace,"spaceStatus.loading")
        }
    }
    static func spaceHeading(font:NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString:InlineStatusLayout.imageAttachment(GitIcons.repository(.huggingFace),
            description:"Hugging Face",font:font,side:font.pointSize,color:.secondaryLabelColor))
        text.append(NSAttributedString(string:" "+L10n.text(.workspace,"spaceStatus.title"),attributes:[.font:font,.foregroundColor:NSColor.labelColor]))
        return text
    }
    static func spaceDetail(_ status:HuggingFaceSpace.Result?,font:NSFont,space:HuggingFaceSpace? = nil) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        if let badge = spaceBadge(status,font:.monospacedSystemFont(ofSize:font.pointSize,weight:.semibold)) {
            text.append(badge)
            text.append(NSAttributedString(string:" ",attributes:attributes))
        }
        let name = space.map {$0.owner+"/"+$0.name+" · "} ?? ""
        text.append(NSAttributedString(string:name+spaceStatusTitle(status),attributes:attributes))
        return text
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
    static func tracking(_ status:GitWorkspaceStatus,font:NSFont,style:GitStatusStyle? = nil,terms:GitTerminology = .localized) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        guard let upstream = status.upstream else {return NSAttributedString(string:terms.text("gitStatusText.tracking.text"),attributes:attributes)}
        let text = NSMutableAttributedString(string:upstream,attributes:attributes)
        let counts = upstreamIndicators.compactMap {direction in
            status[keyPath:direction.count].map {(direction.indicator,$0)}
        }
        guard counts.count == upstreamIndicators.count else {
            let state = status.initial ? terms.text("gitStatusText.state") : terms.text("gitStatusText.state.2")
            text.append(NSAttributedString(string:" · "+state,attributes:attributes))
            return text
        }
        appendComparison(counts,to:text,font:font,style:style,terms:terms)
        return text
    }
    static func push(_ target:GitWorkspaceStatus.PushTarget,font:NSFont,style:GitStatusStyle? = nil,terms:GitTerminology = .localized) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        let destination = target.address.map {[$0.host,$0.repository].compactMap {$0}.joined(separator:"/")} ?? terms.text("gitStatusText.destination.text")
        let text = NSMutableAttributedString(string:target.remote+"/"+target.branch+" · "+destination,attributes:attributes)
        let counts = pushIndicators.compactMap {direction in target[keyPath:direction.count].map {(direction.indicator,$0)}}
        appendComparison(counts,to:text,font:font,style:style,terms:terms)
        return text
    }
    private static func appendComparison(_ counts:[(Indicator,Int)],to text:NSMutableAttributedString,font:NSFont,style:GitStatusStyle?,terms:GitTerminology) {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        for (item,count) in counts {
            text.append(NSAttributedString(string:" · ",attributes:attributes))
            let label = item.label(terms,detail:style != nil)+" \(count)"
            if let style {
                let countFont = count > 0 ? NSFont.systemFont(ofSize:font.pointSize,weight:.semibold) : font
                text.append(marked(item,label:label,font:countFont,style:style))
            } else {
                text.append(NSAttributedString(string:label,attributes:attributes))
            }
        }
    }
    static func stateDetails(_ status:GitWorkspaceStatus,font:NSFont,terms:GitTerminology) -> NSAttributedString {
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
        let labels = [status.detachedSummary(using:terms),status.initial ? terms.text("gitStatusText.labels") : nil]
        return NSAttributedString(string:labels.compactMap {$0}.joined(separator:" · "),attributes:attributes)
    }
    static func operationDetail(_ title:String,font:NSFont) -> NSAttributedString {
        let color = StatusTextColor.red
        let text = NSMutableAttributedString(attributedString:InlineStatusLayout.imageAttachment(GitIcons.git,
            description:"Git",font:font,side:font.pointSize,color:color))
        text.append(NSAttributedString(string:" "+title,attributes:[.font:font,.foregroundColor:color]))
        return text
    }
    static func groupDetail(_ group:GitWorkspaceStatus.Group,count:Int,font:NSFont,style:GitStatusStyle,terms:GitTerminology) -> NSAttributedString {
        let item = groups.first {$0.group == group}!.indicator
        return marked(item,label:item.label(terms)+" · \(count)",font:font,style:style)
    }
    static func stashDetail(_ title:String,font:NSFont,style:GitStatusStyle) -> NSAttributedString {
        marked(stash,label:title,font:font,style:style)
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
