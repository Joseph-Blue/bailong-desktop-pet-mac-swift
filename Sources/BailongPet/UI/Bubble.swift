import AppKit

final class Bubble {
    let window: PetWindow
    private lazy var motion = BubbleMotion(window:window,preferences:preferences)
    private var placement: (CGRect, String?, CGRect, NSSize)?
    private var placementSide:BubblePlacement.Side?
    private var placementArea:CGRect?
    var targetFrame: NSRect {motion.frame}
    func move(to origin: NSPoint) {motion.move(to:origin)}
    private let title = label("", bold:true)
    private let text = StreamingTextView()
    private let scroll = GutterScrollView()
    private let closeButton = BubbleCloseButton()
    private var details: ActionButton!
    private var codexButton: ActionButton!
    private var retryButton: ActionButton!
    private var previousCard:ActionButton!, nextCard:ActionButton!, replyButton:ActionButton!
    private let cardCount = NSTextField(labelWithString:"")
    private var cards = [BubbleCard]()
    private var cardIndex:Int?
    private var refreshStandalone:(() -> Void)?
    private var isBrowsingCards = false
    private var submittingQuestion:Bool {questionForm?.isSubmitting == true}
    var onCardLayout:() -> Void = {}
    var taskProvider:() -> BubbleTaskOverview = {BubbleTaskOverview(status:"任务同步尚未初始化")}
    private var taskList:BubbleTaskList?
    private var timer: Timer?
    private var headingTimer: Timer?
    private var plainHeading = ""
    private var headingPhase = 0
    private var headingStarted = 0.0
    private let elapsedIcon = NSImageView()
    private let elapsedLabel = NSTextField(labelWithString:"00:00")
    private var elapsedTimer: Timer?
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
    func resolveQuestions(taskKey:String? = nil,form:QuestionForm? = nil) {
        let affected = cards.filter {card in
            card.attentionAction && (taskKey == nil || card.timing?.key == taskKey) && (form == nil || card.form === form)
        }.map(\.id)
        let currentID = cardIndex.map {cards[$0].id}
        cards.removeAll {affected.contains($0.id)}
        cardIndex = currentID.flatMap {id in cards.firstIndex(where:{$0.id == id})}
        if (taskKey == nil && form == nil) || currentID.map({affected.contains($0)}) == true {
            questionForm = nil; questionModels = []; questionSize = nil; onQuestionSubmit = nil
            pendingAttention = false; questionTaskKey = nil
            hide()
        } else {updateCardNavigation(); layout(bodyHeight:layoutBodyHeight)}
    }
    func discardCards(conversation:String? = nil) {
        let currentID = cardIndex.map {cards[$0].id}
        cards.removeAll {conversation == nil || $0.thread == conversation}
        cardIndex = currentID.flatMap {id in cards.firstIndex(where:{$0.id == id})}
        if cardIndex == nil {hide()}
        updateCardNavigation()
    }
    private func saveCardForm() {
        guard let index = cardIndex,cards.indices.contains(index) else {return}
        cards[index].form = questionForm; cards[index].questionSize = questionSize
    }
    func present(_ message:BubbleCard,select:Bool = false) {
        saveCardForm()
        let currentID = cardIndex.map {cards[$0].id}, wasVisible = visible
        if let index = cards.firstIndex(where:{$0.id == message.id}) {
            var updated = message
            if message.question?.submit != nil {
                updated.form = cards[index].form; updated.questionSize = cards[index].questionSize
            }
            if message.showsTaskOverview {cards.remove(at:index); cards.append(updated)}
            else {cards[index] = updated}
        } else {cards.append(message)}
        // 只保留本次运行的近期卡片；等待回答的卡片和正在阅读的卡片不被裁掉。
        while cards.count > Int(preferences.number("bubbleCardLimit")),let old = cards.firstIndex(where:{$0.id != currentID && $0.id != message.id && !$0.attentionAction}) {cards.remove(at:old)}
        cardIndex = currentID.flatMap {id in cards.firstIndex(where:{$0.id == id})}
        let current = cardIndex.map {cards[$0]}
        // 概览与随机台词让位于任务消息；阅读对话、填写及提交问卷时不自动切卡。
        let protectsCurrent = submittingQuestion || questionForm != nil || (isBrowsingCards && current?.priority != .companion)
        let replacesCurrent = current.map {
            message.priority.rawValue > $0.priority.rawValue ||
            (message.priority == $0.priority && message.priority != .request)
        } ?? false
        // 主动发送或按键召回概览可选中新卡，但不打断待处理请求或问卷。
        let requestedCard = (select || message.showsTaskOverview) && !pendingAttention && questionForm == nil && !submittingQuestion
        if !wasVisible || cardIndex == nil || requestedCard || (!protectsCurrent && replacesCurrent) {
            if currentID != message.id {isBrowsingCards = false}
            cardIndex = cards.firstIndex(where:{$0.id == message.id}); renderCard()
        }
        else if currentID == message.id {renderCard()}
        else {updateCardNavigation(); layout(bodyHeight:layoutBodyHeight); onCardLayout()}
    }
    func refreshCardPreferences() {
        saveCardForm()
        let currentID = cardIndex.map {cards[$0].id}
        if !preferences.bool("showTaskOverview") {cards.removeAll {$0.showsTaskOverview}}
        while cards.count > Int(preferences.number("bubbleCardLimit")),
              let old = cards.firstIndex(where:{$0.id != currentID && !$0.attentionAction}) {cards.remove(at:old)}
        cardIndex = currentID.flatMap {id in cards.firstIndex(where:{$0.id == id})}
        if visible {
            if cardIndex != nil {renderCard()}
            else if currentID != nil {hide()}
        }
    }
    @discardableResult func refreshAppearance() -> Bool {
        saveCardForm()
        for index in cards.indices {cards[index].questionSize = nil}
        questionSize = nil
        guard visible else {return false}
        let origin = scroll.contentView.bounds.origin
        if cardIndex != nil {renderCard(refreshingAppearance:true)}
        else if let refreshStandalone {refreshStandalone()}
        else {return false}
        scroll.contentView.scroll(to:origin); scroll.reflectScrolledClipView(scroll.contentView)
        onCardLayout(); return true
    }
    private func navigateCard(_ delta:Int) {
        guard !submittingQuestion,let index = cardIndex,cards.indices.contains(index+delta) else {return}
        isBrowsingCards = true
        saveCardForm(); cardIndex = index+delta; renderCard()
    }
    private func updateCardNavigation() {
        let multiple = cardIndex != nil && cards.count > 1
        previousCard.isHidden = !multiple; nextCard.isHidden = !multiple; cardCount.isHidden = !multiple
        previousCard.isEnabled = !submittingQuestion && (cardIndex ?? 0) > 0
        nextCard.isEnabled = !submittingQuestion && (cardIndex ?? cards.count) < cards.count-1
        cardCount.stringValue = "\((cardIndex ?? 0)+1) / \(cards.count)"
        replyButton.isHidden = cardIndex.flatMap {cards[$0].reply} == nil
        replyButton.isEnabled = !submittingQuestion
    }
    private func renderCard(refreshingAppearance:Bool = false) {
        guard let index = cardIndex,cards.indices.contains(index) else {return}
        let card = cards[index]
        questionForm = card.form; questionModels = card.form?.questions ?? card.question?.questions ?? []; questionTaskKey = card.timing?.key; questionSize = card.questionSize
        onQuestionSubmit = card.question?.submit; onQuestionsSkipped = card.question?.skip
        onDetails = card.details; onCodex = card.codex
        updateCardNavigation()
        show(title:card.title,body:card.body,kind:card.kind,scale:preferences.number("bubblePercent")/100,seconds:preferences.duration(card.purpose,text:card.body),
             details:card.thread != nil,followsText:card.followsText,resetText:refreshingAppearance ? false : card.resetText,animateHeading:card.animateHeading,
             attentionAction:card.attentionAction,questions:card.question?.questions ?? [],timing:card.timing,fromCard:true,preserveCountdown:refreshingAppearance)
        relatedConversation = card.thread; purpose = card.purpose
        cards[index].form = questionForm
        if card.showsTaskOverview && preferences.bool("showTaskOverview") {
            let list = BubbleTaskList(width:GutterScrollView.documentWidth(for:scroll.frame.width),scale:scale*preferences.number("messageFontSize")/13,provider:{ [weak self] in
                self?.taskProvider() ?? BubbleTaskOverview(status:"任务同步已停止")
            })
            taskList = list; scroll.documentView = list
            list.onResize = { [weak self] height in guard let self else {return}; self.layout(bodyHeight:min(320*self.scale,height)); self.onCardLayout() }
            layout(bodyHeight:min(320*scale,list.frame.height)); list.start()
        }
        onCardLayout()
    }
    init() {
        window = PetWindow(contentRect:NSRect(x:0,y:0,width:320,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.hidesOnDeactivate = false
        window.worksWhenModal = true; window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces,.ignoresCycle,.fullScreenNone]
        window.delegate = resizeDelegate
        resizeDelegate.resized = { [weak self] in
            guard let self,!self.questionModels.isEmpty else {return}
            self.questionSize = self.window.frame.size; self.motion.adoptUserFrame()
            self.layoutQuestions()
        }
        let content = BubbleBackgroundView()
        window.contentView = content
        text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width:0,height:2)
        text.textColor = .labelColor
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
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
        previousCard = ActionButton("") { [weak self] in self?.navigateCard(-1) }
        nextCard = ActionButton("") { [weak self] in self?.navigateCard(1) }
        replyButton = ActionButton("快捷回复") { [weak self] in
            guard let self,let index = self.cardIndex,let action = self.cards[index].reply else {return}
            self.hide(); action()
        }
        replyButton.keepsAccentWhenInactive = true; replyButton.emphasize()
        for (button,symbol,name) in [(previousCard!,"chevron.left","上一条消息"),(nextCard!,"chevron.right","下一条消息")] {
            button.image = NSImage(systemSymbolName:symbol,accessibilityDescription:name)
            button.imagePosition = .imageOnly; button.hoverHelp = name; button.setAccessibilityLabel(name)
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
        for v in [title,scroll,closeButton,details,codexButton,retryButton,elapsedIcon,elapsedLabel,previousQuestion!,skipQuestion!,previousCard!,nextCard!,replyButton!,cardCount] as [NSView] { content.body.addSubview(v) }
    }
    private var actionButtons:[ActionButton] {[details,codexButton,replyButton,retryButton,previousCard,nextCard,previousQuestion,skipQuestion]}
    private func configureButtons() {
        let fontSize = preferences.number("messageFontSize")*scale
        for button in actionButtons {button.configureFlexible(font:.systemFont(ofSize:fontSize))}
        cardCount.font = .monospacedDigitSystemFont(ofSize:max(11*scale,fontSize-2*scale),weight:.regular)
    }
    private var buttonHeight:CGFloat {max(28*scale,actionButtons.map {$0.intrinsicContentSize.height}.max() ?? 0)}
    private var minimumLayoutWidth:CGFloat {
        let gap = 8*scale
        var column = [details!,codexButton!,replyButton!,retryButton!,previousQuestion!,skipQuestion!]
            .filter {!$0.isHidden}.map {$0.intrinsicContentSize.width}.max() ?? 0
        if !previousCard.isHidden {
            let count = max(cards.count,Int(preferences.number("bubbleCardLimit")))
            let countWidth = ("\(count) / \(count)" as NSString).size(withAttributes:[.font:cardCount.font!]).width.rounded(.up)
            column = max(column,2*(buttonHeight+gap)+countWidth)
        }
        return max(320*scale,32*scale+gap+2*column)
    }
    private var layoutWidth:CGFloat {min(max(questionSize?.width ?? 0,minimumLayoutWidth),placementArea?.width ?? .greatestFiniteMagnitude)}
    private func layout(bodyHeight: Double) {
        layoutBodyHeight = bodyHeight
        configureButtons()
        let w = layoutWidth, margin = 16*scale
        if !questionModels.isEmpty {window.minSize = NSSize(width:min(minimumLayoutWidth,placementArea?.width ?? minimumLayoutWidth),height:220*scale)}
        let hasElapsed = taskStartedAt != nil
        let elapsedWidth = hasElapsed ? elapsedGroupWidth : 0
        elapsedLayoutWidth = elapsedWidth
        let headingWidth = w-margin*2-32*scale-(hasElapsed ? elapsedWidth+10*scale : 0)
        let font = title.font!
        let firstLineHeight = (font.ascender-font.descender+font.leading).rounded(.up)+4
        let headingHeight = max(firstLineHeight,title.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:headingWidth,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up))
        let buttonHeight = self.buttonHeight, gap = 8*scale
        let columnWidth = (w-2*margin-gap)/2
        let actionsHeight = details.isHidden && codexButton.isHidden && retryButton.isHidden ? 0 : buttonHeight+gap+(previousQuestion.isHidden ? 0 : buttonHeight+gap)
        let navigationHeight = previousCard.isHidden && replyButton.isHidden ? 0 : buttonHeight+gap
        let footer = actionsHeight+navigationHeight
        // 关闭、标题首行与计时同一行；标题按剩余宽度换行，不缩字或截断。
        let h = min(questionSize?.height ?? (margin*2+headingHeight+(bodyHeight > 0 ? 12*scale+bodyHeight : 0)+footer),placementArea?.height ?? .greatestFiniteMagnitude)
        let chromeHeight = margin*2+headingHeight+(bodyHeight > 0 ? 12*scale : 0)+footer
        motion.onResize = { [weak self] size in
            guard let self else {return}
            let height = size.height
            self.title.frame = NSRect(x:margin+32*scale,y:height-margin-headingHeight,width:headingWidth,height:headingHeight)
            if hasElapsed {self.layoutElapsed(in:size)}
            let closeSide = 24*scale
            self.closeButton.frame = NSRect(x:margin-2*scale,y:height-margin-firstLineHeight/2-closeSide/2,width:closeSide,height:closeSide)
            self.closeButton.image = NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭气泡")?.withSymbolConfiguration(.init(pointSize:13*scale,weight:.regular))
            let textHeight = max(0,height-chromeHeight)
            self.scroll.frame = NSRect(x:margin,y:margin+footer,width:w-2*margin,height:textHeight)
            self.scroll.isHidden = bodyHeight <= 0
            self.text.frame.size.width = self.scroll.contentView.bounds.width
            self.text.textContainer?.containerSize = NSSize(width:self.scroll.contentView.bounds.width,height:CGFloat.greatestFiniteMagnitude)
            // 两列共享边界与控件高度；翻页留在左下，正文高度不影响导航位置。
            let navigationY = margin, actionY = navigationY+navigationHeight
            self.previousQuestion.frame = NSRect(x:margin,y:actionY+buttonHeight+gap,width:columnWidth,height:buttonHeight)
            self.skipQuestion.frame = NSRect(x:margin+columnWidth+gap,y:actionY+buttonHeight+gap,width:columnWidth,height:buttonHeight)
            self.previousCard.frame = NSRect(x:margin,y:navigationY,width:buttonHeight,height:buttonHeight)
            let countHeight = self.cardCount.intrinsicContentSize.height
            self.cardCount.frame = NSRect(x:margin+buttonHeight+gap,y:navigationY+(buttonHeight-countHeight)/2,width:columnWidth-2*(buttonHeight+gap),height:countHeight)
            self.nextCard.frame = NSRect(x:margin+columnWidth-buttonHeight,y:navigationY,width:buttonHeight,height:buttonHeight)
            self.replyButton.frame = NSRect(x:margin+columnWidth+gap,y:navigationY,width:columnWidth,height:buttonHeight)
            self.retryButton.frame = NSRect(x:margin+columnWidth+gap,y:actionY,width:columnWidth,height:buttonHeight)
            if !self.codexButton.isHidden && self.details.isHidden {
                self.codexButton.frame = NSRect(x:margin,y:actionY,width:w-2*margin,height:buttonHeight)
            } else if !self.codexButton.isHidden {
                self.codexButton.frame = NSRect(x:margin,y:actionY,width:columnWidth,height:buttonHeight)
                self.details.frame = NSRect(x:margin+columnWidth+gap,y:actionY,width:columnWidth,height:buttonHeight)
            } else {
                self.details.frame = self.retryButton.isHidden ? NSRect(x:margin,y:actionY,width:w-2*margin,height:buttonHeight) : NSRect(x:margin,y:actionY,width:columnWidth,height:buttonHeight)
            }
        }
        motion.resize(to:NSSize(width:w,height:h))
    }
    private func layoutQuestions() {
        let width = GutterScrollView.documentWidth(for:layoutWidth-32*scale)
        let document:NSView
        if let questionForm {
            questionForm.updateAppearance(scale:scale,fontSize:preferences.number("messageFontSize")*scale)
            questionForm.reflow(width:width); document = questionForm
        }
        else {document = TaskQuestionLayout.document(questionModels,width:width,scale:scale,fontSize:preferences.number("messageFontSize")*scale)}
        scroll.documentView = document
        layout(bodyHeight:min(320*scale,document.frame.height))
    }

    func show(title heading: String, body: String = "", kind: String, scale: Double, seconds: Double = 4, details enabled: Bool = false, followsText: Bool = true, resetText: Bool = false, animateHeading: Bool = false, attentionAction: Bool = false, questions:[TaskQuestion] = [], timing:TaskTiming? = nil, fromCard:Bool = false,preserveCountdown:Bool = false) {
        taskList?.stop(); taskList = nil
        if !fromCard {saveCardForm(); cardIndex = nil; isBrowsingCards = false; updateCardNavigation()}
        let taskKey = timing?.key
        if !preserveCountdown {timer?.invalidate()}
        if !visible || kind == "interaction" && !isBrowsingCards {placement = nil; placementSide = nil}
        let same = self.kind == kind && scroll.documentView === text && text.automaticallyFollowsEnd == followsText
        text.automaticallyFollowsEnd = followsText
        self.kind = kind; self.scale = scale
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
        window.allowsInput = !questions.isEmpty && onQuestionSubmit != nil
        configureElapsed(start:timing?.start,key:taskKey,finished:timing?.finished,status:timing?.status)
        // 只有任务消息正文允许复制；互动、额度加载及一般提示不参与文本选择。
        text.isSelectable = kind == "task"
        if !text.isSelectable {text.setSelectedRange(NSRange(location:0,length:0))}
        currentBody = body; relatedConversation = nil
        if scroll.documentView !== text {scroll.documentView = text}
        title.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale,weight:.semibold)
        setHeading(heading, animated: animateHeading)
        text.font = .systemFont(ofSize:preferences.number("messageFontSize")*scale)
        details.title = "查看记录详情"; details.isEnabled = true; details.isHidden = !enabled || attentionAction; details.emphasize(replyButton.isHidden); retryButton.isHidden = true
        codexButton.isHidden = !enabled; codexButton.emphasize(attentionAction)
        configureButtons()
        if attentionAction && !questions.isEmpty {
            text.finishReveal()
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
                    self.scroll.contentView.scroll(to:.zero); self.scroll.reflectScrolledClipView(self.scroll.contentView)
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
            scroll.contentView.scroll(to:.zero); scroll.reflectScrolledClipView(scroll.contentView)
        } else {
            let rendered = kind == "task" ? MarkdownText.render(body,font:text.font!,lineSpacing:2,paragraphSpacing:6) : NSAttributedString(string:body,attributes:[.font:text.font!,.foregroundColor:NSColor.labelColor])
            let height = body.isEmpty ? 0 : min(180*scale,max(24*scale,rendered.boundingRect(with:NSSize(width:GutterScrollView.documentWidth(for:layoutWidth-32*scale)-12,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height+12))
            layout(bodyHeight:height)
            text.setContent(rendered,animated:preferences.bool("typingEffect") && kind == "task" && followsText,reset:!same || resetText)
        }
        motion.show()
        if !preserveCountdown {startCountdown(attentionAction ? 0 : seconds)}
        refreshStandalone = fromCard ? nil : { [weak self] in
            guard let self else {return}
            self.show(title:heading,body:body,kind:kind,scale:self.preferences.number("bubblePercent")/100,seconds:seconds,
                details:enabled,followsText:followsText,resetText:false,animateHeading:animateHeading,attentionAction:attentionAction,
                questions:questions,timing:timing,preserveCountdown:true)
        }
    }
    private func setHeading(_ heading: String, animated: Bool) {
        if plainHeading != heading || headingTimer == nil {headingStarted = ProcessInfo.processInfo.systemUptime}
        plainHeading = heading
        if !animated {
            headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0
            title.stringValue = heading; return
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
        let value = NSMutableAttributedString(string:headingFrames[headingPhase] + " " + plainHeading,
            attributes:[.font:title.font ?? NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:NSColor.labelColor])
        value.addAttribute(.foregroundColor,value:AppAccent.color,range:NSRange(location:0,length:1))
        if preferences.bool("bubbleMotion") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // 1.2 秒扫过，2.8 秒停顿；前两字符是盲文和空格，不参与流水。
            let phase = (ProcessInfo.processInfo.systemUptime-headingStarted).truncatingRemainder(dividingBy:4)
            let center = -0.25+1.5*(phase/1.2)
            let dark = title.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
            var offset = 2
            let count = max(1,plainHeading.count-1)
            for (index,character) in plainHeading.enumerated() {
                let length = (String(character) as NSString).length
                let distance = (Double(index)/Double(count)-center)/0.18
                let strength = phase < 1.2 ? exp(-distance*distance) : 0
                // 浅色界面用深字浅扫；深色界面用灰字亮扫，亮带方向一致。
                let opacity = dark ? 0.58+0.42*strength : 1-0.55*strength
                value.addAttribute(.foregroundColor,value:NSColor.labelColor.withAlphaComponent(opacity),range:NSRange(location:offset,length:length))
                offset += length
            }
        }
        title.attributedStringValue = value
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
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.refreshElapsed() }
        elapsedTimer = timer; RunLoop.main.add(timer,forMode:.common)
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
        let baseline = title.alignmentRect(forFrame:title.frame).maxY-title.firstBaselineOffsetFromTop
        elapsedLabel.frame = NSRect(x:size.width-margin-textSize.width,y:0,width:textSize.width,height:textSize.height)
        let elapsedBaseline = elapsedLabel.alignmentRect(forFrame:elapsedLabel.frame).maxY-elapsedLabel.firstBaselineOffsetFromTop
        elapsedLabel.frame.origin.y = baseline-elapsedBaseline
        elapsedIcon.frame = NSRect(x:elapsedLabel.frame.minX-3*scale-side,y:elapsedLabel.frame.midY-side/2,width:side,height:side)
    }
    private func refreshElapsed() {
        guard let start = taskStartedAt else {return}
        elapsedLabel.stringValue = TaskTiming.elapsed(start:start,end:taskFinishedAt ?? Date())
        elapsedLabel.setAccessibilityLabel("已处理 "+elapsedLabel.stringValue)
        if visible && abs(elapsedGroupWidth-elapsedLayoutWidth) > 0.5 {layout(bodyHeight:layoutBodyHeight)}
        layoutElapsed(in:window.frame.size)
    }
    func finishTask(_ key: String, status: String) {
        for index in cards.indices where cards[index].timing?.key == key && cards[index].timing?.finished == nil {
            cards[index].timing?.finished = Date(); cards[index].timing?.status = status
        }
        guard timedTaskKey == key else {return}
        taskFinishedAt = Date(); setElapsedColor(status)
        refreshElapsed(); elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil
    }
    private func startCountdown(_ seconds: Double) {
        timer?.invalidate(); timer = nil
        guard seconds > 0 else {return}
        var remaining = seconds, previous = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else {return}
            let now = ProcessInfo.processInfo.systemUptime, delta = now-previous; previous = now
            let hovering = self.preferences.bool("pauseOnHover") && self.window.frame.contains(NSEvent.mouseLocation)
            if hovering || self.preferences.bool("countAfterReveal") && self.text.isRevealing {return}
            remaining -= delta
            if remaining <= 0 {self.hide(); self.onClose()}
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func finishTyping() {text.finishReveal()}
    func refreshDuration() {if visible {startCountdown(pendingAttention || kind == "error" ? 0 : preferences.duration(purpose,text:currentBody))}}
    func showFailure(_ failure: AppFailure, scale: Double, retry: (() -> Void)? = nil, taskStartedAt: Date? = nil, taskFinishedAt: Date? = nil, taskStatus: String? = nil) {
        onDetails = {failure.showDetails()}
        show(title:taskStatus.map {preferences.taskResultLine($0)} ?? failure.title, body:failure.message, kind:"error", scale:scale, seconds:0, details:true, timing:.init(start:taskStartedAt,finished:taskFinishedAt,status:taskStatus))
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
    func quotaRows(_ overview: QuotaOverview, scale: Double, failure: AppFailure? = nil, retry: (() -> Void)? = nil) {
        let fontScale = scale*preferences.number("messageFontSize")/13
        if let failure {
            purpose = .attention; timer?.invalidate(); timer = nil
            codexButton.isHidden = true
            onDetails = {failure.showDetails()}; details.title = "技术详情…"; details.isHidden = false; details.emphasize(false)
            if let retry {retryButton.title = "重试"; retryButton.callback = retry; retryButton.isHidden = false}
        }
        configureButtons()
        let width = GutterScrollView.documentWidth(for:layoutWidth-32*self.scale)
        let content = TopDownView(frame:NSRect(x:0,y:0,width:width,height:1))
        var y = 0.0
        @discardableResult func addText(_ value: String, font: NSFont, color: NSColor = .labelColor) -> CGFloat {
            let text = label(value); text.font = font; text.textColor = color
            let height = max(font.pointSize+5,(value as NSString).boundingRect(with:NSSize(width:width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height.rounded(.up)+3)
            text.frame = NSRect(x:0,y:y,width:width,height:height); content.addSubview(text); y += height
            return height
        }
        addText("套餐 · "+overview.plan,font:.systemFont(ofSize:13*fontScale,weight:.semibold)); y += 12*scale
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
            for field in [heading,amount] {
                field.maximumNumberOfLines = 1; field.usesSingleLineMode = true
                field.lineBreakMode = .byTruncatingTail; field.hoverHelp = field.stringValue
            }
            let gap = 12*scale
            let headingMinimum = min(heading.fittingSize.width,96*scale)
            let amountWidth = min(amount.fittingSize.width.rounded(.up),width-headingMinimum-gap)
            let rowHeight = max(22*scale,max(heading.fittingSize.height,amount.fittingSize.height).rounded(.up))
            heading.frame = NSRect(x:0,y:y,width:width-amountWidth-gap,height:rowHeight)
            amount.frame = NSRect(x:width-amountWidth,y:y,width:amountWidth,height:rowHeight)
            content.addSubview(heading); content.addSubview(amount); y += rowHeight
            if let amount = row.remaining {
                y += 4*scale
                let bar = AccentProgressIndicator(frame:NSRect(x:0,y:y,width:width,height:9*scale))
                bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = amount
                content.addSubview(bar); y += 16*scale
            }
            if let detail = row.detail {addText(detail,font:.systemFont(ofSize:11*fontScale),color:.secondaryLabelColor)}
            y += 12*scale
        }
        if let notice = overview.notice {addText(notice,font:.systemFont(ofSize:11*fontScale,weight:.medium))}
        content.frame.size.height = y
        layout(bodyHeight:min(320*scale,y))
        scroll.documentView = content; scroll.contentView.scroll(to:.zero)
        let heading = plainHeading
        refreshStandalone = { [weak self] in
            guard let self else {return}
            let scale = self.preferences.number("bubblePercent")/100
            self.show(title:heading,body:" ",kind:"quota",scale:scale,seconds:0,preserveCountdown:true)
            self.quotaRows(overview,scale:scale,failure:failure,retry:retry)
        }
    }
    func place(near rect: CGRect, screen: NSScreen, dock: String?) {
        let area = screen.visibleFrame.insetBy(dx:8,dy:8)
        if placementArea != area {
            placementArea = area
            if !questionModels.isEmpty {
                window.maxSize = area.size
                if let size = questionSize {questionSize = NSSize(width:min(size.width,area.width),height:min(size.height,area.height))}
                layoutQuestions()
            } else {layout(bodyHeight:layoutBodyHeight)}
        }
        let size = motion.frame.size
        if let previous = placement,previous.0 == rect,previous.1 == dock,previous.2 == area,previous.3 == size {return}
        let preferred:[BubblePlacement.Side]
        if dock == "left" {preferred = [.right,.above,.below,.left]}
        else if dock == "right" {preferred = [.left,.above,.below,.right]}
        else if kind.hasPrefix("quota") {preferred = [.right,.left,.above,.below]}
        else if kind == "task" || kind == "preview" {preferred = [.left,.right,.above,.below]}
        else {preferred = [.above,.below,.right,.left]}
        let oldSide = placement?.1 == dock ? placementSide : nil
        let result = BubblePlacement.resolve(size:size,pet:rect,screen:screen.visibleFrame,preferred:preferred,previous:oldSide)
        // 仅正文高度变化、原位置仍安全时保持位置；拖动、越界和遮挡时重新选边。
        let current = CGRect(origin:motion.frame.origin,size:size)
        let keepOrigin = placement.map {$0.0 == rect && $0.1 == dock && $0.2 == area} == true
            && area.contains(current) && !current.intersects(rect.insetBy(dx:-4,dy:-4))
        if !keepOrigin {move(to:result.frame.origin); placementSide = result.side}
        placement = (rect,dock,area,size)
    }
    deinit { timer?.invalidate(); headingTimer?.invalidate(); elapsedTimer?.invalidate() }
    func hide() {saveCardForm(); isBrowsingCards = false; taskList?.stop(); elapsedTimer?.invalidate(); elapsedTimer = nil; timedTaskKey = nil; text.finishReveal(); headingTimer?.invalidate(); headingTimer = nil; headingPhase = 0; timer?.invalidate(); motion.hide(); placement = nil; placementSide = nil; kind = ""; relatedConversation = nil}
}
