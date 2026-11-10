import Foundation

// 缓存输入属于输入，推理输出属于输出；总数使用服务端字段，不重复相加。
struct TokenUsage:Codable,Equatable {
    let input:Int64, cachedInput:Int64, output:Int64, total:Int64
    static let zero = TokenUsage(input:0,cachedInput:0,output:0,total:0)
    static func read(_ raw:Any?,camelCase:Bool = false) -> TokenUsage? {
        guard let value = raw as? [String:Any] else {return nil}
        let keys = camelCase ? ["inputTokens","cachedInputTokens","outputTokens","totalTokens"] : ["input_tokens","cached_input_tokens","output_tokens","total_tokens"]
        let numbers = keys.compactMap {value[$0] as? NSNumber}.map(\.int64Value)
        guard numbers.count == 4,numbers.allSatisfy({$0 >= 0}) else {return nil}
        return TokenUsage(input:numbers[0],cachedInput:numbers[1],output:numbers[2],total:numbers[3])
    }
    func subtracting(_ earlier:TokenUsage) -> TokenUsage? {
        guard input >= earlier.input,cachedInput >= earlier.cachedInput,output >= earlier.output,total >= earlier.total else {return nil}
        return TokenUsage(input:input-earlier.input,cachedInput:cachedInput-earlier.cachedInput,output:output-earlier.output,total:total-earlier.total)
    }
    static func formatted(_ value:Int64) -> String {value.formatted(.number.locale(Locale(identifier:"en_US")))}
    var signature:String {"\(input):\(cachedInput):\(output):\(total)"}
    var details:String {"输入\t\(Self.formatted(input))\tTokens\n缓存命中\t\(Self.formatted(cachedInput))\tTokens\n输出\t\(Self.formatted(output))\tTokens"}
}

// 同一轮中的通知是会话累计快照；重复通知不累加，首次通知的 last 仅用于恢复起点。
struct TurnTokenAccumulator {
    private var baseline:TokenUsage?
    private var latest:TokenUsage?
    private var invalid = false
    mutating func receive(_ raw:Any?) {
        guard let value = raw as? [String:Any],let total = TokenUsage.read(value["total"],camelCase:true) else {return}
        if baseline == nil {
            guard let last = TokenUsage.read(value["last"],camelCase:true),let start = total.subtracting(last) else {invalid = true; return}
            baseline = start
        }
        if let latest,total.subtracting(latest) == nil {invalid = true}
        latest = total
    }
    var usage:TokenUsage? {
        guard !invalid,let baseline,let latest else {return nil}
        return latest.subtracting(baseline)
    }
}
