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
    func move(to origin: NSPoint, screenFrame:CGRect? = nil) {
        motion.move(to:origin)
        closeButtonScreenMidX = (screenFrame ?? window.screen?.visibleFrame)?.midX
        refreshCloseButtonPosition()
    }
    private let title = BubbleHeadingField(wrappingLabelWithString:"")
    private let headingSpinner = NSTextField(labelWithString:"")
    private let headingIcon = TaskActivitySymbolView(frame:.zero)
    private var headingActivity:TaskActivity?
    private let text = MessageTextView()
    private let scroll = BubbleBodyScrollView()
    private let workspace = WorkspaceStatusView()
    private var workspaceContextAvailable = false
    private var workspaceAttached = false, workspaceSuppressed = false, preparingDisplay = false
    var workspaceProvider:(String) -> (conversation:Conversation,executing:Bool)? = {_ in nil}
    var onVisibilityChange:() -> Void = {}
    private let closeButton = BubbleCloseButton()
    private var closeButtonOnRight = false
    private var closeButtonScreenMidX:CGFloat?
    private var closeButtonPreferenceObserver:NSObjectProtocol?
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
    private var quotaBody: QuotaBubbleBody?
    private var plainHeading = ""
    private var headingPhase = 0
    private var headingStarted = 0.0
    private var headingAnimated = false
    private var renderedHeadingSignature = ""
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
    private var headingHeight:CGFloat = 0
    private var elapsedLayoutWidth = 0.0
    private var scale = 1.0
    var preferences = PetPreferences.shared
    var purpose: MessagePurpose = .interaction
    var relatedConversation: String?
    var fileLinkDirectory: (() -> URL?)? {didSet {text.linkBaseDirectory = fileLinkDirectory}}
    private var currentBody = ""
    private var questionForm:QuestionForm?
    private var previousQuestion:ActionButton!
    private var skipQuestion:ActionButton!
    var onQuestionsSkipped: ((Set<String>) -> Void)?
    private var questionModels = [TaskQuestion]()
    private var questionSize:NSSize?
    private var questionTaskKey:String?
    private var pendingAttention = false
    private struct MonitoredPresentation:Equatable {
        let conversation:String, taskKey:String, turn:String?, source:String, label:String
    }
    private var monitoredPresentation:MonitoredPresentation?
    private let resizeDelegate = QuestionResizeDelegate()
    var onQuestionSubmit: (([String:String], @escaping (Error?) -> Void) -> Void)?
    var onClose: () -> Void = {}
    var onDetails: () -> Void = {}
    var onCodex: () -> Void = {CodexConnection.openDesktop()}
    var kind = ""
    var visible: Bool { motion.presented }
    var hasWorkspaceContext:Bool {workspaceAttached}
    var acceptsTransientInteraction:Bool {
        !visible || (!pendingAttention && questionForm == nil && !submittingQuestion &&
            (cardIndex.map {cards[$0].priority == .companion} ?? (purpose == .interaction || purpose == .preview)))
    }
    var blocksProgressToast:Bool {visible && (pendingAttention || questionForm != nil || submittingQuestion || isBrowsingCards)}
    func showProgressToast(_ content:TaskActivity.ProgressToast,timing:TaskTiming,conversation:String? = nil) {
        onQuestionSubmit = nil; onQuestionsSkipped = nil
        show(title:content.heading.title,body:content.body,kind:"progressToast",scale:preferences.number("bubblePercent")/100,
             seconds:preferences.number("progressToastSeconds"),animateHeading:true,timing:timing,headingActivity:content.heading,conversation:conversation)
        purpose = .progress
    }
    func resolveQuestions(taskKey:String? = nil,form:QuestionForm? = nil) {
        let affected = cards.filter {card in
            card.attentionAction && (taskKey == nil || card.content.timing?.key == taskKey) && (form == nil || card.form === form)
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
        cardStore.remove {$0.content.timing?.key == taskKey && $0.id.hasSuffix(":activity")}
        if currentID != nil && cardIndex == nil {hide()}
        else {updateCardNavigation()}
    }
    func discardCards(conversation:String? = nil) {
        cardStore.remove {conversation == nil || $0.content.conversation == conversation}
        if cardIndex == nil {hide()}
        updateCardNavigation()
    }
    private func saveCardForm() {
        guard renderedCardID != nil,renderedCardID == cardStore.selectedID else {return}
        cardStore.saveForm(questionForm,size:questionSize)
    }
    @discardableResult func present(_ message:BubbleCard,select:Bool = false) -> Bool {
        saveCardForm()
        let render = cardStore.present(message,select:select,limit:Int(preferences.number("bubbleCardLimit")),
            wasVisible:visible,protectsInput:submittingQuestion || questionForm != nil,pendingAttention:pendingAttention)
        if render {renderCard()}
        else {updateCardNavigation(); layout(bodyHeight:layoutBodyHeight); onCardLayout()}
        return render
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
        questionForm = card.form; questionModels = card.form?.questions ?? card.question?.questions ?? []; questionTaskKey = card.content.timing?.key; questionSize = card.questionSize
        onQuestionSubmit = card.question?.submit; onQuestionsSkipped = card.question?.skip
        onDetails = card.details; onCodex = card.codex; approval = card.approval
        updateCardNavigation()
        render(card.content,card:card,scale:preferences.number("bubblePercent")/100,
               seconds:preferences.duration(card.purpose,text:card.content.body),details:card.content.conversation != nil,
               resetText:card.resetText || changedCard,preserveCountdown:refreshingAppearance)
        purpose = card.purpose
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
                self.layout(bodyHeight:min(320*self.scale,height)); self.onCardLayout()
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
        let content = BubbleBackgroundView(clipsToRoundedBounds:true)
        window.contentView = content
        workspace.isHidden = true
        workspace.onOpen = {FinderFileReveal.openDirectory($0)}
        workspace.onStatusChange = { [weak self] in self?.updateWorkspacePresentation() }
        content.body.addSubview(workspace)
        title.isSelectable = false; title.font = .boldSystemFont(ofSize:13)
        title.colorsChanged = { [weak self] in
            guard let self else {return}
            self.renderedHeadingSignature = ""
            if self.headingAnimated {self.setHeading(self.plainHeading,animated:true)}
            self.quotaBody?.refreshLoadingAppearance()
            self.refreshTaskProgress()
            if self.userInputPrefixLength > 0,let storage = self.text.textStorage,storage.length >= self.userInputPrefixLength {
                let accent = NSColor(cgColor:AppAppearance.resolvedColor(AppAccent.foregroundColor,for:self.window.effectiveAppearance))!
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
        closeButtonPreferenceObserver = NotificationCenter.default.addObserver(
            forName:PetPreferences.didChange,object:nil,queue:.main
        ) { [weak self] note in
            guard let self,note.object as? PetPreferences === self.preferences,
                  (note.userInfo?["keys"] as? [String])?.contains(BubbleCloseButtonPosition.key) == true,
                  self.visible else {return}
            self.refreshCloseButtonPosition()
        }
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
        previousQuestion = ActionButton("< 上一题") { [weak self] in self?.questionForm?.previousPage() }
        skipQuestion = ActionButton("跳过") { [weak self] in self?.questionForm?.skipPage() }
        previousQuestion.isHidden = true; skipQuestion.isHidden = true
        details.keepsAccentWhenInactive = true
        codexButton = ActionButton("转到 Codex") { [weak self] in
            guard let self else {return}
            let action = self.onCodex
            self.approval?.request.handoffToCodex()
            self.hide(); self.onClose(); action()
        }
        codexButton.image = AppIcons.openAI; codexButton.imagePosition = .imageLeading; codexButton.imageScaling = .scaleProportionallyDown
        codexButton.keepsAccentWhenInactive = true
        retryButton = ActionButton("重试") {}; retryButton.keepsAccentWhenInactive = true; retryButton.emphasize(); retryButton.isHidden = true
        elapsedIcon.image = NSImage(systemSymbolName:"stopwatch",accessibilityDescription:"任务已处理时间")
        elapsedIcon.contentTintColor = .labelColor
        elapsedLabel.alignment = .right; elapsedLabel.textColor = .labelColor
        elapsedIcon.isHidden = true; elapsedLabel.isHidden = true
        taskProgress.isHidden = true; taskProgress.textColor = .secondaryLabelColor
        taskProgressIcon.isHidden = true
        headingSpinner.isHidden = true; headingIcon.isHidden = true
        for v in [title,headingSpinner,headingIcon,scroll,closeButton,details,codexButton,retryButton,elapsedIcon,elapsedLabel,taskProgressIcon,taskProgress,previousQuestion!,skipQuestion!,approvalReject!,approvalAllow!,previousCard!,nextCard!,replyButton!,cardCount] as [NSView] { content.body.addSubview(v) }
    }
    func suppressWorkspace(_ suppressed:Bool) {
        guard workspaceSuppressed != suppressed else {return}
        workspaceSuppressed = suppressed; refreshWorkspace()
    }
    func refreshWorkspace(relayout:Bool = true) {
        guard visible || preparingDisplay else {return}
        let oldAttached = workspaceAttached
        let eligible = preferences.bool("taskInfoBarEnabled") && !workspaceSuppressed && !pendingAttention && (kind == "task" || kind == "progressToast")
        if eligible,let key = relatedConversation,let context = workspaceProvider(key) {
            let fontSize = 11*scale*preferences.number("messageFontSize")/13
            workspace.configure(compact:true,fontSize:fontSize)
            workspaceContextAvailable = true
            workspace.update(conversation:context.conversation,executing:context.executing,visible:true,turnKey:activityTiming?.activityKey ?? activityTiming?.key,turnStart:activityTiming?.start)
        } else {
            workspaceContextAvailable = false; workspace.deactivate()
        }
        updateWorkspacePresentation(relayout:false)
        if relayout && !preparingDisplay && oldAttached != workspaceAttached {
            layout(bodyHeight:layoutBodyHeight); onCardLayout()
        }
    }
    private func updateWorkspacePresentation(relayout:Bool = true) {
        let wasAttached = workspaceAttached
        workspaceAttached = workspaceContextAvailable && workspace.hasStatus
        workspace.isHidden = !workspaceAttached
        if relayout && !preparingDisplay && visible && wasAttached != workspaceAttached {
            layout(bodyHeight:layoutBodyHeight); onCardLayout()
        }
    }
    private var actionButtons:[ActionButton] {[details,codexButton,replyButton,retryButton,previousCard,nextCard,previousQuestion,skipQuestion,approvalReject,approvalAllow]}
    private func configureButtons() {
        let fontSize = preferences.number("messageFontSize")*scale
        for button in actionButtons {button.configureFlexible(font:.systemFont(ofSize:fontSize))}
        details.hoverHelp = questionForm == nil ? nil : preferences.sendShortcut.hint
        cardCount.font = .monospacedDigitSystemFont(ofSize:max(11*scale,fontSize-2*scale),weight:.regular)
    }
    private var buttonHeight:CGFloat {max(28*scale,actionButtons.map {$0.intrinsicContentSize.height}.max() ?? 0)}
    private var usesCustomAspect:Bool {preferences.bool("bubbleAspectEnabled") && kind != "progressToast" && !kind.hasPrefix("quota") && questionModels.isEmpty}
    private var aspectWidth:CGFloat {sqrt(320*240*preferences.number("bubbleAspectRatio"))*scale}
    private var spinnerWidth:CGFloat {headingSpinner.isHidden ? 0 : InlineStatusLayout.brailleFieldSize(font:title.font!).width+6*scale}
    private func headingPrefixWidth(spinnerWidth:CGFloat) -> CGFloat {
        headingActivity == nil ? 0 : spinnerWidth+headingIcon.layoutSize.width+6*scale
    }
    private var minimumLayoutWidth:CGFloat {
        if kind == "progressToast" {
            let font = NSFont.systemFont(ofSize:preferences.number("messageFontSize")*scale)
            let detailWidth = (currentBody as NSString).size(withAttributes:[.font:font]).width+52*scale
            let elapsedWidth = taskStartedAt == nil ? 0 : elapsedGroupWidth+10*scale
            let titleWidth = (plainHeading as NSString).size(withAttributes:[.font:title.font!]).width+64*scale+headingPrefixWidth(spinnerWidth:spinnerWidth)+elapsedWidth
            return min(360*scale,max(280*scale,titleWidth,detailWidth))
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
        let quotaInset = BubbleBodyLayout(width:320*scale,scale:scale).inset
        let quotaWidth = kind == "quota" ? max(360*scale,(quotaBody?.requiredContentWidth ?? 0)+2*quotaInset) : 0
        return max(usesCustomAspect ? aspectWidth : 320*scale,320*scale,quotaWidth,32*scale+gap+2*column,questionWidth)
    }
    private var layoutWidth:CGFloat {min(max(questionSize?.width ?? 0,minimumLayoutWidth),kind == "progressToast" ? 360*scale : .greatestFiniteMagnitude,placementArea?.width ?? .greatestFiniteMagnitude)}
    private var bodyLayout:BubbleBodyLayout {BubbleBodyLayout(width:layoutWidth,scale:scale)}
    private var closeButtonSlotWidth:CGFloat {32*scale}
    private var headingReservedWidth:CGFloat {
        32*scale+closeButtonSlotWidth+(taskStartedAt == nil ? 0 : elapsedLayoutWidth+10*scale)
    }
    @discardableResult private func updateCloseButtonSide() -> Bool {
        let onRight = preferences.bubbleCloseButtonPosition.isOnRight(
            windowMidX:targetFrame.midX,screenMidX:closeButtonScreenMidX,wasOnRight:closeButtonOnRight)
        guard onRight != closeButtonOnRight else {return false}
        closeButtonOnRight = onRight
        return true
    }
    private func refreshCloseButtonPosition() {
        guard updateCloseButtonSide() else {return}
        layoutHeading(in:window.frame.size)
        window.refreshContentCursor()
    }
    private func layoutHeading(in size:NSSize) {
        let margin = 16*scale
        let prefixX = margin+(closeButtonOnRight ? 0 : closeButtonSlotWidth)
        let spinnerWidth = self.spinnerWidth
        let prefixWidth = headingPrefixWidth(spinnerWidth:spinnerWidth)
        title.frame = NSRect(x:prefixX+prefixWidth,y:size.height-margin-headingHeight,
                             width:max(1,size.width-headingReservedWidth-prefixWidth),height:headingHeight)
        if headingActivity != nil {
            headingSpinner.font = title.font
            headingSpinner.frame = NSRect(x:prefixX,y:title.frame.minY,width:spinnerWidth,height:headingHeight)
            if !headingSpinner.isHidden {
                InlineStatusLayout.alignBraille(headingSpinner,to:InlineStatusLayout.baseline(of:title))
            }
            headingIcon.frame.origin.x = prefixX+spinnerWidth
            InlineStatusLayout.align(headingIcon,to:title,side:headingIcon.layoutSize.height,width:headingIcon.layoutSize.width)
        }
        if taskStartedAt != nil {layoutElapsed(in:size)}
        let closeSide = 24*scale
        let inset = margin-2*scale
        closeButton.frame.origin.x = closeButtonOnRight ? size.width-inset-closeSide : inset
        InlineStatusLayout.align(closeButton,to:title,side:closeSide)
    }
    private func layout(bodyHeight: Double) {
        layoutBodyHeight = bodyHeight
        configureButtons()
        let w = layoutWidth, margin = 16*scale
        let bottomMargin = workspaceAttached ? 8*scale : margin
        let targetBodyLayout = self.bodyLayout
        if !questionModels.isEmpty {window.minSize = NSSize(width:min(minimumLayoutWidth,placementArea?.width ?? minimumLayoutWidth),height:220*scale)}
        elapsedLayoutWidth = taskStartedAt == nil ? 0 : elapsedGroupWidth
        let headingWidth = max(1,w-headingReservedWidth-headingPrefixWidth(spinnerWidth:spinnerWidth))
        let font = title.font!
        let firstLineHeight = (font.ascender-font.descender+font.leading).rounded(.up)+4
        headingHeight = max(firstLineHeight,title.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:headingWidth,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up))
        let buttonHeight = self.buttonHeight, gap = 8*scale
        let columnWidth = (w-2*margin-gap)/2
        let codexInNavigation = pendingAttention && !codexButton.isHidden
        let hasActionRow = !details.isHidden || !retryButton.isHidden || (!codexButton.isHidden && !codexInNavigation)
        let actionsHeight = hasActionRow ? buttonHeight+gap : 0
        let navigationHeight = previousCard.isHidden && replyButton.isHidden ? 0 : buttonHeight+gap
        let approvalHeight:CGFloat = approvalReject.isHidden ? 0 : buttonHeight+gap
        let workspaceHeight = workspaceAttached ? max(20*scale,workspace.fittingSize.height)+4*scale : 0
        let rawControlsFooter = actionsHeight+navigationHeight+approvalHeight
        let controlsFooter = rawControlsFooter-(workspaceAttached && rawControlsFooter > 0 ? gap-4*scale : 0)
        let footer = controlsFooter+workspaceHeight
        // 关闭、标题首行与计时同一行；标题按剩余宽度换行，不缩字或截断。
        let progressFont = taskProgress.font ?? .systemFont(ofSize:11*scale)
        let progressIconSize = taskProgressIcon.layoutSize
        let progressIconSide = progressIconSize.height
        let progressLineHeight = max(progressIconSide,ceil(progressFont.ascender-progressFont.descender+progressFont.leading)+2)
        let progressHeight = taskProgress.isHidden ? 0 : progressLineHeight+4*scale
        // 短进展直接接实际摘要，不额外预留标题下的空白；长消息保留正文分隔。
        let bodyGap = bodyHeight > 0 && kind != "progressToast" ? (taskProgress.isHidden ? 12 : 4)*scale : 0
        let baseChromeHeight = margin+bottomMargin+headingHeight+bodyGap+controlsFooter
        let chromeHeight = baseChromeHeight+progressHeight+workspaceHeight
        // 进展独占新增高度，包括启用宽高比时；不从原正文视口扣除。
        let desiredHeight:CGFloat = (usesCustomAspect ? max(baseChromeHeight+(bodyHeight > 0 ? 24*scale : 0),w/preferences.number("bubbleAspectRatio")) : baseChromeHeight+bodyHeight)+progressHeight+workspaceHeight
        let h = min(questionSize?.height ?? desiredHeight,kind == "progressToast" ? 180*scale+workspaceHeight : .greatestFiniteMagnitude,placementArea?.height ?? .greatestFiniteMagnitude)
        let targetTextHeight = ceil(max(0,h-chromeHeight))
        let isToast = kind == "progressToast"
        motion.onResize = { [weak self] size in
            guard let self else {return}
            let height = size.height
            let bodyLayout = isToast ? BubbleBodyLayout(width:size.width,scale:scale) : targetBodyLayout
            self.updateCloseButtonSide()
            self.layoutHeading(in:size)
            self.workspace.frame = NSRect(x:bodyLayout.inset,y:bottomMargin+controlsFooter,width:bodyLayout.contentWidth,height:max(0,workspaceHeight-4*scale))
            let progressY = self.title.frame.minY-progressHeight
            self.taskProgressIcon.frame = NSRect(x:bodyLayout.inset,y:progressY+(progressLineHeight-progressIconSide)/2,width:progressIconSize.width,height:progressIconSide)
            self.taskProgress.frame = NSRect(x:bodyLayout.inset+progressIconSize.width+6*scale,y:progressY,width:max(0,bodyLayout.contentWidth-progressIconSize.width-6*scale),height:progressLineHeight)
            InlineStatusLayout.align(self.taskProgressIcon,toLineIn:self.taskProgress,font:progressFont,side:progressIconSide,width:progressIconSize.width)
            if !self.taskProgress.isHidden {self.taskProgress.start()}
            let textHeight = max(0,height-chromeHeight)
            let viewport = bodyLayout.viewport(y:bottomMargin+footer,height:ceil(textHeight))
            self.scroll.setViewport(viewport,targetHeight:targetTextHeight)
            self.scroll.isHidden = self.scroll.bodyHeight <= 0
            // 两列共享边界与控件高度；翻页留在左下，正文高度不影响导航位置。
            let navigationY = bottomMargin, actionY = navigationY+navigationHeight
            let allowOnLeft = self.preferences.string("approvalButtonOrder") == "allowLeft"
            self.approvalReject.frame = NSRect(x:allowOnLeft ? margin+columnWidth+gap : margin,y:actionY+actionsHeight,width:columnWidth,height:buttonHeight)
            self.approvalAllow.frame = NSRect(x:allowOnLeft ? margin : margin+columnWidth+gap,y:actionY+actionsHeight,width:columnWidth,height:buttonHeight)
            self.previousCard.frame = NSRect(x:margin,y:navigationY,width:buttonHeight,height:buttonHeight)
            let countHeight = self.cardCount.intrinsicContentSize.height
            self.cardCount.frame = NSRect(x:margin+buttonHeight+gap,y:navigationY+(buttonHeight-countHeight)/2,width:columnWidth-2*(buttonHeight+gap),height:countHeight)
            self.nextCard.frame = NSRect(x:margin+columnWidth-buttonHeight,y:navigationY,width:buttonHeight,height:buttonHeight)
            self.replyButton.frame = NSRect(x:margin+columnWidth+gap,y:navigationY,width:columnWidth,height:buttonHeight)
            if codexInNavigation {self.codexButton.frame = self.replyButton.frame}
            self.retryButton.frame = NSRect(x:margin+columnWidth+gap,y:actionY,width:columnWidth,height:buttonHeight)
            if !self.previousQuestion.isHidden {
                let questionColumn = (w-2*margin-2*gap)/3
                self.previousQuestion.frame = NSRect(x:margin,y:actionY,width:questionColumn,height:buttonHeight)
                self.skipQuestion.frame = NSRect(x:margin+questionColumn+gap,y:actionY,width:questionColumn,height:buttonHeight)
                self.details.frame = NSRect(x:margin+2*(questionColumn+gap),y:actionY,width:questionColumn,height:buttonHeight)
            } else if !self.codexButton.isHidden && !codexInNavigation {
                self.codexButton.frame = NSRect(x:margin,y:actionY,width:self.details.isHidden ? w-2*margin : columnWidth,height:buttonHeight)
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

    func show(title:String,body:String = "",kind:String,scale:Double,seconds:Double = 4,details:Bool = false,
              animateHeading:Bool = false,timing:TaskTiming? = nil,preserveCountdown:Bool = false,
              failure:AppFailure? = nil,headingActivity:TaskActivity? = nil,conversation:String? = nil) {
        let content = BubbleContent(title:title,body:body,kind:kind,animateHeading:animateHeading,
                                    timing:timing,conversation:conversation,failure:failure)
        render(content,scale:scale,seconds:seconds,details:details,preserveCountdown:preserveCountdown,
               headingActivity:headingActivity)
    }

    private func render(_ message:BubbleContent,card:BubbleCard? = nil,scale:Double,seconds:Double,details enabled:Bool,
                        resetText:Bool = false,preserveCountdown:Bool,headingActivity:TaskActivity? = nil) {
        let kind = message.kind, heading = message.title, body = card?.approval?.body ?? message.body
        let timing = message.timing, failure = message.failure
        let attentionAction = card?.attentionAction == true, questions = card?.question?.questions ?? []
        let laysOutBody = card?.showsTaskOverview != true || !preferences.bool("showTaskOverview")
        preparingDisplay = true
        defer {preparingDisplay = false; onVisibilityChange()}
        quotaBody?.stop(); quotaBody = nil
        taskList?.stop(); taskList = nil
        userInputPrefixLength = 0
        if (attentionAction && !questions.isEmpty || !laysOutBody) && !text.string.isEmpty {text.releaseRenderedContent()}
        if card == nil {saveCardForm(); approval = nil; cardStore.clearSelection(); renderedCardID = nil; updateCardNavigation()}
        let taskKey = timing?.key
        if !preserveCountdown {countdown.stop()}
        if !visible || kind == "interaction" && !isBrowsingCards {placement = nil; placementSide = nil}
        let same = self.kind == kind && scroll.documentView === text
        self.kind = kind; self.scale = scale; displayedFailure = failure
        closeButton.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭气泡")?.withSymbolConfiguration(.init(pointSize:13*scale,weight:.regular))
        if kind != "progressToast" {motion.originXForWidth = nil}
        self.headingActivity = kind == "progressToast" ? headingActivity : attentionAction ? .waiting(approval:timing?.status == "waitingForApproval" || approval != nil) : nil
        headingIcon.isHidden = self.headingActivity == nil
        // 盲文表示整轮仍在执行，单个工具的结束状态留给操作图标与结果角标。
        headingSpinner.isHidden = kind != "progressToast" || self.headingActivity == nil || self.headingActivity?.kind == .attention || timing?.finished != nil
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
        refreshTaskProgress(relayout:false,recordPresentation:false)
        // 只有任务消息正文允许复制；互动、额度加载及一般提示不参与文本选择。
        text.isSelectable = kind == "task"
        if !text.isSelectable {text.setSelectedRange(NSRange(location:0,length:0))}
        currentBody = body; relatedConversation = message.conversation
        let isToast = kind == "progressToast"
        scroll.allowsScrolling = !isToast
        let bodyLines = isToast ? 1 : 0
        if let container = text.textContainer,container.maximumNumberOfLines != bodyLines {
            container.maximumNumberOfLines = bodyLines
            container.lineBreakMode = isToast ? .byTruncatingTail : .byWordWrapping
        }
        text.setHoverHelp(isToast && !body.isEmpty ? body : nil) { [weak text] in text?.hasTruncatedText == true }
        title.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale,weight:.semibold)
        title.maximumNumberOfLines = isToast ? 1 : 0
        title.lineBreakMode = isToast ? .byTruncatingTail : .byWordWrapping
        title.setHoverHelp(isToast ? heading : nil) { [weak title] in title?.hasTruncatedText == true }
        setHeading(heading, animated: message.animateHeading && timing?.finished == nil)
        refreshWorkspace(relayout:false)
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
            let rendered = approval.map {ApprovalText.render($0,font:bodyFont)} ?? (card?.isUserInput == true ? MarkdownText.renderUserInput(body,font:bodyFont) : kind == "task" ? MarkdownText.render(body,font:bodyFont,lineSpacing:2,paragraphSpacing:6) : NSAttributedString(string:body,attributes:[.font:bodyFont,.foregroundColor:NSColor.labelColor]))
            let content = NSMutableAttributedString(attributedString:rendered)
            if card?.isUserInput == true && !body.isEmpty {
                // 发言人标记仅在气泡排版时添加，原始提问与历史正文保持原文。
                let accent = NSColor(cgColor:AppAppearance.resolvedColor(AppAccent.foregroundColor,for:window.effectiveAppearance))!
                let prefix = NSAttributedString(string:preferences.ownerName+"：",attributes:[.font:bodyFont,.foregroundColor:accent])
                content.insert(prefix,at:0)
                userInputPrefixLength = prefix.length
            }
            if let fileEdits = card?.fileEdits,!fileEdits.isEmpty {
                if content.length > 0 {content.append(NSAttributedString(string:"\n\n",attributes:[.font:bodyFont]))}
                content.append(FileEditRendering.render(fileEdits,font:bodyFont,id:timing?.key ?? renderedCardID ?? "standalone"))
            }
            if let footer = card?.completionFooter {
                if content.length > 0 {content.append(NSAttributedString(string:"\n",attributes:[.font:bodyFont]))}
                content.append(TranscriptActions(footer,font:bodyFont,showsActions:false).placeholder())
            }
            let changed = text.setContent(content,reset:!same || resetText)
            layoutTextBody()
            if changed {scroll.showTop()}
        }
        motion.show()
        refreshTaskProgress(relayout:false)
        if !taskProgress.isHidden {taskProgress.start()}
        if !preserveCountdown {startCountdown(attentionAction ? 0 : seconds)}
        refreshStandalone = card != nil ? nil : { [weak self] in
            guard let self else {return}
            self.render(message,scale:self.preferences.number("bubblePercent")/100,seconds:seconds,details:enabled,
                        preserveCountdown:true,headingActivity:headingActivity)
        }
    }
    private func layoutTextBody() {
        let naturalHeight = text.contentHeight(for:bodyLayout.contentWidth)
        scroll.setBody(text,height:naturalHeight)
        let limit:CGFloat = kind == "progressToast" ? .greatestFiniteMagnitude : (approval == nil ? 180 : 320)*scale
        layout(bodyHeight:min(limit,naturalHeight))
    }
    private func submitApproval(_ allow:Bool) {
        guard let form = approval,form.ready,!allow || form.request.canAllow else {return}
        let context = TerminalMonitor.active.flatMap { _ in relatedConversation.map {TerminalMonitor.context($0,turn:form.request.turn)} }
        if let context {TerminalMonitor.active?.write(.approval,context+"  外部  ·  "+(allow ? "提交允许" : "提交拒绝"))}
        form.isSubmitting = true; renderCard()
        form.request.submit(allow:allow) { [weak self,weak form] error in
            if let context {
                if let error {TerminalMonitor.active?.write(.approval,context+"  外部审批未确认  ·  "+TerminalMonitor.errorCode(error),.warning)}
                else {TerminalMonitor.active?.write(.approval,context+(form?.request.isHook == true ? "  审批决定已交给 Hook" : "  外部审批已确认"),.success)}
            }
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
        renderedHeadingSignature = ""
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
            self.headingPhase = Int((ProcessInfo.processInfo.systemUptime-self.headingStarted)*10) % InlineStatusLayout.brailleFrames.count
            self.renderAnimatedHeading()
        }
        headingTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func renderAnimatedHeading() {
        let font = title.font ?? .systemFont(ofSize:13,weight:.semibold)
        let elapsed = ProcessInfo.processInfo.systemUptime-headingStarted
        let sweep = ProgressTextEffects.sweepTick(elapsed:elapsed)
        let appearanceName = title.effectiveAppearance.name.rawValue
        let hasActivity = headingActivity != nil
        let signature = "\(plainHeading)\u{0}\(headingPhase)\u{0}\(sweep)\u{0}\(hasActivity)\u{0}\(font.fontName)\u{0}\(font.pointSize)\u{0}\(appearanceName)"
        guard signature != renderedHeadingSignature else {return}
        if hasActivity {
            let previousTitleOnly = renderedHeadingSignature.split(separator:"\u{0}",omittingEmptySubsequences:false)
            headingSpinner.font = font
            headingSpinner.attributedStringValue = InlineStatusLayout.braille(InlineStatusLayout.brailleFrames[headingPhase],font:font,color:AppAccent.foregroundColor)
            let titleKey = "\(plainHeading)|\(sweep)|\(font.fontName)|\(font.pointSize)|\(appearanceName)"
            let oldTitleKey = previousTitleOnly.count == 7 ? "\(previousTitleOnly[0])|\(previousTitleOnly[2])|\(previousTitleOnly[4])|\(previousTitleOnly[5])|\(previousTitleOnly[6])" : ""
            if titleKey != oldTitleKey || previousTitleOnly.count != 7 || previousTitleOnly[3] != "true" {
                title.attributedStringValue = ProgressTextEffects.title(plainHeading,font:font,appearance:title.effectiveAppearance,elapsed:elapsed)
            }
        } else {
            title.attributedStringValue = ProgressTextEffects.heading(plainHeading,font:font,appearance:title.effectiveAppearance,elapsed:elapsed,frame:InlineStatusLayout.brailleFrames[headingPhase])
        }
        renderedHeadingSignature = signature
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
    private func refreshTaskProgress(relayout:Bool = true,recordPresentation:Bool = true) {
        let activity:TaskActivity?
        // 外部 key 包含会话与轮次；内置 activityKey 是真实轮次身份，再核对开始时间。
        // 仅任务主气泡显示，额度、2 秒进展小气泡与审批／问卷不加这一行。
        if let failure = displayedFailure,let symbol = failure.statusSymbol {
            activity = TaskActivity(title:failure.title,kind:.status,statusSymbol:symbol)
        } else if kind == "task",!pendingAttention,taskFinishedAt == nil,
           let timing = activityTiming,
           let task = taskProvider().tasks.first(where:{timing.matchesActivity(key:$0.key,start:$0.start) && $0.active}),
           let groupActivity = task.activity?.groupActivity,groupActivity.visible {activity = groupActivity}
        else {activity = nil}
        let activityKey = activityTiming?.activityKey ?? activityTiming?.key
        if progressTaskKey != activityKey {
            taskProgress.stop(); taskProgress.stringValue = ""; progressTaskKey = activityKey
        }
        let wasHidden = taskProgress.isHidden
        taskProgress.font = .systemFont(ofSize:11*scale*preferences.number("messageFontSize")/13)
        taskProgress.stringValue = activity?.line ?? ""
        taskProgress.setHoverHelp(activity?.text) { [weak taskProgress] in taskProgress?.textOverflows == true }
        taskProgress.isHidden = taskProgress.stringValue.isEmpty
        taskProgressIcon.isHidden = taskProgress.isHidden
        let previousIconSize = taskProgressIcon.layoutSize
        taskProgressIcon.update(activity,pointSize:max(15*scale,taskProgress.font!.pointSize*15/11))
        TaskActivityAppearance.apply(activity,icon:taskProgressIcon,text:taskProgress,visible:visible && !taskProgress.isHidden)
        if recordPresentation,visible,let monitor = TerminalMonitor.active {
            let shown = headingActivity ?? activity
            if let timing = activityTiming,let key = timing.key,let conversation = relatedConversation {
                let source = pendingAttention ? "待处理卡" : kind == "progressToast" ? "短进展" : "主气泡"
                let turn = key == "own" ? timing.activityKey : key.split(separator:":").last.map(String.init)
                let label = shown?.monitorLabel ?? timing.status.map(TerminalMonitor.status) ?? "无进展行"
                let next = MonitoredPresentation(conversation:conversation,taskKey:key,turn:turn,source:source,label:label)
                if next != monitoredPresentation {
                    var change = label
                    if let old = monitoredPresentation,old.conversation == conversation,old.taskKey == key,
                       old.turn == turn,old.label != label {change = old.label+" → "+label}
                    monitor.write(.bubble,TerminalMonitor.context(conversation,turn:turn)+"  "+source+"  ·  "+change)
                    monitoredPresentation = next
                }
            } else {monitoredPresentation = nil}
        }
        if taskProgress.isHidden {taskProgress.stop()}
        else if visible {taskProgress.start()}
        if relayout,(wasHidden != taskProgress.isHidden || previousIconSize != taskProgressIcon.layoutSize),visible {
            layout(bodyHeight:layoutBodyHeight); onCardLayout()
        }
    }
    private var elapsedGroupWidth: CGFloat {
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.medium)
        elapsedLabel.maximumNumberOfLines = 1; elapsedLabel.usesSingleLineMode = true
        return elapsedLabel.fittingSize.width+16*scale
    }
    private func setElapsedColor(_ status: String?) {
        let color = taskFinishedAt == nil ? NSColor.labelColor : status == "completed" ? StatusTextColor.green : ["failed","interrupted","cancelled","canceled"].contains(status ?? "") ? StatusTextColor.red : StatusTextColor.secondary
        elapsedIcon.contentTintColor = color; elapsedLabel.textColor = color
    }
    private func layoutElapsed(in size: NSSize) {
        let margin = 16*scale+(closeButtonOnRight ? closeButtonSlotWidth : 0), side = 13*scale
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:11*scale,weight:.medium)
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
            return self.workspace.hasPresentedDetails || self.taskList?.hasPresentedDetails == true || (self.preferences.bool("pauseOnHover") && self.window.frame.contains(NSEvent.mouseLocation))
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
        layout(bodyHeight:layoutBodyHeight)
        refreshStandalone = { [weak self] in
            guard let self else {return}
            self.showFailure(failure,scale:self.preferences.number("bubblePercent")/100,retry:retry,taskStartedAt:taskStartedAt,taskFinishedAt:taskFinishedAt,taskStatus:taskStatus)
        }
    }
    func quotaRows(_ overview:QuotaOverview, scale:Double, failure:AppFailure? = nil, cachedAt:Date? = nil,
                   retry:(() -> Void)? = nil, preserveScroll:Bool = false) {
        quotaBody?.stop()
        retryButton.isHidden = true
        if let failure {
            purpose = .attention; countdown.stop()
            codexButton.isHidden = true
            onDetails = {failure.showDetails()}; details.title = "技术详情…"; details.isHidden = false; details.emphasize(false)
        }
        configureButtons()
        let body = QuotaBubbleBody(overview,scale:scale,preferences:preferences,cachedAt:cachedAt,failed:failure != nil,retry:retry)
        quotaBody = body
        body.onLayoutChange = { [weak self,weak body] height, reveal in
            guard let self, let body, self.quotaBody === body else {return}
            self.scroll.setBody(body,height:height)
            self.layout(bodyHeight:height)
            if let reveal {body.scrollToVisible(reveal)}
            self.onCardLayout()
        }
        let height = body.arrange(width:bodyLayout.contentWidth)
        scroll.setBody(body,height:height)
        layout(bodyHeight:height)
        if !preserveScroll {scroll.showTop()}
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
        if kind == "progressToast" {
            motion.originXForWidth = {BubblePlacement.originX(width:$0,side:result.side,pet:rect,area:area)}
        }
        // 上下方始终重新锚定角色；侧向气泡仅在方向不变且原位置安全时保留原点。
        let current = CGRect(origin:motion.frame.origin,size:size)
        let keepOrigin = (result.side == .left || result.side == .right) && placementSide == result.side
            && placement.map {$0.0 == rect && $0.1 == dock && $0.2 == area} == true
            && area.contains(current) && !current.intersects(rect.insetBy(dx:-4,dy:-4))
            && !avoiding.contains {current.intersects($0.insetBy(dx:-4,dy:-4))}
        if !keepOrigin {
            motion.keepsTopEdge = result.side == .below
            move(to:result.frame.origin,screenFrame:screen.visibleFrame); placementSide = result.side
        }
        placement = (rect,dock,area,size)
    }
    deinit {
        if let closeButtonPreferenceObserver {NotificationCenter.default.removeObserver(closeButtonPreferenceObserver)}
        countdown.stop(); headingTimer?.invalidate(); quotaBody?.stop(); elapsedTimer?.invalidate()
    }
    private func releaseHiddenDisplay() {
        // 卡片及问卷草稿已由 cardStore 保存；淡出结束后释放当前显示的独立持有。
        window.makeFirstResponder(nil)
        scroll.documentView = nil; taskList = nil
        text.releaseRenderedContent(); text.hoverHelp = nil
        currentBody = ""; plainHeading = ""; renderedHeadingSignature = ""; title.stringValue = ""; title.hoverHelp = nil
        headingActivity = nil; headingSpinner.stringValue = ""; headingSpinner.isHidden = true; headingIcon.update(nil,pointSize:16*scale); headingIcon.isHidden = true; TaskActivityAppearance.stop(headingIcon)
        refreshStandalone = nil; renderedCardID = nil
        TaskActivityAppearance.stop(taskProgressIcon); taskProgressIcon.update(nil,pointSize:15*scale); displayedFailure = nil; taskProgress.stop(); taskProgress.stringValue = ""; taskProgress.hoverHelp = nil; taskProgress.isHidden = true; taskProgressIcon.isHidden = true; progressTaskKey = nil; activityTiming = nil
        questionForm = nil; questionModels.removeAll(); questionSize = nil; questionTaskKey = nil
        onQuestionSubmit = nil; onQuestionsSkipped = nil; approval = nil; pendingAttention = false
        onDetails = {}; onCodex = {CodexConnection.openDesktop()}; retryButton.callback = {}
    }
    func hide() {monitoredPresentation = nil; workspace.deactivate(); workspaceAttached = false; workspaceContextAvailable = false; workspace.isHidden = true; TaskActivityAppearance.stop(taskProgressIcon); TaskActivityAppearance.stop(headingIcon); displayedFailure = nil; taskProgress.stop(); quotaBody?.stop(); quotaBody = nil; window.defaultButtonCell = nil; saveCardForm(); cardStore.stopBrowsing(); taskList?.stop(); elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil; headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0; countdown.stop(); motion.hide(); placement = nil; placementSide = nil; kind = ""; relatedConversation = nil; onVisibilityChange()}
}
