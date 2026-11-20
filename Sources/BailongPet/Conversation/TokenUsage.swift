import Foundation

enum TokenCountFormat:String,CaseIterable {
    case full,international,chinese
    static let key = "tokenCountFormat"
    static let options = [(full.rawValue,"完整数字"),(international.rawValue,"K / M / B"),(chinese.rawValue,"万 / 亿")]
    func number(_ value:Int64) -> String {
        let units:[(size:Int64,name:String)]
        switch self {
        case .full:return TokenUsage.formatted(value)
        case .international:units = [(1_000,"K"),(1_000_000,"M"),(1_000_000_000,"B")]
        case .chinese:units = [(10_000,"万"),(100_000_000,"亿")]
        }
        guard let index = units.lastIndex(where:{value >= $0.size}) else {return TokenUsage.formatted(value)}
        var unit = units[index]
        // 用整数余数四舍五入到百分位，保留 Int64 大数精度。
        let step = unit.size/100
        var hundredths = value/step + (value%step >= step/2 ? 1 : 0)
        if index+1 < units.count,hundredths >= units[index+1].size/step {
            unit = units[index+1]; hundredths = 100
        }
        return "\(hundredths/100)."+String(format:"%02d",Int(hundredths%100))+" "+unit.name
    }
}

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
    func adding(_ other:TokenUsage) -> TokenUsage {
        TokenUsage(input:input+other.input,cachedInput:cachedInput+other.cachedInput,output:output+other.output,total:total+other.total)
    }
    static func formatted(_ value:Int64) -> String {value.formatted(.number.locale(Locale(identifier:"en_US")))}
    static func unit(_ value:Int64) -> String {value == 1 ? "Token" : "Tokens"}
    static func amount(_ value:Int64,separator:String = " ",format:TokenCountFormat = .full) -> String {format.number(value)+separator+unit(value)}
    var signature:String {"\(input):\(cachedInput):\(output):\(total)"}
    func details(format:TokenCountFormat) -> String {
        zip(["输入","缓存命中","输出"],[input,cachedInput,output]).map {title,value in title+"\t"+Self.amount(value,separator:"\t",format:format)}.joined(separator:"\n")
    }
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
