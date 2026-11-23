import Foundation

enum TaskOutcome {
    static let stoppedStatuses: Set<String> = ["interrupted", "cancelled", "canceled"]
    static let terminalStatuses = stoppedStatuses.union(["completed", "failed"])

    /// 会话标题来自用户，禁止将它回填为助手的结果正文。
    static func body(status: String, error: String, final: String) -> String {
        if status != "completed",let description = CodexErrorMessage(error) {return description.body}
        if !final.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return final}
        switch status {
        case "completed": return L10n.text(.tasks,"taskOutcome.body.text")
        case _ where stoppedStatuses.contains(status): return L10n.text(.tasks,"taskOutcome.body.text.2")
        default: return L10n.text(.tasks,"taskOutcome.body.text.3")
        }
    }
}
