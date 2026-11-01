import Foundation
import CoreFoundation

struct QuotaResetCards {
    enum Expiration: Hashable {case date(Date), unlimited, unavailable}
    let availableCount: Int?
    let expirations: [Expiration]

    init(_ response: [String:Any]) {
        let summary = response["rateLimitResetCredits"] as? [String:Any]
        if let n = Self.number(summary?["availableCount"]), n >= 0, n < Double(Int.max), n.rounded() == n {
            availableCount = Int(n)
        } else {availableCount = nil}
        expirations = (summary?["credits"] as? [[String:Any]] ?? []).filter {$0["status"] as? String == "available"}.map { card in
            // 协议中显式 null 表示不限期；未返回此字段不作相同推断。
            if card["expiresAt"] is NSNull {return .unlimited}
            if let timestamp = Self.number(card["expiresAt"]) {return .date(Date(timeIntervalSince1970:timestamp))}
            return .unavailable
        }
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {return nil}
        return n.doubleValue
    }
    var amount: String {availableCount.map {"剩余 \($0) 张"} ?? "暂未提供"}
    var detail: String? {
        if availableCount == 0 {return nil}
        if expirations.isEmpty {return "过期时间暂未提供"}
        let groups = Dictionary(grouping:expirations,by:{$0})
        let order = groups.keys.sorted { a,b in
            func rank(_ value: Expiration) -> Double {
                switch value {case .date(let date):return date.timeIntervalSince1970; case .unlimited:return .greatestFiniteMagnitude; case .unavailable:return .infinity}
            }
            return rank(a) < rank(b)
        }
        var lines = order.map { expiration -> String in
            let count = groups[expiration]!.count
            switch expiration {
            case .date(let date):return "\(count) 张 · \(date.formatted(date:.abbreviated,time:.shortened)) 到期"
            case .unlimited:return "\(count) 张 · 不限期"
            case .unavailable:return "\(count) 张 · 过期时间暂未提供"
            }
        }
        if let availableCount, availableCount > expirations.count {
            lines.append("其余 \(availableCount-expirations.count) 张 · 过期时间暂未提供")
        }
        return lines.joined(separator:"\n")
    }
}
