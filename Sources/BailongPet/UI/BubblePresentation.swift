import Foundation

struct TaskTiming {
    var start:Date? = nil
    var key:String? = nil
    var finished:Date? = nil
    var status:String? = nil
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

struct BubbleCard {
    var id:String
    var title:String, body:String, kind:String
    var scale:Double, seconds:Double
    var thread:String?
    var purpose:MessagePurpose
    var followsText:Bool, resetText:Bool, animateHeading:Bool, attentionAction:Bool
    var timing:TaskTiming?
    var question:QuestionPresentation?
    var details:() -> Void
    var codex:() -> Void
    var reply:(() -> Void)?
    var form:QuestionForm? = nil
    var questionSize:NSSize? = nil
}
