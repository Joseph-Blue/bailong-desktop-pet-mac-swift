import AppKit

private final class BubbleHeadingField:NSTextField {
    var colorsChanged:(() -> Void)?
    override init(frame:NSRect) {
        super.init(frame:frame)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshColors),name:AppAccent.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshColors),name:PetPreferences.didChange,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(refreshColors),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refreshColors()}
    @objc private func refreshColors() {colorsChanged?()}
    deinit {NSWorkspace.shared.notificationCenter.removeObserver(self)}
}

final class Bubble {
    let window: PetWindow
    private lazy var motion:BubbleMotion = {
        let value = BubbleMotion(window:window,preferences:preferences)
        value.onHidden = { [weak self] in self?.releaseHiddenDisplay() }
        return value
    }()
    private var placement: (CGRect, String?, CGRect, NSSize)?
    private var placementSide:BubblePlacement.Side?
    private var placementArea:CGRect?
    var targetFrame: NSRect {motion.frame}
    func move(to origin: NSPoint) {motion.move(to:origin)}
    private let title = BubbleHeadingField(wrappingLabelWithString:"")
    private let headingSpinner = NSTextField(labelWithString:"")
    private let headingIcon = TaskActivitySymbolView(frame:.zero)
    private var headingActivity:TaskActivity?
    private let text = MessageTextView()
    private let scroll = BubbleBodyScrollView()
    private let closeButton = BubbleCloseButton()
    private var details: ActionButton!
    private var codexButton: ActionButton!
    private var retryButton: ActionButton!
    private var approvalReject:ActionButton!, approvalAllow:ActionButton!
    private var approval:ApprovalPresentation?
    private var previousCard:ActionButton!, nextCard:ActionButton!, replyButton:ActionButton!
    private let cardCount = NSTextField(labelWithString:"")
    private let cardStore = BubbleCardStore()
    private var cards:[BubbleCard] {cardStore.cards}
    private var cardIndex:Int? {cardStore.cardIndex}
    private var renderedCardID:String?
    private var userInputPrefixLength = 0
    private var refreshStandalone:(() -> Void)?
    private var isBrowsingCards:Bool {cardStore.isBrowsingCards}
    private var submittingQuestion:Bool {questionForm?.isSubmitting == true}
    var onCardLayout:() -> Void = {}
    var taskProvider:() -> BubbleTaskOverview = {BubbleTaskOverview(status:"任务同步尚未初始化")}
    private var taskList:BubbleTaskList?
    private let countdown = BubbleCountdown()
    private var headingTimer: Timer?
    private var quotaLoadingTimer:Timer?
    private weak var quotaLoadingAmount:NSTextField?
    private var quotaLoadingPhase = 0
    private var plainHeading = ""
    private var headingPhase = 0
    private var headingStarted = 0.0
    private var headingAnimated = false
    private let elapsedIcon = NSImageView()
    private let elapsedLabel = NSTextField(labelWithString:"00:00")
    private var elapsedTimer: Timer?
    private let taskProgress = ProgressMarqueeView(frame:.zero)
    private let taskProgressIcon = TaskActivitySymbolView(frame:.zero)
    private var displayedFailure:AppFailure?
    private var progressTaskKey:String?
    private var activityTiming:TaskTiming?
    private var taskStartedAt: Date?
    private var taskFinishedAt: Date?
    private var timedTaskKey: String?
    private var layoutBodyHeight = 0.0
    private var elapsedLayoutWidth = 0.0
    private let headingFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var scale = 1.0
    var preferences = PetPreferences.shared
    var purpose: MessagePurpose = .interaction
    var relatedConversation: String?
    var fileLinkDirectory: (() -> URL?)? {didSet {text.linkBaseDirectory = fileLinkDirectory}}
    private var currentBody = ""
    private var truncatesProgressBody = false
    private var questionForm:QuestionForm?
    private var previousQuestion:ActionButton!
    private var skipQuestion:ActionButton!
    var onQuestionsSkipped: ((Set<String>) -> Void)?
    private var questionModels = [TaskQuestion]()
    private var questionSize:NSSize?
    private var questionTaskKey:String?
    private var pendingAttention = false
    private let resizeDelegate = QuestionResizeDelegate()
    var onQuestionSubmit: (([String:String], @escaping (Error?) -> Void) -> Void)?
    var onClose: () -> Void = {}
    var onDetails: () -> Void = {}
    var onCodex: () -> Void = {CodexConnection.openDesktop()}
    var kind = ""
    var visible: Bool { motion.presented }
    var acceptsTransientInteraction:Bool {
        !visible || (!pendingAttention && questionForm == nil && !submittingQuestion &&
            (cardIndex.map {cards[$0].priority == .companion} ?? (purpose == .interaction || purpose == .preview)))
    }
    var blocksProgressToast:Bool {visible && (pendingAttention || questionForm != nil || submittingQuestion || isBrowsingCards)}
    func showProgressToast(_ activity:TaskActivity,timing:TaskTiming) {
        onQuestionSubmit = nil; onQuestionsSkipped = nil
        let detail = ([activity.actionTitle,activity.displayDetail].filter {!$0.isEmpty}.joined(separator:"\n"))
            .replacingOccurrences(of:"**",with:"")
        show(title:activity.displayTitle,body:detail,kind:"progressToast",scale:preferences.number("bubblePercent")/100,
             seconds:preferences.number("progressToastSeconds"),animateHeading:true,timing:timing,truncateBody:activity.kind == .tool,headingActivity:activity)
        purpose = .progress; text.hoverHelp = activity.text
    }
    func resolveQuestions(taskKey:String? = nil,form:QuestionForm? = nil) {
        let affected = cards.filter {card in
            card.attentionAction && (taskKey == nil || card.timing?.key == taskKey) && (form == nil || card.form === form)
        }.map(\.id)
        let currentID = cardIndex.map {cards[$0].id}
        cardStore.remove {affected.contains($0.id)}
        if (taskKey == nil && form == nil) || currentID.map({affected.contains($0)}) == true {
            questionForm = nil; questionModels = []; questionSize = nil; onQuestionSubmit = nil
            pendingAttention = false; questionTaskKey = nil
            hide()
        } else {updateCardNavigation(); layout(bodyHeight:layoutBodyHeight)}
    }
    func removeActivity(taskKey:String) {
        let currentID = cardIndex.map {cards[$0].id}
        cardStore.remove {$0.timing?.key == taskKey && $0.id.hasSuffix(":activity")}
        if currentID != nil && cardIndex == nil {hide()}
        else {updateCardNavigation()}
    }
    func discardCards(conversation:String? = nil) {
        cardStore.remove {conversation == nil || $0.thread == conversation}
        if cardIndex == nil {hide()}
        updateCardNavigation()
    }
    private func saveCardForm() {
        guard renderedCardID != nil,renderedCardID == cardStore.selectedID else {return}
        cardStore.saveForm(questionForm,size:questionSize)
    }
    func present(_ message:BubbleCard,select:Bool = false) {
        saveCardForm()
        let render = cardStore.present(message,select:select,limit:Int(preferences.number("bubbleCardLimit")),
            wasVisible:visible,protectsInput:submittingQuestion || questionForm != nil,pendingAttention:pendingAttention)
        if render {renderCard()}
        else {updateCardNavigation(); layout(bodyHeight:layoutBodyHeight); onCardLayout()}
    }
    func refreshCardPreferences() {
        saveCardForm()
        let currentID = cardIndex.map {cards[$0].id}
        cardStore.applyLimit(Int(preferences.number("bubbleCardLimit")),showOverview:preferences.bool("showTaskOverview"))
        if visible {
            if cardIndex != nil {renderCard()}
            else if currentID != nil {hide()}
        }
    }
    @discardableResult func refreshAppearance() -> Bool {
        saveCardForm()
        cardStore.clearQuestionSizes()
        questionSize = nil
        guard visible else {return false}
        if cardIndex != nil {renderCard(refreshingAppearance:true)}
        else if let refreshStandalone {refreshStandalone()}
        else {return false}
        scroll.showTop()
        onCardLayout(); return true
    }
    private func navigateCard(_ delta:Int) {
        guard !submittingQuestion else {return}
        saveCardForm()
        if cardStore.navigate(delta) {renderCard()}
    }
    private func updateCardNavigation() {
        let hasCard = cardIndex != nil
        previousCard.isHidden = !hasCard; nextCard.isHidden = !hasCard; cardCount.isHidden = !hasCard
        previousCard.isEnabled = !submittingQuestion && (cardIndex ?? 0) > 0
        nextCard.isEnabled = !submittingQuestion && (cardIndex ?? cards.count) < cards.count-1
        cardCount.stringValue = "\((cardIndex ?? 0)+1) / \(cards.count)"
        replyButton.isHidden = cardIndex.flatMap {cards[$0].reply} == nil
        replyButton.isEnabled = !submittingQuestion
    }
    private func renderCard(refreshingAppearance:Bool = false) {
        guard let index = cardIndex,cards.indices.contains(index) else {return}
        let card = cards[index]
        let changedApproval = approval?.request.identity != card.approval?.request.identity || approval?.request.details != card.approval?.request.details
        let changedCard = renderedCardID != card.id || changedApproval || !visible
        questionForm = card.form; questionModels = card.form?.questions ?? card.question?.questions ?? []; questionTaskKey = card.timing?.key; questionSize = card.questionSize
        onQuestionSubmit = card.question?.submit; onQuestionsSkipped = card.question?.skip
        onDetails = card.details; onCodex = card.codex; approval = card.approval
        updateCardNavigation()
        show(title:card.title,body:card.approval?.body ?? card.body,kind:card.kind,scale:preferences.number("bubblePercent")/100,seconds:preferences.duration(card.purpose,text:card.body),
             details:card.thread != nil,resetText:card.resetText || changedCard,animateHeading:card.animateHeading,
             attentionAction:card.attentionAction,questions:card.question?.questions ?? [],timing:card.timing,fromCard:true,preserveCountdown:refreshingAppearance,laysOutBody:!card.showsTaskOverview || !preferences.bool("showTaskOverview"),fileEdits:card.fileEdits,isUserInput:card.isUserInput,completionFooter:card.completionFooter,failure:card.failure)
        relatedConversation = card.thread; purpose = card.purpose
        renderedCardID = card.id
        cardStore.saveForm(questionForm,size:questionSize)
        if changedCard {scroll.showTop()}
        if card.showsTaskOverview && preferences.bool("showTaskOverview") {
            let list = BubbleTaskList(width:bodyLayout.contentWidth,scale:scale*preferences.number("messageFontSize")/13,provider:{ [weak self] in
                self?.taskProvider() ?? BubbleTaskOverview(status:"任务同步已停止")
            })
            taskList = list
            list.onResize = { [weak self,weak list] height in
                guard let self,let list else {return}
                self.scroll.setBody(list,height:height)
                self.layout(bodyHeight:min(320*self.scale,height)); self.scroll.showTop(); self.onCardLayout()
            }
            scroll.setBody(list,height:list.frame.height)
            layout(bodyHeight:min(320*scale,list.frame.height)); list.start(); scroll.showTop()
        }
        onCardLayout()
    }
    init() {
        window = PetWindow(contentRect:NSRect(x:0,y:0,width:320,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.worksWhenModal = true; window.acceptsMouseMovedEvents = true
        window.tracksContentCursor = true
        window.collectionBehavior = [.canJoinAllSpaces,.ignoresCycle,.fullScreenNone]
        window.delegate = resizeDelegate
        resizeDelegate.resized = { [weak self] in
            guard let self,!self.questionModels.isEmpty else {return}
            self.questionSize = self.window.frame.size; self.motion.adoptUserFrame()
            self.layoutQuestions()
        }
        let content = BubbleBackgroundView()
        window.contentView = content
        title.isSelectable = false; title.font = .boldSystemFont(ofSize:13)
        title.colorsChanged = { [weak self] in
            guard let self else {return}
            if self.headingAnimated {self.setHeading(self.plainHeading,animated:true)}
            self.refreshQuotaLoading()
            self.refreshTaskProgress()
            if self.userInputPrefixLength > 0,let storage = self.text.textStorage,storage.length >= self.userInputPrefixLength {
                let accent = NSColor(cgColor:AppAppearance.resolvedColor(AppAccent.color,for:self.window.effectiveAppearance))!
                storage.addAttribute(.foregroundColor,value:accent,range:NSRange(location:0,length:self.userInputPrefixLength))
            }
        }
        text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
        // 正文宽度由气泡布局统一提供，不随滚动条显隐自动拉伸。
        text.isVerticallyResizable = false; text.isHorizontallyResizable = false; text.autoresizingMask = []
        text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width:0,height:2)
        text.textContainer?.lineFragmentPadding = 0 // 水平留白由 BubbleBodyLayout 统一分配。
        text.textColor = .labelColor
        text.onContentLayoutChange = { [weak self] in
            guard let self,self.scroll.documentView === self.text else {return}
            self.layoutTextBody(); self.onCardLayout()
        }
        scroll.setBody(text,height:0)
        closeButton.onClose = { [weak self] in self?.hide(); self?.onClose() }
        details = ActionButton("查看记录详情") { [weak self] in
            guard let self else{return}
            if let form = self.questionForm,let submit = self.onQuestionSubmit {
                if !form.isLast {form.advance(); return}
                self.window.makeFirstResponder(nil)
                guard form.complete else {return}
                if form.answers.isEmpty {self.onQuestionsSkipped?(form.skippedIDs); self.resolveQuestions(taskKey:self.questionTaskKey); return}
                let taskKey = self.questionTaskKey, skipped = self.onQuestionsSkipped
                form.isSubmitting = true; self.updateCardNavigation()
                self.previousQuestion.isEnabled = false; self.skipQuestion.isEnabled = false; self.details.isEnabled = false; self.details.title = "正在提交…"
                submit(form.answers) { [weak self,weak form] error in
                    guard let self,let form else {return}
                    form.isSubmitting = false; self.updateCardNavigation()
                    if let error {
                        if self.questionForm === form {
                            self.previousQuestion.isEnabled = form.canGoBack; self.skipQuestion.isEnabled = form.canSkip
                            self.details.isEnabled = form.canAdvance; self.details.title = form.actionTitle
                        }
                        showError("回答未提交",error)
                    } else {
                        skipped?(form.skippedIDs); self.resolveQuestions(taskKey:taskKey,form:form)
                    }
                }
                return
            }
            let action = self.onDetails
            self.hide(); self.onClose(); action()
        }
        approvalReject = ActionButton("拒绝") { [weak self] in self?.submitApproval(false) }
        approvalAllow = ActionButton("允许这一次") { [weak self] in self?.submitApproval(true) }
        for button in [approvalReject!,approvalAllow!] {
            button.acceptsKeyboardActivation = false; button.keyEquivalent = ""
            button.imagePosition = .imageLeading
        }
        approvalReject.semanticColor = .systemRed; approvalAllow.semanticColor = .systemGreen
        approvalReject.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:nil)
        approvalAllow.image = NSImage(systemSymbolName:"checkmark",accessibilityDescription:nil)
        approvalReject.isHidden = true; approvalAllow.isHidden = true
        previousCard = ActionButton("") { [weak self] in self?.navigateCard(-1) }
        nextCard = ActionButton("") { [weak self] in self?.navigateCard(1) }
        replyButton = ActionButton("快捷回复") { [weak self] in
            guard let self,let index = self.cardIndex,let action = self.cards[index].reply else {return}
            self.hide(); action()
        }
        replyButton.keepsAccentWhenInactive = true; replyButton.emphasize()
        for (button,symbol,name) in [(previousCard!,"chevron.left","上一条消息"),(nextCard!,"chevron.right","下一条消息")] {
            button.image = NSImage(systemSymbolName:symbol,accessibilityDescription:name)
            button.imagePosition = .imageOnly; button.setAccessibilityLabel(name)
        }
        cardCount.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); cardCount.textColor = .secondaryLabelColor; cardCount.alignment = .center
        [previousCard!,nextCard!,replyButton!,cardCount].forEach {$0.isHidden = true}
        previousQuestion = ActionButton("上一题") { [weak self] in self?.questionForm?.previousPage() }
        skipQuestion = ActionButton("跳过") { [weak self] in self?.questionForm?.skipPage() }
        previousQuestion.isHidden = true; skipQuestion.isHidden = true
        details.keepsAccentWhenInactive = true
        codexButton = ActionButton("转到 Codex") { [weak self] in
            guard let self else {return}
            let action = self.onCodex
            self.hide(); self.onClose(); action()
        }
        codexButton.image = AppIcons.openAI; codexButton.imagePosition = .imageLeading; codexButton.imageScaling = .scaleProportionallyDown
        codexButton.keepsAccentWhenInactive = true
        retryButton = ActionButton("重试") {}; retryButton.keepsAccentWhenInactive = true; retryButton.emphasize(); retryButton.isHidden = true
        elapsedIcon.image = NSImage(systemSymbolName:"stopwatch",accessibilityDescription:"任务已处理时间")
        elapsedIcon.contentTintColor = .secondaryLabelColor
        elapsedLabel.alignment = .right; elapsedLabel.textColor = .secondaryLabelColor
        elapsedIcon.isHidden = true; elapsedLabel.isHidden = true
        taskProgress.isHidden = true; taskProgress.textColor = .secondaryLabelColor
        taskProgressIcon.isHidden = true
        headingSpinner.isHidden = true; headingIcon.isHidden = true
        for v in [title,headingSpinner,headingIcon,scroll,closeButton,details,codexButton,retryButton,elapsedIcon,elapsedLabel,taskProgressIcon,taskProgress,previousQuestion!,skipQuestion!,approvalReject!,approvalAllow!,previousCard!,nextCard!,replyButton!,cardCount] as [NSView] { content.body.addSubview(v) }
    }
    private var actionButtons:[ActionButton] {[details,codexButton,replyButton,retryButton,previousCard,nextCard,previousQuestion,skipQuestion,approvalReject,approvalAllow]}
    private func configureButtons() {
        let fontSize = preferences.number("messageFontSize")*scale
        for button in actionButtons {button.configureFlexible(font:.systemFont(ofSize:fontSize))}
        cardCount.font = .monospacedDigitSystemFont(ofSize:max(11*scale,fontSize-2*scale),weight:.regular)
    }
    private var buttonHeight:CGFloat {max(28*scale,actionButtons.map {$0.intrinsicContentSize.height}.max() ?? 0)}
    private var usesCustomAspect:Bool {preferences.bool("bubbleAspectEnabled") && !kind.hasPrefix("quota") && questionModels.isEmpty}
    private var aspectWidth:CGFloat {sqrt(320*240*preferences.number("bubbleAspectRatio"))*scale}
    private var minimumLayoutWidth:CGFloat {
        if kind == "progressToast" {
            if usesCustomAspect {return max(280*scale,aspectWidth)}
            let font = NSFont.systemFont(ofSize:preferences.number("messageFontSize")*scale)
            let longest = currentBody.components(separatedBy:"\n").map {($0 as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0
            return min(360*scale,max(280*scale,longest+52*scale))
        }
        let gap = 8*scale
        var column = [details!,codexButton!,replyButton!,retryButton!,previousQuestion!,skipQuestion!,approvalReject!,approvalAllow!]
            .filter {!$0.isHidden}.map {$0.intrinsicContentSize.width}.max() ?? 0
        if !previousCard.isHidden {
            let count = max(cards.count,Int(preferences.number("bubbleCardLimit")))
            let countWidth = ("\(count) / \(count)" as NSString).size(withAttributes:[.font:cardCount.font!]).width.rounded(.up)
            column = max(column,2*(buttonHeight+gap)+countWidth)
        }
        let questionWidth = previousQuestion.isHidden ? 0 : 32*scale+2*gap+3*([previousQuestion!,skipQuestion!,details!].map {$0.intrinsicContentSize.width}.max() ?? 0)
        return max(usesCustomAspect ? aspectWidth : 320*scale,320*scale,32*scale+gap+2*column,questionWidth)
    }
    private var layoutWidth:CGFloat {min(max(questionSize?.width ?? 0,minimumLayoutWidth),kind == "progressToast" ? 360*scale : .greatestFiniteMagnitude,placementArea?.width ?? .greatestFiniteMagnitude)}
    private var bodyLayout:BubbleBodyLayout {BubbleBodyLayout(width:layoutWidth,scale:scale)}
    private func layout(bodyHeight: Double) {
        layoutBodyHeight = bodyHeight
        configureButtons()
        let w = layoutWidth, margin = 16*scale
        let bodyLayout = self.bodyLayout
        if !questionModels.isEmpty {window.minSize = NSSize(width:min(minimumLayoutWidth,placementArea?.width ?? minimumLayoutWidth),height:220*scale)}
        let hasElapsed = taskStartedAt != nil
        let elapsedWidth = hasElapsed ? elapsedGroupWidth : 0
        elapsedLayoutWidth = elapsedWidth
        let headingSpinnerWidth = headingSpinner.isHidden ? 0 : InlineStatusLayout.brailleFieldSize(font:title.font!).width+6*scale
        let headingPrefix = headingActivity == nil ? 0 : headingSpinnerWidth+headingIcon.layoutSize.width+6*scale
        let headingWidth = max(1,w-margin*2-32*scale-headingPrefix-(hasElapsed ? elapsedWidth+10*scale : 0))
        let font = title.font!
        let firstLineHeight = (font.ascender-font.descender+font.leading).rounded(.up)+4
        let headingHeight = max(firstLineHeight,title.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:headingWidth,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up))
        let buttonHeight = self.buttonHeight, gap = 8*scale
        let columnWidth = (w-2*margin-gap)/2
        let actionsHeight = details.isHidden && codexButton.isHidden && retryButton.isHidden ? 0 : buttonHeight+gap+(previousQuestion.isHidden ? 0 : buttonHeight+gap)
        let navigationHeight = previousCard.isHidden && replyButton.isHidden ? 0 : buttonHeight+gap
        let approvalHeight:CGFloat = approvalReject.isHidden ? 0 : buttonHeight+gap
        let footer = actionsHeight+navigationHeight+approvalHeight
        // 关闭、标题首行与计时同一行；标题按剩余宽度换行，不缩字或截断。
        let progressFont = taskProgress.font ?? .systemFont(ofSize:11*scale)
        let progressIconSize = taskProgressIcon.layoutSize
        let progressIconSide = progressIconSize.height
        let progressLineHeight = max(progressIconSide,ceil(progressFont.ascender-progressFont.descender+progressFont.leading)+2)
        let progressHeight = taskProgress.isHidden ? 0 : progressLineHeight+4*scale
        // 进展与标题为紧凑状态区；有进展时不再叠加原先 12pt 正文分隔。
        let bodyGap = bodyHeight > 0 ? (taskProgress.isHidden ? 12 : 4)*scale : 0
        let baseChromeHeight = margin*2+headingHeight+bodyGap+footer
        let chromeHeight = baseChromeHeight+progressHeight
        // 进展独占新增高度，包括启用宽高比时；不从原正文视口扣除。
        let desiredHeight:CGFloat = (usesCustomAspect ? max(baseChromeHeight+(bodyHeight > 0 ? 24*scale : 0),w/preferences.number("bubbleAspectRatio")) : baseChromeHeight+bodyHeight)+progressHeight
        let h = min(questionSize?.height ?? desiredHeight,kind == "progressToast" ? 180*scale : .greatestFiniteMagnitude,placementArea?.height ?? .greatestFiniteMagnitude)
        if truncatesProgressBody {fitToolProgressBody(height:max(0,h-chromeHeight),width:bodyLayout.contentWidth)}
        motion.onResize = { [weak self] size in
            guard let self else {return}
            let height = size.height
            self.title.frame = NSRect(x:margin+32*scale+headingPrefix,y:height-margin-headingHeight,width:headingWidth,height:headingHeight)
            if self.headingActivity != nil {
                let spinnerWidth = InlineStatusLayout.brailleFieldSize(font:font).width
                self.headingSpinner.font = font
                self.headingSpinner.frame = NSRect(x:margin+32*scale,y:self.title.frame.minY,width:spinnerWidth,height:headingHeight)
                InlineStatusLayout.alignBraille(self.headingSpinner,to:InlineStatusLayout.baseline(of:self.title))
                self.headingIcon.frame.origin.x = margin+32*scale+headingSpinnerWidth
                InlineStatusLayout.align(self.headingIcon,to:self.title,side:self.headingIcon.layoutSize.height,width:self.headingIcon.layoutSize.width)
            }
            if hasElapsed {self.layoutElapsed(in:size)}
            let progressY = self.title.frame.minY-progressHeight
            self.taskProgressIcon.frame = NSRect(x:bodyLayout.inset,y:progressY+(progressLineHeight-progressIconSide)/2,width:progressIconSize.width,height:progressIconSide)
            self.taskProgress.frame = NSRect(x:bodyLayout.inset+progressIconSize.width+6*scale,y:progressY,width:max(0,bodyLayout.contentWidth-progressIconSize.width-6*scale),height:progressLineHeight)
            InlineStatusLayout.align(self.taskProgressIcon,toLineIn:self.taskProgress,font:progressFont,side:progressIconSide,width:progressIconSize.width)
            if !self.taskProgress.isHidden {self.taskProgress.start()}
            let closeSide = 24*scale
            self.closeButton.frame = NSRect(x:margin-2*scale,y:height-margin-firstLineHeight/2-closeSide/2,width:closeSide,height:closeSide)
            InlineStatusLayout.align(self.closeButton,to:self.title,side:closeSide)
            self.closeButton.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭气泡")?.withSymbolConfiguration(.init(pointSize:13*scale,weight:.regular))
            let textHeight = max(0,height-chromeHeight)
            let viewport = bodyLayout.viewport(y:margin+footer,height:ceil(textHeight))
            self.scroll.setViewport(viewport)
            self.scroll.isHidden = bodyHeight <= 0
            // 两列共享边界与控件高度；翻页留在左下，正文高度不影响导航位置。
            let navigationY = margin, actionY = navigationY+navigationHeight
            let allowOnLeft = self.preferences.string("approvalButtonOrder") == "allowLeft"
            self.approvalReject.frame = NSRect(x:allowOnLeft ? margin+columnWidth+gap : margin,y:actionY+actionsHeight,width:columnWidth,height:buttonHeight)
            self.approvalAllow.frame = NSRect(x:allowOnLeft ? margin : margin+columnWidth+gap,y:actionY+actionsHeight,width:columnWidth,height:buttonHeight)
            self.previousQuestion.frame = NSRect(x:margin,y:actionY+buttonHeight+gap,width:columnWidth,height:buttonHeight)
            self.skipQuestion.frame = NSRect(x:margin+columnWidth+gap,y:actionY+buttonHeight+gap,width:columnWidth,height:buttonHeight)
            self.previousCard.frame = NSRect(x:margin,y:navigationY,width:buttonHeight,height:buttonHeight)
            let countHeight = self.cardCount.intrinsicContentSize.height
            self.cardCount.frame = NSRect(x:margin+buttonHeight+gap,y:navigationY+(buttonHeight-countHeight)/2,width:columnWidth-2*(buttonHeight+gap),height:countHeight)
            self.nextCard.frame = NSRect(x:margin+columnWidth-buttonHeight,y:navigationY,width:buttonHeight,height:buttonHeight)
            self.replyButton.frame = NSRect(x:margin+columnWidth+gap,y:navigationY,width:columnWidth,height:buttonHeight)
            self.retryButton.frame = NSRect(x:margin+columnWidth+gap,y:actionY,width:columnWidth,height:buttonHeight)
            if !self.previousQuestion.isHidden {
                // 题目导航固定一行：上一题、跳过、下一题／提交；Codex 跳转独立一行。
                let questionColumn = (w-2*margin-2*gap)/3
                let questionY = actionY+buttonHeight+gap
                self.previousQuestion.frame = NSRect(x:margin,y:questionY,width:questionColumn,height:buttonHeight)
                self.skipQuestion.frame = NSRect(x:margin+questionColumn+gap,y:questionY,width:questionColumn,height:buttonHeight)
                self.details.frame = NSRect(x:margin+2*(questionColumn+gap),y:questionY,width:questionColumn,height:buttonHeight)
                self.codexButton.frame = NSRect(x:margin,y:actionY,width:w-2*margin,height:buttonHeight)
            } else if !self.codexButton.isHidden && self.details.isHidden {
                self.codexButton.frame = NSRect(x:margin,y:actionY,width:w-2*margin,height:buttonHeight)
            } else if !self.codexButton.isHidden {
                self.codexButton.frame = NSRect(x:margin,y:actionY,width:columnWidth,height:buttonHeight)
                self.details.frame = NSRect(x:margin+columnWidth+gap,y:actionY,width:columnWidth,height:buttonHeight)
            } else {
                self.details.frame = self.retryButton.isHidden ? NSRect(x:margin,y:actionY,width:w-2*margin,height:buttonHeight) : NSRect(x:margin,y:actionY,width:columnWidth,height:buttonHeight)
            }
        }
        motion.resize(to:NSSize(width:w,height:h))
        window.refreshContentCursor()
    }
    private func layoutQuestions() {
        let width = bodyLayout.contentWidth
        let document:NSView
        if let questionForm {
            questionForm.updateAppearance(scale:scale,fontSize:preferences.number("messageFontSize")*scale)
            questionForm.reflow(width:width); document = questionForm
        }
        else {document = TaskQuestionLayout.document(questionModels,width:width,scale:scale,fontSize:preferences.number("messageFontSize")*scale)}
        scroll.setBody(document,height:document.frame.height)
        layout(bodyHeight:min(320*scale,document.frame.height))
    }

    func show(title heading: String, body: String = "", kind: String, scale: Double, seconds: Double = 4, details enabled: Bool = false, resetText: Bool = false, animateHeading: Bool = false, attentionAction: Bool = false, questions:[TaskQuestion] = [], timing:TaskTiming? = nil, fromCard:Bool = false,preserveCountdown:Bool = false,laysOutBody:Bool = true,fileEdits:[FileEditSummary] = [],isUserInput:Bool = false,truncateBody:Bool = false,completionFooter:TranscriptActions? = nil,failure:AppFailure? = nil,headingActivity:TaskActivity? = nil) {
        stopQuotaLoading()
        taskList?.stop(); taskList = nil
        userInputPrefixLength = 0
        if (attentionAction && !questions.isEmpty || !laysOutBody) && !text.string.isEmpty {text.releaseRenderedContent()}
        if !fromCard {saveCardForm(); approval = nil; cardStore.clearSelection(); renderedCardID = nil; updateCardNavigation()}
        let taskKey = timing?.key
        if !preserveCountdown {countdown.stop()}
        if !visible || kind == "interaction" && !isBrowsingCards {placement = nil; placementSide = nil}
        let same = self.kind == kind && scroll.documentView === text
        self.kind = kind; self.scale = scale; displayedFailure = failure
        self.headingActivity = kind == "progressToast" ? headingActivity : attentionAction ? .waiting(approval:timing?.status == "waitingForApproval" || approval != nil) : nil
        headingIcon.isHidden = self.headingActivity == nil
        headingSpinner.isHidden = self.headingActivity == nil || self.headingActivity?.kind == .attention || self.headingActivity?.finished == true
        headingIcon.update(self.headingActivity,pointSize:max(16,preferences.number("messageFontSize"))*scale)
        TaskActivityAppearance.apply(self.headingActivity,icon:headingIcon,visible:true)
        pendingAttention = attentionAction
        let previousForm = questionTaskKey == taskKey ? questionForm : nil
        let sameQuestions = questionTaskKey == taskKey && questionModels == questions
        if !sameQuestions {questionForm = nil; questionSize = nil}
        questionTaskKey = taskKey; questionModels = questions
        if !questions.isEmpty {
            window.styleMask.insert(.resizable); window.minSize = NSSize(width:320*scale,height:220*scale)
            window.maxSize = window.screen?.visibleFrame.insetBy(dx:8,dy:8).size ?? NSSize(width:1200,height:900)
        }
        else {window.styleMask.remove(.resizable)}
        previousQuestion.isHidden = true; skipQuestion.isHidden = true
        window.allowsInput = kind == "task" || approval != nil || (!questions.isEmpty && onQuestionSubmit != nil)
        approvalReject.isHidden = approval == nil; approvalAllow.isHidden = approval == nil
        approvalReject.keyEquivalent = ""
        approvalAllow.keyEquivalent = ""
        approvalReject.isEnabled = approval?.ready == true
        approvalAllow.isEnabled = approval?.ready == true && approval?.request.canAllow == true
        approvalAllow.title = approval?.request.allowTitle ?? "允许这一次"
        window.defaultButtonCell = nil
        activityTiming = timing
        configureElapsed(start:timing?.start,key:taskKey,finished:timing?.finished,status:timing?.status)
        refreshTaskProgress(relayout:false)
        // 只有任务消息正文允许复制；互动、额度加载及一般提示不参与文本选择。
        text.isSelectable = kind == "task"
        if !text.isSelectable {text.setSelectedRange(NSRange(location:0,length:0))}
        currentBody = body; relatedConversation = nil
        truncatesProgressBody = kind == "progressToast" && truncateBody
        scroll.allowsScrolling = !truncatesProgressBody
        title.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale,weight:.semibold)
        title.maximumNumberOfLines = kind == "progressToast" ? 1 : 0
        title.lineBreakMode = kind == "progressToast" ? .byTruncatingTail : .byWordWrapping
        title.hoverHelp = kind == "progressToast" ? heading : nil
        setHeading(heading, animated: animateHeading && timing?.finished == nil)
        let bodyFont = NSFont.systemFont(ofSize:preferences.number("messageFontSize")*scale)
        if let failure {onDetails = {failure.showDetails()}}
        details.title = failure == nil ? "查看记录详情" : "技术详情…"; details.isEnabled = true; details.isHidden = !enabled || attentionAction; details.emphasize(replyButton.isHidden); retryButton.isHidden = true
        codexButton.isHidden = !enabled; codexButton.emphasize(attentionAction && approval == nil)
        configureButtons()
        if attentionAction && !questions.isEmpty {
            if onQuestionSubmit != nil && questions.allSatisfy({!$0.id.isEmpty}) {
                if questionForm == nil {
                    questionForm = QuestionForm(questions:questions,width:288*scale,scale:scale,fontSize:preferences.number("messageFontSize")*scale)
                    if let previousForm {questionForm?.restoreDrafts(from:previousForm)}
                }
                questionForm?.onChange = { [weak self] in
                    guard let self,let form = self.questionForm else {return}
                    self.details.isEnabled = form.canAdvance; self.details.title = form.actionTitle
                    self.previousQuestion.isEnabled = form.canGoBack; self.skipQuestion.isEnabled = form.canSkip
                }
                questionForm?.onNavigate = { [weak self] in
                    guard let self else {return}; self.layoutQuestions()
                    self.scroll.showTop()
                }
                questionForm?.onSkipAll = { [weak self] in
                    guard let self,let form = self.questionForm else {return}
                    self.onQuestionsSkipped?(form.skippedIDs); self.resolveQuestions(taskKey:self.questionTaskKey)
                }
                previousQuestion.isHidden = false; skipQuestion.isHidden = false
                previousQuestion.isEnabled = questionForm?.canGoBack == true; skipQuestion.isEnabled = questionForm?.canSkip == true
                questionForm?.onSubmit = { [weak self] in self?.details.performClick(nil) }
                details.title = submittingQuestion ? "正在提交…" : questionForm?.actionTitle ?? "提交回答"; details.emphasize(); details.isHidden = false; details.isEnabled = !submittingQuestion && questionForm?.canAdvance == true
                codexButton.emphasize(false)
            }
            layoutQuestions()
            if resetText || !sameQuestions {
                scroll.showTop()
            }
        } else if laysOutBody {
            let rendered = approval.map {ApprovalText.render($0,font:bodyFont)} ?? (isUserInput ? MarkdownText.renderUserInput(body,font:bodyFont) : kind == "task" ? MarkdownText.render(body,font:bodyFont,lineSpacing:2,paragraphSpacing:6) : NSAttributedString(string:body,attributes:[.font:bodyFont,.foregroundColor:NSColor.labelColor]))
            let content = NSMutableAttributedString(attributedString:rendered)
            if isUserInput && !body.isEmpty {
                // 发言人标记仅在气泡排版时添加，原始提问与历史正文保持原文。
                let accent = NSColor(cgColor:AppAppearance.resolvedColor(AppAccent.color,for:window.effectiveAppearance))!
                let prefix = NSAttributedString(string:preferences.ownerName+"：",attributes:[.font:bodyFont,.foregroundColor:accent])
                content.insert(prefix,at:0)
                userInputPrefixLength = prefix.length
            }
            if !fileEdits.isEmpty {
                if content.length > 0 {content.append(NSAttributedString(string:"\n\n",attributes:[.font:bodyFont]))}
                content.append(FileEditRendering.render(fileEdits,font:bodyFont,id:timing?.key ?? renderedCardID ?? "standalone"))
            }
            if let footer = completionFooter {
                if content.length > 0 {content.append(NSAttributedString(string:"\n",attributes:[.font:bodyFont]))}
                content.append(TranscriptActions(id:footer.id,text:footer.text,threadID:footer.threadID,font:bodyFont,
                    status:footer.status,completedAt:footer.completedAt,usage:footer.usage,usageError:footer.usageError,showsActions:false).placeholder())
            }
            let changed = text.setContent(content,reset:!same || resetText)
            layoutTextBody()
            if changed {scroll.showTop()}
        }
        motion.show()
        refreshTaskProgress(relayout:false)
        if !taskProgress.isHidden {taskProgress.start()}
        if !preserveCountdown {startCountdown(attentionAction ? 0 : seconds)}
        refreshStandalone = fromCard ? nil : { [weak self] in
            guard let self else {return}
            self.show(title:heading,body:body,kind:kind,scale:self.preferences.number("bubblePercent")/100,seconds:seconds,
                details:enabled,resetText:false,animateHeading:animateHeading,attentionAction:attentionAction,
                questions:questions,timing:timing,preserveCountdown:true,fileEdits:fileEdits,isUserInput:isUserInput,truncateBody:truncateBody,completionFooter:completionFooter,failure:failure,headingActivity:headingActivity)
        }
    }
    private func fitToolProgressBody(height:CGFloat,width:CGFloat) {
        let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:preferences.number("messageFontSize")*scale),.foregroundColor:NSColor.labelColor]
        func measure(_ body:String) -> CGFloat {
            text.setContent(NSAttributedString(string:body,attributes:attributes))
            return text.contentHeight(for:width)
        }
        var fittedHeight = measure(currentBody)
        if fittedHeight > height {
            let source = currentBody as NSString
            var low = 0, high = source.length, fitted = "..."
            while low <= high {
                let middle = (low+high)/2
                let end = middle < source.length ? source.rangeOfComposedCharacterSequence(at:middle).location : middle
                let candidate = source.substring(to:end).trimmingCharacters(in:.whitespacesAndNewlines)+"..."
                if measure(candidate) <= height {fitted = candidate; low = middle+1}
                else {high = middle-1}
            }
            fittedHeight = measure(fitted)
        }
        scroll.setBody(text,height:min(height,fittedHeight))
        scroll.showTop()
    }
    private func layoutTextBody() {
        let naturalHeight = text.contentHeight(for:bodyLayout.contentWidth)
        scroll.setBody(text,height:naturalHeight)
        let limit:CGFloat = kind == "progressToast" ? .greatestFiniteMagnitude : (approval == nil ? 180 : 320)*scale
        layout(bodyHeight:min(limit,naturalHeight))
    }
    private func submitApproval(_ allow:Bool) {
        guard let form = approval,form.ready,!allow || form.request.canAllow else {return}
        form.isSubmitting = true; renderCard()
        form.request.submit(allow:allow) { [weak self,weak form] error in
            guard let self,let form else {return}
            form.isSubmitting = false
            if let error {form.error = error.localizedDescription}
            else {form.submitted = true}
            // 回执仅更新原表单；后到的新请求、问卷和临时额度页面保持原状。
            if self.approval === form,self.cardIndex.flatMap({self.cards[$0].approval}) === form,self.visible {self.renderCard()}
            if error == nil {self.resolveApproval(form)}
        }
    }
    private func resolveApproval(_ form:ApprovalPresentation) {
        cardStore.remove {$0.approval === form}
        if approval === form {approval = nil; window.defaultButtonCell = nil; hide()}
        else {updateCardNavigation()}
    }
    private func setHeading(_ heading: String, animated: Bool) {
        if plainHeading != heading || headingTimer == nil {headingStarted = ProcessInfo.processInfo.systemUptime}
        plainHeading = heading
        headingAnimated = animated
        if !animated {
            headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0
            title.stringValue = heading; title.textColor = .labelColor; return
        }
        if !ProgressTextEffects.enabled {
            headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0
            renderAnimatedHeading(); return
        }
        renderAnimatedHeading()
        guard headingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.headingPhase = Int((ProcessInfo.processInfo.systemUptime-self.headingStarted)*10) % self.headingFrames.count
            self.renderAnimatedHeading()
        }
        headingTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func renderAnimatedHeading() {
        let font = title.font ?? .systemFont(ofSize:13,weight:.semibold)
        let elapsed = ProcessInfo.processInfo.systemUptime-headingStarted
        if headingActivity != nil {
            headingSpinner.font = font
            headingSpinner.attributedStringValue = InlineStatusLayout.braille(headingFrames[headingPhase],font:font,color:AppAccent.color)
            title.attributedStringValue = ProgressTextEffects.title(plainHeading,font:font,appearance:title.effectiveAppearance,elapsed:elapsed)
        } else {
            title.attributedStringValue = ProgressTextEffects.heading(plainHeading,font:font,appearance:title.effectiveAppearance,elapsed:elapsed,frame:headingFrames[headingPhase])
        }
    }

    private func configureElapsed(start: Date?, key: String?, finished: Date?, status: String?) {
        if start == taskStartedAt && key == timedTaskKey && finished == taskFinishedAt && elapsedTimer != nil {return}
        elapsedTimer?.invalidate(); elapsedTimer = nil
        taskStartedAt = start; timedTaskKey = key; taskFinishedAt = finished
        setElapsedColor(finished == nil ? nil : status)
        elapsedIcon.isHidden = start == nil; elapsedLabel.isHidden = start == nil
        guard start != nil else {return}
        refreshElapsed()
        guard finished == nil else {return}
        let timer = Timer(timeInterval:0.2,repeats:true) { [weak self] _ in
            guard let self else {return}
            self.refreshElapsed(); self.refreshTaskProgress()
        }
        elapsedTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func refreshActivity(timing:TaskTiming) -> Bool {
        guard visible,kind == "task",!pendingAttention,activityTiming?.finished == nil,
              activityTiming?.key == timing.key,activityTiming?.start == timing.start else {return false}
        refreshTaskProgress(); return true
    }
    private func refreshTaskProgress(relayout:Bool = true) {
        let activity:TaskActivity?
        // 外部 key 包含会话与轮次；内置 activityKey 是真实轮次身份，再核对开始时间。
        // 仅任务主气泡显示，额度、2 秒进展小气泡与审批／问卷不加这一行。
        if let failure = displayedFailure,let symbol = failure.statusSymbol {
            activity = TaskActivity(title:failure.title,kind:.status,statusSymbol:symbol)
        } else if kind == "task",!pendingAttention,taskFinishedAt == nil,
           let timing = activityTiming,
           let task = taskProvider().tasks.first(where:{timing.matchesActivity(key:$0.key,start:$0.start) && $0.active}),
           task.activity?.visible == true {activity = task.activity}
        else {activity = nil}
        let activityKey = activityTiming?.activityKey ?? activityTiming?.key
        if progressTaskKey != activityKey {
            taskProgress.stop(); taskProgress.stringValue = ""; progressTaskKey = activityKey
        }
        let wasHidden = taskProgress.isHidden
        taskProgress.font = .systemFont(ofSize:11*scale*preferences.number("messageFontSize")/13)
        taskProgress.stringValue = activity?.line ?? ""
        taskProgress.hoverHelp = activity?.text
        taskProgress.isHidden = taskProgress.stringValue.isEmpty
        taskProgressIcon.isHidden = taskProgress.isHidden
        let previousIconSize = taskProgressIcon.layoutSize
        taskProgressIcon.update(activity,pointSize:max(15*scale,taskProgress.font!.pointSize*15/11))
        TaskActivityAppearance.apply(activity,icon:taskProgressIcon,text:taskProgress,visible:visible && !taskProgress.isHidden)
        if taskProgress.isHidden {taskProgress.stop()}
        else if visible {taskProgress.start()}
        if relayout,(wasHidden != taskProgress.isHidden || previousIconSize != taskProgressIcon.layoutSize),visible {
            layout(bodyHeight:layoutBodyHeight); onCardLayout()
        }
    }
    private var elapsedGroupWidth: CGFloat {
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.regular)
        elapsedLabel.maximumNumberOfLines = 1; elapsedLabel.usesSingleLineMode = true
        return elapsedLabel.fittingSize.width+16*scale
    }
    private func setElapsedColor(_ status: String?) {
        let color: NSColor = status == "completed" ? .systemGreen : ["failed","interrupted","cancelled","canceled"].contains(status ?? "") ? .systemRed : .secondaryLabelColor
        elapsedIcon.contentTintColor = color; elapsedLabel.textColor = color
    }
    private func layoutElapsed(in size: NSSize) {
        let margin = 16*scale, side = 13*scale
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.regular)
        elapsedLabel.maximumNumberOfLines = 1; elapsedLabel.usesSingleLineMode = true
        let textSize = elapsedLabel.fittingSize
        // 使用原生标签的第一行基线，不以整个多行标题的矩形中心对齐。
        let baseline = InlineStatusLayout.baseline(of:title)
        elapsedLabel.frame = NSRect(x:size.width-margin-textSize.width,y:0,width:textSize.width,height:textSize.height)
        InlineStatusLayout.align(elapsedLabel,to:baseline)
        elapsedIcon.frame = NSRect(x:elapsedLabel.frame.minX-3*scale-side,y:0,width:side,height:side)
        InlineStatusLayout.align(elapsedIcon,to:elapsedLabel,side:side)
    }
    private func refreshElapsed() {
        guard let start = taskStartedAt else {return}
        let value = TaskTiming.elapsed(start:start,end:taskFinishedAt ?? Date())
        if elapsedLabel.stringValue != value {
            elapsedLabel.stringValue = value; elapsedLabel.setAccessibilityLabel("已处理 "+value)
        }
        if visible && abs(elapsedGroupWidth-elapsedLayoutWidth) > 0.5 {layout(bodyHeight:layoutBodyHeight)}
        layoutElapsed(in:window.frame.size)
    }
    func finishTask(_ key: String, status: String) {
        cardStore.finishTask(key,status:status)
        guard timedTaskKey == key else {return}
        taskFinishedAt = Date(); setElapsedColor(status)
        refreshTaskProgress()
        setHeading(plainHeading,animated:false)
        refreshElapsed(); elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil
    }
    private func startCountdown(_ seconds:Double) {
        countdown.start(seconds,paused:{ [weak self] in
            guard let self else {return false}
            return self.preferences.bool("pauseOnHover") && self.window.frame.contains(NSEvent.mouseLocation)
        },expired:{ [weak self] in self?.hide(); self?.onClose() })
    }
    func refreshDuration() {if visible {startCountdown(pendingAttention || kind == "error" ? 0 : kind == "progressToast" ? preferences.number("progressToastSeconds") : preferences.duration(purpose,text:currentBody))}}
    func showFailure(_ failure: AppFailure, scale: Double, retry: (() -> Void)? = nil, taskStartedAt: Date? = nil, taskFinishedAt: Date? = nil, taskStatus: String? = nil) {
        onDetails = {failure.showDetails()}
        show(title:taskStatus.map {preferences.taskResultLine($0)} ?? failure.title, body:failure.message, kind:"error", scale:scale, seconds:0, details:true, timing:.init(start:taskStartedAt,finished:taskFinishedAt,status:taskStatus),failure:failure)
        purpose = .attention
        details.title = "技术详情…"
        codexButton.isHidden = true
        if let retry {retryButton.title = "重试"; retryButton.isHidden = false; retryButton.callback = retry}
        else if failure.openDesktop {retryButton.title = "打开 Codex"; retryButton.isHidden = false; retryButton.callback = {CodexConnection.openDesktop()}}
        layout(bodyHeight:scroll.frame.height)
        refreshStandalone = { [weak self] in
            guard let self else {return}
            self.showFailure(failure,scale:self.preferences.number("bubblePercent")/100,retry:retry,taskStartedAt:taskStartedAt,taskFinishedAt:taskFinishedAt,taskStatus:taskStatus)
        }
    }
    private func stopQuotaLoading() {
        quotaLoadingTimer?.invalidate(); quotaLoadingTimer = nil; quotaLoadingAmount = nil; quotaLoadingPhase = 0
    }
    private func renderQuotaLoading() {
        guard let field = quotaLoadingAmount else {return}
        let font = field.font ?? .systemFont(ofSize:13)
        let value = NSMutableAttributedString(attributedString:InlineStatusLayout.braille(headingFrames[quotaLoadingPhase],font:font,color:AppAccent.color))
        value.append(NSAttributedString(string:" 加载中",attributes:[.font:font,.foregroundColor:NSColor.labelColor]))
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        value.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:value.length))
        field.attributedStringValue = value
    }
    private func refreshQuotaLoading() {
        guard quotaLoadingAmount != nil else {return}
        if !ProgressTextEffects.enabled {
            quotaLoadingTimer?.invalidate(); quotaLoadingTimer = nil; quotaLoadingPhase = 0
        }
        renderQuotaLoading()
        guard ProgressTextEffects.enabled,quotaLoadingTimer == nil else {return}
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else {return}
            self.quotaLoadingPhase = (self.quotaLoadingPhase+1) % self.headingFrames.count
            self.renderQuotaLoading()
        }
        quotaLoadingTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func quotaRows(_ overview: QuotaOverview, scale: Double, failure: AppFailure? = nil, cachedAt:Date? = nil, retry: (() -> Void)? = nil) {
        stopQuotaLoading()
        let fontScale = scale*preferences.number("messageFontSize")/13
        if let failure {
            purpose = .attention; countdown.stop()
            codexButton.isHidden = true
            onDetails = {failure.showDetails()}; details.title = "技术详情…"; details.isHidden = false; details.emphasize(false)
            if let retry {retryButton.title = "重试"; retryButton.callback = retry; retryButton.isHidden = false}
        } else if cachedAt != nil,let retry {
            retryButton.title = "立即刷新"; retryButton.callback = retry; retryButton.isHidden = false
        }
        configureButtons()
        let width = bodyLayout.contentWidth
        let content = TopDownView(frame:NSRect(x:0,y:0,width:width,height:1))
        var y = 0.0
        @discardableResult func addText(_ value: String, font: NSFont, color: NSColor = .labelColor) -> CGFloat {
            let text = label(value); text.font = font; text.textColor = color
            let height = max(font.pointSize+5,(value as NSString).boundingRect(with:NSSize(width:width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height.rounded(.up)+3)
            text.frame = NSRect(x:0,y:y,width:width,height:height); content.addSubview(text); y += height
            return height
        }
        addText("套餐 · "+overview.plan,font:.systemFont(ofSize:13*fontScale,weight:.semibold))
        if let cachedAt {
            addText("缓存 · 更新于 "+cachedAt.formatted(date:.omitted,time:.standard),font:.systemFont(ofSize:11*fontScale),color:.secondaryLabelColor)
        }
        y += 12*scale
        for (index,row) in overview.rows.enumerated() {
            if index > 0 {
                let line = NSBox(frame:NSRect(x:0,y:y,width:width,height:1)); line.boxType = .separator; content.addSubview(line); y += 12*scale
            }
            let headingFont = NSFont.systemFont(ofSize:12*fontScale,weight:.medium)
            let amountFont = NSFont.monospacedDigitSystemFont(ofSize:13*fontScale,weight:.semibold)
            // 使用单行原生标签的 fittingSize，包含文字单元格内边距；
            // 只按 NSString 字宽分配空间会让“剩余 55%”换行并被固定行高裁掉。
            let heading = NSTextField(labelWithString:row.title); heading.font = headingFont
            let amount = NSTextField(labelWithString:row.value); amount.font = amountFont; amount.alignment = .right
            let quotaColor: NSColor? = row.remaining.flatMap {$0 <= 5 ? .systemRed : $0 <= 10 ? .systemOrange : nil}
            amount.textColor = quotaColor ?? .labelColor
            if row.loading {quotaLoadingAmount = amount; renderQuotaLoading(); amount.setAccessibilityLabel("本机今日用量加载中")}
            for field in [heading,amount] {
                field.maximumNumberOfLines = 1; field.usesSingleLineMode = true
                field.lineBreakMode = .byTruncatingTail
            }
            let gap = 12*scale
            let headingMinimum = min(heading.fittingSize.width,96*scale)
            let amountWidth = min(amount.fittingSize.width.rounded(.up),width-headingMinimum-gap)
            let rowHeight = max(22*scale,max(heading.fittingSize.height,amount.fittingSize.height).rounded(.up))
            if row.wrapsValue,amount.fittingSize.width+heading.fittingSize.width+gap > width {
                heading.frame = NSRect(x:0,y:y,width:width,height:rowHeight); y += rowHeight
                amount.usesSingleLineMode = false; amount.maximumNumberOfLines = 0; amount.lineBreakMode = .byWordWrapping
                let height = max(rowHeight,amount.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:10000)).height.rounded(.up))
                amount.frame = NSRect(x:0,y:y,width:width,height:height); y += height
            } else {
                heading.frame = NSRect(x:0,y:y,width:width-amountWidth-gap,height:rowHeight)
                amount.frame = NSRect(x:width-amountWidth,y:y,width:amountWidth,height:rowHeight); y += rowHeight
            }
            content.addSubview(heading); content.addSubview(amount)
            if let amount = row.remaining {
                y += 4*scale
                let bar = AccentProgressIndicator(frame:NSRect(x:0,y:y,width:width,height:9*scale))
                bar.progressColor = quotaColor
                bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = amount
                content.addSubview(bar); y += 16*scale
            }
            if let detail = row.detail {addText(detail,font:.systemFont(ofSize:11*fontScale),color:.secondaryLabelColor)}
            if row.retry,let retry {
                let button = ActionButton("重试",retry); button.bezelStyle = .inline
                button.font = .systemFont(ofSize:12*fontScale)
                button.frame = NSRect(x:0,y:y,width:60*scale,height:26*scale)
                content.addSubview(button); y += button.frame.height
            }
            y += 12*scale
        }
        if let notice = overview.notice {addText(notice,font:.systemFont(ofSize:11*fontScale,weight:.medium))}
        let management = SubscriptionManagementButton(management:overview.management,font:.systemFont(ofSize:12*fontScale))
        management.frame = NSRect(x:0,y:y,width:min(width,management.intrinsicContentSize.width+12*scale),height:max(24*scale,management.intrinsicContentSize.height))
        content.addSubview(management); y += management.frame.height+4*scale
        content.frame.size.height = y
        scroll.setBody(content,height:y)
        layout(bodyHeight:y); scroll.showTop()
        refreshQuotaLoading()
        let heading = plainHeading
        refreshStandalone = { [weak self] in
            guard let self else {return}
            let scale = self.preferences.number("bubblePercent")/100
            self.show(title:heading,body:" ",kind:"quota",scale:scale,seconds:0,preserveCountdown:true)
            self.quotaRows(overview,scale:scale,failure:failure,cachedAt:cachedAt,retry:retry)
        }
    }
    private var placementObstacles = [CGRect]()
    func place(near rect: CGRect, screen: NSScreen, dock: String?, avoiding:[CGRect] = []) {
        let area = screen.visibleFrame.insetBy(dx:8,dy:8)
        if placementArea != area {
            let previousWidth = layoutWidth
            placementArea = area
            if !questionModels.isEmpty {
                window.maxSize = area.size
                if let size = questionSize {questionSize = NSSize(width:min(size.width,area.width),height:min(size.height,area.height))}
                layoutQuestions()
            } else if layoutWidth != previousWidth {
                // 屏幕限制改变正文宽度时，重新生成内容与自然高度，不沿用旧行数。
                if cardIndex != nil {renderCard()}
                else if let refreshStandalone {refreshStandalone()}
                else {layout(bodyHeight:layoutBodyHeight)}
            } else {layout(bodyHeight:layoutBodyHeight)}
        }
        let size = motion.frame.size
        if let previous = placement,previous.0 == rect,previous.1 == dock,previous.2 == area,previous.3 == size,placementObstacles == avoiding {return}
        placementObstacles = avoiding
        let preferred:[BubblePlacement.Side]
        if kind == "progressToast" {preferred = [.above,.below,.right,.left]}
        else if dock == "notch" {preferred = [.left,.right,.below,.above]}
        else if dock == "left" {preferred = [.right,.above,.below,.left]}
        else if dock == "right" {preferred = [.left,.above,.below,.right]}
        else if kind.hasPrefix("quota") {preferred = [.right,.left,.above,.below]}
        else if kind == "task" || kind == "preview" {preferred = [.left,.right,.above,.below]}
        else {preferred = [.above,.below,.right,.left]}
        let oldSide = placement?.1 == dock ? placementSide : nil
        let result = BubblePlacement.resolve(size:size,pet:rect,screen:screen.visibleFrame,preferred:preferred,previous:oldSide,avoiding:avoiding)
        // 上下方始终重新锚定角色；侧向气泡仅在方向不变且原位置安全时保留原点。
        let current = CGRect(origin:motion.frame.origin,size:size)
        let keepOrigin = (result.side == .left || result.side == .right) && placementSide == result.side
            && placement.map {$0.0 == rect && $0.1 == dock && $0.2 == area} == true
            && area.contains(current) && !current.intersects(rect.insetBy(dx:-4,dy:-4))
            && !avoiding.contains {current.intersects($0.insetBy(dx:-4,dy:-4))}
        if !keepOrigin {
            motion.keepsTopEdge = result.side == .below
            move(to:result.frame.origin); placementSide = result.side
        }
        placement = (rect,dock,area,size)
    }
    deinit { countdown.stop(); headingTimer?.invalidate(); quotaLoadingTimer?.invalidate(); elapsedTimer?.invalidate() }
    private func releaseHiddenDisplay() {
        // 卡片及问卷草稿已由 cardStore 保存；淡出结束后释放当前显示的独立持有。
        window.makeFirstResponder(nil)
        scroll.documentView = nil; taskList = nil
        text.releaseRenderedContent(); text.hoverHelp = nil
        currentBody = ""; plainHeading = ""; title.stringValue = ""; title.hoverHelp = nil
        headingActivity = nil; headingSpinner.stringValue = ""; headingSpinner.isHidden = true; headingIcon.update(nil,pointSize:16*scale); headingIcon.isHidden = true; TaskActivityAppearance.stop(headingIcon)
        refreshStandalone = nil; renderedCardID = nil
        TaskActivityAppearance.stop(taskProgressIcon); taskProgressIcon.update(nil,pointSize:15*scale); displayedFailure = nil; taskProgress.stop(); taskProgress.stringValue = ""; taskProgress.hoverHelp = nil; taskProgress.isHidden = true; taskProgressIcon.isHidden = true; progressTaskKey = nil; activityTiming = nil
        questionForm = nil; questionModels.removeAll(); questionSize = nil; questionTaskKey = nil
        onQuestionSubmit = nil; onQuestionsSkipped = nil; approval = nil; pendingAttention = false
        onDetails = {}; onCodex = {CodexConnection.openDesktop()}; retryButton.callback = {}
    }
    func hide() {TaskActivityAppearance.stop(taskProgressIcon); TaskActivityAppearance.stop(headingIcon); displayedFailure = nil; taskProgress.stop(); stopQuotaLoading(); window.defaultButtonCell = nil; saveCardForm(); cardStore.stopBrowsing(); taskList?.stop(); elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil; headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0; countdown.stop(); motion.hide(); placement = nil; placementSide = nil; kind = ""; relatedConversation = nil}
}
