import Foundation

// 只验证被本客户端消费的必要字段，未知事件仍由上层忽略。
enum CodexProtocol {
    enum Failure: LocalizedError {
        case timeout, disconnected, malformed(String)
        var isTimeout:Bool {if case .timeout = self {return true}; return false}
        var errorDescription:String? {
            switch self {
            case .timeout: return "Codex 请求超时，任务状态尚未确认。"
            case .disconnected: return "Codex 任务连接未建立。"
            case .malformed(let field): return "Codex 协议格式错误："+field+"。"
            }
        }
    }
    static func object(_ data:Data) throws -> [String:Any] {
        guard let value = try JSONSerialization.jsonObject(with:data) as? [String:Any] else {
            throw Failure.malformed("消息必须是对象")
        }
        return value
    }
    static func validate(_ method:String,_ params:[String:Any]) throws {
        func requireID(_ value:Any?) throws {
            guard let id = value as? String,!id.isEmpty else {throw Failure.malformed("缺少有效标识")}
        }
        switch method {
        case "item/agentMessage/delta":
            try requireID(params["itemId"])
            guard params["delta"] is String else {throw Failure.malformed("消息增量必须是文本")}
        case "turn/started", "turn/completed":
            try requireID((params["turn"] as? [String:Any])?["id"])
        case "item/tool/requestUserInput":
            guard let questions = params["questions"] as? [[String:Any]],!questions.isEmpty else {throw Failure.malformed("缺少问题列表")}
            var ids = Set<String>()
            for question in questions {
                try requireID(question["id"])
                guard let id = question["id"] as? String else {throw Failure.malformed("缺少问题标识")}
                guard ids.insert(id).inserted else {throw Failure.malformed("问题标识重复")}
                guard question["question"] is String else {throw Failure.malformed("缺少问题正文")}
            }
        default: break
        }
    }
}
