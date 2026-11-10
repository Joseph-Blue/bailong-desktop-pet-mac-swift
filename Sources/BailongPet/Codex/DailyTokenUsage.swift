import Foundation

enum DailyTokenUsage {
    case loading
    case available(tokens:Int64)
    case failed(String)

    var value:String {
        switch self {
        case .loading:return "加载中"
        case .available(let tokens):return TokenUsage.formatted(tokens)+" Tokens"
        case .failed:return "读取失败"
        }
    }
    var detail:String? {
        if case .failed(let message) = self {return message}
        return nil
    }
    var isLoading:Bool {if case .loading = self {return true}; return false}
    var failed:Bool {if case .failed = self {return true}; return false}
}
