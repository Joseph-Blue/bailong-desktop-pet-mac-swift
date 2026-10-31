import Foundation

enum TaskOutcome {
    static func title(_ status: String) -> String {
        switch status {
        case "completed": return "主人，完成啦！"
        case "interrupted": return "主人，任务已中断。"
        default: return "主人，这次任务执行失败。"
        }
    }
    /// 会话标题来自用户，禁止将它回填为助手的结果正文。
    static func body(status: String, error: String, final: String) -> String {
        let raw = error.trimmingCharacters(in:.whitespacesAndNewlines)
        if !raw.isEmpty, raw != "null" {
            if let json = try? JSONSerialization.jsonObject(with:Data(raw.utf8),options:.fragmentsAllowed) {
                let message = (json as? [String:Any])?["message"] as? String ?? json as? String
                if let message, !message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return message}
            } else {return raw}
        }
        if !final.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return final}
        switch status {
        case "completed": return "任务已完成，Codex 未提供文字回复。"
        case "interrupted": return "本次任务已中断，未收到最终回复。"
        default: return "本次任务执行失败，Codex 未提供错误说明。"
        }
    }
}
