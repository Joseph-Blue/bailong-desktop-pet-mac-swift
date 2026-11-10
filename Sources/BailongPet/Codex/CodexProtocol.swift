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
    // 接收线程只向 UI 交付实际消费的通知；请求和 RPC 回执保持原样。
    // 工具输出、原始思考和图像数据不进入主线程等待队列。
    static func delivery(_ message:[String:Any]) -> [String:Any]? {
        guard message["id"] == nil,let method = message["method"] as? String else {return message}
        guard ["thread/closed","thread/tokenUsage/updated","turn/started","turn/completed","error","item/agentMessage/delta",
               "item/reasoning/summaryTextDelta","item/started","item/completed","turn/plan/updated"].contains(method) else {return nil}
        guard var params = message["params"] as? [String:Any] else {return message}
        if let item = params["item"] as? [String:Any] {params["item"] = publicItem(item)}
        if let turn = params["turn"] as? [String:Any] {
            var projected = turn.filter {["id","status","error"].contains($0.key)}
            if let items = turn["items"] as? [[String:Any]] {projected["items"] = items.map(publicItem)}
            params["turn"] = projected
        }
        var result = message; result["params"] = params
        return result
    }
    private static func publicItem(_ item:[String:Any]) -> [String:Any] {
        var result = DesktopRuntimeProjection.item(item)
        if item["type"] as? String == "agentMessage" {
            result["text"] = item["text"]; result["phase"] = item["phase"]
        } else if item["type"] as? String == "imageGeneration" {result["savedPath"] = item["savedPath"]}
        return result
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
