import Foundation

struct ChatModel: Decodable {
    struct Effort: Decodable {let reasoningEffort: String; let description: String}
    struct ServiceTier: Decodable {let id:String; let name:String; let description:String}
    let id: String, model: String, displayName: String, defaultReasoningEffort: String
    let supportedReasoningEfforts: [Effort]
    let isDefault: Bool, hidden: Bool
    var serviceTiers: [ServiceTier]? = nil
    var defaultServiceTier:String? = nil
    var fastTier:ServiceTier? {serviceTiers?.first {CodexServiceTier.isFast($0.id) || ["fast","priority"].contains($0.name.lowercased())}}
}
enum CodexServiceTier {
    static func isFast(_ tier:String?) -> Bool {tier == "fast" || tier == "priority"}
    static func hasLightning(_ tier:String?) -> Bool {isFast(tier) || tier == "ultrafast"}
    static func displayName(_ tier:String) -> String {
        switch tier {
        case "fast","priority":return "快速（1.5倍速度）"
        case "ultrafast":return "超快"
        case "default","standard":return "标准速度"
        case "flex":return "灵活"
        default:return tier
        }
    }
}
final class ChatModelSettings {
    static let changed = Notification.Name("BailongChatModelChanged")
    private let defaults: UserDefaults
    init(defaults: UserDefaults = SettingsStorage.defaults) {
        self.defaults = defaults
        selectedModel = defaults.string(forKey:"petChatModel"); selectedEffort = defaults.string(forKey:"petChatEffort")
        selectedFast = defaults.bool(forKey:"petChatFastMode")
        NotificationCenter.default.addObserver(self,selector:#selector(preferencesChanged),name:PetPreferences.didChange,object:nil)
    }
    private(set) var models = [ChatModel]()
    private(set) var configuredModel: String?, configuredEffort: String?
    private(set) var configuredProvider:String?
    private var configuredServiceTier:String?, providerName:String?, providerSummaryName:String?, configuredProviderIconID:String?
    private var usesChatGPTAccount = false
    private weak var conversation:Conversation?
    private var providerID:String? {conversation?.modelProvider ?? configuredProvider}
    var providerTitle:String? {
        guard let id = providerID else {return nil}
        let identity = APIProviderDirectory.identity(id:id)
        let fullName = id == configuredProvider ? providerName ?? identity.name : identity.name
        return ModelPresentation.provider(id,name:fullName)
    }
    var summaryProvider:String? {
        guard let id = providerID else {return nil}
        let identity = APIProviderDirectory.identity(id:id)
        let summaryName = id == configuredProvider ? providerSummaryName ?? identity.summaryName : identity.summaryName
        return ModelPresentation.provider(id,name:summaryName,usesChatGPTAccount:usesChatGPTAccount)
    }
    var providerIconID:String? {
        guard let id = providerID,id != "openai" else {return nil}
        let identity = APIProviderDirectory.identity(id:id)
        return id == configuredProvider ? configuredProviderIconID ?? identity.catalogID : identity.catalogID
    }
    var providerMismatch:Bool {
        guard let original = conversation?.modelProvider,let configuredProvider else {return false}
        return original != configuredProvider
    }
    private(set) var selectedFast:Bool?
    var supportsFastMode:Bool {configuredProvider == "openai" && currentModel?.fastTier != nil}
    var fastMode:Bool {
        let tier = configuredServiceTier ?? currentModel?.defaultServiceTier
        let configuredFast = CodexServiceTier.isFast(tier) || (tier != nil && tier == currentModel?.fastTier?.id)
        return supportsFastMode && (selectedFast ?? configuredFast)
    }
    private(set) var loading = false
    private(set) var error: String?
    var onLoad: (Bool) -> Void = {_ in}
    private(set) var selectedModel:String?, selectedEffort:String?
    private var selectionKey:String?
    private var selections = [String:(model:String?,effort:String?,fast:Bool?)]()
    func activate(_ conversation:Conversation) {
        self.conversation = conversation
        let key = conversation.key
        guard selectionKey != key else {return}
        if let selectionKey {selections[selectionKey] = (selectedModel,selectedEffort,selectedFast)}
        selectionKey = key
        let choice = selections[key] ?? (defaults.string(forKey:"petChatModel"),defaults.string(forKey:"petChatEffort"),defaults.bool(forKey:"petChatFastMode"))
        selectedModel = choice.0; selectedEffort = choice.1; selectedFast = choice.2
        notify()
    }
    func clearSelections() {selections.removeAll(); selectionKey = nil; conversation = nil}
    func forget(_ key:String) {selections.removeValue(forKey:key)}
    @objc private func preferencesChanged(_ note:Notification) {
        guard (note.userInfo?["keys"] as? [String])?.contains("petChatFastMode") == true else {return}
        selectedFast = defaults.bool(forKey:"petChatFastMode")
        for key in Array(selections.keys) {selections[key]?.fast = selectedFast}
        notify()
    }
    func chooseFastMode(_ enabled:Bool) {
        guard !enabled || supportsFastMode else {return}
        selectedFast = enabled; defaults.set(enabled,forKey:"petChatFastMode"); notify()
    }
    var currentModelID: String? {
        if providerMismatch {return recordedTurn?.model}
        return modelOverride ?? configuredModel ?? models.first(where:{$0.isDefault})?.model
    }
    private var recordedTurn:Turn? {conversation?.turns.last(where:{$0.id != nil})}
    private var modelOverride:String? {
        guard let selectedModel else {return nil}
        return configuredProvider == "openai" || models.contains(where:{$0.model == selectedModel}) ? selectedModel : nil
    }
    var currentModel: ChatModel? {providerMismatch ? nil : models.first(where:{$0.model == currentModelID})}
    var supportedEfforts: [ChatModel.Effort] {currentModel?.supportedReasoningEfforts ?? []}
    var currentEffort: String? {
        if providerMismatch {return recordedTurn?.effort}
        guard let model = currentModel else {return modelOverride == nil ? configuredEffort : nil}
        let preferred = selectedEffort ?? (modelOverride == nil ? configuredEffort : nil)
        if let preferred, supportedEfforts.contains(where:{$0.reasoningEffort == preferred}) {return preferred}
        if supportedEfforts.contains(where:{$0.reasoningEffort == model.defaultReasoningEffort}) {return model.defaultReasoningEffort}
        return supportedEfforts.first?.reasoningEffort
    }
    // 与已安装 Codex 的简中本地化一致，Max / Ultra 保留原文，不按模型另起译名。
    static func effortName(_ raw: String) -> String {
        ["none":"无","minimal":"极低","low":"轻度","medium":"中","high":"高","xhigh":"极高","max":"Max","ultra":"Ultra","persistent":"持续"][raw] ?? raw
    }
    var effortTitle: String {currentEffort.map(Self.effortName) ?? (providerMismatch ? "未记录" : "不可调")}
    var effortExplanation: String {
        guard let effort = currentEffort else {return "跟随 Codex 的模型与推理强度设置。"}
        let descriptions = ["none":"直接作答，不额外展开推理。", "minimal":"尽量减少思考，适合简单任务。",
            "low":"少量思考，优先响应速度。", "medium":"平衡思考深度与响应速度。",
            "high":"充分分析问题，适合较复杂的任务。", "xhigh":"深入分析复杂问题，可能需要更长时间。",
            "max":"投入更多推理，适合难度较高的任务；在 Codex 中默认隐藏显示。",
            "ultra":"使用最高档推理投入，适合需要深入分析的任务；在特定情况下会更频繁派遣子代理。"]
        return descriptions[effort] ?? "使用当前模型提供的「\(Self.effortName(effort))」推理强度。"
    }
    var defaultTitle: String {
        let id = configuredModel ?? models.first(where:{$0.isDefault})?.model
        let name = models.first(where:{$0.model == id})?.displayName ?? id ?? "未获取模型"
        return "默认（"+name+" - 跟随 Codex）"
    }
    func syncWithCodex() {
        defaults.removeObject(forKey:"petChatModel")
        defaults.removeObject(forKey:"petChatEffort")
        selectedModel = nil; selectedEffort = nil; selectedFast = nil
        notify(); onLoad(true)
    }
    func setLoading() {loading = true; error = nil; notify()}
    func loaded(_ models: [ChatModel], configuredModel: String?, configuredEffort: String?, configuredProvider:String = "openai", configuredServiceTier:String? = nil,providerName:String? = nil,providerSummaryName:String? = nil,providerIconID:String? = nil) {
        let visibleModels = models.filter {!$0.hidden}
        if configuredProvider != "openai",let configuredModel,!visibleModels.contains(where:{$0.model == configuredModel}) {self.models = []}
        else {self.models = visibleModels}
        self.configuredModel = configuredModel; self.configuredEffort = configuredEffort
        if self.configuredProvider != configuredProvider {usesChatGPTAccount = false}
        self.configuredProvider = configuredProvider; self.configuredServiceTier = configuredServiceTier
        self.providerName = providerName; self.providerSummaryName = providerSummaryName
        configuredProviderIconID = providerIconID
        if selectedFast == nil,configuredProvider == "openai" {defaults.set(fastMode,forKey:"petChatFastMode")}
        if configuredProvider == "openai",!providerMismatch,let effort = selectedEffort,!supportedEfforts.contains(where:{$0.reasoningEffort == effort}) {
            defaults.removeObject(forKey:"petChatEffort")
            selectedEffort = nil
        }
        loading = false; error = nil; notify()
    }
    func setUsesChatGPTAccount(_ active:Bool) {
        guard usesChatGPTAccount != active else {return}
        usesChatGPTAccount = active; notify()
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
        if providerMismatch {
            throw PetFailure(message:"此对话使用 \(providerTitle ?? "原供应商")。请在 Codex 切回该供应商并刷新模型，或新建桌宠对话。")
        }
        if let modelOverride, !models.contains(where:{$0.model == modelOverride}) {
            throw PetFailure(message:"所选模型暂不可用，请打开模型选择器刷新或选择其他模型。")
        }
        var result = [String:Any]()
        // 关闭时明确覆盖旧线程的快速档，不能省略后继承上轮设置。
        if configuredProvider == "openai" {result["serviceTier"] = fastMode ? currentModel!.fastTier!.id : "default"}
        if let model = currentModelID {result["model"] = model}
        if let effort = currentEffort {
            if let currentModel, !currentModel.supportedReasoningEfforts.contains(where:{$0.reasoningEffort == effort}) {
                throw PetFailure(message:"当前模型不支持所选推理强度，请重新选择。")
            }
            result["effort"] = effort
        }
        return result
    }
    private func notify() {NotificationCenter.default.post(name:Self.changed,object:self)}
}
