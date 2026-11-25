import Foundation

struct ChatModel: Decodable {
    struct Effort: Decodable {let reasoningEffort: String; let description: String}
    struct ServiceTier: Decodable {let id:String; let name:String; let description:String}
    let id: String, model: String, displayName: String, defaultReasoningEffort: String
    let supportedReasoningEfforts: [Effort]
    let isDefault: Bool, hidden: Bool
    var serviceTiers: [ServiceTier]? = nil
    var defaultServiceTier:String? = nil
    func tier(for speed:ChatSpeed) -> ServiceTier? {
        serviceTiers?.first {ChatSpeed(tier:$0.id) == speed}
            ?? serviceTiers?.first {ChatSpeed(tier:$0.name.lowercased()) == speed}
    }
}

enum ChatSpeed:String,CaseIterable {
    case standard = "default", fast, ultrafast
    static let preferenceKey = "petChatSpeed"

    init?(tier:String?) {
        switch tier {
        case "standard","default":self = .standard
        case "priority","fast":self = .fast
        case "ultrafast":self = .ultrafast
        default:return nil
        }
    }
    static func saved(in defaults:UserDefaults) -> Self {
        if let raw = defaults.string(forKey:preferenceKey),let speed = Self(rawValue:raw) {return speed}
        return defaults.bool(forKey:"petChatFastMode") ? .fast : .standard
    }
    var title:String {CodexServiceTier.displayName(rawValue)}
}
enum CodexServiceTier {
    static func displayName(_ tier:String) -> String {
        switch tier {
        case "fast","priority":return L10n.text(.conversation,"modelSelection.displayName.text")
        case "ultrafast":return L10n.text(.conversation,"modelSelection.displayName.text.2")
        case "default","standard":return L10n.text(.conversation,"modelSelection.displayName.text.3")
        case "flex":return L10n.text(.conversation,"modelSelection.displayName.text.4")
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
        selectedSpeed = ChatSpeed.saved(in:defaults)
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
    private var selectedSpeed:ChatSpeed?
    var availableSpeeds:[ChatSpeed] {
        guard configuredProvider == "openai",let model = currentModel else {return [.standard]}
        return ChatSpeed.allCases.filter {$0 == .standard || model.tier(for:$0) != nil}
    }
    var speed:ChatSpeed {
        let configured = configuredServiceTier ?? currentModel?.defaultServiceTier
        let available = availableSpeeds
        if let selectedSpeed {return available.contains(selectedSpeed) ? selectedSpeed : .standard}
        return available.first { option in
            option != .standard && (ChatSpeed(tier:configured) == option || currentModel?.tier(for:option)?.id == configured)
        } ?? .standard
    }
    private(set) var loading = false
    private(set) var error: String?
    var onLoad: (Bool) -> Void = {_ in}
    private(set) var selectedModel:String?, selectedEffort:String?
    private var selectionKey:String?
    private var selections = [String:(model:String?,effort:String?,speed:ChatSpeed?)]()
    func activate(_ conversation:Conversation) {
        self.conversation = conversation
        let key = conversation.key
        guard selectionKey != key else {return}
        if let selectionKey {selections[selectionKey] = (selectedModel,selectedEffort,selectedSpeed)}
        selectionKey = key
        let choice = selections[key] ?? (defaults.string(forKey:"petChatModel"),defaults.string(forKey:"petChatEffort"),ChatSpeed.saved(in:defaults))
        selectedModel = choice.0; selectedEffort = choice.1; selectedSpeed = choice.2
        notify()
    }
    func clearSelections() {selections.removeAll(); selectionKey = nil; conversation = nil}
    func forget(_ key:String) {selections.removeValue(forKey:key)}
    @objc private func preferencesChanged(_ note:Notification) {
        guard (note.userInfo?["keys"] as? [String])?.contains(ChatSpeed.preferenceKey) == true else {return}
        selectedSpeed = ChatSpeed.saved(in:defaults)
        for key in Array(selections.keys) {selections[key]?.speed = selectedSpeed}
        notify()
    }
    func chooseSpeed(_ speed:ChatSpeed) {
        guard availableSpeeds.contains(speed) else {return}
        selectedSpeed = speed
        defaults.set(speed.rawValue,forKey:ChatSpeed.preferenceKey)
        notify()
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
        ["none":L10n.text(.conversation,"modelSelection.effortName.text"),"minimal":L10n.text(.conversation,"modelSelection.effortName.text.2"),"low":L10n.text(.conversation,"modelSelection.effortName.text.3"),"medium":L10n.text(.conversation,"modelSelection.effortName.text.4"),"high":L10n.text(.conversation,"modelSelection.effortName.text.5"),"xhigh":L10n.text(.conversation,"modelSelection.effortName.text.6"),"max":"Max","ultra":"Ultra","persistent":L10n.text(.conversation,"modelSelection.effortName.text.7")][raw] ?? raw
    }
    var effortTitle: String {currentEffort.map(Self.effortName) ?? (providerMismatch ? L10n.text(.conversation,"modelSelection.effortName.text.8") : L10n.text(.conversation,"modelSelection.effortName.text.9"))}
    var effortExplanation: String {
        guard let effort = currentEffort else {return L10n.text(.conversation,"modelSelection.effortName.text.10")}
        let descriptions = ["none":L10n.text(.conversation,"modelSelection.descriptions"), "minimal":L10n.text(.conversation,"modelSelection.descriptions.2"),
            "low":L10n.text(.conversation,"modelSelection.effortName.text.11"), "medium":L10n.text(.conversation,"modelSelection.effortName.text.12"),
            "high":L10n.text(.conversation,"modelSelection.effortName.text.13"), "xhigh":L10n.text(.conversation,"modelSelection.effortName.text.14"),
            "max":L10n.text(.conversation,"modelSelection.effortName.text.15"),
            "ultra":L10n.text(.conversation,"modelSelection.effortName.text.16")]
        return descriptions[effort] ?? L10n.format(.conversation,"modelSelection.effortName.text.17",String(describing:Self.effortName(effort)))
    }
    var defaultTitle: String {
        let id = configuredModel ?? models.first(where:{$0.isDefault})?.model
        let name = models.first(where:{$0.model == id})?.displayName ?? id ?? L10n.text(.conversation,"modelSelection.effortName.text.18")
        return L10n.text(.conversation,"modelSelection.effortName.text.19")+name+L10n.text(.conversation,"modelSelection.effortName.text.20")
    }
    func syncWithCodex() {
        defaults.removeObject(forKey:"petChatModel")
        defaults.removeObject(forKey:"petChatEffort")
        selectedModel = nil; selectedEffort = nil; selectedSpeed = nil
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
        if selectedSpeed == nil,configuredProvider == "openai" {defaults.set(speed.rawValue,forKey:ChatSpeed.preferenceKey)}
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
            throw PetFailure(message:L10n.format(.conversation,"chatController.submit.text",String(describing:providerTitle ?? L10n.text(.conversation,"modelSelection.parameters.error"))))
        }
        if let modelOverride, !models.contains(where:{$0.model == modelOverride}) {
            throw PetFailure(message:L10n.text(.conversation,"modelSelection.parameters.message.2"))
        }
        var result = [String:Any]()
        // 关闭时明确覆盖旧线程的快速档，不能省略后继承上轮设置。
        if configuredProvider == "openai" {result["serviceTier"] = speed == .standard ? "default" : currentModel?.tier(for:speed)?.id}
        if let model = currentModelID {result["model"] = model}
        if let effort = currentEffort {
            if let currentModel, !currentModel.supportedReasoningEfforts.contains(where:{$0.reasoningEffort == effort}) {
                throw PetFailure(message:L10n.text(.conversation,"modelSelection.parameters.message.3"))
            }
            result["effort"] = effort
        }
        return result
    }
    private func notify() {NotificationCenter.default.post(name:Self.changed,object:self)}
}
