import Foundation

let activeStatuses: Set<String> = ["pending","running","inProgress","waitingForApproval","waitingForInput"]
final class Turn: Codable {
    var id: String? = nil
    var key = UUID().uuidString
    var input = "", status = "pending", messages = "", summary = "", steps = "", final = "", error = ""
    var sensitiveInputNotice: String? = nil
    var sensitiveQuestionNotice: String? = nil
    var model: String? = nil, effort: String? = nil
    var date = Date()
    var owned = true
    var finished = false
    var notices = [String:Double]()
    func snapshot() -> Turn {
        let t = Turn()
        t.id = id; t.key = key; t.input = input; t.status = status
        t.messages = messages; t.summary = summary; t.steps = steps; t.final = final; t.error = error
        t.sensitiveInputNotice = sensitiveInputNotice; t.sensitiveQuestionNotice = sensitiveQuestionNotice
        t.model = model; t.effort = effort; t.date = date; t.owned = owned
        t.finished = finished; t.notices = notices
        return t
    }
}
final class Conversation: Codable {
    var key = UUID().uuidString
    var threadID: String? = nil
    var title = "新对话"
    var cwd = ""
    var external = false
    var historyMode = "legacy"
    var turns = [Turn]()
}
// 可选策略字段兼容已有 schema 1 文件。关闭期间只记录排除身份与时间，不保存正文。
struct HistoryRecordingPolicy: Codable {
    var excludedTurns = Set<String>()
    var externalBefore: Double = 0
    var disabled = false
}
struct HistoryDocument: Codable {
    var schemaVersion = 1
    var conversations: [Conversation]
    var recordingPolicy: HistoryRecordingPolicy? = nil
    func validateIdentity() throws {
        var keys = Set<String>(), turns = Set<String>()
        for conversation in conversations {
            guard keys.insert(conversation.key).inserted else {throw PetFailure(message:"历史包含重复会话标识，原文件已保留。")}
            for turn in conversation.turns {
                guard turns.insert(turn.key).inserted else {throw PetFailure(message:"历史包含重复轮次标识，原文件已保留。")}
            }
        }
    }
}
final class HistoryStore {
    var conversations = [Conversation]()
    var onError: (Error) -> Void = { _ in }
    var onSaved: () -> Void = {}
    private let queue = DispatchQueue(label:"白龙娘历史保存")
    private let lock = NSLock()
    private let url: URL
    private var recording: Bool
    private var archive = HistoryDocument(conversations:[])
    private var policy = HistoryRecordingPolicy()
    // 以下状态只在 lock 内访问；排队快照不再由界面修改。
    private var suspended = false, draining = false
    private var pending: HistoryDocument?
    private var writeEpoch = 0
    init(recording:Bool = true, directory:URL = Paths.data) throws {
        url = directory.appendingPathComponent("conversations.json")
        self.recording = recording
        if FileManager.default.fileExists(atPath:url.path) {
            let document = try JSONDecoder().decode(HistoryDocument.self,from:Data(contentsOf:url))
            guard document.schemaVersion == 1 else {throw PetFailure(message:"历史格式不兼容，原文件已保留。")}
            try document.validateIdentity()
            conversations = document.conversations
            policy = document.recordingPolicy ?? HistoryRecordingPolicy()
            archive = makeSnapshot(preservingExcluded:false)
            for conversation in conversations {for turn in conversation.turns where turn.owned && (activeStatuses.contains(turn.status) || turn.status == "unknown") {
                turn.status = "interrupted"; turn.error = "上次程序退出，任务未确认完成。"
            }}
        }
        if policy.disabled || !recording {
            freezeCurrentTurns()
            policy.externalBefore = Date().timeIntervalSince1970
        }
        policy.disabled = !recording
    }
    private func freezeCurrentTurns() {
        policy.excludedTurns.formUnion(conversations.flatMap {$0.turns.map(\.key)})
    }
    func setRecording(_ enabled:Bool) {
        guard recording != enabled else {return}
        if recording {archive = makeSnapshot()}
        freezeCurrentTurns()
        policy.externalBefore = Date().timeIntervalSince1970
        policy.disabled = !enabled; recording = enabled
        // 正文快照冻结；开关边界与快照一起原子落盘，重启仍遵守排除规则。
        enqueue(HistoryDocument(conversations:archive.conversations,recordingPolicy:policy),retrying:false)
    }
    @discardableResult func create(cwd:String,external:Bool = false) -> Conversation {
        let c = Conversation(); c.cwd = cwd; c.external = external; conversations.append(c); return c
    }
    func save() {save(retrying:false)}
    func retrySave() {save(retrying:true)}
    private func makeSnapshot(preservingExcluded:Bool = true) -> HistoryDocument {
        let saved = Dictionary(uniqueKeysWithValues:archive.conversations.map {($0.key,$0)})
        var records = [Conversation]()
        for c in conversations {
            let old = saved[c.key]
            let oldTurns = Dictionary(uniqueKeysWithValues:(old?.turns ?? []).map {($0.key,$0)})
            let copy = Conversation()
            copy.key = c.key; copy.threadID = c.threadID; copy.title = c.title
            copy.cwd = c.cwd; copy.external = c.external; copy.historyMode = c.historyMode
            var frozen = false
            for t in c.turns {
                let excluded = preservingExcluded && (policy.excludedTurns.contains(t.key) ||
                    (c.external && t.date.timeIntervalSince1970 <= policy.externalBefore))
                if excluded {frozen = true; if let previous = oldTurns[t.key] {copy.turns.append(previous)}}
                else {copy.turns.append(t.snapshot())}
            }
            if frozen {copy.title = old?.title ?? "对话记录"}
            if !preservingExcluded || !copy.turns.isEmpty || old != nil {records.append(copy)}
        }
        return HistoryDocument(conversations:records,recordingPolicy:policy)
    }
    private func save(retrying:Bool) {
        if !recording {freezeCurrentTurns()}
        guard retrying || (recording && !lock.withLock({suspended})) else {return}
        if recording {archive = makeSnapshot()}
        enqueue(HistoryDocument(conversations:archive.conversations,recordingPolicy:policy),retrying:retrying)
    }
    private func enqueue(_ document:HistoryDocument,retrying:Bool) {
        let start = lock.withLock { () -> Bool in
            if retrying {suspended = false}
            guard !suspended else {return false}
            pending = document
            guard !draining else {return false}
            draining = true; return true
        }
        if start {queue.async { [self] in drain() }}
    }
    private func drain() {
        while true {
            let next = lock.withLock { () -> (HistoryDocument,Int)? in
                guard let document = pending,!suspended else {draining = false; return nil}
                pending = nil; return (document,writeEpoch)
            }
            guard let (document,epoch) = next else {return}
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                let data = try encoder.encode(document)
                try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                try data.write(to:url,options:.atomic)
                DispatchQueue.main.async { [self] in if lock.withLock({writeEpoch == epoch && !suspended}) {onSaved()} }
            } catch {
                lock.withLock {suspended = true; pending = nil}
                DispatchQueue.main.async { [self] in if lock.withLock({writeEpoch == epoch}) {onError(error)} }
            }
        }
    }
    func finish() {save(); queue.sync {}}
    func clear() throws {
        queue.sync {}
        let fresh = HistoryRecordingPolicy(externalBefore:Date().timeIntervalSince1970,disabled:!recording)
        let document = HistoryDocument(conversations:[],recordingPolicy:fresh)
        try JSONEncoder().encode(document).write(to:url,options:.atomic)
        conversations.removeAll(); archive = document; policy = fresh
        lock.withLock {suspended = false; writeEpoch += 1}
    }
}
