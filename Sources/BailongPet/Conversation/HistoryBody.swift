import Foundation
import SQLite3

// 元数据常驻；正文是不可变版本，运行轮次与冻结快照共享同一版本。
struct HistoryBody:Codable {
    var input = "", messages = "", summary = "", steps = "", final = "", error = ""
    var sensitiveInputNotice:String?, sensitiveQuestionNotice:String?
    var fileEdits:[FileEditSummary]?
    var notices = [String:Double]()
    var cost:Int {[input,messages,summary,steps,final,error,sensitiveInputNotice ?? "",sensitiveQuestionNotice ?? ""].reduce(0) {$0+$1.utf8.count} + notices.keys.reduce(0) {$0+$1.utf8.count} + (fileEdits ?? []).flatMap(\.signature).reduce(0) {$0+$1.utf8.count}}
}

final class HistoryBodyReference: @unchecked Sendable {
    let id:String
    private let lock = NSLock()
    private var memory:HistoryBody?
    private var disk:HistoryDatabase?
    init(_ value:HistoryBody = HistoryBody()) {id = UUID().uuidString; memory = value}
    init(id:String,disk:HistoryDatabase) {self.id = id; self.disk = disk; disk.register(self)}
    func value() -> HistoryBody {
        let (memory,disk) = lock.withLock {(self.memory,self.disk)}
        if let memory {return memory}
        guard let disk else {preconditionFailure("历史正文缺少存储来源")}
        do {return try disk.body(id)}
        catch {
            disk.reportReadFailure(error)
            return HistoryBody(error:"历史正文读取失败："+error.localizedDescription)
        }
    }
    func persist(in target:HistoryDatabase,turnKey:String) throws {
        let (memory,disk) = lock.withLock {(self.memory,self.disk)}
        if disk === target {return}
        let value:HistoryBody
        if let memory {value = memory}
        else if let disk {value = try disk.body(id)}
        else {preconditionFailure("历史正文缺少存储来源")}
        try target.insert(id,value,turnKey:turnKey)
        // 事务提交后才卸载；失败时仍可显式重试原正文。
    }
    func committed(to disk:HistoryDatabase) {
        lock.withLock {self.disk = disk; memory = nil}
        disk.register(self)
    }
}

extension CodingUserInfoKey {
    static let historyDatabase = CodingUserInfoKey(rawValue:"bailong.historyDatabase")!
    static let historyIndex = CodingUserInfoKey(rawValue:"bailong.historyIndex")!
}

final class HistoryDatabase: @unchecked Sendable {
    private final class WeakBody {weak var value:HistoryBodyReference?; init(_ value:HistoryBodyReference) {self.value = value}}
    private let lock = NSRecursiveLock()
    private var db:OpaquePointer?
    private var references = [String:WeakBody]()
    private var cache = [String:(HistoryBody,Int)]()
    private var order = [String]()
    private var bytes = 0
    let cacheLimit = 2 * 1024 * 1024
    private var failure:String?
    var readFailure:String? {lock.withLock {failure}}
    var cachedBytes:Int {lock.withLock {bytes}}
    var onReadFailure:((Error) -> Void)?
    let url:URL
    init(url:URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else {
            let error = sqlError(); if let db {sqlite3_close(db)}; db = nil; throw error
        }
        var ready = false
        defer {if !ready,let db {sqlite3_close(db); self.db = nil}}
        sqlite3_busy_timeout(db,1000)
        try execute("PRAGMA cache_size=-1024")
        let version = try scalar("PRAGMA user_version")
        guard version == "0" || version == "3" else {throw PetFailure(message:"历史数据库格式不支持："+(version ?? "未提供"))}
        if version == "0" {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE history_index (id INTEGER PRIMARY KEY CHECK(id=1), document BLOB NOT NULL)")
                try execute("CREATE TABLE history_bodies (id TEXT PRIMARY KEY, turn_key TEXT NOT NULL, body BLOB NOT NULL)")
                try execute("PRAGMA user_version=3")
                try execute("COMMIT")
            } catch {
                let original = error
                do {try execute("ROLLBACK")} catch {throw PetFailure(message:original.localizedDescription+"；建库回滚失败："+error.localizedDescription)}
                throw original
            }
        }
        ready = true
    }
    deinit {if let db {sqlite3_close(db)}}
    private func sqlError() -> Error {PetFailure(message:db.map {String(cString:sqlite3_errmsg($0))} ?? "无法打开历史数据库")}
    private func statement(_ sql:String,_ values:[String] = []) throws -> OpaquePointer {
        var result:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&result,nil) == SQLITE_OK,let result else {throw sqlError()}
        for (index,value) in values.enumerated() {
            let status = value.withCString {sqlite3_bind_text(result,Int32(index+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
            guard status == SQLITE_OK else {sqlite3_finalize(result); throw sqlError()}
        }
        return result
    }
    private func execute(_ sql:String,_ values:[String] = []) throws {
        let stmt = try statement(sql,values); defer {sqlite3_finalize(stmt)}
        let status = sqlite3_step(stmt)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {throw sqlError()}
    }
    private func scalar(_ sql:String,_ values:[String] = []) throws -> String? {
        let stmt = try statement(sql,values); defer {sqlite3_finalize(stmt)}
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE {return nil}
        guard status == SQLITE_ROW else {throw sqlError()}
        return sqlite3_column_text(stmt,0).map {String(cString:$0)}
    }
    func register(_ body:HistoryBodyReference) {lock.withLock {references[body.id] = WeakBody(body)}}
    func reportReadFailure(_ error:Error) {
        let first = lock.withLock {() -> Bool in guard failure == nil else {return false}; failure = "历史正文读取失败，已停止写入："+error.localizedDescription; return true}
        if first {DispatchQueue.main.async { [weak self] in self?.onReadFailure?(error) }}
    }
    func body(_ id:String) throws -> HistoryBody {
        try lock.withLock {
            if let cached = cache[id] {order.removeAll {$0 == id}; order.append(id); return cached.0}
            guard let json = try scalar("SELECT body FROM history_bodies WHERE id=?",[id]) else {throw PetFailure(message:"历史正文缺失："+id)}
            let value = try JSONDecoder().decode(HistoryBody.self,from:Data(json.utf8))
            let cost = max(json.utf8.count,value.cost)
            if cost <= cacheLimit {
                while bytes+cost > cacheLimit || cache.count >= 16 {
                    let first = order.removeFirst(); bytes -= cache.removeValue(forKey:first)!.1
                }
                cache[id] = (value,cost); order.append(id); bytes += cost
            }
            return value
        }
    }
    func clearCache() {lock.withLock {cache.removeAll(); order.removeAll(); bytes = 0}}
    func load() throws -> HistoryDocument? {
        try lock.withLock {
            guard let json = try scalar("SELECT document FROM history_index WHERE id=1") else {return nil}
            let decoder = JSONDecoder(); decoder.userInfo[.historyDatabase] = self
            let document = try decoder.decode(HistoryDocument.self,from:Data(json.utf8))
            guard document.schemaVersion == 3 else {throw PetFailure(message:"历史索引格式不支持")}
            try document.validateIdentity()
            return document
        }
    }
    fileprivate func insert(_ id:String,_ body:HistoryBody,turnKey:String) throws {
        let json = String(decoding:try JSONEncoder().encode(body),as:UTF8.self)
        try execute("INSERT OR IGNORE INTO history_bodies(id,turn_key,body) VALUES(?,?,?)",[id,turnKey,json])
    }
    func write(_ source:HistoryDocument) throws {
        try lock.withLock {
            if let failure {throw PetFailure(message:failure)}
            var document = source; document.schemaVersion = 3
            let turns = document.conversations.flatMap(\.turns)
            let bodies = turns.map(\.bodyReference)
            try execute("BEGIN IMMEDIATE")
            do {
                for turn in turns {try autoreleasepool {try turn.bodyReference.persist(in:self,turnKey:turn.key)}}
                let encoder = JSONEncoder(); encoder.userInfo[.historyIndex] = true
                let json = String(decoding:try encoder.encode(document),as:UTF8.self)
                try execute("INSERT OR REPLACE INTO history_index(id,document) VALUES(1,?)",[json])
                references = references.filter {$0.value.value != nil}
                let retained = Set(bodies.map(\.id)).union(references.keys)
                let ids = String(decoding:try JSONEncoder().encode(Array(retained)),as:UTF8.self)
                let manifestIDs = String(decoding:try JSONEncoder().encode(bodies.map(\.id)),as:UTF8.self)
                let turnKeys = String(decoding:try JSONEncoder().encode(turns.map(\.key)),as:UTF8.self)
                if try scalar("SELECT value FROM json_each(?) WHERE value NOT IN (SELECT id FROM history_bodies) LIMIT 1",[manifestIDs]) != nil {throw PetFailure(message:"历史正文缺失，事务未保存")}
                try execute("DELETE FROM history_bodies WHERE id NOT IN (SELECT value FROM json_each(?)) AND (id NOT IN (SELECT value FROM json_each(?)) OR turn_key NOT IN (SELECT value FROM json_each(?)))",[manifestIDs,ids,turnKeys])
                try execute("COMMIT")
            } catch {
                let original = error
                do {try execute("ROLLBACK")} catch {throw PetFailure(message:original.localizedDescription+"；事务回滚失败："+error.localizedDescription)}
                throw original
            }
            for body in bodies {body.committed(to:self)}
        }
    }
    func export(to destination:URL) throws {
        try lock.withLock {
            var output:OpaquePointer?
            guard sqlite3_open(destination.path,&output) == SQLITE_OK,let output else {if let output {sqlite3_close(output)}; throw PetFailure(message:"无法创建历史导出文件")}
            defer {sqlite3_close(output)}
            guard let backup = sqlite3_backup_init(output,"main",db,"main") else {throw PetFailure(message:String(cString:sqlite3_errmsg(output)))}
            let status = sqlite3_backup_step(backup,-1)
            let finish = sqlite3_backup_finish(backup)
            guard status == SQLITE_DONE,finish == SQLITE_OK else {throw PetFailure(message:String(cString:sqlite3_errmsg(output)))}
        }
    }
}
