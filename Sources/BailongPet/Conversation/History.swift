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
    var completedAt:Date? = nil
    var lastMessageAt:Date? = nil
    var owned = true
    var finished = false
    var notices = [String:Double]()
    func snapshot() -> Turn {
        let t = Turn()
        t.id = id; t.key = key; t.input = input; t.status = status
        t.messages = messages; t.summary = summary; t.steps = steps; t.final = final; t.error = error
        t.sensitiveInputNotice = sensitiveInputNotice; t.sensitiveQuestionNotice = sensitiveQuestionNotice
        t.model = model; t.effort = effort; t.date = date; t.completedAt = completedAt; t.lastMessageAt = lastMessageAt; t.owned = owned
        t.finished = finished; t.notices = notices
        return t
    }
}
final class Conversation: Codable {
    var key = UUID().uuidString
    var threadID: String? = nil
    var title = "新对话"
    var localTitle: String? = nil
    var cwd = ""
    var external = false
    var historyMode = "legacy"
    var turns = [Turn]()
    var lastActivity:Date {
        turns.map {max($0.date,$0.completedAt ?? .distantPast,$0.lastMessageAt ?? .distantPast)}.max() ?? .distantPast
    }
    func snapshot() -> Conversation {
        let copy = Conversation()
        copy.key = key; copy.threadID = threadID; copy.title = title; copy.localTitle = localTitle
        copy.cwd = cwd; copy.external = external; copy.historyMode = historyMode
        copy.turns = turns.map {$0.snapshot()}
        return copy
    }
}
// 可选策略字段兼容已有 schema 1 文件。关闭期间只记录排除身份与时间，不保存正文。
struct HistoryRecordingPolicy: Codable {
    var excludedTurns = Set<String>()
    var externalBefore: Double = 0
    var disabled = false
    var deletedThreads: Set<String>? = nil
}
struct HistoryDocument: Codable {
    var schemaVersion = 2
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
    private(set) var readOnlyReason:String?
    var isReadOnly:Bool {readOnlyReason != nil}
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
    var deletedThreads: Set<String> {policy.deletedThreads ?? []}
    var recordsAutomatically: Bool {recording}
    init(recording:Bool = true, directory:URL = Paths.data) throws {
        url = directory.appendingPathComponent("conversations.json")
        self.recording = recording
        if FileManager.default.fileExists(atPath:url.path) {
            do {
                var document = try JSONDecoder().decode(HistoryDocument.self,from:Data(contentsOf:url))
                try document.validateIdentity()
                conversations = document.conversations
                policy = document.recordingPolicy ?? HistoryRecordingPolicy()
                if document.schemaVersion == 1 {
                    let backup = directory.appendingPathComponent("conversations-before-schema2-\(Int(Date().timeIntervalSince1970*1000)).json")
                    try FileManager.default.copyItem(at:url,to:backup)
                    document.schemaVersion = 2
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                    try encoder.encode(document).write(to:url,options:.atomic)
                } else if document.schemaVersion != 2 {
                    readOnlyReason = "历史格式 \(document.schemaVersion) 由其他版本保存，当前只读展示可识别的内容。"
                }
            } catch {
                readOnlyReason = "历史读取或升级未完成，原文件保留："+error.localizedDescription
            }
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
    func requireWritable() throws {
        if let readOnlyReason {throw PetFailure(message:readOnlyReason+" 请在设置 → 高级中导出原文件或重新读取。")}
    }
    func exportOriginal(to destination:URL) throws {try Data(contentsOf:url).write(to:destination,options:.atomic)}
    func reload(recording:Bool) throws {
        guard isReadOnly else {return}
        let fresh = try HistoryStore(recording:recording,directory:url.deletingLastPathComponent())
        try fresh.requireWritable()
        queue.sync {}
        conversations = fresh.conversations; archive = fresh.archive; policy = fresh.policy; self.recording = fresh.recording
        readOnlyReason = nil
        lock.withLock {suspended = false; pending = nil; writeEpoch += 1}
    }
    func setRecording(_ enabled:Bool) {
        guard !isReadOnly else {return}
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
            copy.key = c.key; copy.threadID = c.threadID; copy.title = c.title; copy.localTitle = c.localTitle
            copy.cwd = c.cwd; copy.external = c.external; copy.historyMode = c.historyMode
            var frozen = false
            for t in c.turns {
                let excluded = preservingExcluded && (policy.excludedTurns.contains(t.key) ||
                    (c.external && t.date.timeIntervalSince1970 <= policy.externalBefore))
                if excluded {frozen = true; if let previous = oldTurns[t.key] {copy.turns.append(previous)}}
                else {copy.turns.append(t.snapshot())}
            }
            if frozen {copy.title = old?.title ?? "对话记录"; copy.localTitle = old?.localTitle}
            if !preservingExcluded || !copy.turns.isEmpty || old != nil {records.append(copy)}
        }
        return HistoryDocument(conversations:records,recordingPolicy:policy)
    }
    private func save(retrying:Bool) {
        guard !isReadOnly else {return}
        if !recording {freezeCurrentTurns()}
        guard retrying || (recording && !lock.withLock({suspended})) else {return}
        if recording {archive = makeSnapshot()}
        enqueue(HistoryDocument(conversations:archive.conversations,recordingPolicy:policy),retrying:retrying)
    }
    private func enqueue(_ document:HistoryDocument,retrying:Bool) {
        guard !isReadOnly else {return}
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
    // 明确的管理操作也适用于关闭自动记录时的冻结副本；落盘成功后才改变界面。
    func setTitle(_ title:String, for conversation:Conversation, manual:Bool) throws {
        queue.sync {}
        var document = recording ? makeSnapshot() : archive
        document.conversations = document.conversations.map {$0.snapshot()}
        if let copy = document.conversations.first(where:{$0.key == conversation.key}) {
            copy.title = title; copy.localTitle = manual ? title : nil
        } else {
            let copy = Conversation(); copy.key = conversation.key; copy.threadID = conversation.threadID
            copy.cwd = conversation.cwd; copy.external = conversation.external; copy.historyMode = conversation.historyMode
            copy.title = title; copy.localTitle = manual ? title : nil
            document.conversations.append(copy)
        }
        document.recordingPolicy = policy
        try commitManagement(document)
        conversation.title = title; conversation.localTitle = manual ? title : nil
    }
    func delete(_ conversation:Conversation) throws {
        queue.sync {}
        var document = recording ? makeSnapshot() : archive
        document.conversations.removeAll {$0.key == conversation.key}
        var nextPolicy = policy
        if let id = conversation.threadID {
            var deleted = nextPolicy.deletedThreads ?? []; deleted.insert(id); nextPolicy.deletedThreads = deleted
        }
        nextPolicy.excludedTurns.subtract(conversation.turns.map(\.key))
        document.recordingPolicy = nextPolicy
        try commitManagement(document)
        policy = nextPolicy; conversations.removeAll {$0.key == conversation.key}
    }
    private func commitManagement(_ document:HistoryDocument) throws {
        try requireWritable()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
        archive = document
        lock.withLock {suspended = false; pending = nil; writeEpoch += 1}
        onSaved()
    }
    func clear() throws {
        try requireWritable()
        queue.sync {}
        let fresh = HistoryRecordingPolicy(externalBefore:Date().timeIntervalSince1970,disabled:!recording)
        let document = HistoryDocument(conversations:[],recordingPolicy:fresh)
        try JSONEncoder().encode(document).write(to:url,options:.atomic)
        conversations.removeAll(); archive = document; policy = fresh
        lock.withLock {suspended = false; writeEpoch += 1}
    }
}
