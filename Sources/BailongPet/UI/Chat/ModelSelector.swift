import AppKit

// 两个聊天入口共享偏好；模型与可用思考档位均来自 app-server。
final class ModelSelector: ModelSummaryButton, NSPopoverDelegate {
    let settings: ChatModelSettings
    private let popover = AnchoredPopover()
    var onSummaryChange:() -> Void = {}
    init(_ settings: ChatModelSettings) {
        self.settings = settings; super.init(frame:.zero)
        popover.delegate = self
        image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil); imagePosition = .imageTrailing
        target = self; action = #selector(openChoices)
        setAccessibilityLabel("选择模型与推理强度")
        NotificationCenter.default.addObserver(self,selector:#selector(updateTitle),name:ChatModelSettings.changed,object:settings)
        updateTitle()
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func updateTitle() {
        let summary = ModelPresentation.summary(model:settings.currentModelID ?? "未获取模型",displayName:settings.currentModel?.displayName,
            effort:settings.effortTitle,provider:settings.summaryProvider)
        let fastMode = settings.fastMode
        let changed = setSummary(summary,lightning:fastMode,providerIcon:AppIcons.apiProvider(settings.providerIconID))
        var details = [summary,settings.providerTitle.map {"供应商："+$0}].compactMap {$0}.joined(separator:"\n")
        if fastMode {details += "\n速度档位：1.5倍速度"}
        setHoverHelp(details) { [weak self] in
            fastMode || self?.hasTruncatedTitle == true
        }
        if changed {onSummaryChange()}
    }
    func closeChoices() {popover.performClose(nil)}
    func popoverDidClose(_ notification:Notification) {
        popover.contentViewController = nil
    }
    func containsInteraction(at point: NSPoint, window: NSWindow?) -> Bool {
        guard popover.isShown else{return false}
        if let panel = popover.contentViewController?.view.window, panel.frame.contains(point) {return true}
        // 模型下拉菜单由 AppKit 单独呈现，仍属于这个输入气泡的操作。
        return window.map {$0.level >= .popUpMenu} ?? false
    }
    @objc private func openChoices() {
        if popover.isShown {popover.performClose(nil); return}
        settings.onLoad(false)
        let available = window?.screen?.visibleFrame.size ?? NSSize(width:1024,height:768)
        let controls = ModelSelectorContent(settings,fontSize:font?.pointSize ?? 13,
            maximumSize:NSSize(width:max(1,available.width-48),height:max(1,available.height-80)))
        controls.onResize = { [weak self] size in
            guard let self,self.popover.contentSize != size else {return}
            self.popover.contentSize = size
        }
        popover.contentViewController = controls; popover.behavior = .transient; popover.animates = DisclosureMotion.enabled
        _ = controls.view; popover.contentSize = controls.preferredContentSize
        // 使用 AppKit 的视图边界锚点，弹窗随按钮的实际尺寸更新位置。
        popover.show(relativeTo:.zero,of:self,preferredEdge:.maxY)
    }
}
final class ModelSelectorContent: NSViewController {
    var onResize: (NSSize) -> Void = {_ in}
    private let settings: ChatModelSettings
    private let heading = label("模型与推理强度",bold:true)
    private let picker = AccentPopUpButton(frame:.zero,pullsDown:false)
    private let effort = NSTextField(wrappingLabelWithString:"")
    private let speedLabel = NSTextField(labelWithString:"1.5倍速度")
    private let speedIcon = NSImageView()
    private let speedSwitch = AccentSwitch(frame:.zero)
    private let explanation = NSTextField(wrappingLabelWithString:"")
    private let slider = NSSlider(value:0,minValue:0,maxValue:1,target:nil,action:nil)
    private let sync = ActionButton("与 Codex 同步") {}
    private let refresh = ActionButton("刷新模型") {}
    private var footerButtons:[ActionButton] {[refresh,sync]}
    private var options = [ChatModel.Effort]()
    private var effortMarks = [NSTextField]()
    private let scroll = GutterScrollView(), body = TopDownView()
    private let scale:CGFloat, maximumSize:NSSize
    private var layingOut = false
    init(_ settings: ChatModelSettings,fontSize:CGFloat = 13,maximumSize:NSSize = NSSize(width:900,height:700)) {
        self.settings = settings; scale = fontSize/13; self.maximumSize = maximumSize
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        view = scroll; scroll.hasVerticalScroller = true; scroll.documentView = body
        picker.target = self; picker.action = #selector(modelChanged)
        heading.font = .systemFont(ofSize:13*scale,weight:.semibold)
        picker.font = .systemFont(ofSize:13*scale)
        effort.font = .systemFont(ofSize:14*scale,weight:.semibold)
        speedLabel.font = .systemFont(ofSize:12*scale)
        speedIcon.image = NSImage(systemSymbolName:"bolt",accessibilityDescription:nil)
        speedSwitch.controlSize = .small; speedSwitch.target = self; speedSwitch.action = #selector(speedChanged)
        speedSwitch.setAccessibilityLabel("1.5倍速度")
        slider.target = self; slider.action = #selector(effortChanged)
        slider.allowsTickMarkValuesOnly = true; slider.isContinuous = false; slider.setAccessibilityLabel("推理强度")
        for text in [explanation] {text.font = .systemFont(ofSize:12*scale); text.isSelectable = false}
        explanation.textColor = .secondaryLabelColor
        refresh.callback = { [weak self] in self?.settings.onLoad(true) }
        sync.emphasize(); sync.callback = { [weak self] in self?.settings.syncWithCodex() }
        [heading,picker,effort,speedIcon,speedLabel,speedSwitch,slider,explanation].forEach {body.addSubview($0)}
        for button in footerButtons {
            button.configureFlexible(font:.systemFont(ofSize:13*scale))
            body.addSubview(button)
        }
        NotificationCenter.default.addObserver(self,selector:#selector(refreshControls),name:ChatModelSettings.changed,object:settings)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshControls),name:AppAccent.didChange,object:nil)
        refreshControls()
    }
    @objc private func refreshControls() {
        picker.removeAllItems(); picker.addItem(withTitle:settings.defaultTitle)
        for model in settings.models {picker.addItem(withTitle:model.displayName); picker.lastItem?.representedObject = model.model}
        if let model = settings.selectedModel, let index = settings.models.firstIndex(where:{$0.model == model}) {picker.selectItem(at:index+1)}
        picker.isEnabled = !settings.loading && !settings.providerMismatch
        options = settings.supportedEfforts
        slider.isHidden = options.count < 2
        slider.minValue = 0; slider.maxValue = Double(max(1,options.count-1)); slider.numberOfTickMarks = options.count
        slider.isEnabled = !settings.loading && options.count > 1; slider.trackFillColor = AppAccent.color
        slider.integerValue = options.firstIndex(where:{$0.reasoningEffort == settings.currentEffort}) ?? 0
        effortMarks.forEach {$0.removeFromSuperview()}
        effortMarks = options.map {option in
            let mark = NSTextField(labelWithString:ChatModelSettings.effortName(option.reasoningEffort))
            mark.font = .systemFont(ofSize:11*scale); mark.alignment = .center
            mark.usesSingleLineMode = true; mark.maximumNumberOfLines = 1; mark.lineBreakMode = .byClipping
            mark.textColor = option.reasoningEffort == settings.currentEffort ? AppAccent.color : .secondaryLabelColor
            body.addSubview(mark); return mark
        }
        effort.stringValue = "推理强度 · "+settings.effortTitle
        effort.textColor = AppAccent.color
        speedSwitch.state = settings.fastMode ? .on : .off
        speedSwitch.isEnabled = !settings.loading && settings.supportsFastMode
        speedLabel.textColor = speedSwitch.isEnabled ? .labelColor : .disabledControlTextColor
        speedIcon.contentTintColor = speedLabel.textColor
        let speedHelp = settings.supportsFastMode ? "开启后使用 Codex 官方快速模式（1.5倍速度），关闭后恢复标准速度。" : "当前模型未提供 Codex 官方快速档位。"
        speedSwitch.hoverHelp = speedHelp
        if settings.loading {explanation.stringValue = "正在读取可用模型…"}
        else if let error = settings.error {explanation.stringValue = "模型读取失败："+error}
        else if settings.providerMismatch {explanation.stringValue = "请在 Codex 切回原供应商并刷新模型，或新建桌宠对话。"}
        else {explanation.stringValue = options.isEmpty ? "此模型不提供可调整的推理强度。" : settings.effortExplanation}
        explanation.setHoverHelp(settings.error) { [weak explanation] in explanation?.hasTruncatedText == true }
        picker.setHoverHelp(picker.title) { [weak picker] in picker?.hasTruncatedTitle == true }
        refresh.isEnabled = !settings.loading; sync.isEnabled = !settings.loading
        layoutControls()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !layingOut, view.bounds.width > 0 else {return}
        // AppKit 会按锚点和屏幕空间调整弹窗，正文必须使用最终视口重新换行。
        resizeContent(width:view.bounds.width)
    }
    private func layoutControls() {
        let margin = 16*scale, gap = 8*scale
        let footerWidth = footerButtons.reduce(CGFloat(0)) {$0+$1.intrinsicContentSize.width}+gap
        let menuWidth = picker.itemTitles.map {($0 as NSString).size(withAttributes:[.font:picker.font!]).width}.max() ?? 0
        let effortWidth = (effort.stringValue as NSString).size(withAttributes:[.font:effort.font!]).width
        let marksWidth = effortMarks.map {($0.stringValue as NSString).size(withAttributes:[.font:$0.font!]).width+gap}.max() ?? 0
        let contentWidth = max(428*scale,menuWidth+28*scale,footerWidth,effortWidth+speedWidth+gap,marksWidth*CGFloat(options.count))
        resizeContent(width:min(maximumSize.width,contentWidth+2*margin+GutterScrollView.gutter))
    }
    private func resizeContent(width:CGFloat) {
        guard !layingOut else {return}
        layingOut = true
        defer {layingOut = false}
        let height = layoutBody(width:width)
        let size = NSSize(width:width,height:min(height,maximumSize.height))
        if view.frame.size != size {view.setFrameSize(size)}
        if preferredContentSize != size {preferredContentSize = size; onResize(size)}
    }
    @discardableResult private func layoutBody(width:CGFloat) -> CGFloat {
        let margin = 16*scale, gap = 8*scale
        let buttons = footerButtons
        let footerWidth = buttons.reduce(CGFloat(0)) {$0+$1.intrinsicContentSize.width}+gap
        let documentWidth = GutterScrollView.documentWidth(for:width), contentWidth = max(1,documentWidth-2*margin)
        var y = margin
        func place(_ control:NSView,_ height:CGFloat,_ spacing:CGFloat) {
            control.frame = NSRect(x:margin,y:y,width:contentWidth,height:height); y += height+spacing
        }
        // 从顶部布局，不依赖弹窗上一次高度；只按当前可见内容计算新尺寸。
        place(heading,22*scale,gap)
        place(picker,28*scale,12*scale)
        func textHeight(_ text:NSTextField,width:CGFloat,minimum:CGFloat) -> CGFloat {
            max(minimum,text.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up))
        }
        let effortWidth = max(1,contentWidth-speedWidth-gap)
        let rowHeight = max(textHeight(effort,width:effortWidth,minimum:22*scale),speedSwitch.intrinsicContentSize.height)
        effort.frame = NSRect(x:margin,y:y,width:effortWidth,height:rowHeight)
        let switchSize = speedSwitch.intrinsicContentSize
        speedSwitch.frame = NSRect(x:documentWidth-margin-switchSize.width,y:y+(rowHeight-switchSize.height)/2,width:switchSize.width,height:switchSize.height)
        let labelSize = speedLabel.intrinsicContentSize
        speedLabel.frame = NSRect(x:speedSwitch.frame.minX-gap-labelSize.width,y:y+(rowHeight-labelSize.height)/2,width:labelSize.width,height:labelSize.height)
        speedIcon.frame = NSRect(x:speedLabel.frame.minX-18*scale,y:y+(rowHeight-14*scale)/2,width:14*scale,height:14*scale)
        y += rowHeight+gap
        if !slider.isHidden {
            slider.frame = NSRect(x:margin,y:y,width:contentWidth,height:32*scale)
            var marksHeight:CGFloat = 18*scale
            for (index,mark) in effortMarks.enumerated() {
                let tick = slider.rectOfTickMark(at:index)
                let width = min(contentWidth,max(1,ceil((mark.stringValue as NSString).size(withAttributes:[.font:mark.font!]).width)+8*scale))
                let x:CGFloat
                if index == 0 {
                    x = margin; mark.alignment = .left
                } else if index == effortMarks.count-1 {
                    x = documentWidth-margin-width; mark.alignment = .right
                } else {
                    x = margin+tick.midX-width/2; mark.alignment = .center
                }
                let height = textHeight(mark,width:width,minimum:18*scale)
                mark.frame = NSRect(x:max(margin,min(x,documentWidth-margin-width)),y:y+32*scale,width:width,height:height)
                mark.isHidden = false; marksHeight = max(marksHeight,height)
            }
            y += 32*scale+marksHeight+gap
        } else {effortMarks.forEach {$0.isHidden = true}}
        for text in [explanation] where !text.isHidden {
            let height = text.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:contentWidth,height:CGFloat.greatestFiniteMagnitude)).height.rounded(.up)
            place(text,max(18*scale,height),gap)
        }
        let buttonHeight = buttons.map {$0.intrinsicContentSize.height}.max() ?? 28*scale
        if footerWidth <= contentWidth {
            var x = margin
            for (index,button) in buttons.enumerated() {
                let w = button.intrinsicContentSize.width
                if index == buttons.count-1 {x = documentWidth-margin-w}
                button.frame = NSRect(x:x,y:y,width:w,height:buttonHeight); x += w+gap
            }
            y += buttonHeight+margin
        } else {
            for button in buttons {place(button,buttonHeight,gap)}
            y += margin-gap
        }
        let bodySize = NSSize(width:documentWidth,height:y)
        if body.frame.size != bodySize {body.setFrameSize(bodySize)}
        return y
    }
    @objc private func modelChanged() {settings.chooseModel(picker.selectedItem?.representedObject as? String)}
    private var speedWidth:CGFloat {18*scale+speedLabel.intrinsicContentSize.width+8*scale+speedSwitch.intrinsicContentSize.width}
    @objc private func speedChanged() {settings.chooseFastMode(speedSwitch.state == .on)}
    @objc private func effortChanged() {guard options.indices.contains(slider.integerValue) else{return}; settings.chooseEffort(options[slider.integerValue].reasoningEffort)}
}
