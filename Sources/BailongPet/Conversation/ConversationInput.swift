import Foundation

enum ConversationKind:Int,CaseIterable {
    case persona, project
    var title:String {self == .persona ? L10n.text(.conversation,"conversationInput.conversationKind.text") : L10n.text(.conversation,"conversationInput.conversationKind.text.2")}
    var symbol:String {self == .persona ? "bubble.left" : "folder"}
}
extension Conversation {
    var kind:ConversationKind {external ? .project : .persona}
}

struct ComposerDestination {
    static let defaultsKey = "lastComposerDestination"
    let kind:ConversationKind
    let conversationKey:String?

    init?(defaults:UserDefaults) {
        guard let saved = defaults.dictionary(forKey:Self.defaultsKey),
              let raw = saved["kind"] as? Int,let kind = ConversationKind(rawValue:raw) else {return nil}
        self.kind = kind
        conversationKey = saved["conversation"] as? String
    }

    func resolve(in conversations:[Conversation]) -> Conversation? {
        conversations.first {$0.key == conversationKey && $0.kind == kind}
    }

    static func save(_ kind:ConversationKind,conversation:Conversation?,in defaults:UserDefaults) {
        var saved:[String:Any] = ["kind":kind.rawValue]
        saved["conversation"] = conversation?.key
        defaults.set(saved,forKey:defaultsKey)
    }
}
enum ChatEntry:Hashable {case composer, history}

// 两个输入入口各自按会话保存文字，仅驻留内存。普通刷新不保存或覆盖输入。
final class ChatDraftCache {
    private var values = [ChatEntry:[String:String]]()
    private var targets = [ChatEntry:String]()
    func target(_ entry:ChatEntry) -> String? {targets[entry]}
    func select(_ key:String?,entry:ChatEntry,current:String) -> String? {
        guard targets[entry] != key else {return nil}
        if let old = targets[entry] {values[entry,default:[:]][old] = current}
        targets[entry] = key
        return key.flatMap {values[entry]?[$0]} ?? ""
    }
    func clearSubmitted(key:String,entry:ChatEntry,text:String) {
        if values[entry]?[key]?.trimmingCharacters(in:.whitespacesAndNewlines) == text {values[entry]?[key] = ""}
    }
    func forget(_ key:String) {
        for entry in [ChatEntry.composer,.history] {values[entry]?.removeValue(forKey:key)}
    }
    func clear() {values.removeAll(); targets.removeAll()}
}

// 两个界面共用的显示状态，不持有发送逻辑或改变任务生命周期。
struct ChatInputState {
    static let jumpToCodexTitle = L10n.text(.conversation,"conversationInput.jumpToCodexTitle")
    static let steeringHint = L10n.format(.conversation,"conversationInput.steeringHint",String(describing:jumpToCodexTitle))
    var conversation:Conversation?
    var kind:ConversationKind = .persona
    var runningTitle:String?
    var ownsRunningTask = false
    var stopping = false, executing = false, newConversation = false
    var sending = false, unconfirmed = false, readOnly = false
    var replyMode:DesktopReply.Mode?
    var modelSettings:DesktopReply.Settings?
    var modelNote:DesktopConversationSession.ModelNotice?
    var replyNote:String?
    var desktopReady = false
    var desktopPreparing = false
    var requiresCodexForSteering = false
    var showsSteeringHint:Bool {requiresCodexForSteering && canEdit && !unconfirmed && replyNote == nil}
    var showsModelRetry:Bool {!desktopReady && modelNote?.canRetry == true}
    var canEdit:Bool {conversation != nil && runningTitle == nil && !sending && !readOnly}
    func canSend(models:ChatModelSettings) -> Bool {
        canEdit && !unconfirmed && (kind == .project ? conversation?.threadID != nil && replyMode != nil : !models.loading && models.error == nil)
    }
    var composerTitle:String {
        let preferences = PetPreferences.shared
        if stopping {return preferences.statusLine("taskStoppingTemplate")}
        if executing {return preferences.statusLine("conversationBusyTemplate")}
        if newConversation {return preferences.statusLine("conversationNewTemplate")}
        return preferences.fixedText(L10n.text(.dialogue,"dialogue.askWhatToHelp"))
    }
    var historyNote:String {
        if !note.isEmpty {return note}
        guard conversation != nil,kind == .persona else {return ""}
        return PetPreferences.shared.statusLine(newConversation ? "conversationNewTemplate" : "historyIdleTemplate")
    }
    var note:String {
        if readOnly {return L10n.text(.conversation,"conversationInput.canSend.text")}
        if conversation == nil {return L10n.text(.conversation,"conversationInput.canSend.text.2")}
        if sending {return replyNote ?? L10n.text(.conversation,"conversationInput.canSend.text.3")}
        if unconfirmed {return replyNote ?? L10n.text(.conversation,"conversationInput.canSend.text.4")}
        if stopping {return PetPreferences.shared.statusLine("taskStoppingTemplate")}
        if ownsRunningTask {return PetPreferences.shared.statusLine("historyBusyTemplate")}
        if let runningTitle {return L10n.text(.conversation,"conversationInput.canSend.text.5")+runningTitle}
        if let replyNote {return replyNote}
        if showsSteeringHint {return Self.steeringHint}
        if kind == .project {
            if replyMode == nil {return L10n.text(.conversation,"conversationInput.canSend.text.6")}
            if !desktopReady {return L10n.text(.conversation,"conversationInput.canSend.text.7")}
            return replyMode == .steer ? L10n.text(.conversation,"conversationInput.canSend.text.8") : ""
        }
        return ""
    }
}
