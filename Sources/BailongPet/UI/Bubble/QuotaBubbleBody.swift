import AppKit

final class QuotaBubbleBody: NSView {
    override var isFlipped: Bool {true}
    private let overview: QuotaOverview
    private let preferences: PetPreferences
    private let scale: CGFloat
    private let fontScale: CGFloat
    private let resetFont: NSFont
    private let resetTab: CGFloat
    let requiredContentWidth: CGFloat
    private let cachedAt: Date?
    private let failed: Bool
    private let retry: (() -> Void)?
    private static let resetTextColor = NSColor(name:nil) {$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .white : .black}

    private var rowWidth: CGFloat = 0
    private var y: CGFloat = 0
    private var usageTail: NSRect?
    private var loadingTimer: Timer?
    private weak var loadingAmount: NSTextField?
    private var loadingPhase = 0
    private var pricingTimer: Timer?
    private weak var pricingCountdown: NSTextField?
    private var pricingTarget: Date?
    var onLayoutChange: ((_ height:CGFloat, _ reveal:NSRect?) -> Void)?

    init(_ overview:QuotaOverview, scale:CGFloat, preferences:PetPreferences, cachedAt:Date?, failed:Bool, retry:(() -> Void)?) {
        self.overview = overview; self.scale = scale; self.preferences = preferences
        self.cachedAt = cachedAt; self.failed = failed; self.retry = retry
        let fontScale = scale*preferences.number("messageFontSize")/13
        self.fontScale = fontScale
        let resetFont = NSFont.monospacedDigitSystemFont(ofSize:12.5*fontScale,weight:.medium)
        self.resetFont = resetFont
        let resetDates = overview.rows.compactMap(\.resetsAt)
        let now = Date()
        resetTab = ceil(resetDates.map {(QuotaPresentation.resetDateText($0) as NSString).size(withAttributes:[.font:resetFont]).width}.max() ?? 0)+16*fontScale
        let resetTail = ceil(resetDates.map {(QuotaPresentation.countdown(until:$0,now:now) as NSString).size(withAttributes:[.font:resetFont]).width}.max() ?? 0)
        requiredContentWidth = resetDates.isEmpty ? 0 : resetTab+resetTail+8
        super.init(frame:.zero)
        autoresizesSubviews = false
    }
    required init?(coder:NSCoder) {fatalError()}

    func arrange(width:CGFloat, now:Date = Date()) -> CGFloat {
        stopTimers()
        subviews.forEach {$0.removeFromSuperview()}
        rowWidth = width; y = 0; usageTail = nil
        if let provider = overview.apiProvider {
            addProviderHeading(provider,font:.systemFont(ofSize:13*fontScale,weight:.semibold))
        } else {
            addText(overview.subscriptionHeading,font:.systemFont(ofSize:13*fontScale,weight:.semibold))
        }
        if let cachedAt {
            addText(L10n.text(.usage,"quotaBubbleBody.arrange.text")+cachedAt.formatted(date:.omitted,time:.standard),font:.systemFont(ofSize:11*fontScale))
        }
        y += 12*scale
        let rows = overview.displayRows(at:now)
        for (index,row) in rows.enumerated() {
            if index > 0 && row.startsSection {
                let line = NSBox(frame:NSRect(x:0,y:y,width:width,height:1))
                line.boxType = .separator; addSubview(line); y += 12*scale
            }
            if let usage = row.usage {
                addUsage(usage)
            } else {
                addQuotaRow(row,now:now)
                let compact = overview.showsDeepSeekPricing && index+1 < rows.count && !rows[index+1].startsSection
                y += (compact ? 4 : 12)*scale
            }
        }
        if let notice = overview.notice {addText(notice,font:.systemFont(ofSize:11*fontScale,weight:.medium))}
        addActions()
        refreshLoadingAppearance()
        schedulePricingRefresh(from:now)
        return y
    }

    private func addText(_ value: String, font: NSFont, color: NSColor = .labelColor) {
        let text = label(value); text.font = font; text.textColor = color
        let height = max(font.pointSize+5,(value as NSString).boundingRect(with:NSSize(width:rowWidth,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height.rounded(.up)+3)
        text.frame = NSRect(x:0,y:y,width:rowWidth,height:height); addSubview(text); y += height
    }

    private func addProviderHeading(_ provider:APIProviderIdentity,font:NSFont) {
        let iconSide = 18*scale
        let icon = AppIcons.apiProvider(provider.catalogID)
        let height = max(font.pointSize+8,iconSide)
        let row = NSStackView()
        row.orientation = .horizontal; row.alignment = .centerY; row.distribution = .fill
        row.spacing = 6*scale
        if let icon {
            let image = NSImageView()
            image.image = icon; image.imageScaling = .scaleProportionallyDown
            image.contentTintColor = .labelColor
            image.widthAnchor.constraint(equalToConstant:iconSide).isActive = true
            image.heightAnchor.constraint(equalToConstant:iconSide).isActive = true
            row.addArrangedSubview(image)
        }
        let text = label(provider.heading)
        text.font = font; text.textColor = .labelColor
        text.maximumNumberOfLines = 1; text.usesSingleLineMode = true; text.lineBreakMode = .byTruncatingTail
        text.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        row.addArrangedSubview(text)
        row.frame = NSRect(x:0,y:y,width:rowWidth,height:height)
        addSubview(row); y += height
    }

    private func addReset(_ date: Date, now:Date) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment:.left,location:resetTab)]
        let line = QuotaPresentation.resetDateText(date)+"\t"+QuotaPresentation.countdown(until:date,now:now)
        let view = SelectableRichText(frame:.zero)
        view.textContainer?.lineFragmentPadding = 2
        view.font = resetFont
        view.attributedStringValue = NSAttributedString(string:line,attributes:[.font:resetFont,.foregroundColor:Self.resetTextColor,.paragraphStyle:paragraph])
        let height = max(ceil(resetFont.pointSize+5),view.height(for:rowWidth))
        view.frame = NSRect(x:0,y:y,width:rowWidth,height:height)
        addSubview(view); y += height
    }

    private func addUsage(_ usage:TokenUsage) {
        let expanded = preferences.bool(PetPreferences.tokenDetailsKey)
        let usageView = QuotaTokenUsageView(usage:usage,expanded:expanded,scale:scale,fontScale:fontScale,
                                            headingText:overview.usageHeading,format:preferences.tokenCountFormat)
        let height = usageView.arrange(width:rowWidth)
        usageView.frame.origin.y = y; addSubview(usageView)
        let lastLineHeight = 24*fontScale
        usageTail = NSRect(x:0,y:max(0,usageView.frame.maxY-lastLineHeight),width:1,height:lastLineHeight)
        y += height+12*scale
        usageView.onToggle = { [weak self,weak usageView] in
            self?.preferences.set(!expanded,for:PetPreferences.tokenDetailsKey,from:usageView)
        }
        usageView.onExpansionChange = { [weak self] reveal in
            guard let self, self.onLayoutChange != nil else {return}
            DisclosureMotion.update(in:self,animatesLayout:false) {
                self.refreshLayout(at:Date(), revealUsage:reveal)
            }
        }
    }

    private func addQuotaRow(_ row:QuotaRow, now:Date) {
        let width = rowWidth
        let amountFont = NSFont.monospacedDigitSystemFont(ofSize:13*fontScale,weight:.semibold)
        let headingFont = NSFont.systemFont(ofSize:row.subtitle == nil ? amountFont.pointSize : 12*fontScale,weight:.medium)
        // 使用单行原生标签的 fittingSize，包含文字单元格内边距；
        // 只按 NSString 字宽分配空间会让“剩余 55%”换行并被固定行高裁掉。
        let heading = NSTextField(labelWithString:row.title); heading.font = headingFont; heading.textColor = .labelColor
        if let subtitle = row.subtitle {
            heading.usesSingleLineMode = false; heading.maximumNumberOfLines = 0; heading.lineBreakMode = .byWordWrapping
            let title = NSMutableAttributedString(string:row.title+"\n",attributes:[.font:headingFont,.foregroundColor:NSColor.labelColor])
            title.append(NSAttributedString(string:subtitle,attributes:[.font:NSFont.systemFont(ofSize:11*fontScale),.foregroundColor:NSColor.labelColor]))
            heading.attributedStringValue = title
        }
        let amount = NSTextField(labelWithString:row.value); amount.font = amountFont; amount.alignment = .right
        if let target = row.countdownTarget {pricingCountdown = amount; pricingTarget = target}
        let quotaColor: NSColor? = row.remaining.flatMap {$0 <= 5 ? .systemRed : $0 <= 10 ? .systemOrange : nil}
        amount.textColor = row.tone == .positive ? StatusTextColor.green : row.tone == .negative ? StatusTextColor.red
            : row.remaining.map {$0 <= 5 ? StatusTextColor.red : $0 <= 10 ? StatusTextColor.orange : .labelColor} ?? .labelColor
        if row.loading {loadingAmount = amount; renderLoading(); amount.setAccessibilityLabel(L10n.text(.usage,"quotaBubbleBody.addQuotaRow.text"))}
        for field in [heading,amount] where field !== heading || row.subtitle == nil {
            field.maximumNumberOfLines = 1; field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
        }
        let gap = 12*scale
        let headingMinimum = min(heading.fittingSize.width,96*scale)
        let amountWidth = min(amount.fittingSize.width.rounded(.up),width-headingMinimum-gap)
        let rowHeight = max(22*scale,max(heading.fittingSize.height,amount.fittingSize.height).rounded(.up))
        if overview.showsDeepSeekPricing {
            let headingWidth = floor(max(1,width-gap)*0.42)
            let valueWidth = max(1,width-gap-headingWidth)
            for field in [heading,amount] {
                field.usesSingleLineMode = false; field.maximumNumberOfLines = 0; field.lineBreakMode = .byWordWrapping
                field.cell?.wraps = true; field.cell?.isScrollable = false
            }
            let height = max(rowHeight,max(
                heading.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:headingWidth,height:10000)).height,
                amount.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:valueWidth,height:10000)).height).rounded(.up))
            heading.frame = NSRect(x:0,y:y,width:headingWidth,height:height)
            amount.frame = NSRect(x:headingWidth+gap,y:y,width:valueWidth,height:height); y += height
        } else if row.wrapsValue,amount.fittingSize.width+heading.fittingSize.width+gap > width {
            heading.frame = NSRect(x:0,y:y,width:width,height:rowHeight); y += rowHeight
            amount.usesSingleLineMode = false; amount.maximumNumberOfLines = 0; amount.lineBreakMode = .byWordWrapping
            let height = max(rowHeight,amount.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:10000)).height.rounded(.up))
            amount.frame = NSRect(x:0,y:y,width:width,height:height); y += height
        } else {
            heading.frame = NSRect(x:0,y:y,width:width-amountWidth-gap,height:rowHeight)
            amount.frame = NSRect(x:width-amountWidth,y:y,width:amountWidth,height:rowHeight); y += rowHeight
        }
        addSubview(heading); addSubview(amount)
        if let amount = row.remaining {
            y += 4*scale
            let bar = AccentProgressIndicator(frame:NSRect(x:0,y:y,width:width,height:9*scale))
            bar.progressColor = quotaColor
            bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = amount
            addSubview(bar); y += 16*scale
        }
        if let resetDate = row.resetsAt {
            addReset(resetDate,now:now)
            if row.detail != nil {y += 4*scale}
        }
        if let detail = row.detail {addText(detail,font:.systemFont(ofSize:11*fontScale))}
        if let footnote = row.footnote {
            y += 4*scale
            addText(footnote,font:.systemFont(ofSize:11*fontScale))
        }
        if row.retry,let retry {
            let button = ActionButton(L10n.text(.usage,"quotaBubbleBody.addQuotaRow.button"),retry); button.bezelStyle = .inline
            button.font = .systemFont(ofSize:12*fontScale)
            button.frame = NSRect(x:0,y:y,width:60*scale,height:26*scale)
            addSubview(button); y += button.frame.height
        }
    }

    private func addActions() {
        let width = rowWidth
        let actionFont = NSFont.systemFont(ofSize:12*fontScale,weight:.medium)
        let actionSymbol = NSImage.SymbolConfiguration(pointSize:11*fontScale,weight:.semibold)
        let management:SubscriptionManagementButton? = overview.apiProvider == nil
            ? SubscriptionManagementButton(management:overview.management,font:actionFont) : nil
        management?.symbolConfiguration = actionSymbol
        let providerPage:ActionButton? = overview.apiProvider.flatMap {provider in
            guard let address = provider.pageURL,let url = URL(string:address) else {return nil}
            let button = ActionButton(L10n.text(.usage,"quotaBubbleBody.addActions.button")) {NSWorkspace.shared.open(url)}
            button.font = actionFont
            button.image = NSImage(systemSymbolName:"arrow.up.right.square",accessibilityDescription:nil)?
                .withSymbolConfiguration(actionSymbol)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel(L10n.text(.usage,"quotaBubbleBody.addActions.button"))
            return button
        }
        let refresh = retry.map {ActionButton(failed ? L10n.text(.usage,"quotaBubbleBody.addQuotaRow.button") : L10n.text(.usage,"quotaBubbleBody.addActions.button.2"),$0)}
        if let refresh {
            refresh.font = actionFont
            refresh.image = NSImage(systemSymbolName:"arrow.clockwise",accessibilityDescription:nil)?
                .withSymbolConfiguration(actionSymbol)
            refresh.imagePosition = .imageLeading
            refresh.keepsAccentWhenInactive = true
            refresh.emphasize()
        }
        let leading:NSView? = providerPage ?? management
        let leadingSize = leading?.intrinsicContentSize ?? .zero, refreshSize = refresh?.intrinsicContentSize ?? .zero
        let actionHeight = max(26*scale,leadingSize.height,refreshSize.height)
        let refreshWidth = min(width,refreshSize.width)
        let leadingWidth = max(0,min(leadingSize.width,width-refreshWidth-8*scale))
        if let leading {
            leading.frame = NSRect(x:0,y:y,width:leadingWidth,height:actionHeight)
            addSubview(leading)
        }
        if let refresh {
            refresh.frame = NSRect(x:width-refreshWidth,y:y,width:refreshWidth,height:actionHeight)
            addSubview(refresh)
        }
        y += actionHeight+4*scale
    }

    private func stopLoading() {
        loadingTimer?.invalidate(); loadingTimer = nil; loadingAmount = nil; loadingPhase = 0
    }
    private func renderLoading() {
        guard let field = loadingAmount else {return}
        let font = field.font ?? .systemFont(ofSize:13)
        let value = NSMutableAttributedString(attributedString:InlineStatusLayout.braille(InlineStatusLayout.brailleFrames[loadingPhase],font:font,color:AppAccent.foregroundColor))
        value.append(NSAttributedString(string:L10n.text(.usage,"quotaBubbleBody.renderLoading.text"),attributes:[.font:font,.foregroundColor:NSColor.labelColor]))
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        value.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:value.length))
        field.attributedStringValue = value
    }
    func refreshLoadingAppearance() {
        guard loadingAmount != nil else {return}
        if !ProgressTextEffects.enabled {
            loadingTimer?.invalidate(); loadingTimer = nil; loadingPhase = 0
        }
        renderLoading()
        guard ProgressTextEffects.enabled,loadingTimer == nil else {return}
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else {return}
            self.loadingPhase = (self.loadingPhase+1) % InlineStatusLayout.brailleFrames.count
            self.renderLoading()
        }
        loadingTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }

    private func refreshLayout(at date:Date, revealUsage:Bool = false) {
        let height = arrange(width:rowWidth, now:date)
        onLayoutChange?(height,revealUsage ? usageTail : nil)
    }

    private func schedulePricingRefresh(from now:Date) {
        guard overview.showsDeepSeekPricing, let change = DeepSeekPricing.nextDisplayChange(at:now) else {return}
        let ticks = pricingTarget != nil
        let firstFire = ticks ? Date(timeIntervalSince1970:floor(now.timeIntervalSince1970)+1) : change
        let timer = Timer(fire:firstFire, interval:ticks ? 1 : 0, repeats:ticks) { [weak self] _ in
            guard let self else {return}
            let current = Date()
            if current >= change || current < now {
                self.refreshLayout(at:current)
            } else if let target = self.pricingTarget {
                self.pricingCountdown?.stringValue = DeepSeekPricing.countdown(until:target,now:current)
            }
        }
        pricingTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }

    private func stopTimers() {
        stopLoading()
        pricingTimer?.invalidate(); pricingTimer = nil
        pricingTarget = nil; pricingCountdown = nil
    }

    func stop() {
        stopTimers()
        onLayoutChange = nil
    }

    deinit {stopTimers()}
}
