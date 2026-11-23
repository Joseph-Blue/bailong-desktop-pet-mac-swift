import Foundation

// 仅在查询额度时运行。索引用于发现日志，按文件增量读取；内存只留当天计数、事件身份和读取位置。
final class LocalDailyTokenReader {
    struct Source:Equatable {
        let path:String
        let provider:String?
        let createdAt:Date?
        init(path:String,provider:String? = nil,createdAt:Date? = nil) {
            self.path = URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath().path
            self.provider = provider; self.createdAt = createdAt
        }
    }
    private struct FileState {
        var offset:UInt64 = 0
        var previous:TokenUsage?
        var turn:String?
        var inode:UInt64
        var size:UInt64
        var modified:Date
        let source:Source
    }
    private let queue = DispatchQueue(label:L10n.text(.tasks,"localDailyTokenReader.queue.label"),qos:.utility,autoreleaseFrequency:.workItem)
    private var day:DateInterval?
    private var files = [String:FileState]()
    private var seen = Set<String>()
    private var total = TokenUsage.zero
    private var selectedProvider:String?
    private let fractional:ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return f
    }()
    private let seconds = ISO8601DateFormatter()
    private static let markers = ["\"token_count\"","\"task_started\"","\"turn_context\""].map {Data($0.utf8)}
    private static let chunkSize = 65536

    func query(provider:String? = nil,_ completion:@escaping (DailyTokenUsage) -> Void) {
        queue.async { [self] in
            let result:DailyTokenUsage
            do {
                let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
                let database = try ReadDatabase(root+"/state_5.sqlite")
                // 供应商取会话索引的真实标识；普通查询继续汇总当前 CODEX_HOME 内的全部日志。
                let columns = provider == nil ? "rollout_path" : "rollout_path,model_provider,created_at,created_at_ms"
                let filter = provider == nil ? "" : " AND model_provider=?"
                let rows = try database.rows("SELECT DISTINCT "+columns+" FROM threads WHERE rollout_path<>''"+filter,
                    provider.map {[$0]} ?? [])
                let sources = try rows.map {row -> Source in
                    guard let path = row["rollout_path"] else {throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.query.message"))}
                    guard provider != nil else {return Source(path:path)}
                    guard let seconds = row["created_at"].flatMap(Double.init) else {
                        throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.query.message.2"))
                    }
                    let created = row["created_at_ms"].flatMap(Double.init).map {$0/1000} ?? seconds
                    return Source(path:path,provider:row["model_provider"],createdAt:Date(timeIntervalSince1970:created))
                }
                result = .available(usage:try read(sources:sources,provider:provider))
            } catch {reset(); result = .failed(error.localizedDescription)}
            DispatchQueue.main.async {completion(result)}
        }
    }
    // 测试与后台查询共用；调用者须在同一串行队列使用该实例。
    func read(paths:[String],now:Date = Date(),calendar:Calendar = .current) throws -> TokenUsage {
        try read(sources:paths.map {Source(path:$0)},now:now,calendar:calendar)
    }
    func read(sources:[Source],provider:String? = nil,now:Date = Date(),calendar:Calendar = .current) throws -> TokenUsage {
        let interval = DateInterval(start:calendar.startOfDay(for:now),end:calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now))!)
        if day != interval || selectedProvider != provider {reset(); day = interval; selectedProvider = provider}
        do {
            var unique = [String:Source]()
            for source in sources where provider == nil || source.provider == provider {
                if let previous = unique[source.path],previous != source {
                    throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.read.message"))
                }
                unique[source.path] = source
            }
            var candidates = [(Source,UInt64,UInt64,Date)]()
            for source in unique.values.sorted(by:{$0.path < $1.path}) {
                let path = source.path
                let attributes:[FileAttributeKey:Any]
                do {attributes = try FileManager.default.attributesOfItem(atPath:path)}
                catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {continue}
                guard let modified = attributes[.modificationDate] as? Date,
                      let size = attributes[.size] as? NSNumber,let inode = attributes[.systemFileNumber] as? NSNumber else {
                    throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.read.message.2"))
                }
                guard modified >= interval.start || files[path] != nil else {continue}
                candidates.append((source,inode.uint64Value,size.uint64Value,modified))
            }
            let present = Set(candidates.map {$0.0.path})
            let replaced = candidates.contains {source,inode,size,modified in
                guard let old = files[source.path] else {return false}
                return old.source != source || old.inode != inode || size < old.size || (size == old.size && modified != old.modified)
            }
            if replaced || !Set(files.keys).isSubset(of:present) {reset(); day = interval; selectedProvider = provider}
            for (source,inode,size,modified) in candidates {
                var state = files[source.path] ?? FileState(inode:inode,size:size,modified:modified,source:source)
                if state.offset < size {try scan(path:source.path,size:size,state:&state,interval:interval)}
                state.size = size; state.modified = modified; files[source.path] = state
            }
            return total
        } catch {reset(); throw error}
    }
    private func reset() {files.removeAll(); seen.removeAll(); total = .zero; day = nil; selectedProvider = nil}
    private func scan(path:String,size:UInt64,state:inout FileState,interval:DateInterval) throws {
        let file = try FileHandle(forReadingFrom:URL(fileURLWithPath:path)); defer {try? file.close()}
        try file.seek(toOffset:state.offset)
        var cursor = state.offset,pending = Data(),discarded = false
        func append(_ part:Data.SubSequence) throws {
            guard !discarded else {return}
            if pending.count+part.count > Self.chunkSize {
                if Self.markers.contains(where:{pending.prefix(1024).range(of:$0) != nil}) {
                    throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.append.message"))
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
            throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.consume.message"))
        }
        guard timestamp >= interval.start && timestamp < interval.end else {return}
        // 分叉保留原事件时间；创建前的继承事件不计入当前供应商。
        if selectedProvider != nil,let created = state.source.createdAt,timestamp < created {return}
        guard let increment else {throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.consume.message.2"))}
        guard increment.total > 0 else {return}
        guard let turn = state.turn else {throw PetFailure(message:L10n.text(.usage,"localDailyTokenReader.consume.message.3"))}
        // 分叉复制保留原轮次、时间和累计值；独立子任务有自己的轮次身份。
        let identity = turn+"\u{001f}"+stamp+"\u{001f}"+cumulative.signature
        if seen.insert(identity).inserted {total = total.adding(increment)}
    }
}
