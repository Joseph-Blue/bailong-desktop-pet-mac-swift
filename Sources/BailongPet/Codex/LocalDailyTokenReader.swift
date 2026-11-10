import Foundation

// 仅在查询额度时运行。索引用于发现日志，按文件增量读取；内存只留当天计数、事件身份和读取位置。
final class LocalDailyTokenReader {
    private struct FileState {
        var offset:UInt64 = 0
        var previous:TokenUsage?
        var turn:String?
        var inode:UInt64
        var size:UInt64
        var modified:Date
    }
    private let queue = DispatchQueue(label:"白龙娘本机每日用量",qos:.utility,autoreleaseFrequency:.workItem)
    private var day:DateInterval?
    private var files = [String:FileState]()
    private var seen = Set<String>()
    private var total:Int64 = 0
    private let fractional:ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return f
    }()
    private let seconds = ISO8601DateFormatter()
    private static let markers = ["\"token_count\"","\"task_started\"","\"turn_context\""].map {Data($0.utf8)}
    private static let chunkSize = 65536

    func query(_ completion:@escaping (DailyTokenUsage) -> Void) {
        queue.async { [self] in
            let result:DailyTokenUsage
            do {
                let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
                let database = try ReadDatabase(root+"/state_5.sqlite")
                // 不按账号、归档、CLI 或子任务过滤，统计当前 Codex 数据目录内已有的本机日志。
                let paths = try database.rows("SELECT DISTINCT rollout_path FROM threads WHERE rollout_path<>''").compactMap {$0["rollout_path"]}
                result = .available(tokens:try read(paths:paths))
            } catch {reset(); result = .failed(error.localizedDescription)}
            DispatchQueue.main.async {completion(result)}
        }
    }
    // 测试与后台查询共用；调用者须在同一串行队列使用该实例。
    func read(paths:[String],now:Date = Date(),calendar:Calendar = .current) throws -> Int64 {
        let interval = DateInterval(start:calendar.startOfDay(for:now),end:calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now))!)
        if day != interval {reset(); day = interval}
        do {
            var candidates = [(String,UInt64,UInt64,Date)]()
            for path in Set(paths.map {URL(fileURLWithPath:$0).standardizedFileURL.resolvingSymlinksInPath().path}).sorted() {
                let attributes:[FileAttributeKey:Any]
                do {attributes = try FileManager.default.attributesOfItem(atPath:path)}
                catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {continue}
                guard let modified = attributes[.modificationDate] as? Date,
                      let size = attributes[.size] as? NSNumber,let inode = attributes[.systemFileNumber] as? NSNumber else {
                    throw PetFailure(message:"无法读取本机用量日志的文件信息。")
                }
                guard modified >= interval.start || files[path] != nil else {continue}
                candidates.append((path,inode.uint64Value,size.uint64Value,modified))
            }
            let present = Set(candidates.map {$0.0})
            let replaced = candidates.contains {path,inode,size,modified in
                guard let old = files[path] else {return false}
                return old.inode != inode || size < old.size || (size == old.size && modified != old.modified)
            }
            if replaced || !Set(files.keys).isSubset(of:present) {reset(); day = interval}
            for (path,inode,size,modified) in candidates {
                var state = files[path] ?? FileState(inode:inode,size:size,modified:modified)
                if state.offset < size {try scan(path:path,size:size,state:&state,interval:interval)}
                state.size = size; state.modified = modified; files[path] = state
            }
            return total
        } catch {reset(); throw error}
    }
    private func reset() {files.removeAll(); seen.removeAll(); total = 0; day = nil}
    private func scan(path:String,size:UInt64,state:inout FileState,interval:DateInterval) throws {
        let file = try FileHandle(forReadingFrom:URL(fileURLWithPath:path)); defer {try? file.close()}
        try file.seek(toOffset:state.offset)
        var cursor = state.offset,pending = Data(),discarded = false
        func append(_ part:Data.SubSequence) throws {
            guard !discarded else {return}
            if pending.count+part.count > Self.chunkSize {
                if Self.markers.contains(where:{pending.prefix(1024).range(of:$0) != nil}) {
                    throw PetFailure(message:"本机用量事件超出读取长度。")
                }
                discarded = true; pending.removeAll(keepingCapacity:true)
            } else {pending.append(part)}
        }
        while cursor < size {
            guard let chunk = try file.read(upToCount:Int(min(UInt64(Self.chunkSize),size-cursor))),!chunk.isEmpty else {break}
            var start = chunk.startIndex
            while let end = chunk[start...].firstIndex(of:10) {
                try append(chunk[start..<end])
                if !discarded,!pending.isEmpty {try consume(pending,state:&state,interval:interval)}
                state.offset = cursor+UInt64(end+1)
                pending.removeAll(keepingCapacity:true); discarded = false; start = end+1
            }
            try append(chunk[start...]); cursor += UInt64(chunk.count)
        }
        // 未落盘完整的末行留待下次读取，不将半条事件计入或报作损坏。
    }
    private func consume(_ line:Data,state:inout FileState,interval:DateInterval) throws {
        guard Self.markers.contains(where:{line.prefix(1024).range(of:$0) != nil}) else {return}
        guard let record = try JSONSerialization.jsonObject(with:line) as? [String:Any],
              let payload = record["payload"] as? [String:Any] else {return}
        let type = record["type"] as? String
        if type == "turn_context" || (type == "event_msg" && payload["type"] as? String == "task_started") {
            state.turn = payload["turn_id"] as? String; return
        }
        guard type == "event_msg",payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String:Any],let cumulative = TokenUsage.read(info["total_token_usage"]) else {return}
        let increment = state.previous.flatMap {cumulative.subtracting($0)} ?? TokenUsage.read(info["last_token_usage"])
        state.previous = cumulative
        guard let stamp = record["timestamp"] as? String,
              let timestamp = fractional.date(from:stamp) ?? seconds.date(from:stamp) else {
            throw PetFailure(message:"本机用量事件缺少有效时间。")
        }
        guard timestamp >= interval.start && timestamp < interval.end else {return}
        guard let increment else {throw PetFailure(message:"本机用量事件缺少请求计数。")}
        guard increment.total > 0 else {return}
        guard let turn = state.turn else {throw PetFailure(message:"本机用量事件缺少轮次标识。")}
        // 分叉复制保留原轮次、时间和累计值；独立子任务有自己的轮次身份。
        let identity = turn+"\u{001f}"+stamp+"\u{001f}"+cumulative.signature
        if seen.insert(identity).inserted {total += increment.total}
    }
}
