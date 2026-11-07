import Foundation

let activeStatuses: Set<String> = ["pending","running","inProgress","waitingForApproval","waitingForInput"]
final class Turn: Codable {
    var bodyReference = HistoryBodyReference()
    var id: String? = nil
    var key: String = UUID().uuidString
    var status: String = "pending"
    var model: String? = nil
    var effort: String? = nil
    var date: Date = Date()
    var completedAt: Date? = nil
    var lastMessageAt: Date? = nil
    var owned: Bool = true
    var finished: Bool = false
    var input:String {
        get {bodyReference.value().input}
        set {var body = bodyReference.value(); guard body.input != newValue else {return}; body.input = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var messages:String {
        get {bodyReference.value().messages}
        set {var body = bodyReference.value(); guard body.messages != newValue else {return}; body.messages = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var summary:String {
        get {bodyReference.value().summary}
        set {var body = bodyReference.value(); guard body.summary != newValue else {return}; body.summary = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var steps:String {
        get {bodyReference.value().steps}
        set {var body = bodyReference.value(); guard body.steps != newValue else {return}; body.steps = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var final:String {
        get {bodyReference.value().final}
        set {var body = bodyReference.value(); guard body.final != newValue else {return}; body.final = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var error:String {
        get {bodyReference.value().error}
        set {var body = bodyReference.value(); guard body.error != newValue else {return}; body.error = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var sensitiveInputNotice:String? {
        get {bodyReference.value().sensitiveInputNotice}
        set {var body = bodyReference.value(); guard body.sensitiveInputNotice != newValue else {return}; body.sensitiveInputNotice = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var sensitiveQuestionNotice:String? {
        get {bodyReference.value().sensitiveQuestionNotice}
        set {var body = bodyReference.value(); guard body.sensitiveQuestionNotice != newValue else {return}; body.sensitiveQuestionNotice = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var fileEdits:[FileEditSummary]? {
        get {bodyReference.value().fileEdits}
        set {var body = bodyReference.value(); guard body.fileEdits != newValue else {return}; body.fileEdits = newValue; bodyReference = HistoryBodyReference(body)}
    }
    var notices:[String:Double] {
        get {bodyReference.value().notices}
        set {var body = bodyReference.value(); guard body.notices != newValue else {return}; body.notices = newValue; bodyReference = HistoryBodyReference(body)}
    }
    init() {}
    private enum CodingKeys:String,CodingKey {case id,key,status,model,effort,date,completedAt,lastMessageAt,owned,finished,bodyID}
    init(from decoder:Swift.Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decodeIfPresent(String.self,forKey:.id)
        key = try c.decode(String.self,forKey:.key)
        status = try c.decode(String.self,forKey:.status)
        model = try c.decodeIfPresent(String.self,forKey:.model)
        effort = try c.decodeIfPresent(String.self,forKey:.effort)
        date = try c.decode(Date.self,forKey:.date)
        completedAt = try c.decodeIfPresent(Date.self,forKey:.completedAt)
        lastMessageAt = try c.decodeIfPresent(Date.self,forKey:.lastMessageAt)
        owned = try c.decode(Bool.self,forKey:.owned)
        finished = try c.decode(Bool.self,forKey:.finished)
        if let id = try c.decodeIfPresent(String.self,forKey:.bodyID) {
            guard let disk = decoder.userInfo[.historyDatabase] as? HistoryDatabase else {throw PetFailure(message:"历史正文引用缺少数据库")}
            bodyReference = HistoryBodyReference(id:id,disk:disk)
        } else {bodyReference = HistoryBodyReference(try HistoryBody(from:decoder))}
    }
    func encode(to encoder:Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encodeIfPresent(id,forKey:.id)
        try c.encode(key,forKey:.key)
        try c.encode(status,forKey:.status)
        try c.encodeIfPresent(model,forKey:.model)
        try c.encodeIfPresent(effort,forKey:.effort)
        try c.encode(date,forKey:.date)
        try c.encodeIfPresent(completedAt,forKey:.completedAt)
        try c.encodeIfPresent(lastMessageAt,forKey:.lastMessageAt)
        try c.encode(owned,forKey:.owned)
        try c.encode(finished,forKey:.finished)
        if encoder.userInfo[.historyIndex] as? Bool == true {try c.encode(bodyReference.id,forKey:.bodyID)}
        else {try bodyReference.value().encode(to:encoder)}
    }
    func snapshot() -> Turn {
        let t = Turn()
        t.id = id
        t.key = key
        t.status = status
        t.model = model
        t.effort = effort
        t.date = date
        t.completedAt = completedAt
        t.lastMessageAt = lastMessageAt
        t.owned = owned
        t.finished = finished
        t.bodyReference = bodyReference
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
    private var initialReadOnlyReason:String?
    var readOnlyReason:String? {initialReadOnlyReason ?? database?.readFailure}
    private var database:HistoryDatabase?
    var exportExtension:String {exportSourceURL.pathExtension}
    func clearBodyCache() {database?.clearCache()}
    var cachedBodyBytes:Int {database?.cachedBytes ?? 0}
    var isReadOnly:Bool {readOnlyReason != nil}
    private let queue = DispatchQueue(label:"白龙娘历史保存")
    private let lock = NSLock()
    private let url: URL
    private var exportSourceURL:URL
    private var recording: Bool
    private var archive = HistoryDocument(conversations:[])
    private var policy = HistoryRecordingPolicy()
    // 以下状态只在 lock 内访问；排队快照不再由界面修改。
    private var suspended = false, draining = false
    private var pending: HistoryDocument?
    private var writeEpoch = 0
    var deletedThreads: Set<String> {policy.deletedThreads ?? []}
    var recordsAutomatically: Bool {recording}
    func canEnrichInput(_ turn:Turn,in conversation:Conversation) -> Bool {
        recording && !isReadOnly && !policy.excludedTurns.contains(turn.key) &&
            (!conversation.external || turn.date.timeIntervalSince1970 > policy.externalBefore)
    }
    init(recording:Bool = true, directory:URL = Paths.data) throws {
        url = directory.appendingPathComponent("conversations.json")
        exportSourceURL = url
        self.recording = recording
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        do {
            let existed = FileManager.default.fileExists(atPath:databaseURL.path)
            var legacy:HistoryDocument?
            func readLegacy() throws -> HistoryDocument {
                let old = try JSONDecoder().decode(HistoryDocument.self,from:Data(contentsOf:url))
                try old.validateIdentity()
                guard [1,2].contains(old.schemaVersion) else {throw PetFailure(message:"历史格式不支持："+String(old.schemaVersion))}
                return old
            }
            if !existed,FileManager.default.fileExists(atPath:url.path) {legacy = try readLegacy()}
            if existed {exportSourceURL = databaseURL}
            let disk = try HistoryDatabase(url:databaseURL)
            var document = try disk.load()
            if document == nil {
                if legacy == nil,FileManager.default.fileExists(atPath:url.path) {exportSourceURL = url; legacy = try readLegacy()}
                if let legacy {try disk.write(legacy); document = try disk.load()}
            }
            database = disk; exportSourceURL = databaseURL
            if let document {
                conversations = document.conversations
                policy = document.recordingPolicy ?? HistoryRecordingPolicy()
            }
            archive = makeSnapshot(preservingExcluded:false)
            for conversation in conversations {for turn in conversation.turns where turn.owned && (activeStatuses.contains(turn.status) || turn.status == "unknown") {
                turn.status = "interrupted"; turn.error = "上次程序退出，任务未确认完成。"
            }}
        } catch {initialReadOnlyReason = "历史读取或升级未完成，原文件保留："+error.localizedDescription}
        database?.onReadFailure = { [weak self] error in self?.onError(error) }
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
    func exportOriginal(to destination:URL) throws {
        queue.sync {}
        if let database {try database.export(to:destination)}
        else {try Data(contentsOf:exportSourceURL).write(to:destination,options:.atomic)}
    }
    func reload(recording:Bool) throws {
        guard isReadOnly else {return}
        let fresh = try HistoryStore(recording:recording,directory:url.deletingLastPathComponent())
        try fresh.requireWritable()
        queue.sync {}
        conversations = fresh.conversations; archive = fresh.archive; policy = fresh.policy; self.recording = fresh.recording
        database = fresh.database; exportSourceURL = fresh.exportSourceURL; initialReadOnlyReason = nil
        database?.onReadFailure = { [weak self] error in self?.onError(error) }
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
                guard let database else {throw PetFailure(message:"历史数据库未打开")}
                try database.write(document)
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
        database?.clearCache()
    }
    private func commitManagement(_ document:HistoryDocument) throws {
        try requireWritable()
        guard let database else {throw PetFailure(message:"历史数据库未打开")}
        try database.write(document)
        archive = document
        lock.withLock {suspended = false; pending = nil; writeEpoch += 1}
        // 管理操作调用者还需更新当前会话；回执在其完成选择切换后刷新界面。
        DispatchQueue.main.async { [weak self] in self?.onSaved() }
    }
    func clear() throws {
        try requireWritable()
        queue.sync {}
        let fresh = HistoryRecordingPolicy(externalBefore:Date().timeIntervalSince1970,disabled:!recording)
        let document = HistoryDocument(conversations:[],recordingPolicy:fresh)
        guard let database else {throw PetFailure(message:"历史数据库未打开")}
        try database.write(document)
        database.clearCache()
        conversations.removeAll(); archive = document; policy = fresh
        lock.withLock {suspended = false; writeEpoch += 1}
    }
}
