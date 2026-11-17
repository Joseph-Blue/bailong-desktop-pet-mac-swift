import Foundation

enum DailyTokenUsage {
    case loading
    case available(usage:TokenUsage)
    case failed(String)

    var value:String {
        switch self {
        case .loading:return "加载中"
        case .available(let usage):return TokenUsage.amount(usage.total)
        case .failed:return "读取失败"
        }
    }
    var usage:TokenUsage? {if case .available(let usage) = self {return usage}; return nil}
    var detail:String? {
        if case .failed(let message) = self {return message}
        return nil
    }
    var isLoading:Bool {if case .loading = self {return true}; return false}
    var failed:Bool {if case .failed = self {return true}; return false}
}
