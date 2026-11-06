import AppKit

struct ChatModel: Decodable {
    struct Effort: Decodable {let reasoningEffort: String; let description: String}
    let id: String, model: String, displayName: String, defaultReasoningEffort: String
    let supportedReasoningEfforts: [Effort]
    let isDefault: Bool, hidden: Bool
}
final class ChatModelSettings {
    static let changed = Notification.Name("BailongChatModelChanged")
    private let defaults: UserDefaults
    init(defaults: UserDefaults = SettingsStorage.defaults) {
        self.defaults = defaults
        selectedModel = defaults.string(forKey:"petChatModel"); selectedEffort = defaults.string(forKey:"petChatEffort")
    }
    private(set) var models = [ChatModel]()
    private(set) var configuredModel: String?, configuredEffort: String?
    private(set) var loading = false
    private(set) var error: String?
    var onLoad: (Bool) -> Void = {_ in}
    private(set) var selectedModel:String?, selectedEffort:String?
    private var selectionKey:String?
    private var selections = [String:(model:String?,effort:String?)]()
    func activate(_ key:String) {
        guard selectionKey != key else {return}
        if let selectionKey {selections[selectionKey] = (selectedModel,selectedEffort)}
        selectionKey = key
        let choice = selections[key] ?? (defaults.string(forKey:"petChatModel"),defaults.string(forKey:"petChatEffort"))
        selectedModel = choice.0; selectedEffort = choice.1
        notify()
    }
    func clearSelections() {selections.removeAll(); selectionKey = nil}
    func forget(_ key:String) {selections.removeValue(forKey:key)}
    var currentModelID: String? {selectedModel ?? configuredModel ?? models.first(where:{$0.isDefault})?.model}
    var currentModel: ChatModel? {models.first(where:{$0.model == currentModelID})}
    var supportedEfforts: [ChatModel.Effort] {currentModel?.supportedReasoningEfforts ?? []}
    var currentEffort: String? {
        guard let model = currentModel else {return nil}
        let preferred = selectedEffort ?? (selectedModel == nil ? configuredEffort : nil)
        if let preferred, supportedEfforts.contains(where:{$0.reasoningEffort == preferred}) {return preferred}
        if supportedEfforts.contains(where:{$0.reasoningEffort == model.defaultReasoningEffort}) {return model.defaultReasoningEffort}
        return supportedEfforts.first?.reasoningEffort
    }
    // 与已安装 Codex 的简中本地化一致，Max / Ultra 保留原文，不按模型另起译名。
    static func effortName(_ raw: String) -> String {
        ["none":"无","minimal":"极低","low":"轻度","medium":"中","high":"高","xhigh":"极高","max":"Max","ultra":"Ultra","persistent":"持续"][raw] ?? raw
    }
    var effortTitle: String {currentEffort.map(Self.effortName) ?? "不可调"}
    var effortExplanation: String {
        guard let effort = currentEffort else {return "跟随 Codex 的模型与推理强度设置。"}
        let descriptions = ["none":"直接作答，不额外展开推理。", "minimal":"尽量减少思考，适合简单任务。",
            "low":"少量思考，优先响应速度。", "medium":"平衡思考深度与响应速度。",
            "high":"充分分析问题，适合较复杂的任务。", "xhigh":"深入分析复杂问题，可能需要更长时间。",
            "max":"投入更多推理，适合难度较高的任务。", "ultra":"使用最高档推理投入，适合需要深入分析的任务。"]
        return descriptions[effort] ?? "使用当前模型提供的「\(Self.effortName(effort))」推理强度。"
    }
    var defaultTitle: String {
        let id = configuredModel ?? models.first(where:{$0.isDefault})?.model
        let name = models.first(where:{$0.model == id})?.displayName ?? id ?? "未获取模型"
        return "默认（"+name+" - 跟随 Codex）"
    }
    var lunaMinimum: (String,String)? {
        guard let luna = models.first(where:{$0.model == "gpt-5.6-luna"}) else {return nil}
        let order = ["none","minimal","low","medium","high","xhigh","max","ultra"]
        guard let effort = luna.supportedReasoningEfforts.min(by:{
            (order.firstIndex(of:$0.reasoningEffort) ?? Int.max) < (order.firstIndex(of:$1.reasoningEffort) ?? Int.max)
        }) else {return nil}
        return (luna.model,effort.reasoningEffort)
    }
    func chooseLunaMinimum() {
        guard let (model,effort) = lunaMinimum else {return}
        defaults.set(model,forKey:"petChatModel")
        selectedModel = model; selectedEffort = effort
        defaults.set(effort,forKey:"petChatEffort")
        notify()
    }
    func syncWithCodex() {
        defaults.removeObject(forKey:"petChatModel")
        defaults.removeObject(forKey:"petChatEffort")
        selectedModel = nil; selectedEffort = nil
        notify(); onLoad(true)
    }
    var title: String {
        let name = selectedModel == nil ? defaultTitle : currentModel?.displayName ?? selectedModel!
        return name+" · "+effortTitle
    }
    func setLoading() {loading = true; error = nil; notify()}
    func loaded(_ models: [ChatModel], configuredModel: String?, configuredEffort: String?) {
        self.models = models.filter {!$0.hidden}; self.configuredModel = configuredModel; self.configuredEffort = configuredEffort
        if let effort = selectedEffort, !supportedEfforts.contains(where:{$0.reasoningEffort == effort}) {
            defaults.removeObject(forKey:"petChatEffort")
            selectedEffort = nil
        }
        loading = false; error = nil; notify()
    }
    func failed(_ error: Error) {loading = false; self.error = error.localizedDescription; notify()}
    func chooseModel(_ model: String?) {
        defaults.set(model,forKey:"petChatModel")
        selectedModel = model
        if let effort = selectedEffort, currentModel?.supportedReasoningEfforts.contains(where:{$0.reasoningEffort == effort}) != true {
            defaults.removeObject(forKey:"petChatEffort")
            selectedEffort = nil
        }
        notify()
    }
    func chooseEffort(_ effort: String?) {
        guard effort == nil || supportedEfforts.contains(where:{$0.reasoningEffort == effort}) else{return}
        defaults.set(effort,forKey:"petChatEffort")
        selectedEffort = effort; notify()
    }
    func parameters() throws -> [String:Any] {
        if let selectedModel, !models.contains(where:{$0.model == selectedModel}) {
            throw PetFailure(message:"所选模型暂不可用，请打开模型选择器刷新或选择其他模型。")
        }
        var result = [String:Any]()
        if let model = currentModelID {result["model"] = model}
        if let effort = currentEffort {
            if let currentModel, !currentModel.supportedReasoningEfforts.contains(where:{$0.reasoningEffort == effort}) {
                throw PetFailure(message:"当前模型不支持所选思考等级，请重新选择。")
            }
            result["effort"] = effort
        }
        return result
    }
    private func notify() {NotificationCenter.default.post(name:Self.changed,object:self)}
}

// 两个聊天入口共享偏好；模型与可用思考档位均来自 app-server。
final class ModelSelector: ModelSummaryButton, NSPopoverDelegate {
    let settings: ChatModelSettings
    private let popover = NSPopover()
    private var controls: ModelSelectorContent!
    private var anchorWidth:NSLayoutConstraint?
    private var restingHugging:NSLayoutConstraint.Priority?
    var layoutWidth:CGFloat {anchorWidth?.constant ?? min(320,intrinsicContentSize.width.rounded(.up))}
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
        title = ModelPresentation.summary(model:settings.currentModelID ?? "未获取模型",displayName:settings.currentModel?.displayName,effort:settings.effortTitle)
        hoverHelp = settings.title
    }
    func closeChoices() {popover.performClose(nil)}
    func popoverDidClose(_ notification:Notification) {
        anchorWidth?.isActive = false; anchorWidth = nil
        if let restingHugging {setContentHuggingPriority(restingHugging,for:.horizontal)}
        restingHugging = nil; invalidateIntrinsicContentSize()
        popover.contentViewController = nil; controls = nil
    }
    func containsInteraction(at point: NSPoint, window: NSWindow?) -> Bool {
        guard popover.isShown else{return false}
        if let panel = popover.contentViewController?.view.window, panel.frame.contains(point) {return true}
        // 模型下拉菜单由 AppKit 单独呈现，仍属于这个输入气泡的操作。
        return window.map {$0.level >= .popUpMenu} ?? false
    }
    @objc private func openChoices() {
        if popover.isShown {popover.performClose(nil); return}
        // 弹窗展开时固定锚点宽度，档位标题变化不推动弹窗。关闭后恢复内容定宽。
        restingHugging = contentHuggingPriority(for:.horizontal)
        setContentHuggingPriority(.defaultLow,for:.horizontal)
        anchorWidth = widthAnchor.constraint(equalToConstant:bounds.width); anchorWidth?.isActive = true
        settings.onLoad(false)
        let available = window?.screen?.visibleFrame.size ?? NSSize(width:1024,height:768)
        controls = ModelSelectorContent(settings,fontSize:font?.pointSize ?? 13,
            maximumSize:NSSize(width:max(1,available.width-48),height:max(1,available.height-80)))
        controls.onResize = { [weak self] size in
            guard let self,self.popover.contentSize != size else {return}
            self.popover.contentSize = size
        }
        popover.contentViewController = controls; popover.behavior = .transient; popover.animates = false
        _ = controls.view; popover.contentSize = controls.preferredContentSize
        popover.show(relativeTo:bounds,of:self,preferredEdge:.maxY)
    }
}
final class ModelSelectorContent: NSViewController {
    var onResize: (NSSize) -> Void = {_ in}
    private let settings: ChatModelSettings
    private let heading = label("模型与推理强度",bold:true)
    private let picker = NSPopUpButton(frame:.zero,pullsDown:false)
    private let effort = NSTextField(labelWithString:"")
    private let explanation = NSTextField(wrappingLabelWithString:"")
    private let slider = NSSlider(value:0,minValue:0,maxValue:1,target:nil,action:nil)
    private let sync = ActionButton("与 Codex 同步") {}
    private let luna = ActionButton("设置为 5.6-Luna 最低") {}
    private let refresh = ActionButton("刷新模型") {}
    private var options = [ChatModel.Effort]()
    private var effortMarks = [NSTextField]()
    private let scroll = GutterScrollView(), body = TopDownView()
    private let scale:CGFloat, maximumSize:NSSize
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
        slider.target = self; slider.action = #selector(effortChanged)
        slider.allowsTickMarkValuesOnly = true; slider.isContinuous = false; slider.setAccessibilityLabel("推理强度")
        for text in [explanation] {text.font = .systemFont(ofSize:12*scale); text.isSelectable = false}
        explanation.textColor = .secondaryLabelColor
        refresh.frame = NSRect(x:16,y:9,width:88,height:28); refresh.callback = { [weak self] in self?.settings.onLoad(true) }
        luna.frame = NSRect(x:112,y:9,width:176,height:28); luna.callback = { [weak self] in self?.settings.chooseLunaMinimum() }
        sync.frame = NSRect(x:304,y:9,width:140,height:28); sync.emphasize(); sync.callback = { [weak self] in self?.settings.syncWithCodex() }
        for button in [refresh,luna,sync] {button.configureFlexible(font:.systemFont(ofSize:13*scale))}
        [heading,picker,effort,slider,explanation,refresh,luna,sync].forEach {body.addSubview($0)}
        NotificationCenter.default.addObserver(self,selector:#selector(refreshControls),name:ChatModelSettings.changed,object:settings)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshControls),name:AppAccent.didChange,object:nil)
        refreshControls()
    }
    @objc private func refreshControls() {
        picker.removeAllItems(); picker.addItem(withTitle:settings.defaultTitle)
        for model in settings.models {picker.addItem(withTitle:model.displayName); picker.lastItem?.representedObject = model.model}
        if let model = settings.selectedModel, let index = settings.models.firstIndex(where:{$0.model == model}) {picker.selectItem(at:index+1)}
        picker.isEnabled = !settings.loading
        options = settings.supportedEfforts
        slider.isHidden = options.count < 2
        slider.minValue = 0; slider.maxValue = Double(max(1,options.count-1)); slider.numberOfTickMarks = options.count
        slider.isEnabled = !settings.loading && options.count > 1; slider.trackFillColor = AppAccent.color
        slider.integerValue = options.firstIndex(where:{$0.reasoningEffort == settings.currentEffort}) ?? 0
        effortMarks.forEach {$0.removeFromSuperview()}
        effortMarks = options.map {option in
            let mark = NSTextField(labelWithString:ChatModelSettings.effortName(option.reasoningEffort))
            mark.font = .systemFont(ofSize:11*scale); mark.alignment = .center
            mark.textColor = option.reasoningEffort == settings.currentEffort ? AppAccent.color : .secondaryLabelColor
            body.addSubview(mark); return mark
        }
        effort.stringValue = "推理强度 · "+settings.effortTitle
        effort.textColor = AppAccent.color
        explanation.stringValue = settings.loading ? "正在读取可用模型…" : settings.error != nil ? "模型列表暂不可用，请点击刷新模型重试。" : options.isEmpty ? "此模型不提供可调整的推理强度。" : settings.effortExplanation
        explanation.hoverHelp = settings.error
        refresh.isEnabled = !settings.loading; sync.isEnabled = !settings.loading
        luna.isEnabled = !settings.loading && settings.lunaMinimum != nil
        luna.hoverHelp = settings.lunaMinimum == nil ? "当前模型列表未提供 GPT-5.6 Luna。" : "切换到 GPT-5.6 Luna 支持的最低推理强度，并记住选择。"
        layoutControls()
    }
    private func layoutControls() {
        let margin = 16*scale, gap = 8*scale
        let buttons = [refresh,luna,sync]
        let footerWidth = buttons.reduce(CGFloat(0)) {$0+$1.intrinsicContentSize.width}+2*gap
        let menuWidth = picker.itemTitles.map {($0 as NSString).size(withAttributes:[.font:picker.font!]).width}.max() ?? 0
        let width = min(maximumSize.width,max(460*scale,menuWidth+60*scale,footerWidth+2*margin)+GutterScrollView.gutter)
        let documentWidth = GutterScrollView.documentWidth(for:width), contentWidth = max(1,documentWidth-2*margin)
        var y = margin
        func place(_ control:NSView,_ height:CGFloat,_ spacing:CGFloat) {
            control.frame = NSRect(x:margin,y:y,width:contentWidth,height:height); y += height+spacing
        }
        // 从顶部布局，不依赖弹窗上一次高度；只按当前可见内容计算新尺寸。
        place(heading,22*scale,gap)
        place(picker,28*scale,12*scale)
        place(effort,22*scale,gap)
        if !slider.isHidden {
            slider.frame = NSRect(x:margin,y:y,width:contentWidth,height:32*scale)
            for (index,mark) in effortMarks.enumerated() {
                let tick = slider.rectOfTickMark(at:index)
                let width = max(32*scale,mark.fittingSize.width+8*scale)
                mark.frame = NSRect(x:max(margin,min(margin+tick.midX-width/2,documentWidth-margin-width)),y:y+32*scale,width:width,height:18*scale)
                mark.isHidden = false
            }
            y += 56*scale
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
        body.setFrameSize(NSSize(width:documentWidth,height:y))
        let size = NSSize(width:width,height:min(y,maximumSize.height))
        view.setFrameSize(size); preferredContentSize = size; onResize(size)
    }
    @objc private func modelChanged() {settings.chooseModel(picker.selectedItem?.representedObject as? String)}
    @objc private func effortChanged() {guard options.indices.contains(slider.integerValue) else{return}; settings.chooseEffort(options[slider.integerValue].reasoningEffort)}
}
