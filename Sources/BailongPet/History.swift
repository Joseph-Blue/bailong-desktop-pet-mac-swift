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
struct HistoryDocument: Codable { var schemaVersion = 1; var conversations: [Conversation] }
final class HistoryStore {
    var conversations = [Conversation]()
    var onError: (Error) -> Void = { _ in }
    var onSaved: () -> Void = {}
    private let queue = DispatchQueue(label:"白龙娘历史保存")
    private let url = Paths.data.appendingPathComponent("conversations.json")
    private var recording: Bool
    private var archive = HistoryDocument(conversations:[])
    private var excludedTurns = Set<String>()
    private var savingSuspended = false // 仅由写入队列访问。
    init(recording:Bool = true) throws {
        self.recording = recording
        if FileManager.default.fileExists(atPath:url.path) {
            let data = try Data(contentsOf:url)
            let document = try JSONDecoder().decode(HistoryDocument.self,from:data)
            guard document.schemaVersion == 1 else { throw PetFailure(message:"历史格式不兼容，原文件已保留。") }
            conversations = document.conversations
            archive = try JSONDecoder().decode(HistoryDocument.self,from:data)
            for conversation in conversations { for turn in conversation.turns where turn.owned && (activeStatuses.contains(turn.status) || turn.status == "unknown") {
                turn.status = "interrupted"; turn.error = "上次程序退出，任务未确认完成。"
            }}
        }
    }
    func setRecording(_ enabled:Bool) {
        guard recording != enabled else {return}
        if recording {save()}
        // 关闭期间的内容不在重新开启时补写，进行中的旧条目保留关闭前的版本。
        excludedTurns.formUnion(conversations.flatMap { $0.turns.map(\.key) })
        recording = enabled
    }
    @discardableResult func create(cwd: String, external: Bool = false) -> Conversation {
        let c = Conversation(); c.cwd = cwd; c.external = external; conversations.append(c); return c
    }
    func save() {save(retrying:false)}
    func retrySave() {save(retrying:true)}
    private func save(retrying:Bool) {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            if recording {
                // 独立快照避免后续任务修改已冻结的历史对象。
                let snapshot = try JSONDecoder().decode(HistoryDocument.self,from:encoder.encode(HistoryDocument(conversations:conversations)))
                let saved = Dictionary(uniqueKeysWithValues:archive.conversations.map {($0.key,$0)})
                var records = [Conversation]()
                for conversation in snapshot.conversations {
                    let old = saved[conversation.key]
                    let oldTurns = Dictionary(uniqueKeysWithValues:(old?.turns ?? []).map {($0.key,$0)})
                    let hadExcluded = conversation.turns.contains {excludedTurns.contains($0.key)}
                    conversation.turns = conversation.turns.compactMap {excludedTurns.contains($0.key) ? oldTurns[$0.key] : $0}
                    guard !conversation.turns.isEmpty || old != nil else {continue}
                    if hadExcluded {conversation.title = old?.title ?? "对话记录"}
                    records.append(conversation)
                }
                archive = HistoryDocument(conversations:records)
            } else {
                excludedTurns.formUnion(conversations.flatMap {$0.turns.map(\.key)})
                if !retrying {return}
            }
            // 关闭记录时，手动重新保存仅写关闭前的快照。
            let data = try encoder.encode(archive)
            queue.async { [self] in
                if retrying {savingSuspended = false}
                guard !savingSuspended else {return}
                do {
                    try FileManager.default.createDirectory(at:Paths.data,withIntermediateDirectories:true)
                    try data.write(to:url,options:.atomic)
                    DispatchQueue.main.async { self.onSaved() }
                } catch {
                    savingSuspended = true
                    DispatchQueue.main.async { self.onError(error) }
                }
            }
        } catch { onError(error) }
    }
    func finish() { save(); queue.sync {} }
    func clear() throws {
        queue.sync {}
        let data = try JSONEncoder().encode(HistoryDocument(conversations:[]))
        try data.write(to:url,options:.atomic)
        conversations.removeAll(); archive = HistoryDocument(conversations:[]); excludedTurns.removeAll()
        queue.sync {savingSuspended = false}
    }
}
