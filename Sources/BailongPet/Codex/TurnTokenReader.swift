import Foundation

// 只读取已结束目标轮次的用量事件；文件偏移来自 Codex 现有索引。
// 不解析对话、工具输出或 reasoning 内容。缓存仅保存至多 160 组计数。
enum TurnTokenReader {
    private static let lock = NSLock()
    private struct Entry {let usage:TokenUsage?}
    private static var cache = [String:Entry]()
    private static var order = [String]()
    private static let tokenMarker = Data("\"token_count\"".utf8)
    private static let eventMarker = Data("\"event_msg\"".utf8)
    private static let limit = 65536

    static func read(path:String,turn:String,start:UInt64?,end:UInt64?) throws -> TokenUsage? {
        guard !path.isEmpty,let start,let end,end > start else {return nil}
        let key = "\(path):\(turn):\(start):\(end)"
        if let entry = lock.withLock({cache[key]}) {return entry.usage}
        let file = try FileHandle(forReadingFrom:URL(fileURLWithPath:path))
        defer {try? file.close()}
        var baseline = try previousTotal(file,before:start)
        var latest:TokenUsage?,invalid = false,matched = false
        try lines(file,from:start,to:end) {line in
            if !matched {
                guard let raw = try JSONSerialization.jsonObject(with:line) as? [String:Any],
                      let payload = raw["payload"] as? [String:Any],payload["turn_id"] as? String == turn else {
                    throw PetFailure(message:"Token 记录与目标轮次不一致。")
                }
                matched = true
            }
            if let value = try counters(line) {
                // 新文件或分叉缺少前置事件时，用首个请求恢复起点，不把继承累计算入本轮。
                if baseline == nil {
                    baseline = value.last.flatMap {value.total.subtracting($0)}
                    if baseline == nil {invalid = true}
                }
                if let earlier = latest ?? baseline,value.total.subtracting(earlier) == nil {invalid = true}
                latest = value.total
            }
        }
        let usage = matched && !invalid ? baseline.flatMap {latest?.subtracting($0)} : nil
        lock.withLock {
            cache[key] = Entry(usage:usage); order.removeAll {$0 == key}; order.append(key)
            while order.count > 160 {cache.removeValue(forKey:order.removeFirst())}
        }
        return usage
    }
    // 向前寻找累计基线，使用重叠窗口覆盖跨块的短用量事件，不载入整份 rollout。
    private static func previousTotal(_ file:FileHandle,before offset:UInt64) throws -> TokenUsage? {
        var end = offset
        while end > 0 {
            let start = end > UInt64(limit*2) ? end-UInt64(limit*2) : 0
            try file.seek(toOffset:start)
            let data = try file.read(upToCount:Int(end-start)) ?? Data()
            var pieces = data.split(separator:10,omittingEmptySubsequences:false)
            if data.last != 10 {pieces.removeLast()}
            let complete = start == 0 ? pieces[...] : pieces.dropFirst()
            for line in complete.reversed() where !line.isEmpty {
                if let value = try counters(Data(line)) {return value.total}
            }
            if start == 0 {break}
            end -= UInt64(limit)
        }
        return nil
    }
    private static func counters(_ line:Data) throws -> (total:TokenUsage,last:TokenUsage?)? {
        let header = line.prefix(1024)
        guard header.range(of:tokenMarker) != nil,header.range(of:eventMarker) != nil else {return nil}
        guard let raw = try JSONSerialization.jsonObject(with:line) as? [String:Any],raw["type"] as? String == "event_msg",
              let payload = raw["payload"] as? [String:Any],payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String:Any],let total = TokenUsage.read(info["total_token_usage"]) else {return nil}
        return (total,TokenUsage.read(info["last_token_usage"]))
    }
    private static func lines(_ file:FileHandle,from start:UInt64,to end:UInt64,visit:(Data) throws -> Void) throws {
        try file.seek(toOffset:start)
        var offset = start, pending = Data(),oversized = false
        while offset < end {
            guard let chunk = try file.read(upToCount:Int(min(UInt64(limit),end-offset))),!chunk.isEmpty else {break}
            offset += UInt64(chunk.count)
            for part in chunk.split(separator:10,omittingEmptySubsequences:false).enumerated() {
                if part.offset > 0 {
                    if !oversized,!pending.isEmpty {try visit(pending)}
                    pending.removeAll(keepingCapacity:true); oversized = false
                }
                if pending.count+part.element.count > limit {
                    if pending.range(of:tokenMarker) != nil {throw PetFailure(message:"Token 用量事件超出读取长度。")}
                    oversized = true; pending.removeAll(keepingCapacity:true)
                }
                if !oversized {pending.append(contentsOf:part.element)}
            }
        }
        if !oversized,!pending.isEmpty {try visit(pending)}
    }
}
