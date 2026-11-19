import Foundation

enum DeepSeekPricing {
    static let platform = URL(string:"https://platform.deepseek.com/")!
    static let source = URL(string:"https://api-docs.deepseek.com/zh-cn/quick_start/pricing/")!
    static let calendar:Calendar = {
        var value = Calendar(identifier:.gregorian)
        value.timeZone = TimeZone(identifier:"Asia/Shanghai")!
        return value
    }()
    enum Period {
        case peak,offPeak
        var title:String {self == .peak ? "高峰时段（峰）" : "空闲时段（谷）"}
    }
    struct Snapshot {
        let period:Period
        let holiday:Bool
        let weekend:Bool
        let next:Date?
        var title:String {period.title+(holiday ? "中国法定节假日" : weekend ? "周末" : "")}
        var nextDescription:String {
            guard let next else {return "下一时段开始时间：未提供"}
            let format = DateFormatter(); format.locale = Locale(identifier:"en_US_POSIX")
            format.timeZone = DeepSeekPricing.calendar.timeZone; format.dateFormat = "yyyy-MM-dd HH:mm"
            let nextPeriod:Period = period == .peak ? .offPeak : .peak
            return "下一个\(nextPeriod.title)开始时间：\n\(format.string(from:next))\n（北京时间）"
        }
    }
    // 国务院公布的放假区间（包含调休休息日）；周末补班不改变 DeepSeek 的周末谷价。
    // 2026：https://www.beijing.gov.cn/cs/gncs/zcwj/202603/t20260327_4568275.html
    // 2027：https://www.forestry.gov.cn/lyj/1/szxx/20261105/695102.html
    private static let holidays:[Int:[ClosedRange<Int>]] = [
        2026:[101...103,215...223,404...406,501...505,619...621,925...927,1001...1007],
        2027:[101...103,205...213,403...405,501...505,609...609,915...915,1001...1007]
    ]
    static func state(at date:Date) -> (period:Period,holiday:Bool,weekend:Bool)? {
        let fields = calendar.dateComponents([.year,.month,.day,.weekday,.hour,.minute],from:date)
        guard let year = fields.year,let month = fields.month,let day = fields.day,
              let weekday = fields.weekday,let hour = fields.hour,let minute = fields.minute,
              let ranges = holidays[year] else {return nil}
        let holiday = ranges.contains {$0.contains(month*100+day)}
        let minutes = hour*60+minute
        let peak = !holiday && (2...6).contains(weekday) && ((540..<720).contains(minutes) || (840..<1080).contains(minutes))
        return (peak ? .peak : .offPeak,holiday,weekday == 1 || weekday == 7)
    }
    static func snapshot(at date:Date = Date()) -> Snapshot? {
        guard let current = state(at:date) else {return nil}
        // 最长已公布假期不足两周；逐日检查真实边界，不用每分钟轮询。
        let day = calendar.startOfDay(for:date)
        for offset in 0...15 {
            let candidateDay = calendar.date(byAdding:.day,value:offset,to:day)!
            for hour in [9,12,14,18] {
                let boundary = calendar.date(bySettingHour:hour,minute:0,second:0,of:candidateDay)!
                guard boundary > date else {continue}
                guard let next = state(at:boundary) else {
                    return Snapshot(period:current.period,holiday:current.holiday,weekend:current.weekend,next:nil)
                }
                if next.period != current.period {
                    return Snapshot(period:current.period,holiday:current.holiday,weekend:current.weekend,next:boundary)
                }
            }
        }
        return Snapshot(period:current.period,holiday:current.holiday,weekend:current.weekend,next:nil)
    }
    static func nextDisplayChange(at date:Date = Date()) -> Date? {
        guard let snapshot = snapshot(at:date) else {return nil}
        // 午夜更新节假日后缀；峰谷边界更新状态。只在界面可见期间使用。
        let midnight = calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:date))!
        return min(snapshot.next ?? midnight,midnight)
    }
    static func grouped(_ number:String) -> String {
        // 接口的十进制金额已验证；保留小数位，只在整数部分插入逗号。
        let parts = number.split(separator:".",omittingEmptySubsequences:false)
        let negative = parts[0].hasPrefix("-")
        let digits = negative ? String(parts[0].dropFirst()) : String(parts[0])
        let grouped = digits.enumerated().map {index,character in
            (index > 0 && (digits.count-index)%3 == 0 ? "," : "")+String(character)
        }.joined()
        return (negative ? "-" : "")+grouped+(parts.count > 1 ? "."+parts[1] : "")
    }
}
