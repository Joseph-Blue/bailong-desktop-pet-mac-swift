import Foundation

struct TaskTiming {
    var start:Date? = nil
    var key:String? = nil
    var finished:Date? = nil
    var status:String? = nil
    // 内置任务的调度键为 own，显示进展仍使用真实轮次 key。
    var activityKey:String? = nil
    func matchesActivity(key:String,start:Date) -> Bool {
        finished == nil && key == (activityKey ?? self.key) && self.start == start
    }
    static func elapsed(start:Date,end:Date = Date()) -> String {
        let seconds = max(0,Int(end.timeIntervalSince(start)))
        return seconds >= 3600 ? String(format:"%d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60) : String(format:"%02d:%02d",seconds/60,seconds%60)
    }
}
struct QuestionPresentation {
    var questions:[TaskQuestion] = []
    var submit: (([String:String], @escaping (Error?) -> Void) -> Void)? = nil
    var skip: ((Set<String>) -> Void)? = nil
}

struct BubbleContent {
    var title: String
    var body: String
    var kind: String
    var animateHeading = false
    var timing: TaskTiming?
    var conversation: String?
    var failure: AppFailure?
}

struct BubbleCard {
    enum Priority:Int {case companion, message, request}
    var id:String
    var content: BubbleContent
    var purpose:MessagePurpose
    var resetText:Bool, attentionAction:Bool
    var question:QuestionPresentation?
    var details:() -> Void
    var codex:() -> Void
    var reply:(() -> Void)?
    var approval:ApprovalPresentation? = nil
    var fileEdits = [FileEditSummary]()
    var showsTaskOverview = false
    var isUserInput = false
    var completionFooter:TurnCompletion? = nil
    var form:QuestionForm? = nil
    var questionSize:NSSize? = nil
    var retainsQuestionDraft = false
    var priority:Priority {
        if attentionAction {return .request}
        if showsTaskOverview || (content.conversation == nil && purpose == .interaction) {return .companion}
        return .message
    }
}
