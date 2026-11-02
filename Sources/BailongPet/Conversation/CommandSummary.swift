import Foundation

// 只持久化操作与结果状态；原始命令输出留在 Codex 原会话。
enum CommandSummary {
    static func text(_ item:[String:Any]) -> String {
        let status = item["status"] as? String ?? ""
        let command = item["command"] as? String ?? ""
        return [status,command].filter {!$0.isEmpty}.joined(separator:" · ")
    }
}
