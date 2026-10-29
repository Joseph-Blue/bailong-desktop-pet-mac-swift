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
    init(defaults: UserDefaults = .standard) {self.defaults = defaults}
    private(set) var models = [ChatModel]()
    private(set) var configuredModel: String?, configuredEffort: String?
    private(set) var loading = false
    private(set) var error: String?
    var onLoad: (Bool) -> Void = {_ in}
    var selectedModel: String? {defaults.string(forKey:"petChatModel")}
    var selectedEffort: String? {defaults.string(forKey:"petChatEffort")}
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
    var showsAstraRedWarning: Bool {currentModelID == "gpt-6-astra" && (currentEffort == "max" || currentEffort == "ultra")}
    var effortExplanation: String {
        guard let effort = currentEffort else {return "跟随 Codex 的模型与推理强度设置。"}
        let descriptions = ["none":"直接作答，不额外展开推理。", "minimal":"尽量减少思考，适合简单任务。",
            "low":"少量思考，优先响应速度。", "medium":"平衡思考深度与响应速度。",
            "high":"充分分析问题，适合较复杂的任务。", "xhigh":"深入分析复杂问题，可能需要更长时间。",
            "max":"投入更多推理，适合难度较高的任务。", "ultra":"使用最高档推理投入，适合需要深入分析的任务。"]
        return descriptions[effort] ?? "使用当前模型提供的「\(Self.effortName(effort))」推理强度。"
    }
    var caution: String? {
        if showsAstraRedWarning {return "⚠️ 穷玩车，富玩表，顶富就玩 Astra 快跑。如果不是顶富，请更换模型及推理强度！"}
        if currentModelID == "gpt-6-astra" {return "⚠️ 发送消息后会使用 Astra 模型，注意额度消耗！"}
        return nil
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
        defaults.set(effort,forKey:"petChatEffort"); notify()
    }
    func syncWithCodex() {
        defaults.removeObject(forKey:"petChatModel")
        defaults.removeObject(forKey:"petChatEffort")
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
        }
        loading = false; error = nil; notify()
    }
    func failed(_ error: Error) {loading = false; self.error = error.localizedDescription; notify()}
    func chooseModel(_ model: String?) {
        defaults.set(model,forKey:"petChatModel")
        if let effort = selectedEffort, currentModel?.supportedReasoningEfforts.contains(where:{$0.reasoningEffort == effort}) != true {
            defaults.removeObject(forKey:"petChatEffort")
        }
        notify()
    }
    func chooseEffort(_ effort: String?) {
        guard effort == nil || supportedEfforts.contains(where:{$0.reasoningEffort == effort}) else{return}
        defaults.set(effort,forKey:"petChatEffort"); notify()
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
final class ModelSelector: NSButton {
    let settings: ChatModelSettings
    private let popover = NSPopover()
    private var controls: ModelSelectorContent!
    init(_ settings: ChatModelSettings) {
        self.settings = settings; super.init(frame:.zero)
        bezelStyle = .rounded; image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil); imagePosition = .imageTrailing
        font = .systemFont(ofSize:12); target = self; action = #selector(openChoices)
        setContentCompressionResistancePriority(.required,for:.horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant:280).isActive = true
        setAccessibilityLabel("选择模型与推理强度")
        NotificationCenter.default.addObserver(self,selector:#selector(updateTitle),name:ChatModelSettings.changed,object:settings)
        updateTitle()
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func updateTitle() {title = settings.title; toolTip = settings.currentModel?.displayName ?? "默认跟随 Codex 设置"}
    func closeChoices() {popover.performClose(nil)}
    func containsInteraction(at point: NSPoint, window: NSWindow?) -> Bool {
        guard popover.isShown else{return false}
        if let panel = popover.contentViewController?.view.window, panel.frame.contains(point) {return true}
        // 模型下拉菜单由 AppKit 单独呈现，仍属于这个输入气泡的操作。
        return window.map {$0.level >= .popUpMenu} ?? false
    }
    @objc private func openChoices() {
        if popover.isShown {popover.performClose(nil); return}
        settings.onLoad(false)
        controls = ModelSelectorContent(settings)
        controls.onResize = { [weak self] size in self?.popover.contentSize = size }
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
    private let defaultInfo = NSTextField(wrappingLabelWithString:"ℹ️ 使用当前模型的默认思考等级。")
    private let caution = NSTextField(wrappingLabelWithString:"")
    private let slider = NSSlider(value:0,minValue:0,maxValue:1,target:nil,action:nil)
    private let sync = ActionButton("与 Codex 同步") {}
    private let luna = ActionButton("设置为 5.6-Luna 最低") {}
    private let refresh = ActionButton("刷新模型") {}
    private var options = [ChatModel.Effort]()
    private var effortMarks = [NSTextField]()
    init(_ settings: ChatModelSettings) {self.settings = settings; super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
        view = NSView(frame:NSRect(x:0,y:0,width:460,height:280))
        picker.target = self; picker.action = #selector(modelChanged)
        effort.font = .systemFont(ofSize:14,weight:.semibold)
        slider.target = self; slider.action = #selector(effortChanged)
        slider.allowsTickMarkValuesOnly = true; slider.isContinuous = true; slider.setAccessibilityLabel("推理强度")
        for text in [explanation,defaultInfo,caution] {text.font = .systemFont(ofSize:12); text.isSelectable = false}
        explanation.textColor = .secondaryLabelColor; defaultInfo.textColor = .systemBlue
        refresh.frame = NSRect(x:16,y:9,width:88,height:28); refresh.callback = { [weak self] in self?.settings.onLoad(true) }
        luna.frame = NSRect(x:112,y:9,width:176,height:28); luna.callback = { [weak self] in self?.settings.chooseLunaMinimum() }
        sync.frame = NSRect(x:304,y:9,width:140,height:28); sync.emphasize(); sync.callback = { [weak self] in self?.settings.syncWithCodex() }
        [heading,picker,effort,slider,explanation,defaultInfo,caution,refresh,luna,sync].forEach {view.addSubview($0)}
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
            mark.font = .systemFont(ofSize:11); mark.alignment = .center
            mark.textColor = option.reasoningEffort == settings.currentEffort ? AppAccent.color : .secondaryLabelColor
            view.addSubview(mark); return mark
        }
        effort.stringValue = "推理强度 · "+settings.effortTitle
        effort.textColor = AppAccent.color
        explanation.stringValue = settings.loading ? "正在读取可用模型…" : settings.error != nil ? "模型列表暂不可用，请点击刷新模型重试。" : options.isEmpty ? "此模型不提供可调整的推理强度。" : settings.effortExplanation
        defaultInfo.isHidden = settings.loading || settings.error != nil || settings.selectedEffort != nil || options.isEmpty
        caution.stringValue = settings.caution ?? ""
        caution.isHidden = settings.loading || settings.error != nil || settings.caution == nil
        caution.textColor = settings.showsAstraRedWarning ? .systemRed : .systemOrange
        explanation.toolTip = settings.error
        refresh.isEnabled = !settings.loading; sync.isEnabled = !settings.loading
        luna.isEnabled = !settings.loading && settings.lunaMinimum != nil
        luna.toolTip = settings.lunaMinimum == nil ? "当前模型列表未提供 GPT-5.6 Luna。" : "切换到 GPT-5.6 Luna 支持的最低推理强度，并记住选择。"
        layoutControls()
    }
    private func layoutControls() {
        var y: CGFloat = 49
        // 从底部向上排，阅读顺序为灰色说明、蓝色默认提示、红/橙彩蛋。
        for text in [caution,defaultInfo,explanation] where !text.isHidden {
            let height = max(20,(text.stringValue as NSString).boundingRect(with:NSSize(width:428,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:text.font!]).height.rounded(.up)+4)
            text.frame = NSRect(x:16,y:y,width:428,height:height); y += height+8
        }
        if !slider.isHidden {
            slider.frame = NSRect(x:16,y:y+20,width:428,height:32)
            for (index,mark) in effortMarks.enumerated() {
                let tick = slider.rectOfTickMark(at:index)
                let width = max(32,mark.fittingSize.width+8)
                mark.frame = NSRect(x:max(16,min(16+tick.midX-width/2,444-width)),y:y,width:width,height:18)
                mark.isHidden = false
            }
            y += 60
        } else {effortMarks.forEach {$0.isHidden = true}}
        effort.frame = NSRect(x:16,y:y,width:428,height:22); y += 30
        picker.frame = NSRect(x:16,y:y,width:428,height:28); y += 40
        heading.frame = NSRect(x:16,y:y,width:428,height:22); y += 38
        let size = NSSize(width:460,height:y)
        view.setFrameSize(size); preferredContentSize = size; onResize(size)
    }
    @objc private func modelChanged() {settings.chooseModel(picker.selectedItem?.representedObject as? String)}
    @objc private func effortChanged() {guard options.indices.contains(slider.integerValue) else{return}; settings.chooseEffort(options[slider.integerValue].reasoningEffort)}
}
