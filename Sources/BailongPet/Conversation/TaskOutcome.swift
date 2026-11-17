import Foundation

enum TaskOutcome {
    /// 会话标题来自用户，禁止将它回填为助手的结果正文。
    static func body(status: String, error: String, final: String) -> String {
        if status != "completed",let description = CodexErrorMessage(error) {return description.body}
        if !final.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return final}
        switch status {
        case "completed": return "任务已完成，Codex 未提供文字回复。"
        case "interrupted": return "本次任务已中断，未收到最终回复。"
        default: return "本次任务执行失败，Codex 未提供错误说明。"
        }
    }
}
