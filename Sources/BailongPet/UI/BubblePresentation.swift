import Foundation

struct TaskTiming {
    var start:Date? = nil
    var key:String? = nil
    var finished:Date? = nil
    var status:String? = nil
}
struct QuestionPresentation {
    var questions:[TaskQuestion] = []
    var submit: (([String:String], @escaping (Error?) -> Void) -> Void)? = nil
    var skip: ((Set<String>) -> Void)? = nil
}
