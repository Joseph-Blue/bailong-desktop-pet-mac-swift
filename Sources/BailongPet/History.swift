import Foundation

let activeStatuses: Set<String> = ["pending","running","inProgress","waitingForApproval","waitingForInput"]
final class Turn: Codable {
    var id: String? = nil
    var key = UUID().uuidString
    var input = "", status = "pending", messages = "", summary = "", steps = "", final = "", error = ""
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
    private let queue = DispatchQueue(label:"白龙娘历史保存")
    private let url = Paths.data.appendingPathComponent("conversations.json")
    init() throws {
        if FileManager.default.fileExists(atPath:url.path) {
            let document = try JSONDecoder().decode(HistoryDocument.self,from:Data(contentsOf:url))
            guard document.schemaVersion == 1 else { throw PetFailure(message:"历史格式不兼容，原文件已保留。") }
            conversations = document.conversations
            for conversation in conversations { for turn in conversation.turns where turn.owned && (activeStatuses.contains(turn.status) || turn.status == "unknown") {
                turn.status = "interrupted"; turn.error = "上次程序退出，任务未确认完成。"
            }}
        }
    }
    @discardableResult func create(cwd: String, external: Bool = false) -> Conversation {
        let c = Conversation(); c.cwd = cwd; c.external = external; conversations.append(c); return c
    }
    func save() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            let data = try encoder.encode(HistoryDocument(conversations:conversations))
            queue.async { [self] in
                do { try FileManager.default.createDirectory(at:Paths.data,withIntermediateDirectories:true); try data.write(to:url,options:.atomic) }
                catch { DispatchQueue.main.async { self.onError(error) } }
            }
        } catch { onError(error) }
    }
    func finish() { save(); queue.sync {} }
}
